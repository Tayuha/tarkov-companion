import { BUNDLE_MODES, type BundleMode } from "../bundle/index.js";
import { NORMALIZE_DATASETS, type NormalizeDataset } from "../normalize/index.js";
import {
  DEFAULT_BASE_URL,
  fetchDataset,
  type DatasetMeta,
  type FetchDatasetResult,
} from "../upstream/fetch.js";
import type { DatasetCacheStore } from "../upstream/cache.js";
import type { DatasetFetchResult, DatasetProvider, DatasetSourceMeta } from "./types.js";

/**
 * Live upstream provider used by the scheduled sync.
 *
 * It is a thin adapter over `fetchDataset`: the conditional cache, retries,
 * localization and conditional-request semantics stay exactly where task 2.4
 * put them. The only job here is to translate the fetcher's result into the
 * provider shape and expose the checksum that keys the normalized cache.
 */

export interface UpstreamDatasetProviderOptions {
  /** Required: the conditional-request and checksum cache. */
  readonly cache: DatasetCacheStore;
  readonly baseUrl?: string;
  readonly lang?: string;
  /** Test seam; defaults to global fetch. */
  readonly fetchImpl?: typeof fetch;
  readonly now?: () => Date;
}

function sourceMeta(meta: DatasetMeta, url: string): DatasetSourceMeta {
  return {
    url,
    etag: meta.etag,
    lastModified: meta.lastModified,
    fetchedAt: meta.fetchedAt,
  };
}

function toProviderResult(result: FetchDatasetResult): DatasetFetchResult {
  const meta = sourceMeta(result.meta, result.sources.data);
  if (result.status === "not-modified") {
    return { status: "not-modified", checksum: result.cache.checksum, meta };
  }
  return { status: "modified", data: result.data, checksum: result.cache.checksum, meta };
}

export class UpstreamDatasetProvider implements DatasetProvider {
  readonly #cache: DatasetCacheStore;
  readonly #baseUrl: string;
  readonly #lang: string;
  readonly #fetchImpl: typeof fetch;
  readonly #now: () => Date;

  constructor(options: UpstreamDatasetProviderOptions) {
    this.#cache = options.cache;
    this.#baseUrl = options.baseUrl ?? DEFAULT_BASE_URL;
    this.#lang = options.lang ?? "en";
    this.#fetchImpl = options.fetchImpl ?? fetch;
    this.#now = options.now ?? (() => new Date());
  }

  modes(): Promise<readonly BundleMode[]> {
    return Promise.resolve(BUNDLE_MODES);
  }

  datasets(_mode: BundleMode): Promise<readonly NormalizeDataset[]> {
    return Promise.resolve(NORMALIZE_DATASETS);
  }

  source(_mode: BundleMode): Promise<{ baseUrl: string | null; capturedAt: string | null }> {
    return Promise.resolve({ baseUrl: this.#baseUrl, capturedAt: null });
  }

  async fetch(input: {
    readonly mode: BundleMode;
    readonly dataset: NormalizeDataset;
    readonly forceRefresh: boolean;
  }): Promise<DatasetFetchResult> {
    const result = await fetchDataset({
      mode: input.mode,
      dataset: input.dataset,
      lang: this.#lang,
      baseUrl: this.#baseUrl,
      fetchImpl: this.#fetchImpl,
      cache: this.#cache,
      forceRefresh: input.forceRefresh,
      resolveUncoveredPlaceholders: true,
      now: this.#now,
    });
    return toProviderResult(result);
  }
}
