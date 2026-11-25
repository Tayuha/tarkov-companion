/**
 * Persistent metadata cache for upstream datasets, keyed by
 * `{mode, dataset, lang}`.
 *
 * Only conditional-request validators and a content checksum are stored; the
 * payload itself is never cached here. That keeps the cache small and makes
 * "not modified" a metadata-only result.
 */

import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import type { GameMode } from "./fetch.js";

export interface DatasetCacheKey {
  readonly mode: GameMode;
  readonly dataset: string;
  readonly lang: string;
}

export interface DatasetCacheEntry extends DatasetCacheKey {
  /** `ETag` of the base dataset response, forwarded verbatim as `If-None-Match`. */
  readonly etag: string | null;
  /** `Last-Modified` of the base dataset response, forwarded as `If-Modified-Since`. */
  readonly lastModified: string | null;
  readonly dictionaryEtag: string | null;
  readonly dictionaryLastModified: string | null;
  /** SHA-256 (lowercase hex) over the canonical JSON of the localized dataset. */
  readonly checksum: string;
  /** When the cached content was downloaded; revalidations keep this value. */
  readonly fetchedAt: string;
  /** Size of the base dataset response body in bytes. */
  readonly byteSize: number;
}

export interface DatasetCacheStore {
  get(key: DatasetCacheKey): Promise<DatasetCacheEntry | undefined>;
  set(entry: DatasetCacheEntry): Promise<void>;
}

/** Default cache directory, relative to the process working directory. */
export const DEFAULT_CACHE_DIR = join(".cache", "pipeline");

/** In-memory store for tests and short-lived runs. */
export class MemoryDatasetCacheStore implements DatasetCacheStore {
  readonly #entries = new Map<string, DatasetCacheEntry>();

  get(key: DatasetCacheKey): Promise<DatasetCacheEntry | undefined> {
    return Promise.resolve(this.#entries.get(entryKey(key)));
  }

  set(entry: DatasetCacheEntry): Promise<void> {
    this.#entries.set(entryKey(entry), entry);
    return Promise.resolve();
  }
}

export interface FileDatasetCacheStoreOptions {
  /** Directory holding one JSON file per dataset. Defaults to `.cache/pipeline`. */
  readonly dir?: string;
}

/**
 * One JSON file per `{mode, dataset, lang}`, written atomically via a
 * temporary file and rename. Unreadable or malformed entries are treated as a
 * cache miss so a damaged cache never breaks a fetch.
 */
export class FileDatasetCacheStore implements DatasetCacheStore {
  readonly dir: string;

  constructor(options: FileDatasetCacheStoreOptions = {}) {
    this.dir = resolve(options.dir ?? DEFAULT_CACHE_DIR);
  }

  async get(key: DatasetCacheKey): Promise<DatasetCacheEntry | undefined> {
    const file = this.pathFor(key);

    let text: string;
    try {
      text = await readFile(file, "utf8");
    } catch (error) {
      if (isErrorWithCode(error, "ENOENT")) return undefined;
      throw error;
    }

    try {
      const parsed: unknown = JSON.parse(text);
      return isDatasetCacheEntry(parsed) ? parsed : undefined;
    } catch {
      return undefined;
    }
  }

  async set(entry: DatasetCacheEntry): Promise<void> {
    await mkdir(this.dir, { recursive: true });
    const file = this.pathFor(entry);
    const temp = `${file}.${process.pid}.tmp`;
    await writeFile(temp, `${JSON.stringify(entry, null, 2)}\n`, "utf8");
    await rename(temp, file);
  }

  /** Absolute path of the file backing `key`. Exposed for diagnostics/tests. */
  pathFor(key: DatasetCacheKey): string {
    return join(this.dir, `${slug(key.mode)}__${slug(key.dataset)}__${slug(key.lang)}.json`);
  }
}

function entryKey(key: DatasetCacheKey): string {
  return `${key.mode}/${key.dataset}/${key.lang}`;
}

/** Keep cache filenames portable and path-traversal free. */
function slug(value: string): string {
  const safe = value.replace(/[^A-Za-z0-9_-]/g, "_");
  return safe.length > 0 ? safe : "_";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isNullableString(value: unknown): value is string | null {
  return value === null || typeof value === "string";
}

function isDatasetCacheEntry(value: unknown): value is DatasetCacheEntry {
  if (!isRecord(value)) return false;
  return (
    typeof value["mode"] === "string" &&
    typeof value["dataset"] === "string" &&
    typeof value["lang"] === "string" &&
    isNullableString(value["etag"]) &&
    isNullableString(value["lastModified"]) &&
    isNullableString(value["dictionaryEtag"]) &&
    isNullableString(value["dictionaryLastModified"]) &&
    typeof value["checksum"] === "string" &&
    typeof value["fetchedAt"] === "string" &&
    typeof value["byteSize"] === "number"
  );
}

function isErrorWithCode(error: unknown, code: string): boolean {
  return error instanceof Error && "code" in error && error.code === code;
}
