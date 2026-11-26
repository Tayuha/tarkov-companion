import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import {
  DEFAULT_MAX_COMPRESSED_BYTES,
  DEFAULT_MAX_MISSING_KEYS,
  compressZstd,
  gateBundle,
  manifestSchema,
  type BundleManifest,
  type DatasetLocalizationMetrics,
  type GateIssueCode,
} from "./index.js";

/**
 * Offline tests for the publication gate.
 *
 * The clean case uses the committed hand-built bundle; the failure cases build
 * a synthetic manifest or a mutated payload, so nothing here touches the
 * network. The CLI tests run the real entry point in a temp directory.
 */

const PIPELINE_ROOT = fileURLToPath(new URL("../..", import.meta.url));
const FIXTURE_DIR = fileURLToPath(
  new URL("../../../test/fixtures/handbuilt-bundle/", import.meta.url),
);
const GATE_CLI = join(PIPELINE_ROOT, "src/cli/gate.ts");

const tempDirs: string[] = [];

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "tarkov-gate-"));
  tempDirs.push(dir);
  return dir;
}

afterAll(async () => {
  await Promise.all(tempDirs.map((dir) => rm(dir, { recursive: true, force: true })));
});

function sha256(data: Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

interface LoadedBundle {
  readonly manifestText: string;
  readonly manifest: BundleManifest;
  readonly files: Map<string, Uint8Array>;
}

async function loadBundle(dir: string): Promise<LoadedBundle> {
  const manifestText = await readFile(join(dir, "manifest.json"), "utf8");
  const manifest = manifestSchema.parse(JSON.parse(manifestText) as unknown);
  const files = new Map<string, Uint8Array>();
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!entry.isFile() || entry.name === "manifest.json") continue;
    files.set(entry.name, await readFile(join(dir, entry.name)));
  }
  return { manifestText, manifest, files };
}

function firstEntry(manifest: BundleManifest): BundleManifest["datasets"][number] {
  const entry = manifest.datasets[0];
  if (entry === undefined) throw new Error("fixture manifest has no dataset");
  return entry;
}

/** A manifest whose datasets declare the given compressed sizes, with no files. */
async function manifestWithSizes(sizes: readonly number[]): Promise<BundleManifest> {
  const loaded = await loadBundle(FIXTURE_DIR);
  const template = firstEntry(loaded.manifest);
  const datasets = sizes.map((compressedBytes, index) => ({
    ...template,
    dataset: `synthetic-${String(index)}`,
    path: `synthetic-${String(index)}.jsonl.zst`,
    compressedBytes,
  }));

  return manifestSchema.parse({
    ...loaded.manifest,
    datasets,
    totals: {
      datasets: datasets.length,
      records: datasets.reduce((sum, entry) => sum + entry.records, 0),
      uncompressedBytes: datasets.reduce((sum, entry) => sum + entry.uncompressedBytes, 0),
      compressedBytes: datasets.reduce((sum, entry) => sum + entry.compressedBytes, 0),
    },
  });
}

/** Replace the hand-built payload and keep every manifest field consistent. */
async function bundleWithPayload(
  jsonl: string,
): Promise<{ readonly manifest: BundleManifest; readonly files: Map<string, Uint8Array> }> {
  const loaded = await loadBundle(FIXTURE_DIR);
  const payload = Buffer.from(jsonl, "utf8");
  const frame = compressZstd(payload);
  const entry = firstEntry(loaded.manifest);

  entry.compressedBytes = frame.byteLength;
  entry.uncompressedBytes = payload.byteLength;
  entry.sha256 = sha256(frame);
  entry.records = jsonl.trimEnd().split("\n").length;
  loaded.manifest.totals = {
    datasets: loaded.manifest.datasets.length,
    records: loaded.manifest.datasets.reduce((sum, item) => sum + item.records, 0),
    uncompressedBytes: loaded.manifest.datasets.reduce(
      (sum, item) => sum + item.uncompressedBytes,
      0,
    ),
    compressedBytes: loaded.manifest.datasets.reduce(
      (sum, item) => sum + item.compressedBytes,
      0,
    ),
  };

  const files = new Map(loaded.files);
  files.set("items.jsonl.zst", frame);
  return { manifest: loaded.manifest, files };
}

function localization(
  dataset: string,
  values: {
    readonly missingKeys?: number;
    readonly failedPaths?: DatasetLocalizationMetrics["failedPaths"];
    readonly stalePointers?: readonly string[];
  } = {},
): DatasetLocalizationMetrics {
  return {
    dataset,
    translated: 10,
    visited: 10,
    missingKeys: values.missingKeys ?? 0,
    failedPaths: values.failedPaths ?? [],
    stalePointers: [...(values.stalePointers ?? [])],
  };
}

function failureCodes(result: ReturnType<typeof gateBundle>): GateIssueCode[] {
  return result.failures.map((entry) => entry.code);
}

function warningCodes(result: ReturnType<typeof gateBundle>): GateIssueCode[] {
  return result.warnings.map((entry) => entry.code);
}

describe("gateBundle", () => {
  it("passes the clean hand-built bundle", async () => {
    const loaded = await loadBundle(FIXTURE_DIR);
    const result = gateBundle({
      manifest: loaded.manifest,
      files: loaded.files,
      localization: [localization("items")],
    });

    expect(result.ok).toBe(true);
    expect(result.failures).toEqual([]);
    expect(result.warnings).toEqual([]);
    expect(result.metrics.compressedBytes).toBe(169);
    expect(result.metrics.maxCompressedBytes).toBe(DEFAULT_MAX_COMPRESSED_BYTES);
    expect(result.metrics.maxMissingKeys).toBe(DEFAULT_MAX_MISSING_KEYS);
  });

  it("fails a synthetic manifest whose compressed datasets exceed the budget", async () => {
    const manifest = await manifestWithSizes([
      6 * 1024 * 1024,
      6 * 1024 * 1024,
    ]);
    const result = gateBundle({ manifest });

    expect(result.ok).toBe(false);
    expect(failureCodes(result)).toEqual(["compressed-size"]);
    expect(result.metrics.compressedBytes).toBe(12 * 1024 * 1024);
    expect(result.metrics.maxCompressedBytes).toBe(10 * 1024 * 1024);
  });

  it("passes a manifest whose compressed datasets are exactly at the budget", async () => {
    const manifest = await manifestWithSizes([
      5 * 1024 * 1024,
      5 * 1024 * 1024,
    ]);
    const result = gateBundle({ manifest });

    expect(result.metrics.compressedBytes).toBe(DEFAULT_MAX_COMPRESSED_BYTES);
    expect(result.ok).toBe(true);
    expect(result.failures).toEqual([]);
  });

  it("honors a custom --max-bytes budget", async () => {
    const manifest = await manifestWithSizes([169]);
    expect(gateBundle({ manifest, maxCompressedBytes: 168 }).ok).toBe(false);
    expect(gateBundle({ manifest, maxCompressedBytes: 169 }).ok).toBe(true);
  });

  it("fails on missing dictionary keys and passes with zero", async () => {
    const manifest = await manifestWithSizes([169]);
    const missing = gateBundle({
      manifest,
      localization: [localization("items", { missingKeys: 1 })],
    });
    const covered = gateBundle({
      manifest,
      localization: [localization("items", { missingKeys: 0 })],
    });

    expect(missing.ok).toBe(false);
    expect(failureCodes(missing)).toEqual(["missing-keys"]);
    expect(missing.metrics.missingKeys).toBe(1);
    expect(covered.ok).toBe(true);
  });

  it("allows a raised missing-key threshold", async () => {
    const manifest = await manifestWithSizes([169]);
    const result = gateBundle({
      manifest,
      localization: [localization("items", { missingKeys: 2 })],
      maxMissingKeys: 2,
    });

    expect(result.ok).toBe(true);
    expect(result.metrics.maxMissingKeys).toBe(2);
  });

  it("fails when a placeholder survives in a JSONL asset", async () => {
    const { manifest, files } = await bundleWithPayload(
      '{"id":"example","kind":"item","name":"5447a9cd4bdc2dbd208b4567 Name"}\n',
    );
    const result = gateBundle({ manifest, files });

    expect(result.ok).toBe(false);
    expect(failureCodes(result)).toContain("placeholder");
    expect(result.failures[0]?.message).toContain("unresolved localization placeholder");
  });

  it("fails on unparsable translation pointers", async () => {
    const manifest = await manifestWithSizes([169]);
    const result = gateBundle({
      manifest,
      localization: [
        localization("tasks", {
          failedPaths: [{ path: "$.[", error: "unexpected token" }],
        }),
      ],
    });

    expect(result.ok).toBe(false);
    expect(failureCodes(result)).toEqual(["failed-path"]);
    expect(result.metrics.failedPaths).toBe(1);
  });

  it("warns about stale pointers without failing", async () => {
    const manifest = await manifestWithSizes([169]);
    const result = gateBundle({
      manifest,
      localization: [
        localization("tasks", {
          stalePointers: ["$.data.tasks.*.story", "$.data.tasks.*.finishRewards"],
        }),
      ],
    });

    expect(result.ok).toBe(true);
    expect(failureCodes(result)).toEqual([]);
    expect(warningCodes(result)).toEqual(["stale-pointer"]);
    expect(result.metrics.stalePointers).toBe(2);
  });

  it("warns about skipped datasets and inactive prune candidates", async () => {
    const loaded = await loadBundle(FIXTURE_DIR);
    loaded.manifest.skipped = [{ dataset: "tasks", reason: "not-supplied" }];
    loaded.files.set("old-tasks.jsonl.zst", new Uint8Array([1, 2, 3]));

    const result = gateBundle({ manifest: loaded.manifest, files: loaded.files });

    expect(result.ok).toBe(true);
    expect(warningCodes(result)).toContain("skipped-dataset");
    expect(warningCodes(result)).toContain("prune-candidate");
    expect(result.metrics.skippedDatasets).toBe(1);
    expect(result.metrics.pruneCandidates).toBe(1);
  });
});

interface CliResult {
  readonly status: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

function runGateCli(args: readonly string[]): CliResult {
  const result = spawnSync(process.execPath, ["--import", "tsx", GATE_CLI, ...args], {
    cwd: PIPELINE_ROOT,
    encoding: "utf8",
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

interface GateJsonOutput {
  readonly dir: string;
  readonly manifest: string;
  readonly report: string | null;
  readonly mode: string;
  readonly ok: boolean;
  readonly failures: readonly { readonly code: string; readonly message: string }[];
  readonly warnings: readonly { readonly code: string; readonly message: string }[];
  readonly metrics: {
    readonly compressedBytes: number;
    readonly maxCompressedBytes: number;
    readonly missingKeys: number;
    readonly stalePointers: number;
  };
}

async function writeReport(
  entries: readonly DatasetLocalizationMetrics[],
  mode = "regular",
): Promise<string> {
  const dir = await tempDir();
  const path = join(dir, "sync-report.json");
  await writeFile(
    path,
    JSON.stringify({
      generatedAt: "2026-11-26T00:00:00.000Z",
      modes: [
        {
          mode,
          localization: entries,
        },
      ],
      exitCode: 0,
    }),
    "utf8",
  );
  return path;
}

describe("gate CLI", () => {
  it("exits 0 for the clean hand-built bundle", () => {
    const result = runGateCli(["--dir", FIXTURE_DIR]);

    expect(result.status).toBe(0);
    expect(result.stdout).toContain("PASS");
    expect(result.stdout).toContain("regular");
  });

  it("prints the machine-readable shape with --json", () => {
    const result = runGateCli(["--dir", FIXTURE_DIR, "--json"]);

    expect(result.status).toBe(0);
    const output = JSON.parse(result.stdout) as GateJsonOutput;
    expect(output.ok).toBe(true);
    expect(output.mode).toBe("regular");
    expect(output.failures).toEqual([]);
    expect(output.metrics.compressedBytes).toBe(169);
    expect(output.metrics.maxCompressedBytes).toBe(DEFAULT_MAX_COMPRESSED_BYTES);
    expect(output.manifest.endsWith("manifest.json")).toBe(true);
  });

  it("exits 1 when the budget is exceeded", () => {
    const result = runGateCli(["--dir", FIXTURE_DIR, "--max-bytes", "100", "--json"]);

    expect(result.status).toBe(1);
    const output = JSON.parse(result.stdout) as GateJsonOutput;
    expect(output.ok).toBe(false);
    expect(output.failures.map((entry) => entry.code)).toContain("compressed-size");
  });

  it("consumes localization stats from a sync report", async () => {
    const report = await writeReport([localization("items", { missingKeys: 2 })]);
    const result = runGateCli(["--dir", FIXTURE_DIR, "--report", report, "--json"]);

    expect(result.status).toBe(1);
    const output = JSON.parse(result.stdout) as GateJsonOutput;
    expect(output.failures.map((entry) => entry.code)).toContain("missing-keys");
    expect(output.metrics.missingKeys).toBe(2);
    expect(output.report).toBe(report);
  });

  it("passes with a clean sync report", async () => {
    const report = await writeReport([
      localization("items", { stalePointers: ["$.data.items.*.description"] }),
    ]);
    const result = runGateCli(["--dir", FIXTURE_DIR, "--report", report]);

    expect(result.status).toBe(0);
    expect(result.stdout).toContain("stale 1");
  });

  it("exits 2 on missing or invalid input", async () => {
    expect(runGateCli([]).status).toBe(2);
    expect(runGateCli(["--dir", join(tmpdir(), "does-not-exist-gate")]).status).toBe(2);
    expect(runGateCli(["--dir", FIXTURE_DIR, "--max-bytes", "nope"]).status).toBe(2);

    const wrongMode = await writeReport([localization("items")], "pve");
    expect(runGateCli(["--dir", FIXTURE_DIR, "--report", wrongMode]).status).toBe(2);
  });
});
