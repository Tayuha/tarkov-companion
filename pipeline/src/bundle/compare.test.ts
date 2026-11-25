import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import {
  BUNDLE_SCHEMA_VERSION,
  MANIFEST_VERSION,
  ManifestError,
  compareBundles,
  describeComparison,
  loadPreviousManifest,
  manifestSchema,
  readManifestFile,
  resolveManifestPath,
  serializeManifest,
  type BundleManifest,
  type BundleMode,
  type ManifestErrorKind,
} from "./index.js";

/**
 * Offline tests for dataset comparison and no-op gating.
 *
 * Comparison is pure, so most cases use small synthetic manifests instead of
 * full builds. The CLI cases run the real entry points against temp dirs: a
 * second `bundle --previous` run over identical fixtures must write nothing and
 * exit 0.
 */

const PIPELINE_ROOT = fileURLToPath(new URL("../..", import.meta.url));
const COMPARE_CLI = join(PIPELINE_ROOT, "src/cli/compare.ts");
const BUNDLE_CLI = join(PIPELINE_ROOT, "src/cli/bundle.ts");

const FIXED_TIME = "2026-11-25T20:00:00.000Z";

const tempDirs: string[] = [];

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "tarkov-compare-"));
  tempDirs.push(dir);
  return dir;
}

afterAll(async () => {
  await Promise.all(tempDirs.map((dir) => rm(dir, { recursive: true, force: true })));
});

function sha(seed: string): string {
  return createHash("sha256").update(seed).digest("hex");
}

interface DatasetSeed {
  readonly dataset: string;
  /** Changing the seed changes the (fake) content checksum. */
  readonly seed: string;
  readonly schemaVersion?: number;
  readonly fetchedAt?: string | null;
}

interface ManifestOptions {
  readonly mode?: BundleMode;
  readonly bundleSchemaVersion?: number;
  readonly minAppSchemaVersion?: number;
  readonly generatedAt?: string;
  readonly capturedAt?: string;
  readonly datasets?: readonly DatasetSeed[];
}

const DEFAULT_DATASETS: readonly DatasetSeed[] = [
  { dataset: "items", seed: "items" },
  { dataset: "tasks", seed: "tasks" },
];

/** A schema-valid manifest with one entry per seeded dataset. */
function makeManifest(options: ManifestOptions = {}): BundleManifest {
  const datasets = (options.datasets ?? DEFAULT_DATASETS).map((entry) => ({
    dataset: entry.dataset,
    path: `${entry.dataset}.jsonl.zst`,
    schemaVersion: entry.schemaVersion ?? 1,
    sha256: sha(entry.seed),
    compressedBytes: 100,
    uncompressedBytes: 200,
    records: 3,
    source: {
      url: `https://json.tarkov.dev/regular/${entry.dataset}`,
      lastModified: "Wed, 25 Nov 2026 12:00:00 GMT",
      etag: `W/"${entry.seed}"`,
      fetchedAt: entry.fetchedAt === undefined ? "2026-11-25T12:00:00.000Z" : entry.fetchedAt,
    },
  }));

  return manifestSchema.parse({
    manifestVersion: MANIFEST_VERSION,
    bundleSchemaVersion: options.bundleSchemaVersion ?? BUNDLE_SCHEMA_VERSION,
    minAppSchemaVersion: options.minAppSchemaVersion ?? 1,
    mode: options.mode ?? "regular",
    generatedAt: options.generatedAt ?? FIXED_TIME,
    source: {
      baseUrl: "https://json.tarkov.dev",
      capturedAt: options.capturedAt ?? "2026-11-25T12:00:00.000Z",
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
}

async function writeManifest(path: string, manifest: BundleManifest): Promise<string> {
  await mkdir(join(path, ".."), { recursive: true });
  await writeFile(path, serializeManifest(manifest));
  return path;
}

async function expectManifestError(
  promise: Promise<unknown>,
  kind: ManifestErrorKind,
): Promise<ManifestError> {
  const error = await promise.then(
    () => undefined,
    (reason: unknown) => reason,
  );
  expect(error, "expected a ManifestError").toBeInstanceOf(ManifestError);
  if (!(error instanceof ManifestError)) throw new Error("unreachable");
  expect(error.kind).toBe(kind);
  expect(error.message.length).toBeGreaterThan(0);
  return error;
}

interface CliResult {
  readonly status: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

/** Run a pipeline CLI with tsx, exactly as `npm run <script>` would. */
function runCli(cli: string, args: readonly string[]): CliResult {
  const result = spawnSync(process.execPath, ["--import", "tsx", cli, ...args], {
    cwd: PIPELINE_ROOT,
    encoding: "utf8",
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

describe("compareBundles classification", () => {
  it("reports no changes for identical content and lists every dataset as unchanged", () => {
    const comparison = compareBundles(makeManifest(), makeManifest());

    expect(comparison.hasChanges).toBe(false);
    expect(comparison.added).toEqual([]);
    expect(comparison.changed).toEqual([]);
    expect(comparison.removed).toEqual([]);
    expect(comparison.unchanged).toEqual(["items", "tasks"]);
    expect(Object.keys(comparison.reasons)).toEqual(["items", "tasks"]);
    expect(comparison.reasons["items"]).toMatch(/matches/);
    expect(describeComparison(comparison)[0]).toBe("no changes: all 2 dataset(s) unchanged");
  });

  it("ignores generatedAt, source timestamps and other non-content metadata", () => {
    const previous = makeManifest({ generatedAt: "2026-11-25T20:00:00.000Z" });
    const current = makeManifest({
      generatedAt: "2026-11-25T23:59:59.000Z",
      capturedAt: "2026-11-25T23:00:00.000Z",
      datasets: [
        { dataset: "items", seed: "items", fetchedAt: "2026-11-25T23:00:00.000Z" },
        { dataset: "tasks", seed: "tasks", fetchedAt: null },
      ],
    });

    expect(current.generatedAt).not.toBe(previous.generatedAt);
    expect(current.source.capturedAt).not.toBe(previous.source.capturedAt);
    expect(current.datasets[0]?.source.fetchedAt).not.toBe(previous.datasets[0]?.source.fetchedAt);

    const comparison = compareBundles(previous, current);
    expect(comparison.hasChanges).toBe(false);
    expect(comparison.changed).toEqual([]);
    expect(comparison.unchanged).toEqual(["items", "tasks"]);
  });

  it("classifies exactly the dataset whose checksum changed", () => {
    const comparison = compareBundles(
      makeManifest(),
      makeManifest({
        datasets: [
          { dataset: "items", seed: "items-v2" },
          { dataset: "tasks", seed: "tasks" },
        ],
      }),
    );

    expect(comparison.hasChanges).toBe(true);
    expect(comparison.changed).toEqual(["items"]);
    expect(comparison.unchanged).toEqual(["tasks"]);
    expect(comparison.added).toEqual([]);
    expect(comparison.removed).toEqual([]);
    expect(comparison.reasons["items"]).toMatch(/^sha256 [0-9a-f]{12} -> [0-9a-f]{12}$/);
  });

  it("classifies added and removed datasets explicitly", () => {
    const comparison = compareBundles(
      makeManifest({
        datasets: [
          { dataset: "items", seed: "items" },
          { dataset: "tasks", seed: "tasks" },
        ],
      }),
      makeManifest({
        datasets: [
          { dataset: "items", seed: "items" },
          { dataset: "maps", seed: "maps" },
        ],
      }),
    );

    expect(comparison.hasChanges).toBe(true);
    expect(comparison.added).toEqual(["maps"]);
    expect(comparison.removed).toEqual(["tasks"]);
    expect(comparison.changed).toEqual([]);
    expect(comparison.unchanged).toEqual(["items"]);
    expect(comparison.reasons["maps"]).toBe("not present in previous manifest");
    expect(comparison.reasons["tasks"]).toBe("not present in current manifest");
  });

  it("treats every dataset as changed when bundleSchemaVersion changes", () => {
    const comparison = compareBundles(
      makeManifest({ bundleSchemaVersion: BUNDLE_SCHEMA_VERSION }),
      makeManifest({ bundleSchemaVersion: BUNDLE_SCHEMA_VERSION + 1 }),
    );

    expect(comparison.hasChanges).toBe(true);
    expect(comparison.changed).toEqual(["items", "tasks"]);
    expect(comparison.unchanged).toEqual([]);
    for (const name of comparison.changed) {
      expect(comparison.reasons[name]).toMatch(/client contract changed \(bundleSchemaVersion 1 -> 2\)/);
    }
  });

  it("treats every dataset as changed when minAppSchemaVersion changes", () => {
    const comparison = compareBundles(
      makeManifest({ minAppSchemaVersion: 1 }),
      makeManifest({ minAppSchemaVersion: 2 }),
    );

    expect(comparison.changed).toEqual(["items", "tasks"]);
    for (const name of comparison.changed) {
      expect(comparison.reasons[name]).toMatch(/minAppSchemaVersion 1 -> 2/);
    }
  });

  it("rejects a schema-invalid manifest instead of comparing it", () => {
    const invalid = { manifestVersion: MANIFEST_VERSION } as unknown as BundleManifest;
    expect(() => compareBundles(invalid, makeManifest())).toThrow(ManifestError);
    expect(() => compareBundles(makeManifest(), invalid)).toThrow(/current manifest is not a valid/);
  });

  it("rejects comparing manifests from different modes", () => {
    expect(() => compareBundles(makeManifest({ mode: "regular" }), makeManifest({ mode: "pve" }))).toThrow(
      /cannot compare mode "regular" with mode "pve"/,
    );
  });
});

describe("manifest loading", () => {
  it("loads a manifest file and resolves a bundles root or mode directory", async () => {
    const root = await tempDir();
    const manifest = makeManifest();
    const manifestPath = await writeManifest(join(root, "regular", "manifest.json"), manifest);

    expect(await resolveManifestPath(manifestPath, "regular")).toBe(manifestPath);
    expect(await resolveManifestPath(root, "regular")).toBe(manifestPath);
    expect(await resolveManifestPath(join(root, "regular"), "regular")).toBe(manifestPath);

    const loaded = await loadPreviousManifest(root, "regular");
    expect(loaded.path).toBe(manifestPath);
    expect(loaded.manifest).toEqual(manifest);
  });

  it("fails with a typed error for a missing previous manifest", async () => {
    const root = await tempDir();
    const error = await expectManifestError(
      loadPreviousManifest(join(root, "nothing-here"), "regular"),
      "not-found",
    );
    expect(error.message).toContain('no manifest for mode "regular"');

    await expectManifestError(
      readManifestFile(join(root, "regular", "manifest.json")),
      "not-found",
    );
  });

  it("fails with a typed error for malformed JSON", async () => {
    const root = await tempDir();
    const path = join(root, "manifest.json");
    await writeFile(path, "{ not json");

    const error = await expectManifestError(readManifestFile(path), "invalid-json");
    expect(error.message).toContain("is not valid JSON");
  });

  it("fails with a typed error for a manifest that misses required fields", async () => {
    const root = await tempDir();
    const path = join(root, "manifest.json");
    await writeFile(path, JSON.stringify({ manifestVersion: MANIFEST_VERSION }));

    const error = await expectManifestError(readManifestFile(path), "invalid-schema");
    expect(error.message).toContain("is not a valid bundle manifest");
  });

  it("fails with a typed error when the previous manifest is for another mode", async () => {
    const root = await tempDir();
    const path = await writeManifest(join(root, "pve", "manifest.json"), makeManifest({ mode: "pve" }));

    const error = await expectManifestError(loadPreviousManifest(path, "regular"), "mode-mismatch");
    expect(error.message).toContain('is for mode "pve", not "regular"');
  });
});

describe("compare CLI", () => {
  it("exits 0 and prints no changes for identical manifests", async () => {
    const root = await tempDir();
    const previous = await writeManifest(join(root, "previous.json"), makeManifest());
    const current = await writeManifest(
      join(root, "current.json"),
      makeManifest({ generatedAt: "2026-11-26T00:00:00.000Z" }),
    );

    const result = runCli(COMPARE_CLI, ["--previous", previous, "--current", current]);

    expect(result.stderr).toBe("");
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("no changes: all 2 dataset(s) unchanged");
  });

  it("exits 0 with changes and emits the documented --json shape", async () => {
    const root = await tempDir();
    const previous = await writeManifest(join(root, "previous.json"), makeManifest());
    const current = await writeManifest(
      join(root, "current.json"),
      makeManifest({
        datasets: [
          { dataset: "items", seed: "items-v2" },
          { dataset: "tasks", seed: "tasks" },
          { dataset: "maps", seed: "maps" },
        ],
      }),
    );

    const result = runCli(COMPARE_CLI, ["--previous", previous, "--current", current, "--json"]);

    expect(result.status).toBe(0);
    const report = JSON.parse(result.stdout) as Record<string, unknown>;
    expect(Object.keys(report).sort()).toEqual(
      [
        "added",
        "changed",
        "current",
        "hasChanges",
        "mode",
        "previous",
        "reasons",
        "removed",
        "unchanged",
      ].sort(),
    );
    expect(report["mode"]).toBe("regular");
    expect(report["hasChanges"]).toBe(true);
    expect(report["changed"]).toEqual(["items"]);
    expect(report["added"]).toEqual(["maps"]);
    expect(report["unchanged"]).toEqual(["tasks"]);
    expect(report["removed"]).toEqual([]);
    expect(report["previous"]).toMatchObject({ path: previous, generatedAt: FIXED_TIME });
    expect(report["current"]).toMatchObject({ path: current });

    const reasons = report["reasons"] as Record<string, string>;
    expect(Object.keys(reasons).sort()).toEqual(["items", "maps", "tasks"]);
  });

  it("exits non-zero on a missing previous manifest", async () => {
    const root = await tempDir();
    const current = await writeManifest(join(root, "current.json"), makeManifest());

    const result = runCli(COMPARE_CLI, [
      "--previous",
      join(root, "missing.json"),
      "--current",
      current,
    ]);

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("not-found");
    expect(result.stderr).toContain("manifest not found");
  });

  it("exits non-zero when an argument is missing", () => {
    const result = runCli(COMPARE_CLI, ["--current", "whatever.json"]);
    expect(result.status).toBe(1);
    expect(result.stderr).toContain("--previous");
  });
});

describe("bundle CLI --previous", () => {
  it("writes nothing and exits 0 when the second run has no changes", async () => {
    const root = await tempDir();
    const firstOut = join(root, "first");
    const secondOut = join(root, "second");

    const first = runCli(BUNDLE_CLI, ["--mode", "regular", "--out", firstOut]);
    expect(first.stderr).toBe("");
    expect(first.status).toBe(0);
    const previousManifest = join(firstOut, "regular", "manifest.json");
    expect(existsSync(previousManifest)).toBe(true);

    // A bundles root, the documented directory form.
    const second = runCli(BUNDLE_CLI, [
      "--mode",
      "regular",
      "--out",
      secondOut,
      "--previous",
      firstOut,
    ]);

    expect(second.stderr).toBe("");
    expect(second.status).toBe(0);
    expect(second.stdout).toContain("no changes");
    expect(second.stdout).toContain(previousManifest);
    expect(existsSync(secondOut), "the no-op run must not create the output directory").toBe(false);
  });

  it("writes the full bundle and reports changed datasets and reasons", async () => {
    const root = await tempDir();
    const firstOut = join(root, "first");
    const secondOut = join(root, "second");

    expect(runCli(BUNDLE_CLI, ["--mode", "regular", "--out", firstOut]).status).toBe(0);

    // Pretend the previously published items dataset had different content.
    const original = JSON.parse(
      await readFile(join(firstOut, "regular", "manifest.json"), "utf8"),
    ) as BundleManifest;
    const edited: BundleManifest = {
      ...original,
      datasets: original.datasets.map((entry) =>
        entry.dataset === "items" ? { ...entry, sha256: sha("items-edited") } : entry,
      ),
    };
    const previousPath = await writeManifest(join(root, "previous.json"), edited);

    const run = runCli(BUNDLE_CLI, [
      "--mode",
      "regular",
      "--out",
      secondOut,
      "--previous",
      previousPath,
    ]);

    expect(run.stderr).toBe("");
    expect(run.status).toBe(0);
    expect(run.stdout).toContain("changes");
    expect(run.stdout).toContain("changed");
    expect(run.stdout).toContain("items");
    expect(run.stdout).toContain("sha256");

    const files = await readdir(join(secondOut, "regular"));
    expect(files).toContain("manifest.json");
    expect(files).toContain("items.jsonl.zst");
    expect(files.some((file) => file.endsWith(".tmp"))).toBe(false);
  });

  it("fails with a typed error when the previous manifest is missing", async () => {
    const root = await tempDir();
    const result = runCli(BUNDLE_CLI, [
      "--mode",
      "regular",
      "--out",
      join(root, "out"),
      "--previous",
      join(root, "missing"),
    ]);

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("not-found");
    expect(existsSync(join(root, "out"))).toBe(false);
  });
});
