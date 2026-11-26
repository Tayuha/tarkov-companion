import { z } from "zod";
import type { NormalizeDataset } from "../normalize/index.js";
import { canonicalJson } from "../util/canonical.js";

/**
 * The closed set of dataset names a bundle may contain. Kept as an explicit
 * tuple so the Zod enum is literal-typed; a test asserts it stays in sync with
 * the normalization registry, and the client validates the same closed set.
 */
export const BUNDLE_DATASETS = [
  "items",
  "tasks",
  "traders",
  "hideout",
  "crafts",
  "barters",
  "maps",
] as const satisfies readonly NormalizeDataset[];

export const bundleDatasetSchema = z.enum(BUNDLE_DATASETS);

/**
 * Bundle manifest contract.
 *
 * A manifest is the only document a client needs to decide whether it can
 * consume a bundle and which datasets it must download. It is written as
 * canonical JSON (sorted keys, no insignificant whitespace) with a trailing
 * newline, so two runs over the same data differ only in `generatedAt`.
 *
 * `manifestVersion` versions this document. `bundleSchemaVersion` versions the
 * bundle layout as a whole. Each dataset additionally carries its own
 * `schemaVersion` for the JSONL record shape. `minAppSchemaVersion` is the
 * oldest app data-schema version that can ingest every dataset in the bundle;
 * a client whose supported version is lower must update the app instead of
 * applying the bundle.
 */

export const BUNDLE_MODES = ["regular", "pve", "pvp-season"] as const;

export type BundleMode = (typeof BUNDLE_MODES)[number];

export const bundleModeSchema = z.enum(BUNDLE_MODES);

export const MANIFEST_FILE = "manifest.json";
export const DATASET_FILE_SUFFIX = ".jsonl.zst";

export const MANIFEST_VERSION = 1;
export const BUNDLE_SCHEMA_VERSION = 1;
export const MIN_APP_SCHEMA_VERSION = 1;

/**
 * Per-dataset record schema version. Bump one entry when that dataset's JSONL
 * shape changes incompatibly; the app then refuses a bundle that needs a
 * newer data schema than it implements.
 */
export const DATASET_SCHEMA_VERSIONS: Readonly<Record<NormalizeDataset, number>> = {
  items: 1,
  tasks: 1,
  traders: 1,
  hideout: 1,
  crafts: 1,
  barters: 1,
  maps: 1,
};

export function datasetSchemaVersion(dataset: NormalizeDataset): number {
  return DATASET_SCHEMA_VERSIONS[dataset];
}

export function isBundleMode(value: string): value is BundleMode {
  return (BUNDLE_MODES as readonly string[]).includes(value);
}

const isoDateTime = z.iso.datetime();
const sha256Hex = z.string().regex(/^[0-9a-f]{64}$/);

export const manifestSourceSchema = z.object({
  baseUrl: z.string().nullable(),
  capturedAt: isoDateTime.nullable(),
});

export const manifestDatasetSourceSchema = z.object({
  url: z.string().nullable(),
  lastModified: z.string().nullable(),
  etag: z.string().nullable(),
  fetchedAt: isoDateTime.nullable(),
});

export const manifestDatasetSchema = z.object({
  dataset: bundleDatasetSchema,
  path: z.string().min(1),
  schemaVersion: z.number().int().positive(),
  sha256: sha256Hex,
  compressedBytes: z.number().int().nonnegative(),
  uncompressedBytes: z.number().int().nonnegative(),
  records: z.number().int().nonnegative(),
  source: manifestDatasetSourceSchema,
});

/**
 * A dataset the writer did not receive. `not-supplied` means the caller had no
 * data for it (for example the trimmed `pve` fixture set only carries items),
 * so no file was written and the client must leave its existing rows alone.
 */
export const manifestSkippedSchema = z.object({
  dataset: bundleDatasetSchema,
  reason: z.literal("not-supplied"),
});

export const manifestTotalsSchema = z.object({
  datasets: z.number().int().nonnegative(),
  records: z.number().int().nonnegative(),
  uncompressedBytes: z.number().int().nonnegative(),
  compressedBytes: z.number().int().nonnegative(),
});

export const manifestSchema = z.object({
  manifestVersion: z.literal(MANIFEST_VERSION),
  bundleSchemaVersion: z.number().int().positive(),
  minAppSchemaVersion: z.number().int().positive(),
  mode: bundleModeSchema,
  generatedAt: isoDateTime,
  source: manifestSourceSchema,
  totals: manifestTotalsSchema,
  datasets: z.array(manifestDatasetSchema).min(1),
  skipped: z.array(manifestSkippedSchema),
});

/** Canonical JSON (sorted keys, no whitespace) plus one trailing newline. */
export function serializeManifest(manifest: BundleManifest): string {
  return `${canonicalJson(manifest)}\n`;
}

export type ManifestSource = z.infer<typeof manifestSourceSchema>;
export type ManifestDatasetSource = z.infer<typeof manifestDatasetSourceSchema>;
export type ManifestDatasetEntry = z.infer<typeof manifestDatasetSchema>;
export type ManifestSkippedDataset = z.infer<typeof manifestSkippedSchema>;
export type ManifestTotals = z.infer<typeof manifestTotalsSchema>;
export type BundleManifest = z.infer<typeof manifestSchema>;
