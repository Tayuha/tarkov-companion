import { canonicalSha256 } from "../util/canonical.js";
import type { DatasetCacheEntry, DatasetCacheStore } from "./cache.js";
import { localizeInPlace, resolveDictionaryFallback, type LocalizationStats } from "./localize.js";

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
  /**
   * Persistent metadata cache used for conditional requests and checksum
   * comparison. Omit it to always download the dataset.
   */
  readonly cache?: DatasetCacheStore;
  /** Ignore stored validators and re-download both resources. */
  readonly forceRefresh?: boolean;
  /**
   * Also resolve dictionary-covered placeholder strings that no declared
   * translation pointer selects. The scheduled sync opts in; fixture
   * localization keeps the pointer-only contract.
   */
  readonly resolveUncoveredPlaceholders?: boolean;
  /** Clock seam for cache timestamps. Defaults to `new Date()`. */
  readonly now?: () => Date;
}

export interface DatasetMeta {
  readonly mode: GameMode;
  readonly dataset: string;
  readonly lang: string;
  /** When the cached content was downloaded. Revalidations keep this value. */
  readonly fetchedAt: string;
  readonly etag: string | null;
  readonly lastModified: string | null;
}

export interface DictionaryMeta {
  readonly etag: string | null;
  readonly lastModified: string | null;
}

export interface ModifiedDatasetResult {
  readonly status: "modified";
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
  /** Cache entry written for this response. */
  readonly cache: DatasetCacheEntry;
  /** False when the localized content checksum matches the cached one. */
  readonly changed: boolean;
  readonly warnings: readonly string[];
}

/**
 * The upstream answered `304 Not Modified`. No body was read and no
 * dictionary was requested; the returned metadata is the cached entry.
 */
export interface NotModifiedDatasetResult {
  readonly status: "not-modified";
  readonly meta: DatasetMeta;
  readonly dictionaryMeta: DictionaryMeta | null;
  readonly sources: { readonly data: string; readonly dictionary: string | null };
  readonly cache: DatasetCacheEntry;
  readonly warnings: readonly string[];
}

export type FetchDatasetResult = ModifiedDatasetResult | NotModifiedDatasetResult;

interface JsonResponse {
  readonly status: "ok";
  readonly body: unknown;
  readonly etag: string | null;
  readonly lastModified: string | null;
  readonly byteSize: number;
}

interface NotModifiedResponse {
  readonly status: "not-modified";
  readonly etag: string | null;
  readonly lastModified: string | null;
}

type ResponseResult = JsonResponse | NotModifiedResponse;

interface ConditionalHeaders {
  readonly etag: string | null;
  readonly lastModified: string | null;
}

interface RequestSettings {
  readonly timeoutMs: number;
  readonly retries: number;
  readonly retryDelayMs: number;
  readonly fetchImpl: typeof fetch;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryable(status: number | undefined): boolean {
  return status === undefined || status === 429 || status >= 500;
}

async function requestJson(
  url: string,
  options: RequestSettings,
  conditional: ConditionalHeaders | undefined,
): Promise<ResponseResult> {
  let lastError: UpstreamError | undefined;

  for (let attempt = 0; attempt <= options.retries; attempt += 1) {
    if (attempt > 0) {
      await sleep(options.retryDelayMs * 2 ** (attempt - 1));
    }

    try {
      const headers: Record<string, string> = {
        accept: "application/json",
        "user-agent": USER_AGENT,
      };
      if (conditional?.etag !== null && conditional?.etag !== undefined) {
        headers["if-none-match"] = conditional.etag;
      }
      if (conditional?.lastModified !== null && conditional?.lastModified !== undefined) {
        headers["if-modified-since"] = conditional.lastModified;
      }

      const response = await options.fetchImpl(url, {
        headers,
        signal: AbortSignal.timeout(options.timeoutMs),
        redirect: "follow",
      });

      if (response.status === 304) {
        // A 304 has no body by definition; never call `text()` on it.
        return {
          status: "not-modified",
          etag: response.headers.get("etag"),
          lastModified: response.headers.get("last-modified"),
        };
      }

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
        status: "ok",
        body,
        etag: response.headers.get("etag"),
        lastModified: response.headers.get("last-modified"),
        byteSize: Buffer.byteLength(text, "utf8"),
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

function dictionaryMetaFrom(entry: DatasetCacheEntry | undefined): DictionaryMeta | null {
  if (entry === undefined) return null;
  if (entry.dictionaryEtag === null && entry.dictionaryLastModified === null) return null;
  return { etag: entry.dictionaryEtag, lastModified: entry.dictionaryLastModified };
}

/**
 * Fetch one dataset and its locale dictionary, resolve the translation
 * pointers in place, and return the localized data plus diagnostics.
 *
 * With a `cache`, the request is conditional: `If-None-Match` and
 * `If-Modified-Since` are sent for both the base dataset and the dictionary.
 *
 * A `304` on the base dataset short-circuits the whole call. It never reads a
 * body and never requests the dictionary, because the cached entry's
 * validators were written atomically with the content it describes. The
 * dictionary is only consulted when the base dataset was downloaded again.
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
    cache,
    forceRefresh = false,
    resolveUncoveredPlaceholders = false,
    now = () => new Date(),
  } = options;

  const dataUrl = `${baseUrl}/${mode}/${dataset}`;
  const dictionaryUrl = `${baseUrl}/${mode}/${dataset}_${lang}`;
  const requestOptions: RequestSettings = { timeoutMs, retries, retryDelayMs, fetchImpl };
  const cached = cache === undefined ? undefined : await cache.get({ mode, dataset, lang });

  const dataResponse = await requestJson(
    dataUrl,
    requestOptions,
    !forceRefresh && cached !== undefined
      ? { etag: cached.etag, lastModified: cached.lastModified }
      : undefined,
  );

  if (dataResponse.status === "not-modified") {
    if (cached === undefined) {
      throw new UpstreamError(
        `GET ${dataUrl} returned 304 but no cached metadata exists`,
        dataUrl,
        304,
      );
    }

    const dictionaryMeta = dictionaryMetaFrom(cached);
    return {
      status: "not-modified",
      meta: {
        mode,
        dataset,
        lang,
        fetchedAt: cached.fetchedAt,
        etag: dataResponse.etag ?? cached.etag,
        lastModified: dataResponse.lastModified ?? cached.lastModified,
      },
      dictionaryMeta,
      sources: { data: dataUrl, dictionary: dictionaryMeta === null ? null : dictionaryUrl },
      cache: cached,
      warnings: [],
    };
  }

  if (!isRecord(dataResponse.body) || !("data" in dataResponse.body)) {
    throw new UpstreamError(`Response from ${dataUrl} has no "data" field`, dataUrl);
  }

  const payload = dataResponse.body as { data: unknown; translations?: unknown };
  const rawData = structuredClone(payload.data);
  const translations = Array.isArray(payload.translations)
    ? payload.translations.filter((path): path is string => typeof path === "string")
    : [];

  const warnings: string[] = [];
  let dictionary: Record<string, string> = {};
  let fetchedDictionaryUrl: string | null = null;
  let dictionaryMeta: DictionaryMeta | null = null;

  if (translations.length > 0) {
    fetchedDictionaryUrl = dictionaryUrl;
    const dictionaryConditional =
      !forceRefresh &&
      cached !== undefined &&
      (cached.dictionaryEtag !== null || cached.dictionaryLastModified !== null)
        ? { etag: cached.dictionaryEtag, lastModified: cached.dictionaryLastModified }
        : undefined;

    try {
      let dictionaryResponse = await requestJson(
        dictionaryUrl,
        requestOptions,
        dictionaryConditional,
      );

      if (dictionaryResponse.status === "not-modified") {
        // Validators matched, but dictionary bodies are not cached (only
        // checksums and validators are), so the content is needed anyway.
        dictionaryResponse = await requestJson(dictionaryUrl, requestOptions, undefined);
      }
      if (dictionaryResponse.status === "not-modified") {
        throw new UpstreamError(
          `GET ${dictionaryUrl} returned 304 without conditional headers`,
          dictionaryUrl,
          304,
        );
      }

      dictionary = readDictionary(dictionaryResponse.body, dictionaryUrl);
      dictionaryMeta = {
        etag: dictionaryResponse.etag,
        lastModified: dictionaryResponse.lastModified,
      };
    } catch (error) {
      if (error instanceof UpstreamError && error.status === 404 && allowMissingDictionary) {
        dictionary = {};
        dictionaryMeta = null;
        warnings.push(
          `Locale dictionary ${dictionaryUrl} is missing; ${translations.length} pointers left unresolved`,
        );
      } else {
        throw error;
      }
    }
  }

  const stats = localizeInPlace({ data: payload.data, translations }, dictionary);

  if (resolveUncoveredPlaceholders && Object.keys(dictionary).length > 0) {
    const extra = resolveDictionaryFallback(payload.data, dictionary);
    if (extra > 0) stats.resolvedOutsidePointers = extra;
  }

  if (stats.missingKeys.length > 0) {
    warnings.push(
      `${stats.missingKeys.length} placeholder key(s) had no ${lang} translation`,
    );
  }

  const checksum = canonicalSha256(payload.data);
  const changed = cached === undefined || cached.checksum !== checksum;

  const entry: DatasetCacheEntry = {
    mode,
    dataset,
    lang,
    etag: dataResponse.etag,
    lastModified: dataResponse.lastModified,
    dictionaryEtag: dictionaryMeta?.etag ?? null,
    dictionaryLastModified: dictionaryMeta?.lastModified ?? null,
    checksum,
    fetchedAt: now().toISOString(),
    byteSize: dataResponse.byteSize,
  };
  await cache?.set(entry);

  return {
    status: "modified",
    data: payload.data,
    rawData,
    dictionary,
    dictionaryMeta,
    translations,
    stats,
    sources: { data: dataUrl, dictionary: fetchedDictionaryUrl },
    meta: {
      mode,
      dataset,
      lang,
      fetchedAt: entry.fetchedAt,
      etag: entry.etag,
      lastModified: entry.lastModified,
    },
    cache: entry,
    changed,
    warnings,
  };
}
