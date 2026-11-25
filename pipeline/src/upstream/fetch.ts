import { localizeInPlace, type LocalizationStats } from "./localize.js";

export type GameMode = "regular" | "pve" | "pvp-season";

export const DEFAULT_BASE_URL = "https://json.tarkov.dev";
export const USER_AGENT =
  "tarkov-companion-pipeline/0.0.0 (+https://github.com/Tayuha/tarkov-companion)";

export class UpstreamError extends Error {
  readonly url: string;
  readonly status: number | undefined;

  constructor(message: string, url: string, status?: number) {
    super(message);
    this.name = "UpstreamError";
    this.url = url;
    this.status = status;
  }
}

export interface FetchDatasetOptions {
  readonly mode: GameMode;
  readonly dataset: string;
  /** Locale for the `_{lang}` dictionary. Defaults to English. */
  readonly lang?: string;
  readonly baseUrl?: string;
  readonly timeoutMs?: number;
  readonly retries?: number;
  /** Test seam; defaults to global fetch. */
  readonly fetchImpl?: typeof fetch;
  /** Delay before retrying, in ms. Defaults to exponential backoff. */
  readonly retryDelayMs?: number;
  /**
   * When true, a missing locale dictionary is tolerated and placeholders are
   * returned as-is. Defaults to false when the payload declares translations,
   * so bad data never reaches a bundle silently.
   */
  readonly allowMissingDictionary?: boolean;
}

export interface DatasetMeta {
  readonly mode: GameMode;
  readonly dataset: string;
  readonly lang: string;
  readonly fetchedAt: string;
  readonly etag: string | null;
  readonly lastModified: string | null;
}

export interface DictionaryMeta {
  readonly etag: string | null;
  readonly lastModified: string | null;
}

export interface FetchDatasetResult {
  /** Localized dataset, ready for normalization. Mutated copy of the payload's `data`. */
  readonly data: unknown;
  /** Unresolved copy of the payload's `data`, useful for recording fixtures. */
  readonly rawData: unknown;
  /** Locale dictionary used to resolve `rawData`, keyed by placeholder string. */
  readonly dictionary: Readonly<Record<string, string>>;
  /** Conditional-request metadata for the dictionary response, when fetched. */
  readonly dictionaryMeta: DictionaryMeta | null;
  /** Translation pointers declared by the upstream payload, preserved for fixtures. */
  readonly translations: readonly string[];
  readonly stats: LocalizationStats;
  readonly sources: { readonly data: string; readonly dictionary: string | null };
  readonly meta: DatasetMeta;
  readonly warnings: readonly string[];
}

interface JsonResponse {
  readonly body: unknown;
  readonly etag: string | null;
  readonly lastModified: string | null;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryable(status: number | undefined): boolean {
  return status === undefined || status === 429 || status >= 500;
}

async function requestJson(
  url: string,
  options: Required<Pick<FetchDatasetOptions, "timeoutMs" | "retries" | "retryDelayMs">> & {
    fetchImpl: typeof fetch;
  },
): Promise<JsonResponse> {
  let lastError: UpstreamError | undefined;

  for (let attempt = 0; attempt <= options.retries; attempt += 1) {
    if (attempt > 0) {
      await sleep(options.retryDelayMs * 2 ** (attempt - 1));
    }

    try {
      const response = await options.fetchImpl(url, {
        headers: { accept: "application/json", "user-agent": USER_AGENT },
        signal: AbortSignal.timeout(options.timeoutMs),
        redirect: "follow",
      });

      if (!response.ok) {
        const error = new UpstreamError(
          `GET ${url} returned ${response.status} ${response.statusText}`,
          url,
          response.status,
        );
        if (!isRetryable(response.status) || attempt === options.retries) {
          throw error;
        }
        lastError = error;
        continue;
      }

      const text = await response.text();
      let body: unknown;
      try {
        body = JSON.parse(text);
      } catch {
        throw new UpstreamError(`GET ${url} returned invalid JSON`, url, response.status);
      }

      return {
        body,
        etag: response.headers.get("etag"),
        lastModified: response.headers.get("last-modified"),
      };
    } catch (error) {
      if (error instanceof UpstreamError) {
        if (!isRetryable(error.status) || attempt === options.retries) throw error;
        lastError = error;
        continue;
      }
      const error_ = new UpstreamError(
        `GET ${url} failed: ${error instanceof Error ? error.message : String(error)}`,
        url,
      );
      if (attempt === options.retries) throw error_;
      lastError = error_;
    }
  }

  throw lastError ?? new UpstreamError(`GET ${url} failed`, url);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function readDictionary(body: unknown, url: string): Record<string, string> {
  if (!isRecord(body)) {
    throw new UpstreamError(`Dictionary ${url} is not a JSON object`, url);
  }

  const candidate = isRecord(body.data) ? body.data : body;
  const dictionary: Record<string, string> = {};

  for (const [key, value] of Object.entries(candidate)) {
    if (typeof value === "string") {
      dictionary[key] = value;
    } else if (value !== undefined) {
      throw new UpstreamError(`Dictionary ${url} has a non-string value for "${key}"`, url);
    }
  }

  return dictionary;
}

/**
 * Fetch one dataset and its locale dictionary, resolve the translation
 * pointers in place, and return the localized data plus diagnostics.
 */
export async function fetchDataset(options: FetchDatasetOptions): Promise<FetchDatasetResult> {
  const {
    mode,
    dataset,
    lang = "en",
    baseUrl = DEFAULT_BASE_URL,
    timeoutMs = 30_000,
    retries = 3,
    fetchImpl = fetch,
    retryDelayMs = 500,
    allowMissingDictionary = false,
  } = options;

  const dataUrl = `${baseUrl}/${mode}/${dataset}`;
  const requestOptions = { timeoutMs, retries, retryDelayMs, fetchImpl };

  const response = await requestJson(dataUrl, requestOptions);
  if (!isRecord(response.body) || !("data" in response.body)) {
    throw new UpstreamError(`Response from ${dataUrl} has no "data" field`, dataUrl);
  }

  const payload = response.body as { data: unknown; translations?: unknown };
  const rawData = structuredClone(payload.data);
  const translations = Array.isArray(payload.translations)
    ? payload.translations.filter((path): path is string => typeof path === "string")
    : [];

  const warnings: string[] = [];
  let dictionary: Record<string, string> = {};
  let dictionaryUrl: string | null = null;
  let dictionaryMeta: DictionaryMeta | null = null;

  if (translations.length > 0) {
    dictionaryUrl = `${baseUrl}/${mode}/${dataset}_${lang}`;
    try {
      const dictionaryResponse = await requestJson(dictionaryUrl, requestOptions);
      dictionary = readDictionary(dictionaryResponse.body, dictionaryUrl);
      dictionaryMeta = {
        etag: dictionaryResponse.etag,
        lastModified: dictionaryResponse.lastModified,
      };
    } catch (error) {
      if (error instanceof UpstreamError && error.status === 404 && allowMissingDictionary) {
        warnings.push(
          `Locale dictionary ${dictionaryUrl} is missing; ${translations.length} pointers left unresolved`,
        );
      } else {
        throw error;
      }
    }
  }

  const stats = localizeInPlace({ data: payload.data, translations }, dictionary);

  if (stats.missingKeys.length > 0) {
    warnings.push(
      `${stats.missingKeys.length} placeholder key(s) had no ${lang} translation`,
    );
  }

  return {
    data: payload.data,
    rawData,
    dictionary,
    dictionaryMeta,
    translations,
    stats,
    sources: { data: dataUrl, dictionary: dictionaryUrl },
    meta: {
      mode,
      dataset,
      lang,
      fetchedAt: new Date().toISOString(),
      etag: response.etag,
      lastModified: response.lastModified,
    },
    warnings,
  };
}
