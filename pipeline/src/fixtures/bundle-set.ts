import { BUNDLE_MODES, type BundleMode } from "../bundle/manifest.js";
import type { BundleInput, BundleDatasetSource, BundleSourceMeta } from "../bundle/writer.js";
import {
  isNormalizeDataset,
  normalizeDataset,
  type BundleRecord,
  type NormalizeDataset,
} from "../normalize/index.js";
import {
  listFixtureFiles,
  readFixtureManifest,
  type FixtureManifest,
} from "../schemas/fixtures.js";
import { datasetForFixturePath } from "../schemas/registry.js";
import { loadLocalizedFixture } from "./load.js";

/**
 * Adapt the committed upstream fixtures into bundle-writer input.
 *
 * Everything here is offline: it localizes and validates each fixture with the
 * same loader the golden tests use, normalizes it, and copies the upstream
 * source timestamps recorded in the fixture set's manifest. Datasets with a
 * fixture but no registered normalizer (for example `pvp-season/season`) are
 * intentionally not part of the bundle.
 */

/** Datasets with a committed base fixture and a registered normalizer, sorted. */
export async function fixtureBundleDatasets(mode: BundleMode): Promise<NormalizeDataset[]> {
  const names = new Set<string>();
  for (const file of await listFixtureFiles()) {
    if (file.fixtureSet !== mode || file.kind !== "base") continue;
    const dataset = datasetForFixturePath(file.pathWithinSet);
    if (isNormalizeDataset(dataset)) names.add(dataset);
  }
  return [...names].sort() as NormalizeDataset[];
}

/** Modes whose committed fixture sets can produce a bundle, in mode order. */
export async function fixtureBundleModes(): Promise<BundleMode[]> {
  const files = await listFixtureFiles();
  return BUNDLE_MODES.filter((mode) => {
    return files.some((file) => {
      if (file.fixtureSet !== mode || file.kind !== "base") return false;
      return isNormalizeDataset(datasetForFixturePath(file.pathWithinSet));
    });
  });
}

function sourceMetaFor(
  manifest: FixtureManifest,
  datasets: readonly NormalizeDataset[],
): BundleSourceMeta {
  const entries: Record<string, BundleDatasetSource> = {};
  for (const dataset of datasets) {
    const file = manifest.files[`${dataset}.json`];
    if (file === undefined) continue;
    entries[dataset] = {
      url: file.source ?? null,
      lastModified: file.lastModified ?? null,
      etag: file.etag ?? null,
      fetchedAt: file.fetchedAt ?? null,
    };
  }

  return {
    baseUrl: manifest.sourceBaseUrl ?? null,
    capturedAt: manifest.capturedAt ?? null,
    datasets: entries,
  };
}

/** Build writer input from the committed fixtures of one mode. */
export async function loadFixtureBundleInput(mode: BundleMode): Promise<BundleInput> {
  const datasets = await fixtureBundleDatasets(mode);
  const manifest = await readFixtureManifest(mode);

  const recordsByDataset: Record<string, readonly BundleRecord[]> = {};
  for (const dataset of datasets) {
    const fixture = await loadLocalizedFixture(mode, dataset);
    recordsByDataset[dataset] = normalizeDataset(dataset, fixture.data).records;
  }

  return {
    mode,
    datasets: recordsByDataset,
    sourceMeta: sourceMetaFor(manifest, datasets),
  };
}
