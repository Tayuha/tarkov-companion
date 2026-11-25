import { createHash } from "node:crypto";
import { mkdir, mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import type { BundleInput } from "./writer.js";
import { buildBundle, writeBundle } from "./writer.js";
import {
  BUNDLE_SCHEMA_VERSION,
  MANIFEST_VERSION,
  ZSTD_COMPRESSION_LEVEL,
  decompressZstd,
  manifestSchema,
  type BundleMode,
} from "./index.js";
import type { BundleRecord } from "../normalize/index.js";
import { canonicalJson } from "../util/canonical.js";
import { loadFixtureBundleInput } from "../fixtures/bundle-set.js";

/**
 * Offline tests for the bundle writer.
 *
 * Determinism is the contract: the same committed fixtures must always produce
 * the same `.jsonl.zst` bytes and SHA-256 checksums. `generatedAt` is the only
 * value allowed to differ between runs, so the tests compare dataset payloads
 * and checksums rather than the manifest timestamp.
 */

const GOLDEN_DIR = fileURLToPath(new URL("../../../test/fixtures/normalized/", import.meta.url));
const FIXED_TIME = "2026-11-25T20:00:00.000Z";

const tempDirs: string[] = [];
const inputs = new Map<BundleMode, Promise<BundleInput>>();

function fixtureInput(mode: BundleMode): Promise<BundleInput> {
  const cached = inputs.get(mode);
  if (cached !== undefined) return cached;
  const loaded = loadFixtureBundleInput(mode);
  inputs.set(mode, loaded);
  return loaded;
}

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "tarkov-bundle-"));
  tempDirs.push(dir);
  return dir;
}

function sha256(buffer: Uint8Array): string {
  return createHash("sha256").update(buffer).digest("hex");
}

function sortedDatasetNames(input: BundleInput): string[] {
  return Object.keys(input.datasets).sort();
}

afterAll(async () => {
  await Promise.all(tempDirs.map((dir) => rm(dir, { recursive: true, force: true })));
});

describe("bundle determinism", () => {
  it("rebuilds the regular fixture set twice with identical bytes and checksums", async () => {
    const first = buildBundle(await loadFixtureBundleInput("regular"), FIXED_TIME);
    const second = buildBundle(await loadFixtureBundleInput("regular"), FIXED_TIME);

    expect(second.manifestJson).toBe(first.manifestJson);
    expect(second.artifacts).toHaveLength(first.artifacts.length);

    for (const [index, artifact] of first.artifacts.entries()) {
      const other = second.artifacts[index];
      expect(other).toBeDefined();
      if (other === undefined) continue;

      expect(other.dataset).toBe(artifact.dataset);
      expect(other.compressed.equals(artifact.compressed), `${artifact.dataset} bytes`).toBe(true);
      expect(other.sha256, `${artifact.dataset} checksum`).toBe(artifact.sha256);
    }

    // Two independent writes into separate directories agree as well.
    const dirA = await tempDir();
    const dirB = await tempDir();
    const writtenA = await writeBundle(first, { outDir: dirA });
    const writtenB = await writeBundle(second, { outDir: dirB });

    expect(await readFile(writtenA.manifestPath)).toEqual(await readFile(writtenB.manifestPath));

    for (const artifact of first.artifacts) {
      const bytesA = await readFile(join(writtenA.modeDir, artifact.path));
      const bytesB = await readFile(join(writtenB.modeDir, artifact.path));
      expect(bytesA.equals(bytesB), `${artifact.dataset} file bytes`).toBe(true);
      expect(sha256(bytesA), `${artifact.dataset} on-disk checksum`).toBe(artifact.sha256);
    }
  });

  it("is independent of input record order", async () => {
    const input = await fixtureInput("regular");
    const reversedRecords: Record<string, readonly BundleRecord[]> = {};
    for (const name of sortedDatasetNames(input)) {
      const records = input.datasets[name];
      if (records !== undefined) reversedRecords[name] = [...records].reverse();
    }

    const forward = buildBundle(input, FIXED_TIME);
    const reversed = buildBundle({ ...input, datasets: reversedRecords }, FIXED_TIME);

    expect(reversed.manifestJson).toBe(forward.manifestJson);
    for (const [index, artifact] of forward.artifacts.entries()) {
      const other = reversed.artifacts[index];
      expect(other?.compressed.equals(artifact.compressed)).toBe(true);
      expect(other?.sha256).toBe(artifact.sha256);
    }
  });

  it("keeps dataset checksums stable when only generatedAt changes", async () => {
    const input = await fixtureInput("regular");
    const first = buildBundle(input, FIXED_TIME);
    const second = buildBundle(input, "2026-11-26T00:00:00.000Z");

    expect(second.artifacts.map((artifact) => artifact.sha256)).toEqual(
      first.artifacts.map((artifact) => artifact.sha256),
    );
    expect(second.manifestJson).not.toBe(first.manifestJson);
    expect(second.manifest.generatedAt).toBe("2026-11-26T00:00:00.000Z");
  });
});

describe("bundle payloads", () => {
  it("decompresses to the exact normalized JSONL bytes", async () => {
    const bundle = buildBundle(await fixtureInput("regular"), FIXED_TIME);
    const dir = await tempDir();
    const written = await writeBundle(bundle, { outDir: dir });

    for (const artifact of bundle.artifacts) {
      const decompressed = decompressZstd(artifact.compressed).toString("utf8");
      expect(decompressed).toBe(artifact.jsonl);
      expect(Buffer.byteLength(decompressed, "utf8")).toBe(artifact.uncompressedBytes);

      const golden = await readFile(join(GOLDEN_DIR, `${artifact.dataset}.jsonl`), "utf8");
      expect(decompressed, `${artifact.dataset} golden`).toBe(golden);

      const onDisk = await readFile(join(written.modeDir, artifact.path));
      expect(decompressZstd(onDisk).toString("utf8")).toBe(artifact.jsonl);
    }
  });

  it("uses the documented zstd level and a standard frame header", async () => {
    const bundle = buildBundle(await fixtureInput("pve"), FIXED_TIME);
    const artifact = bundle.artifacts[0];
    expect(ZSTD_COMPRESSION_LEVEL).toBe(3);
    expect(artifact).toBeDefined();
    if (artifact === undefined) return;

    // zstd magic number 0xFD2FB528, little-endian on disk.
    expect(artifact.compressed.subarray(0, 4).toString("hex")).toBe("28b52ffd");
  });
});

describe("bundle manifest", () => {
  it("validates against the Zod schema with sorted, matching datasets", async () => {
    const input = await fixtureInput("regular");
    const bundle = buildBundle(input, FIXED_TIME);
    const parsed = manifestSchema.parse(JSON.parse(bundle.manifestJson) as unknown);

    expect(parsed.manifestVersion).toBe(MANIFEST_VERSION);
    expect(parsed.bundleSchemaVersion).toBe(BUNDLE_SCHEMA_VERSION);
    expect(parsed.mode).toBe("regular");
    expect(parsed.generatedAt).toBe(FIXED_TIME);

    const names = parsed.datasets.map((entry) => entry.dataset);
    expect(names).toEqual([...names].sort());
    expect(names).toEqual(sortedDatasetNames(input));
    expect(parsed.skipped).toEqual([]);

    expect(parsed.totals.datasets).toBe(parsed.datasets.length);
    expect(parsed.totals.records).toBe(
      parsed.datasets.reduce((sum, entry) => sum + entry.records, 0),
    );
    expect(parsed.totals.uncompressedBytes).toBe(
      parsed.datasets.reduce((sum, entry) => sum + entry.uncompressedBytes, 0),
    );
    expect(parsed.totals.compressedBytes).toBe(
      parsed.datasets.reduce((sum, entry) => sum + entry.compressedBytes, 0),
    );

    for (const entry of parsed.datasets) {
      const records = input.datasets[entry.dataset];
      expect(records).toBeDefined();
      expect(entry.records).toBe(records?.length);
      expect(entry.sha256).toMatch(/^[0-9a-f]{64}$/);
      expect(entry.path).toBe(`${entry.dataset}.jsonl.zst`);
      expect(entry.source.url).not.toBeNull();
      expect(entry.source.fetchedAt).not.toBeNull();
    }

    const items = parsed.datasets.find((entry) => entry.dataset === "items");
    expect(items?.source.lastModified).not.toBeNull();
    expect(items?.source.etag).not.toBeNull();

    expect(parsed.minAppSchemaVersion).toBeGreaterThanOrEqual(
      Math.max(...parsed.datasets.map((entry) => entry.schemaVersion)),
    );
  });

  it("is canonical JSON with sorted keys and one trailing newline", async () => {
    const bundle = buildBundle(await fixtureInput("regular"), FIXED_TIME);
    expect(bundle.manifestJson.endsWith("\n")).toBe(true);
    expect(bundle.manifestJson.slice(0, -1)).toBe(
      canonicalJson(JSON.parse(bundle.manifestJson) as unknown),
    );

    const root = JSON.parse(bundle.manifestJson) as Record<string, unknown>;
    expect(Object.keys(root)).toEqual([...Object.keys(root)].sort());
  });
});

describe("bundle modes", () => {
  for (const mode of ["pve", "pvp-season"] as const) {
    it(`writes the ${mode} item markers and records skipped datasets`, async () => {
      const bundle = buildBundle(await fixtureInput(mode), FIXED_TIME);
      const parsed = manifestSchema.parse(JSON.parse(bundle.manifestJson) as unknown);

      expect(parsed.mode).toBe(mode);
      expect(parsed.datasets.map((entry) => entry.dataset)).toEqual(["items"]);
      expect(parsed.skipped.map((entry) => entry.dataset)).toEqual([
        "tasks",
        "traders",
        "hideout",
        "crafts",
        "barters",
        "maps",
      ]);
      expect(parsed.skipped.every((entry) => entry.reason === "not-supplied")).toBe(true);

      const artifact = bundle.artifacts[0];
      expect(artifact).toBeDefined();
      if (artifact === undefined) return;

      const lines = artifact.jsonl.trimEnd().split("\n");
      const kinds = lines.map((line) => {
        const record = JSON.parse(line) as { kind?: unknown };
        return record.kind;
      });
      expect(kinds.filter((kind) => kind === "item")).toHaveLength(3);
      expect(artifact.records).toBe(lines.length);
    });
  }
});

describe("bundle writer edge cases", () => {
  it("refuses an explicitly supplied but empty dataset", async () => {
    const input = await fixtureInput("regular");
    expect(() =>
      buildBundle({ ...input, datasets: { items: [] } }, FIXED_TIME),
    ).toThrow(/refusing to write an empty dataset/);
  });

  it("rejects unknown dataset names", async () => {
    const input = await fixtureInput("pve");
    expect(() => buildBundle({ ...input, datasets: { seasons: [] } }, FIXED_TIME)).toThrow(
      /unknown bundle dataset "seasons"/,
    );
  });

  it("removes stale dataset files from the mode directory", async () => {
    const dir = await tempDir();
    const modeDir = join(dir, "pve");
    await mkdir(modeDir, { recursive: true });
    const stale = join(modeDir, "obsolete.jsonl.zst");
    await writeFile(stale, "stale");

    await writeBundle(buildBundle(await fixtureInput("pve"), FIXED_TIME), { outDir: dir });

    const entries = await readdir(modeDir);
    expect(entries).not.toContain("obsolete.jsonl.zst");
    expect(entries).toContain("items.jsonl.zst");
    expect(entries).toContain("manifest.json");
    expect(entries.some((entry) => entry.endsWith(".tmp"))).toBe(false);
  });
});
