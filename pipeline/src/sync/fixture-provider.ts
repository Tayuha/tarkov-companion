import { BUNDLE_MODES, type BundleMode } from "../bundle/index.js";
import { isNormalizeDataset, type NormalizeDataset } from "../normalize/index.js";
import { loadLocalizedFixtureFrom } from "../fixtures/load.js";
import {
  listFixtureFiles,
  readFixtureManifest,
  type FixtureFile,
  type FixtureManifest,
} from "../schemas/fixtures.js";
import { canonicalSha256 } from "../util/canonical.js";
import type { DatasetFetchResult, DatasetProvider } from "./types.js";

/**
 * Offline provider reading a committed fixture set.
 *
 * `--fixtures <dir>` uses it for local verification and tests. Every fixture is
 * localized and schema-validated by the same loader the golden tests use, so an
 * offline run exercises the real normalization path without a socket.
 */

function bundleDatasetOf(file: FixtureFile): NormalizeDataset | null {
  if (file.kind !== "base" || file.pathWithinSet.includes("/")) return null;
  const dataset = file.pathWithinSet.replace(/\.json$/, "");
  return isNormalizeDataset(dataset) ? dataset : null;
}

export class FixtureDatasetProvider implements DatasetProvider {
  readonly root: string;
  #files: Promise<readonly FixtureFile[]> | undefined;
  readonly #manifests = new Map<string, Promise<FixtureManifest>>();

  constructor(options: { readonly root: string }) {
    this.root = options.root;
  }

  #allFiles(): Promise<readonly FixtureFile[]> {
    this.#files ??= listFixtureFiles(this.root);
    return this.#files;
  }

  #manifest(mode: BundleMode): Promise<FixtureManifest> {
    let manifest = this.#manifests.get(mode);
    if (manifest === undefined) {
      manifest = readFixtureManifest(mode, this.root);
      this.#manifests.set(mode, manifest);
    }
    return manifest;
  }

  async modes(): Promise<readonly BundleMode[]> {
    const files = await this.#allFiles();
    return BUNDLE_MODES.filter((mode) =>
      files.some((file) => file.fixtureSet === mode && bundleDatasetOf(file) !== null),
    );
  }

  async datasets(mode: BundleMode): Promise<readonly NormalizeDataset[]> {
    const files = await this.#allFiles();
    const names = new Set<NormalizeDataset>();
    for (const file of files) {
      if (file.fixtureSet !== mode) continue;
      const dataset = bundleDatasetOf(file);
      if (dataset !== null) names.add(dataset);
    }
    return [...names].sort();
  }

  async source(mode: BundleMode): Promise<{
    baseUrl: string | null;
    capturedAt: string | null;
  }> {
    const manifest = await this.#manifest(mode);
    return {
      baseUrl: manifest.sourceBaseUrl ?? null,
      capturedAt: manifest.capturedAt ?? null,
    };
  }

  async fetch(input: {
    readonly mode: BundleMode;
    readonly dataset: NormalizeDataset;
    readonly forceRefresh: boolean;
  }): Promise<DatasetFetchResult> {
    const fixture = await loadLocalizedFixtureFrom(this.root, input.mode, input.dataset);
    const manifest = await this.#manifest(input.mode);
    const file = manifest.files[`${input.dataset}.json`];

    return {
      status: "modified",
      data: fixture.data,
      checksum: canonicalSha256(fixture.data),
      localization: fixture.stats,
      meta: {
        url: file?.source ?? null,
        etag: file?.etag ?? null,
        lastModified: file?.lastModified ?? null,
        fetchedAt: file?.fetchedAt ?? null,
      },
    };
  }
}
