import { mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import type { BundleMode } from "../bundle/index.js";
import { assertBundleRecords, isRecord } from "../normalize/contract.js";
import type { BundleRecord, NormalizeDataset } from "../normalize/index.js";
import { DEFAULT_CACHE_DIR } from "../upstream/cache.js";

/**
 * Cache of normalized dataset JSONL, keyed by the upstream content checksum.
 *
 * A `304 Not Modified` only proves the localized payload did not change. To
 * rebuild the bundle on a fresh runner without downloading again, the sync path
 * stores the exact normalized JSONL that was produced for that checksum. The
 * key is content-addressed, so a changed upstream payload can never be served
 * from an older entry.
 *
 * `NORMALIZED_CACHE_VERSION` is part of the file name. Bump it whenever the
 * normalizer or the bundle record contract changes incompatibly; old entries
 * then simply become unreachable instead of being trusted.
 */

export const NORMALIZED_CACHE_VERSION = 1;

export interface NormalizedCacheKey {
  readonly mode: BundleMode;
  readonly dataset: NormalizeDataset;
  readonly lang: string;
  /** SHA-256 of the canonical localized dataset, from the upstream fetch cache. */
  readonly checksum: string;
}

export interface NormalizedDatasetCacheStore {
  /** JSONL text for `key`, or undefined on a miss. */
  get(key: NormalizedCacheKey): Promise<string | undefined>;
  set(key: NormalizedCacheKey, jsonl: string): Promise<void>;
}

/** Keep cache filenames portable and path-traversal free. */
function safeSegment(value: string): string {
  const safe = value.replace(/[^A-Za-z0-9_-]/g, "_");
  return safe.length > 0 ? safe : "_";
}

export function normalizedCacheFileName(key: NormalizedCacheKey): string {
  return [
    `v${String(NORMALIZED_CACHE_VERSION)}`,
    safeSegment(key.mode),
    safeSegment(key.dataset),
    safeSegment(key.lang),
    safeSegment(key.checksum),
  ].join("__") + ".jsonl";
}

export interface FileNormalizedDatasetCacheOptions {
  /** Defaults to `.cache/pipeline/normalized`. */
  readonly dir?: string;
}

/** One JSONL file per `{mode, dataset, lang, checksum}`, written atomically. */
export class FileNormalizedDatasetCacheStore implements NormalizedDatasetCacheStore {
  readonly dir: string;

  constructor(options: FileNormalizedDatasetCacheOptions = {}) {
    this.dir = resolve(options.dir ?? join(DEFAULT_CACHE_DIR, "normalized"));
  }

  pathFor(key: NormalizedCacheKey): string {
    return join(this.dir, normalizedCacheFileName(key));
  }

  async get(key: NormalizedCacheKey): Promise<string | undefined> {
    try {
      return await readFile(this.pathFor(key), "utf8");
    } catch (error) {
      if (isErrorWithCode(error, "ENOENT")) return undefined;
      throw error;
    }
  }

  async set(key: NormalizedCacheKey, jsonl: string): Promise<void> {
    await mkdir(this.dir, { recursive: true });
    const file = this.pathFor(key);
    const temporary = `${file}.${String(process.pid)}.tmp`;
    await writeFile(temporary, jsonl, "utf8");
    try {
      await rename(temporary, file);
    } catch (error) {
      await rm(temporary, { force: true });
      throw error;
    }
  }
}

/** In-memory store for tests and offline fixture runs. */
export class MemoryNormalizedDatasetCacheStore implements NormalizedDatasetCacheStore {
  readonly #entries = new Map<string, string>();

  get(key: NormalizedCacheKey): Promise<string | undefined> {
    return Promise.resolve(this.#entries.get(entryKey(key)));
  }

  set(key: NormalizedCacheKey, jsonl: string): Promise<void> {
    this.#entries.set(entryKey(key), jsonl);
    return Promise.resolve();
  }
}

function entryKey(key: NormalizedCacheKey): string {
  return `${key.mode}/${key.dataset}/${key.lang}/${key.checksum}`;
}

function isErrorWithCode(error: unknown, code: string): boolean {
  return error instanceof Error && "code" in error && error.code === code;
}

/**
 * Parse cached JSONL back into bundle records.
 *
 * The cache is derived data, so a malformed line is an error rather than a
 * silent miss: publishing half a dataset would erase client rows. The contract
 * checker runs again on the parsed records for the same reason.
 */
export function parseJsonlRecords(dataset: NormalizeDataset, jsonl: string): BundleRecord[] {
  const records: BundleRecord[] = [];
  const lines = jsonl.split("\n");

  for (const [index, line] of lines.entries()) {
    if (line.length === 0) continue;

    let value: unknown;
    try {
      value = JSON.parse(line) as unknown;
    } catch {
      throw new Error(`${dataset}: cached JSONL line ${String(index + 1)} is not valid JSON`);
    }

    if (!isRecord(value)) {
      throw new Error(`${dataset}: cached JSONL line ${String(index + 1)} is not an object`);
    }
    const kind = value["kind"];
    const id = value["id"];
    if (typeof kind !== "string" || kind.length === 0) {
      throw new Error(`${dataset}: cached JSONL line ${String(index + 1)} has no kind`);
    }
    if (typeof id !== "string" || id.length === 0) {
      throw new Error(`${dataset}: cached JSONL line ${String(index + 1)} has no id`);
    }

    records.push({ ...value, kind, id });
  }

  assertBundleRecords(dataset, records);
  return records;
}
