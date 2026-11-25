import {
  MANIFEST_FILE,
  compareBundles,
  parseManifest,
  type BundleComparison,
  type BundleManifest,
  type BundleMode,
} from "../bundle/index.js";
import {
  datasetAssetName,
  isDatasetAsset,
  preparePublishedManifest,
} from "./assets.js";
import type { ReleaseAsset } from "./client.js";

/**
 * Publication planning.
 *
 * The plan is computed before any mutation and is the single source of truth
 * for the uploader. It is ordered: dataset assets sorted by dataset name, then
 * `manifest.json` last. That order is what makes a publication safe to
 * interrupt: until the manifest swap, clients keep reading the previous
 * manifest and its (still present) immutable assets.
 *
 * Idempotency is per asset, not per run: a content-addressed dataset asset that
 * already exists with the expected size is skipped. Whether the manifest must
 * be replaced is decided by the task 2.7 comparison (content checksums and
 * contract versions), so a rebuild with a new `generatedAt` is a no-op.
 */

export interface DatasetUploadStep {
  readonly kind: "dataset";
  readonly dataset: string;
  readonly name: string;
  readonly size: number;
  readonly sha256: string;
  /** Local file in the mode directory, e.g. `items.jsonl.zst`. */
  readonly sourcePath: string;
  readonly reason: string;
}

export interface ManifestUploadStep {
  readonly kind: "manifest";
  readonly name: typeof MANIFEST_FILE;
  readonly size: number;
  readonly reason: string;
}

export type UploadStep = DatasetUploadStep | ManifestUploadStep;

export interface DatasetSkip {
  readonly dataset: string;
  readonly name: string;
  readonly size: number;
  readonly reason: string;
}

export type ManifestAction = "upload" | "skip";

export interface PlanOptions {
  /** Account for executing `prune` when deciding `noop`. */
  readonly prune?: boolean;
}

export interface PublicationPlan {
  readonly mode: BundleMode;
  /** Dataset assets first, `manifest.json` last when `manifestAction` is upload. */
  readonly uploads: readonly UploadStep[];
  readonly skip: readonly DatasetSkip[];
  readonly manifestAction: ManifestAction;
  readonly manifestReason: string;
  /** Dataset assets in the release that the new manifest does not reference. */
  readonly prune: readonly string[];
  /** True when applying the plan would make no mutation, including `prune` when requested. */
  readonly noop: boolean;
  /** Null only when the release has no readable manifest at all. */
  readonly comparison: BundleComparison | null;
}

function describeChanges(comparison: BundleComparison): string {
  const parts: string[] = [];
  if (comparison.added.length > 0) parts.push(`${String(comparison.added.length)} added`);
  if (comparison.changed.length > 0) parts.push(`${String(comparison.changed.length)} changed`);
  if (comparison.removed.length > 0) parts.push(`${String(comparison.removed.length)} removed`);
  if (parts.length === 0) return "client contract changed";
  return `bundle content changed (${parts.join(", ")})`;
}

/**
 * Plan a publication.
 *
 * `localManifest` is the freshly built manifest; its dataset `path` values are
 * still the unversioned local file names. `remoteManifest` is the manifest
 * currently published, or null when the release or its manifest is missing.
 * `remoteAssets` is the release's asset list, used for per-asset idempotency
 * and prune candidates.
 */
export function planPublication(
  localManifest: BundleManifest,
  remoteManifest: BundleManifest | null,
  remoteAssets: readonly ReleaseAsset[],
  options: PlanOptions = {},
): PublicationPlan {
  const local = parseManifest(localManifest, "local manifest");
  const prepared = preparePublishedManifest(local);
  const remote = remoteManifest === null ? null : parseManifest(remoteManifest, "published manifest");
  const comparison = remote === null ? null : compareBundles(remote, prepared.manifest);

  const remoteByName = new Map(remoteAssets.map((asset) => [asset.name, asset] as const));
  const localPaths = new Map(local.datasets.map((entry) => [entry.dataset, entry.path] as const));

  const uploads: UploadStep[] = [];
  const skip: DatasetSkip[] = [];

  for (const entry of prepared.manifest.datasets) {
    const name = datasetAssetName(entry);
    const existing = remoteByName.get(name);

    if (existing !== undefined && existing.size === entry.compressedBytes) {
      skip.push({
        dataset: entry.dataset,
        name,
        size: entry.compressedBytes,
        reason: "asset already published with matching size",
      });
      continue;
    }

    let reason: string;
    if (remote === null) {
      reason = "first publication";
    } else if (existing === undefined) {
      reason = "new content-addressed asset";
    } else {
      reason = `published asset size ${String(existing.size)} does not match ${String(entry.compressedBytes)}`;
    }

    uploads.push({
      kind: "dataset",
      dataset: entry.dataset,
      name,
      size: entry.compressedBytes,
      sha256: entry.sha256,
      sourcePath: localPaths.get(entry.dataset) ?? `${entry.dataset}.jsonl.zst`,
      reason,
    });
  }

  let manifestAction: ManifestAction = "upload";
  let manifestReason: string;
  if (remote === null) {
    manifestReason = "no published manifest";
  } else {
    const pathsAreVersioned = remote.datasets.every((entry) => entry.path === datasetAssetName(entry));
    if (comparison !== null && comparison.hasChanges) {
      manifestReason = describeChanges(comparison);
    } else if (!pathsAreVersioned) {
      manifestReason = "published manifest does not use versioned asset paths";
    } else {
      manifestAction = "skip";
      manifestReason = "bundle content unchanged";
    }
  }

  if (manifestAction === "upload") {
    uploads.push({
      kind: "manifest",
      name: MANIFEST_FILE,
      size: prepared.bytes.byteLength,
      reason: manifestReason,
    });
  }

  const referenced = new Set(
    prepared.manifest.datasets.map((entry) => datasetAssetName(entry)),
  );
  const prune = remoteAssets
    .map((asset) => asset.name)
    .filter((name) => isDatasetAsset(name) && !referenced.has(name))
    .sort();

  const wouldPrune = options.prune === true && prune.length > 0;

  return {
    mode: prepared.manifest.mode,
    uploads,
    skip,
    manifestAction,
    manifestReason,
    prune,
    noop: uploads.length === 0 && manifestAction === "skip" && !wouldPrune,
    comparison,
  };
}
