import type {
  BundleMode,
  DatasetLocalizationMetrics,
  GateResult,
  ManifestDatasetEntry,
  ManifestTotals,
} from "../bundle/index.js";
import type { NormalizeDataset } from "../normalize/index.js";
import type { LocalizationStats } from "../upstream/localize.js";

/**
 * Shared types for the production sync orchestration.
 *
 * The sync path is deliberately split into a provider (where localized data
 * comes from), a normalized-record cache (so a `304` can be rebuilt without a
 * network fetch) and the runner, which validates, normalizes, bundles and
 * publishes. Tests inject a fake upstream `fetch`, an in-memory release client
 * and a small clock; nothing in `sync/run.ts` opens a socket on its own.
 */

/** One upstream validator set plus timestamps, recorded in the bundle manifest. */
export interface DatasetSourceMeta {
  readonly url: string | null;
  readonly etag: string | null;
  readonly lastModified: string | null;
  readonly fetchedAt: string | null;
}

/** Result of asking a provider for one dataset. */
export type DatasetFetchResult =
  | {
      readonly status: "modified";
      /** Localized dataset, ready for schema validation and normalization. */
      readonly data: unknown;
      /** SHA-256 of the canonical localized data, used as the cache key. */
      readonly checksum: string;
      readonly meta: DatasetSourceMeta;
      /** Translation diagnostics for this fetch, consumed by the publication gate. */
      readonly localization: LocalizationStats;
    }
  | {
      readonly status: "not-modified";
      /** Checksum stored with the validators that produced the `304`. */
      readonly checksum: string;
      readonly meta: DatasetSourceMeta;
    };

export interface DatasetFetchInput {
  readonly mode: BundleMode;
  readonly dataset: NormalizeDataset;
  /** Ignore stored validators and download unconditionally. */
  readonly forceRefresh: boolean;
}

/**
 * Source of localized upstream datasets.
 *
 * `UpstreamDatasetProvider` uses the conditional HTTP cache; the offline
 * `FixtureDatasetProvider` reads the committed fixture sets. Both return the
 * same shape, so the runner has no network-specific branch.
 */
export interface DatasetProvider {
  /** Modes this provider can supply, in bundle mode order. */
  modes(): Promise<readonly BundleMode[]>;
  /** Bundlable datasets for one mode, sorted. */
  datasets(mode: BundleMode): Promise<readonly NormalizeDataset[]>;
  /** Per-mode source metadata copied into the manifest. */
  source(mode: BundleMode): Promise<{
    readonly baseUrl: string | null;
    readonly capturedAt: string | null;
  }>;
  fetch(input: DatasetFetchInput): Promise<DatasetFetchResult>;
}

/** How one dataset reached the bundle. */
export type DatasetOutcome = "fetched" | "reused" | "refetched";

export interface DatasetSyncSummary {
  readonly dataset: NormalizeDataset;
  readonly outcome: DatasetOutcome;
  readonly records: number;
}

export interface SyncFailure {
  readonly mode: BundleMode;
  /** `null` when the failure is not tied to one dataset. */
  readonly dataset: NormalizeDataset | null;
  readonly message: string;
}

export interface ModePublication {
  readonly tag: string;
  readonly manifestUrl: string;
  /** Asset names in upload order; the manifest is last when it changed. */
  readonly uploads: readonly string[];
  readonly skips: number;
  readonly mutations: number;
  readonly noop: boolean;
  /** True when the release was not read and the plan assumes a first publication. */
  readonly offlinePlan: boolean;
  readonly releaseExisted: boolean;
  readonly releaseCreated: boolean;
}

export type ModeSyncStatus = "published" | "noop" | "dry-run" | "failed";

export interface ModeSyncSummary {
  readonly mode: BundleMode;
  readonly status: ModeSyncStatus;
  readonly datasets: readonly DatasetSyncSummary[];
  /** Upstream responses that returned a body (including forced re-fetches). */
  readonly fetched: number;
  /** Upstream `304` responses. */
  readonly notModified: number;
  /** Datasets rebuilt from the normalized cache (a `304` that needed no fetch). */
  readonly reused: number;
  /** `304` responses whose normalized cache entry was missing, forcing a fetch. */
  readonly refetched: number;
  readonly totals: ManifestTotals | null;
  readonly entries: readonly ManifestDatasetEntry[];
  /** Localization diagnostics per fetched dataset (a reused 304 has none). */
  readonly localization: readonly DatasetLocalizationMetrics[];
  /** Publication gate result; `null` when the mode failed before it ran. */
  readonly gate: GateResult | null;
  readonly publication: ModePublication | null;
  readonly errors: readonly SyncFailure[];
}

export interface SyncReport {
  readonly generatedAt: string;
  readonly modes: readonly ModeSyncSummary[];
  readonly exitCode: number;
}
