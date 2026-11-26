import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { cp, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import {
  compressZstd,
  decompressZstd,
  manifestSchema,
  serializeManifest,
  validateBundle,
  type BundleManifest,
  type BundleValidationCode,
  type BundleValidationResult,
} from "./index.js";

/**
 * Offline tests for the bundle validator.
 *
 * The committed `test/fixtures/handbuilt-bundle/` was built by hand exactly as
 * `docs/data-bundles.md` describes: two JSONL records, a zstd frame compressed
 * at level 3, a SHA-256 over the compressed bytes, and a manifest with the
 * matching sizes and counts. The valid case checks that the documented
 * arithmetic is what the validator expects; the remaining cases mutate a copy
 * and prove each failure mode is reported.
 */

const PIPELINE_ROOT = fileURLToPath(new URL("../..", import.meta.url));
const FIXTURE_DIR = fileURLToPath(new URL("../../../test/fixtures/handbuilt-bundle/", import.meta.url));
const VALIDATE_CLI = join(PIPELINE_ROOT, "src/cli/validate-bundle.ts");

const tempDirs: string[] = [];

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "tarkov-validate-"));
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
  readonly files: ReadonlyMap<string, Uint8Array>;
  readonly extraFiles: readonly string[];
}

async function loadBundle(dir: string): Promise<LoadedBundle> {
  const manifestText = await readFile(join(dir, "manifest.json"), "utf8");
  const files = new Map<string, Uint8Array>();
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    if (!entry.isFile() || entry.name === "manifest.json") continue;
    files.set(entry.name, await readFile(join(dir, entry.name)));
  }
  const referenced = new Set(files.keys());
  return { manifestText, files, extraFiles: [...referenced].sort() };
}

async function validateDir(dir: string): Promise<BundleValidationResult> {
  const loaded = await loadBundle(dir);
  return validateBundle(loaded);
}

async function copyFixture(): Promise<string> {
  const dir = await tempDir();
  await cp(FIXTURE_DIR, dir, { recursive: true });
  return dir;
}

async function readManifest(dir: string): Promise<BundleManifest> {
  const text = await readFile(join(dir, "manifest.json"), "utf8");
  return manifestSchema.parse(JSON.parse(text) as unknown);
}

async function writeManifest(dir: string, manifest: BundleManifest): Promise<void> {
  await writeFile(join(dir, "manifest.json"), serializeManifest(manifest));
}

function firstDataset(manifest: BundleManifest): BundleManifest["datasets"][number] {
  const entry = manifest.datasets[0];
  if (entry === undefined) throw new Error("fixture manifest has no dataset");
  return entry;
}

/** Replace the payload and keep every manifest field consistent with it. */
async function rewritePayload(dir: string, jsonl: string): Promise<void> {
  const payload = Buffer.from(jsonl, "utf8");
  const frame = compressZstd(payload);
  await writeFile(join(dir, "items.jsonl.zst"), frame);

  const manifest = await readManifest(dir);
  const entry = firstDataset(manifest);
  entry.compressedBytes = frame.byteLength;
  entry.uncompressedBytes = payload.byteLength;
  entry.sha256 = sha256(frame);
  entry.records = jsonl === "" ? 0 : jsonl.trimEnd().split("\n").length;
  await writeManifest(dir, manifest);
}

/** Replace the page bytes and make the manifest describe exactly those bytes. */
async function replaceFrame(dir: string, frame: Uint8Array): Promise<void> {
  await writeFile(join(dir, "items.jsonl.zst"), frame);
  const manifest = await readManifest(dir);
  const entry = firstDataset(manifest);
  entry.compressedBytes = frame.byteLength;
  entry.sha256 = sha256(frame);
  await writeManifest(dir, manifest);
}

function codes(result: BundleValidationResult): BundleValidationCode[] {
  return result.errors.map((entry) => entry.code);
}

function expectFailure(result: BundleValidationResult, code: BundleValidationCode): void {
  expect(result.ok, `expected failure with ${code}`).toBe(false);
  expect(codes(result), `expected ${code}`).toContain(code);
}

interface CliResult {
  readonly status: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

function runCli(args: readonly string[]): CliResult {
  const result = spawnSync(process.execPath, ["--import", "tsx", VALIDATE_CLI, ...args], {
    cwd: PIPELINE_ROOT,
    encoding: "utf8",
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

describe("hand-built bundle", () => {
  it("follows the documented arithmetic and passes validation", async () => {
    const manifest = await readManifest(FIXTURE_DIR);
    const entry = firstDataset(manifest);
    const bytes = await readFile(join(FIXTURE_DIR, entry.path));

    expect(entry.path).toBe("items.jsonl.zst");
    expect(entry.compressedBytes).toBe(bytes.byteLength);
    expect(entry.sha256).toBe(sha256(bytes));

    const jsonl = decompressZstd(bytes).toString("utf8");
    expect(jsonl.endsWith("\n")).toBe(true);
    expect(jsonl.trimEnd().split("\n")).toHaveLength(entry.records);
    expect(Buffer.byteLength(jsonl, "utf8")).toBe(entry.uncompressedBytes);

    expect(manifest.totals).toEqual({
      datasets: manifest.datasets.length,
      records: entry.records,
      uncompressedBytes: entry.uncompressedBytes,
      compressedBytes: entry.compressedBytes,
    });

    const result = await validateDir(FIXTURE_DIR);
    expect(result.ok).toBe(true);
    expect(result.errors).toEqual([]);
    expect(result.warnings).toEqual([]);
    expect(result.mode).toBe("regular");
    expect(result.datasets).toEqual([
      {
        dataset: "items",
        path: "items.jsonl.zst",
        ok: true,
        records: 2,
        compressedBytes: entry.compressedBytes,
        sha256: entry.sha256,
      },
    ]);
  });

  it("reports unknown extra files as warnings without failing", async () => {
    const dir = await copyFixture();
    await writeFile(join(dir, "notes.txt"), "kept next to the bundle\n");

    const result = await validateDir(dir);
    expect(result.ok).toBe(true);
    expect(result.warnings.map((entry) => entry.code)).toContain("extra-file");
  });
});

describe("validator failure modes", () => {
  it("detects a missing dataset file", async () => {
    const dir = await copyFixture();
    await rm(join(dir, "items.jsonl.zst"));
    expectFailure(await validateDir(dir), "missing-file");
  });

  it("detects a checksum mismatch", async () => {
    const dir = await copyFixture();
    const manifest = await readManifest(dir);
    firstDataset(manifest).sha256 = "0".repeat(64);
    await writeManifest(dir, manifest);
    expectFailure(await validateDir(dir), "sha256-mismatch");
  });

  it("detects a compressed size mismatch", async () => {
    const dir = await copyFixture();
    const manifest = await readManifest(dir);
    const entry = firstDataset(manifest);
    entry.compressedBytes += 1;
    await writeManifest(dir, manifest);
    expectFailure(await validateDir(dir), "size-mismatch");
  });

  it("detects a corrupt zstd frame", async () => {
    const dir = await copyFixture();
    await replaceFrame(dir, Buffer.from("this is not a zstd frame", "utf8"));
    expectFailure(await validateDir(dir), "zstd-error");
  });

  it("detects invalid JSONL", async () => {
    const dir = await copyFixture();
    await rewritePayload(dir, '{"id":"example-ammo","kind":"item"}\nnot json\n');
    expectFailure(await validateDir(dir), "invalid-jsonl");
  });

  it("detects a record without kind or id", async () => {
    const dir = await copyFixture();
    await rewritePayload(dir, '{"name":"no kind"}\n');
    expectFailure(await validateDir(dir), "invalid-record");
  });

  it("detects a duplicate kind+id", async () => {
    const dir = await copyFixture();
    await rewritePayload(
      dir,
      '{"id":"same","kind":"item"}\n{"id":"same","kind":"item"}\n',
    );
    expectFailure(await validateDir(dir), "duplicate-record");
  });

  it("detects a record count mismatch", async () => {
    const dir = await copyFixture();
    const manifest = await readManifest(dir);
    firstDataset(manifest).records = 3;
    await writeManifest(dir, manifest);
    expectFailure(await validateDir(dir), "record-count-mismatch");
  });

  it("detects an unresolved localization placeholder", async () => {
    const dir = await copyFixture();
    await rewritePayload(
      dir,
      '{"id":"example-ammo","kind":"item","name":"5447a9cd4bdc2dbd208b4567 Name"}\n',
    );
    expectFailure(await validateDir(dir), "placeholder");
  });

  it("detects minAppSchemaVersion below a dataset schema", async () => {
    const dir = await copyFixture();
    const manifest = await readManifest(dir);
    firstDataset(manifest).schemaVersion = 2;
    await writeManifest(dir, manifest);
    expectFailure(await validateDir(dir), "min-app-schema-mismatch");
  });

  it("detects a traversal path", async () => {
    const dir = await copyFixture();
    const manifest = await readManifest(dir);
    firstDataset(manifest).path = "../items.jsonl.zst";
    await writeManifest(dir, manifest);
    expectFailure(await validateDir(dir), "unsafe-path");
  });

  it("rejects a manifest that does not match the schema", async () => {
    const dir = await copyFixture();
    await writeFile(join(dir, "manifest.json"), '{"manifestVersion":1}\n');
    expectFailure(await validateDir(dir), "invalid-manifest");
  });
});

describe("validate:bundle CLI", () => {
  it("passes the committed hand-built bundle", () => {
    const result = runCli(["--dir", FIXTURE_DIR]);
    expect(result.status).toBe(0);
    expect(result.stdout).toContain("PASS: 1 dataset(s), 0 error(s)");
    expect(result.stderr).toBe("");
  });

  it("prints machine-readable JSON with --json", () => {
    const result = runCli(["--dir", FIXTURE_DIR, "--json"]);
    expect(result.status).toBe(0);

    const report = JSON.parse(result.stdout) as {
      readonly ok: boolean;
      readonly mode: string;
      readonly datasets: ReadonlyArray<{ readonly dataset: string }>;
      readonly errors: readonly unknown[];
    };
    expect(report.ok).toBe(true);
    expect(report.mode).toBe("regular");
    expect(report.datasets.map((entry) => entry.dataset)).toEqual(["items"]);
    expect(report.errors).toEqual([]);
  });

  it("exits 1 and names the failure with --json", async () => {
    const dir = await copyFixture();
    const manifest = await readManifest(dir);
    firstDataset(manifest).sha256 = "0".repeat(64);
    await writeManifest(dir, manifest);

    const result = runCli(["--dir", dir, "--json"]);
    expect(result.status).toBe(1);

    const report = JSON.parse(result.stdout) as {
      readonly ok: boolean;
      readonly errors: ReadonlyArray<{ readonly code: string }>;
    };
    expect(report.ok).toBe(false);
    expect(report.errors.map((entry) => entry.code)).toContain("sha256-mismatch");
  });

  it("exits 1 when the directory has no manifest", async () => {
    const dir = await tempDir();
    const result = runCli(["--dir", dir]);
    expect(result.status).toBe(1);
    expect(result.stderr).toContain("manifest.json not found");
  });
});
