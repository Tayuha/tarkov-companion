import { createHash } from "node:crypto";
import { mkdir, readdir, rename, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import {
  NORMALIZE_DATASETS,
  isNormalizeDataset,
  serializeJsonl,
  type BundleRecord,
  type NormalizeDataset,
} from "../normalize/index.js";
import { assertBundleRecords } from "../normalize/contract.js";
import {
  BUNDLE_SCHEMA_VERSION,
  DATASET_FILE_SUFFIX,
  MANIFEST_FILE,
  MANIFEST_VERSION,
  MIN_APP_SCHEMA_VERSION,
  datasetSchemaVersion,
  isBundleMode,
  manifestSchema,
  serializeManifest,
  type BundleManifest,
  type BundleMode,
  type ManifestDatasetEntry,
  type ManifestSkippedDataset,
} from "./manifest.js";
import { compressZstd } from "./zstd.js";

/**
 * Bundle writer.
 *
 * Input is already normalized, schema-validated data. The writer is pure with
 * respect to the data: it takes the generation timestamp from the caller, does
 * no network I/O, and serializes with stable ordering, so identical input
 * always produces identical `.jsonl.zst` bytes and SHA-256 checksums.
 *
 * Layout (relative to `outDir`):
 *
 *   <mode>/manifest.json
 *   <mode>/<dataset>.jsonl.zst
 *
 * Manifest `path` values are relative to the manifest's own directory, so a
 * client can concatenate its base URL with the path.
 *
 * Missing datasets (keys absent from `datasets`) are skipped and recorded under
 * `skipped`. An explicitly supplied dataset with zero records fails the build:
 * publishing an empty file would erase the client's rows, and upstream
 * emptiness is far more likely a bug than truth.
 */

/** Upstream source metadata for one dataset, as recorded in the fixture manifest. */
export interface BundleDatasetSource {
  readonly url?: string | null;
  readonly lastModified?: string | null;
  readonly etag?: string | null;
  readonly fetchedAt?: string | null;
}

export interface BundleSourceMeta {
  readonly baseUrl?: string | null;
  readonly capturedAt?: string | null;
  readonly datasets?: Readonly<Record<string, BundleDatasetSource | undefined>>;
}

export interface BundleInput {
  readonly mode: BundleMode;
  readonly datasets: Readonly<Record<string, readonly BundleRecord[]>>;
  readonly sourceMeta: BundleSourceMeta;
}

export interface BundleArtifact {
  readonly dataset: NormalizeDataset;
  /** File name relative to the manifest, e.g. `items.jsonl.zst`. */
  readonly path: string;
  readonly jsonl: string;
  readonly records: number;
  readonly uncompressedBytes: number;
  readonly compressedBytes: number;
  readonly sha256: string;
  readonly compressed: Buffer;
}

export interface BuiltBundle {
  readonly mode: BundleMode;
  readonly artifacts: readonly BundleArtifact[];
  readonly manifest: BundleManifest;
  readonly manifestJson: string;
}

export interface WriteBundleOptions {
  /** Root directory; the mode directory is created inside it. */
  readonly outDir: string;
}

export interface WrittenBundle {
  readonly modeDir: string;
  readonly manifestPath: string;
  readonly artifacts: readonly BundleArtifact[];
}

function sha256Hex(data: Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

function datasetSource(
  sourceMeta: BundleSourceMeta,
  dataset: NormalizeDataset,
): ManifestDatasetEntry["source"] {
  const source = sourceMeta.datasets?.[dataset];
  return {
    url: source?.url ?? null,
    lastModified: source?.lastModified ?? null,
    etag: source?.etag ?? null,
    fetchedAt: source?.fetchedAt ?? null,
  };
}

/**
 * Serialize and compress every supplied dataset, then assemble the manifest.
 *
 * `generatedAt` is supplied by the caller (the CLI uses the wall clock) so the
 * writer itself never reads a clock and tests can compare manifests directly.
 */
export function buildBundle(input: BundleInput, generatedAt: string): BuiltBundle {
  if (!isBundleMode(input.mode)) {
    throw new Error(`unknown bundle mode "${String(input.mode)}"`);
  }

  const names = Object.keys(input.datasets).sort();

  const artifacts: BundleArtifact[] = [];
  for (const name of names) {
    if (!isNormalizeDataset(name)) {
      throw new Error(`unknown bundle dataset "${name}"`);
    }
    const dataset: NormalizeDataset = name;
    const records = input.datasets[name];
    if (records === undefined) continue;
    if (records.length === 0) {
      throw new Error(`${input.mode}/${dataset}: refusing to write an empty dataset`);
    }

    assertBundleRecords(dataset, records);

    // `serializeJsonl` sorts by `kind` then `id`, so record order in the
    // caller's array cannot change the bytes.
    const jsonl = serializeJsonl(records);
    const jsonlBytes = Buffer.from(jsonl, "utf8");
    const compressed = compressZstd(jsonlBytes);

    artifacts.push({
      dataset,
      path: `${dataset}${DATASET_FILE_SUFFIX}`,
      jsonl,
      records: records.length,
      uncompressedBytes: jsonlBytes.byteLength,
      compressedBytes: compressed.byteLength,
      sha256: sha256Hex(compressed),
      compressed,
    });
  }

  const present = new Set(artifacts.map((artifact) => artifact.dataset));
  const skipped: ManifestSkippedDataset[] = NORMALIZE_DATASETS.filter(
    (dataset) => !present.has(dataset),
  ).map((dataset) => ({ dataset, reason: "not-supplied" }));

  const entries: ManifestDatasetEntry[] = artifacts.map((artifact) => ({
    dataset: artifact.dataset,
    path: artifact.path,
    schemaVersion: datasetSchemaVersion(artifact.dataset),
    sha256: artifact.sha256,
    compressedBytes: artifact.compressedBytes,
    uncompressedBytes: artifact.uncompressedBytes,
    records: artifact.records,
    source: datasetSource(input.sourceMeta, artifact.dataset),
  }));

  const manifest: BundleManifest = manifestSchema.parse({
    manifestVersion: MANIFEST_VERSION,
    bundleSchemaVersion: BUNDLE_SCHEMA_VERSION,
    minAppSchemaVersion: Math.max(
      MIN_APP_SCHEMA_VERSION,
      ...entries.map((entry) => entry.schemaVersion),
    ),
    mode: input.mode,
    generatedAt,
    source: {
      baseUrl: input.sourceMeta.baseUrl ?? null,
      capturedAt: input.sourceMeta.capturedAt ?? null,
    },
    totals: {
      datasets: entries.length,
      records: entries.reduce((sum, entry) => sum + entry.records, 0),
      uncompressedBytes: entries.reduce((sum, entry) => sum + entry.uncompressedBytes, 0),
      compressedBytes: entries.reduce((sum, entry) => sum + entry.compressedBytes, 0),
    },
    datasets: entries,
    skipped,
  });

  return {
    mode: input.mode,
    artifacts,
    manifest,
    manifestJson: serializeManifest(manifest),
  };
}

async function writeFileAtomic(path: string, data: Uint8Array | string): Promise<void> {
  const temporary = `${path}.tmp`;
  await writeFile(temporary, data);
  try {
    await rename(temporary, path);
  } catch (error) {
    await rm(temporary, { force: true });
    throw error;
  }
}

/**
 * Write the built bundle. Dataset files are written first and the manifest
 * last, each through a temporary file plus rename, so a reader never sees a
 * manifest pointing at a half-written dataset.
 *
 * Stale `*.jsonl.zst` files in the mode directory that this build no longer
 * produces are removed; nothing else in the directory is touched.
 */
export async function writeBundle(
  bundle: BuiltBundle,
  options: WriteBundleOptions,
): Promise<WrittenBundle> {
  const modeDir = join(options.outDir, bundle.mode);
  await mkdir(modeDir, { recursive: true });

  const keep = new Set(bundle.artifacts.map((artifact) => artifact.path));
  for (const entry of await readdir(modeDir, { withFileTypes: true })) {
    if (
      entry.isFile() &&
      entry.name.endsWith(DATASET_FILE_SUFFIX) &&
      !keep.has(entry.name)
    ) {
      await rm(join(modeDir, entry.name), { force: true });
    }
  }

  for (const artifact of bundle.artifacts) {
    await writeFileAtomic(join(modeDir, artifact.path), artifact.compressed);
  }

  const manifestPath = join(modeDir, MANIFEST_FILE);
  await writeFileAtomic(manifestPath, bundle.manifestJson);

  return { modeDir, manifestPath, artifacts: bundle.artifacts };
}
