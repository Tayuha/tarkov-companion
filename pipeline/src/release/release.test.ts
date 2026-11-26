import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import {
  BUNDLE_SCHEMA_VERSION,
  MANIFEST_FILE,
  MANIFEST_VERSION,
  ManifestError,
  manifestSchema,
  serializeManifest,
  type BundleManifest,
  type BundleMode,
} from "../bundle/index.js";
import {
  DATASET_ASSET_SUFFIX,
  DEFAULT_REPOSITORY,
  MemoryReleaseClient,
  ReleaseError,
  assertTagMatchesMode,
  datasetAssetName,
  defaultTag,
  describePublication,
  planPublication,
  preparePublishedManifest,
  publicationReport,
  publishBundle,
  resolveGhEnvironment,
  stableManifestUrl,
  validateMode,
  validateTag,
  type ReleaseErrorKind,
} from "./index.js";

/**
 * Offline publication tests.
 *
 * Planning is pure, so most cases build small synthetic bundles with real file
 * bytes and a schema-valid manifest; the publisher then runs against
 * `MemoryReleaseClient`, which records every create/upload/delete in order.
 * Nothing here touches the network or the `gh` binary; the one CLI case that
 * needs `gh` deliberately clears PATH to prove the typed "gh not found" error.
 */

const PIPELINE_ROOT = fileURLToPath(new URL("../..", import.meta.url));
const PUBLISH_CLI = join(PIPELINE_ROOT, "src/cli/publish.ts");
const FIXED_TIME = "2026-11-25T20:00:00.000Z";
const TEST_TAG = "data-test-regular-latest";

const tempDirs: string[] = [];

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "tarkov-release-"));
  tempDirs.push(dir);
  return dir;
}

afterAll(async () => {
  await Promise.all(tempDirs.map((dir) => rm(dir, { recursive: true, force: true })));
});

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

interface BundleSeed {
  readonly dataset: string;
  /** Changing the seed changes the dataset bytes and therefore its checksum. */
  readonly seed: string;
  readonly records?: number;
}

interface WriteBundleOptions {
  readonly mode?: BundleMode;
  /** Write a manifest of another mode into the requested mode directory. */
  readonly manifestMode?: BundleMode;
  readonly generatedAt?: string;
}

async function writeBundle(
  root: string,
  seeds: readonly BundleSeed[],
  options: WriteBundleOptions = {},
): Promise<BundleManifest> {
  const mode = options.mode ?? "regular";
  const manifestMode = options.manifestMode ?? mode;
  const modeDir = join(root, mode);
  await mkdir(modeDir, { recursive: true });

  const datasets = [];
  for (const seed of [...seeds].sort((left, right) => left.dataset.localeCompare(right.dataset))) {
    const bytes = Buffer.from(`payload:${seed.dataset}:${seed.seed}\n`, "utf8");
    await writeFile(join(modeDir, `${seed.dataset}${DATASET_ASSET_SUFFIX}`), bytes);
    datasets.push({
      dataset: seed.dataset,
      path: `${seed.dataset}${DATASET_ASSET_SUFFIX}`,
      schemaVersion: 1,
      sha256: sha256(bytes),
      compressedBytes: bytes.byteLength,
      uncompressedBytes: bytes.byteLength * 2,
      records: seed.records ?? 1,
      source: {
        url: `https://json.tarkov.dev/${mode}/${seed.dataset}`,
        lastModified: "Wed, 25 Nov 2026 12:00:00 GMT",
        etag: `W/"${seed.seed}"`,
        fetchedAt: "2026-11-25T12:00:00.000Z",
      },
    });
  }

  const manifest = manifestSchema.parse({
    manifestVersion: MANIFEST_VERSION,
    bundleSchemaVersion: BUNDLE_SCHEMA_VERSION,
    minAppSchemaVersion: 1,
    mode: manifestMode,
    generatedAt: options.generatedAt ?? FIXED_TIME,
    source: {
      baseUrl: "https://json.tarkov.dev",
      capturedAt: "2026-11-25T12:00:00.000Z",
    },
    totals: {
      datasets: datasets.length,
      records: datasets.reduce((sum, entry) => sum + entry.records, 0),
      uncompressedBytes: datasets.reduce((sum, entry) => sum + entry.uncompressedBytes, 0),
      compressedBytes: datasets.reduce((sum, entry) => sum + entry.compressedBytes, 0),
    },
    datasets,
    skipped: [],
  });

  await writeFile(join(modeDir, MANIFEST_FILE), serializeManifest(manifest));
  return manifest;
}

function remoteAssets(manifest: BundleManifest): {
  id: number;
  name: string;
  size: number;
}[] {
  return manifest.datasets.map((entry, index) => ({
    id: index + 1,
    name: datasetAssetName(entry),
    size: entry.compressedBytes,
  }));
}

function publishedManifest(manifest: BundleManifest): BundleManifest {
  return preparePublishedManifest(manifest).manifest;
}

function assetName(manifest: BundleManifest, index: number): string {
  const entry = manifest.datasets[index];
  if (entry === undefined) throw new Error(`dataset ${String(index)} is missing from the manifest`);
  return datasetAssetName(entry);
}

async function readPublishedManifest(
  client: MemoryReleaseClient,
  tag: string,
): Promise<BundleManifest> {
  const bytes = await client.downloadAsset({ tag, name: MANIFEST_FILE });
  if (bytes === null) throw new Error("published manifest is missing");
  return manifestSchema.parse(JSON.parse(Buffer.from(bytes).toString("utf8")));
}

function uploadNames(plan: ReturnType<typeof planPublication>): string[] {
  return plan.uploads.map((step) => step.name);
}

async function expectReleaseError(
  promise: Promise<unknown>,
  kind: ReleaseErrorKind,
): Promise<ReleaseError> {
  const error = await promise.then(
    () => undefined,
    (reason: unknown) => reason,
  );
  expect(error, "expected a ReleaseError").toBeInstanceOf(ReleaseError);
  if (!(error instanceof ReleaseError)) throw new Error("unreachable");
  expect(error.kind).toBe(kind);
  expect(error.message.length).toBeGreaterThan(0);
  return error;
}

interface CliResult {
  readonly status: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

function runCli(args: readonly string[], env: NodeJS.ProcessEnv = process.env): CliResult {
  const result = spawnSync(process.execPath, ["--import", "tsx", PUBLISH_CLI, ...args], {
    cwd: PIPELINE_ROOT,
    encoding: "utf8",
    env,
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

describe("asset naming and manifest rewriting", () => {
  it("derives a content-addressed, flat asset name from the first 12 checksum characters", () => {
    expect(
      datasetAssetName({
        dataset: "items",
        sha256: "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
      }),
    ).toBe(`items-abcdef012345${DATASET_ASSET_SUFFIX}`);
  });

  it("rewrites every manifest path to the versioned asset name and preserves content fields", () => {
    const manifest = manifestSchema.parse({
      manifestVersion: MANIFEST_VERSION,
      bundleSchemaVersion: BUNDLE_SCHEMA_VERSION,
      minAppSchemaVersion: 1,
      mode: "regular",
      generatedAt: FIXED_TIME,
      source: { baseUrl: null, capturedAt: null },
      totals: { datasets: 1, records: 1, uncompressedBytes: 10, compressedBytes: 5 },
      datasets: [
        {
          dataset: "items",
          path: "items.jsonl.zst",
          schemaVersion: 1,
          sha256: "a".repeat(64),
          compressedBytes: 5,
          uncompressedBytes: 10,
          records: 1,
          source: { url: null, lastModified: null, etag: null, fetchedAt: null },
        },
      ],
      skipped: [],
    });

    const prepared = preparePublishedManifest(manifest);

    expect(prepared.manifest.datasets[0]?.path).toBe(`items-aaaaaaaaaaaa${DATASET_ASSET_SUFFIX}`);
    expect(prepared.manifest.datasets[0]?.sha256).toBe("a".repeat(64));
    expect(prepared.manifest.datasets[0]?.compressedBytes).toBe(5);
    expect(prepared.json.endsWith("\n")).toBe(true);
    expect(prepared.bytes.byteLength).toBe(Buffer.byteLength(prepared.json));
  });

  it("builds the documented stable URL", () => {
    expect(stableManifestUrl("data-regular-latest", DEFAULT_REPOSITORY)).toBe(
      "https://github.com/Tayuha/tarkov-companion/releases/download/data-regular-latest/manifest.json",
    );
    expect(defaultTag("pve")).toBe("data-pve-latest");
  });
});

describe("tag, mode and environment validation", () => {
  it("accepts stable and custom tags and rejects unsafe ref names", () => {
    for (const tag of ["data-regular-latest", TEST_TAG, "data-2026.11.25"]) {
      expect(validateTag(tag)).toBe(tag);
    }
    for (const tag of ["", "-leading", "has space", "a..b", "tag.lock", "x".repeat(101), "a/b"]) {
      expect(() => validateTag(tag)).toThrow(ReleaseError);
    }
  });

  it("refuses to publish a mode onto another mode's stable tag", () => {
    expect(() => assertTagMatchesMode("data-pve-latest", "regular")).toThrow(
      /belongs to mode "pve", not "regular"/,
    );
    expect(() => assertTagMatchesMode(TEST_TAG, "regular")).not.toThrow();
    expect(() => assertTagMatchesMode("data-regular-latest", "regular")).not.toThrow();
  });

  it("validates the three bundle modes", () => {
    expect(validateMode("regular")).toBe("regular");
    expect(validateMode("pve")).toBe("pve");
    expect(validateMode("pvp-season")).toBe("pvp-season");
    expect(() => validateMode("hardcore")).toThrow(/unknown mode "hardcore"/);
  });

  it("maps a lone GITHUB_TOKEN to GH_TOKEN without overriding GH_TOKEN", () => {
    expect(resolveGhEnvironment({})).toEqual({});
    expect(resolveGhEnvironment({ GITHUB_TOKEN: "ghs_test" })).toMatchObject({
      GITHUB_TOKEN: "ghs_test",
      GH_TOKEN: "ghs_test",
    });
    expect(resolveGhEnvironment({ GH_TOKEN: "ghp_one", GITHUB_TOKEN: "ghs_two" })).toEqual({
      GH_TOKEN: "ghp_one",
      GITHUB_TOKEN: "ghs_two",
    });
  });
});

describe("planPublication", () => {
  it("publishes every dataset first and the manifest last on a first publication", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [
      { dataset: "tasks", seed: "tasks" },
      { dataset: "items", seed: "items" },
    ]);

    const plan = planPublication(manifest, null, []);

    expect(uploadNames(plan)).toEqual([
      `items-${manifest.datasets[0]?.sha256.slice(0, 12)}${DATASET_ASSET_SUFFIX}`,
      `tasks-${manifest.datasets[1]?.sha256.slice(0, 12)}${DATASET_ASSET_SUFFIX}`,
      MANIFEST_FILE,
    ]);
    expect(plan.manifestAction).toBe("upload");
    expect(plan.manifestReason).toBe("no published manifest");
    expect(plan.skip).toEqual([]);
    expect(plan.prune).toEqual([]);
    expect(plan.comparison).toBeNull();
    expect(plan.noop).toBe(false);
  });

  it("is a no-op when the published manifest and every asset already match", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "tasks", seed: "tasks" },
    ]);

    const plan = planPublication(
      manifest,
      publishedManifest(manifest),
      remoteAssets(manifest),
    );

    expect(plan.uploads).toEqual([]);
    expect(plan.skip).toHaveLength(2);
    expect(plan.skip.every((entry) => entry.reason === "asset already published with matching size")).toBe(
      true,
    );
    expect(plan.manifestAction).toBe("skip");
    expect(plan.manifestReason).toBe("bundle content unchanged");
    expect(plan.noop).toBe(true);
  });

  it("uploads only the changed immutable asset plus the manifest", async () => {
    const root = await tempDir();
    const first = await writeBundle(root, [
      { dataset: "items", seed: "items-v1" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const second = await writeBundle(root, [
      { dataset: "items", seed: "items-v2" },
      { dataset: "tasks", seed: "tasks" },
    ]);

    const plan = planPublication(second, publishedManifest(first), remoteAssets(first));

    expect(uploadNames(plan)).toEqual([
      assetName(second, 0),
      MANIFEST_FILE,
    ]);
    expect(plan.skip.map((entry) => entry.dataset)).toEqual(["tasks"]);
    expect(plan.manifestReason).toBe("bundle content changed (1 changed)");
    expect(plan.noop).toBe(false);
  });

  it("handles an added dataset and lists the removed dataset's asset as prunable", async () => {
    const root = await tempDir();
    const first = await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const second = await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "maps", seed: "maps" },
    ]);

    const plan = planPublication(second, publishedManifest(first), remoteAssets(first));

    expect(plan.uploads.map((step) => step.kind === "dataset" ? step.dataset : step.kind)).toEqual([
      "maps",
      "manifest",
    ]);
    expect(plan.skip.map((entry) => entry.dataset)).toEqual(["items"]);
    expect(plan.prune).toEqual([assetName(first, 1)]);
    expect(plan.manifestReason).toBe("bundle content changed (1 added, 1 removed)");
  });

  it("never treats manifest.json or non-dataset assets as prune candidates", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [{ dataset: "items", seed: "items" }]);

    const plan = planPublication(manifest, publishedManifest(manifest), [
      ...remoteAssets(manifest),
      { id: 10, name: MANIFEST_FILE, size: 10 },
      { id: 11, name: "notes.txt", size: 10 },
      { id: 12, name: `tasks-aaaaaaaaaaaa${DATASET_ASSET_SUFFIX}`, size: 10 },
    ]);

    expect(plan.prune).toEqual([`tasks-aaaaaaaaaaaa${DATASET_ASSET_SUFFIX}`]);
  });

  it("counts requested pruning when deciding whether the plan is a no-op", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [{ dataset: "items", seed: "items" }]);
    const remote = publishedManifest(manifest);
    const assets = [
      ...remoteAssets(manifest),
      { id: 9, name: `tasks-aaaaaaaaaaaa${DATASET_ASSET_SUFFIX}`, size: 10 },
    ];

    expect(planPublication(manifest, remote, assets).noop).toBe(true);

    const pruning = planPublication(manifest, remote, assets, { prune: true });
    expect(pruning.prune).toEqual([`tasks-aaaaaaaaaaaa${DATASET_ASSET_SUFFIX}`]);
    expect(pruning.noop).toBe(false);
  });

  it("updates the manifest when the published paths are not versioned yet", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [{ dataset: "items", seed: "items" }]);

    const plan = planPublication(manifest, manifest, remoteAssets(manifest));

    expect(plan.skip).toHaveLength(1);
    expect(uploadNames(plan)).toEqual([MANIFEST_FILE]);
    expect(plan.manifestReason).toBe("published manifest does not use versioned asset paths");
  });

  it("repairs a missing dataset asset without replacing an unchanged manifest", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [{ dataset: "items", seed: "items" }]);

    const plan = planPublication(manifest, publishedManifest(manifest), []);

    expect(uploadNames(plan)).toEqual([assetName(manifest, 0)]);
    expect(plan.manifestAction).toBe("skip");
    expect(plan.noop).toBe(false);
  });

  it("re-uploads an asset whose published size does not match", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [{ dataset: "items", seed: "items" }]);
    const assets = remoteAssets(manifest);
    const first = assets[0];
    if (first === undefined) throw new Error("missing asset");
    assets[0] = { ...first, size: first.size + 1 };

    const plan = planPublication(manifest, publishedManifest(manifest), assets);

    expect(uploadNames(plan)).toEqual([
      assetName(manifest, 0),
    ]);
    expect(plan.uploads[0]?.reason).toContain("does not match");
    expect(plan.manifestAction).toBe("skip");
  });
});

describe("publishBundle", () => {
  it("creates the release, uploads datasets in order, and swaps the manifest last", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const client = new MemoryReleaseClient();

    const result = await publishBundle({
      bundlesDir: root,
      mode: "regular",
      tag: TEST_TAG,
      client,
    });

    expect(result.release).toEqual({ existed: false, created: true });
    expect(result.mutations).toBe(4); // 1 create + 2 datasets + 1 manifest
    expect(client.mutationCalls.map((call) => `${call.operation}:${String(call.name)}`)).toEqual([
      "create:undefined",
      `upload:${assetName(manifest, 0)}`,
      `upload:${assetName(manifest, 1)}`,
      `upload:${MANIFEST_FILE}`,
    ]);

    const published = await readPublishedManifest(client, TEST_TAG);
    expect(published.datasets.map((entry) => entry.path)).toEqual(
      manifest.datasets.map((entry) => datasetAssetName(entry)),
    );
    for (const [index, entry] of published.datasets.entries()) {
      expect(entry.sha256).toBe(manifest.datasets[index]?.sha256);
      expect(entry.compressedBytes).toBe(manifest.datasets[index]?.compressedBytes);

      const name = datasetAssetName(entry);
      const uploaded = await client.downloadAsset({ tag: TEST_TAG, name });
      const onDisk = await readFile(join(root, "regular", `${entry.dataset}${DATASET_ASSET_SUFFIX}`));
      expect(uploaded, name).not.toBeNull();
      if (uploaded === null) throw new Error("unreachable");
      expect(Buffer.from(uploaded).equals(onDisk)).toBe(true);
    }
  });

  it("makes zero mutations on an identical second run even when generatedAt moved", async () => {
    const root = await tempDir();
    const seeds = [
      { dataset: "items", seed: "items" },
      { dataset: "tasks", seed: "tasks" },
    ];
    await writeBundle(root, seeds, { generatedAt: FIXED_TIME });
    const client = new MemoryReleaseClient();

    await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });
    const before = client.mutations;

    await writeBundle(root, seeds, { generatedAt: "2026-11-26T00:00:00.000Z" });
    const second = await publishBundle({
      bundlesDir: root,
      mode: "regular",
      tag: TEST_TAG,
      client,
    });

    expect(second.plan.noop).toBe(true);
    expect(second.mutations).toBe(0);
    expect(second.uploaded).toEqual([]);
    expect(second.deleted).toEqual([]);
    expect(second.release).toEqual({ existed: true, created: false });
    expect(client.mutations).toBe(before);
    expect(describePublication(second).at(-1)).toBe("no changes: nothing published");
  });

  it("publishes one changed dataset plus the manifest and leaves the old asset in place", async () => {
    const root = await tempDir();
    const first = await writeBundle(root, [
      { dataset: "items", seed: "items-v1" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const client = new MemoryReleaseClient();
    await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });
    const oldItemsName = assetName(first, 0);

    const second = await writeBundle(root, [
      { dataset: "items", seed: "items-v2" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const result = await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });

    const newItemsName = assetName(second, 0);
    expect(result.uploaded).toEqual([newItemsName, MANIFEST_FILE]);
    expect(result.plan.skip.map((entry) => entry.dataset)).toEqual(["tasks"]);
    expect(result.mutations).toBe(2);

    const release = await client.getRelease(TEST_TAG);
    const names = release?.assets.map((asset) => asset.name) ?? [];
    expect(names).toContain(oldItemsName);
    expect(names).toContain(newItemsName);
  });

  it("prunes unreferenced dataset assets after the manifest swap and never deletes the manifest", async () => {
    const root = await tempDir();
    const first = await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const client = new MemoryReleaseClient();
    await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });
    const oldTasksName = assetName(first, 1);
    const oldItemsName = assetName(first, 0);

    const second = await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "maps", seed: "maps" },
    ]);
    const before = client.mutationCalls.length;
    const result = await publishBundle({
      bundlesDir: root,
      mode: "regular",
      tag: TEST_TAG,
      prune: true,
      client,
    });

    const newMutations = client.mutationCalls.slice(before);
    expect(newMutations.map((call) => `${call.operation}:${String(call.name)}`)).toEqual([
      `upload:${assetName(second, 1)}`,
      `upload:${MANIFEST_FILE}`,
      `delete:${oldTasksName}`,
    ]);
    expect(result.deleted).toEqual([oldTasksName]);
    expect(result.deleted).not.toContain(MANIFEST_FILE);
    expect(result.plan.noop).toBe(false);

    const release = await client.getRelease(TEST_TAG);
    const names = release?.assets.map((asset) => asset.name) ?? [];
    expect(names).toContain(oldItemsName);
    expect(names).not.toContain(oldTasksName);
    expect(names).toContain(MANIFEST_FILE);
  });

  it("does not prune without --prune", async () => {
    const root = await tempDir();
    await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const client = new MemoryReleaseClient();
    await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });

    await writeBundle(root, [{ dataset: "items", seed: "items" }]);
    const result = await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });

    expect(result.plan.prune).toHaveLength(1);
    expect(result.plan.noop).toBe(false);
    expect(result.deleted).toEqual([]);
  });

  it("makes zero mutations in dry-run while returning the full ordered plan", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const client = new MemoryReleaseClient();

    const result = await publishBundle({
      bundlesDir: root,
      mode: "regular",
      tag: TEST_TAG,
      dryRun: true,
      client,
    });

    expect(result.dryRun).toBe(true);
    expect(result.mutations).toBe(0);
    expect(client.mutations).toBe(0);
    expect(client.operations.some((call) => call.operation === "create")).toBe(false);
    expect(result.release).toEqual({ existed: false, created: false });
    expect(result.uploaded).toEqual([]);
    expect(result.plan.uploads.map((step) => step.name)).toEqual(
      [
        ...manifest.datasets.map((entry) => datasetAssetName(entry)),
        MANIFEST_FILE,
      ],
    );
    expect(describePublication(result).at(-1)).toBe("dry-run: no API mutations performed");
  });

  it("dry-runs an existing release with a changed dataset without touching it", async () => {
    const root = await tempDir();
    await writeBundle(root, [{ dataset: "items", seed: "items-v1" }]);
    const client = new MemoryReleaseClient();
    await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });
    const mutations = client.mutations;

    await writeBundle(root, [{ dataset: "items", seed: "items-v2" }]);
    const result = await publishBundle({
      bundlesDir: root,
      mode: "regular",
      tag: TEST_TAG,
      dryRun: true,
      prune: true,
      client,
    });

    expect(result.mutations).toBe(0);
    expect(client.mutations).toBe(mutations);
    expect(result.uploaded).toEqual([]);
    expect(result.deleted).toEqual([]);
    expect(result.plan.uploads).toHaveLength(2);
  });

  it("publishes the manifest onto an existing release that only has dataset assets", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [
      { dataset: "items", seed: "items" },
      { dataset: "tasks", seed: "tasks" },
    ]);
    const client = new MemoryReleaseClient();
    client.seedRelease({
      tag: TEST_TAG,
      title: TEST_TAG,
      assets: manifest.datasets.map((entry) => ({
        name: datasetAssetName(entry),
        size: entry.compressedBytes,
      })),
    });

    const result = await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });

    expect(result.release).toEqual({ existed: true, created: false });
    expect(result.uploaded).toEqual([MANIFEST_FILE]);
    expect(result.plan.skip).toHaveLength(2);
    expect(result.mutations).toBe(1);
  });

  it("rejects a missing local manifest with a typed error", async () => {
    const root = await tempDir();
    const error = await publishBundle({
      bundlesDir: root,
      mode: "regular",
      tag: TEST_TAG,
      client: new MemoryReleaseClient(),
    }).then(
      () => undefined,
      (reason: unknown) => reason,
    );

    expect(error).toBeInstanceOf(ManifestError);
    if (!(error instanceof ManifestError)) throw new Error("unreachable");
    expect(error.kind).toBe("not-found");
  });

  it("rejects a local manifest of another mode", async () => {
    const root = await tempDir();
    await writeBundle(root, [{ dataset: "items", seed: "items" }], { manifestMode: "pve" });

    await expectReleaseError(
      publishBundle({
        bundlesDir: root,
        mode: "regular",
        tag: TEST_TAG,
        client: new MemoryReleaseClient(),
      }),
      "manifest-mismatch",
    );
  });

  it("rejects a dataset whose bytes do not match the manifest before touching the release", async () => {
    const root = await tempDir();
    await writeBundle(root, [{ dataset: "items", seed: "items" }]);
    await writeFile(join(root, "regular", `items${DATASET_ASSET_SUFFIX}`), "tampered");
    const client = new MemoryReleaseClient();

    const error = await expectReleaseError(
      publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client }),
      "dataset-mismatch",
    );

    expect(error.message).toContain("items");
    expect(client.operations).toEqual([]);
  });

  it("rejects invalid mode/tag combinations", async () => {
    const root = await tempDir();

    await expectReleaseError(
      publishBundle({
        bundlesDir: root,
        mode: "hardcore" as BundleMode,
        tag: TEST_TAG,
        client: new MemoryReleaseClient(),
      }),
      "invalid-mode",
    );
    await expectReleaseError(
      publishBundle({
        bundlesDir: root,
        mode: "regular",
        tag: "data pve latest",
        client: new MemoryReleaseClient(),
      }),
      "invalid-tag",
    );
    await expectReleaseError(
      publishBundle({
        bundlesDir: root,
        mode: "regular",
        tag: "data-pve-latest",
        client: new MemoryReleaseClient(),
      }),
      "tag-mismatch",
    );
  });
});

describe("publication report", () => {
  it("exposes the upload order with the manifest last and the mutation count", async () => {
    const root = await tempDir();
    const manifest = await writeBundle(root, [{ dataset: "items", seed: "items" }]);
    const client = new MemoryReleaseClient();
    const result = await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });
    const report = publicationReport(result);

    expect(report.mode).toBe("regular");
    expect(report.tag).toBe(TEST_TAG);
    expect(report.manifestUrl).toContain(`/download/${TEST_TAG}/manifest.json`);
    expect(report.uploadOrder).toEqual([assetName(manifest, 0), MANIFEST_FILE]);
    expect(report.uploads.at(-1)?.kind).toBe("manifest");
    expect(report.mutations).toBe(3);
    expect(report.noop).toBe(false);

    const second = await publishBundle({ bundlesDir: root, mode: "regular", tag: TEST_TAG, client });
    const noop = publicationReport(second);
    expect(noop.uploads).toEqual([]);
    expect(noop.skip).toHaveLength(1);
    expect(noop.manifestAction).toBe("skip");
    expect(noop.noop).toBe(true);
    expect(noop.mutations).toBe(0);
  });
});

describe("publish CLI without network", () => {
  it("exits 1 with a typed error for a missing mode or an unknown mode", () => {
    const missing = runCli([]);
    expect(missing.status).toBe(1);
    expect(missing.stderr).toContain("invalid-mode");
    expect(missing.stderr).toContain("--mode is required");

    const unknown = runCli(["--mode", "hardcore"]);
    expect(unknown.status).toBe(1);
    expect(unknown.stderr).toContain('unknown mode "hardcore"');
  });

  it("exits 1 before touching GitHub for an invalid tag or a missing manifest", async () => {
    const root = await tempDir();

    const invalidTag = runCli(["--mode", "regular", "--bundles", root, "--tag", "bad tag"]);
    expect(invalidTag.status).toBe(1);
    expect(invalidTag.stderr).toContain("invalid-tag");

    const mismatch = runCli([
      "--mode",
      "regular",
      "--bundles",
      root,
      "--tag",
      "data-pve-latest",
    ]);
    expect(mismatch.status).toBe(1);
    expect(mismatch.stderr).toContain("tag-mismatch");

    const missing = runCli(["--mode", "regular", "--bundles", root]);
    expect(missing.status).toBe(1);
    expect(missing.stderr).toContain("not-found");
    expect(missing.stderr).toContain("manifest not found");
  });

  it("exits 1 with a typed error when gh is not installed", async () => {
    const root = await tempDir();
    await writeBundle(root, [{ dataset: "items", seed: "items" }]);

    const result = runCli(["--mode", "regular", "--bundles", root, "--dry-run"], {
      ...process.env,
      PATH: "",
    });

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("gh-not-found");
    expect(result.stderr).toContain("GitHub CLI");
    // The local bundle is valid, so the failure is the missing binary, not data.
    expect(existsSync(join(root, "regular", MANIFEST_FILE))).toBe(true);
  });
});
