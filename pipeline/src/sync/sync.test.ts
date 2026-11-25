import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, describe, expect, it } from "vitest";
import { MANIFEST_FILE, manifestSchema } from "../bundle/index.js";
import { MemoryReleaseClient } from "../release/index.js";
import { FIXTURES_ROOT } from "../schemas/fixtures.js";
import {
  FileNormalizedDatasetCacheStore,
  UpstreamDatasetProvider,
  runSync,
  type ModeSyncSummary,
  type SyncReport,
} from "./index.js";
import { FileDatasetCacheStore } from "../upstream/cache.js";

/**
 * Offline orchestration tests.
 *
 * The fake `fetch` serves the committed regular fixtures for any `{mode,
 * dataset}` URL, implements real ETag/304 behaviour and can inject an invalid
 * payload. That exercises the production conditional cache, validation, the
 * normalized JSONL cache and the real publisher against `MemoryReleaseClient`.
 * Nothing here touches the network or the `gh` binary.
 */

const PIPELINE_ROOT = fileURLToPath(new URL("../..", import.meta.url));
const SYNC_CLI = fileURLToPath(new URL("../cli/sync.ts", import.meta.url));
const FIXED_TIME = new Date("2026-11-26T00:00:00.000Z");
const BASE_URL = "https://fixture.test";

const tempDirs: string[] = [];

async function tempDir(prefix: string): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), prefix));
  tempDirs.push(dir);
  return dir;
}

afterAll(async () => {
  await Promise.all(tempDirs.map((dir) => rm(dir, { recursive: true, force: true })));
});

interface FakeUpstreamOptions {
  /** Return `{"data":null}` for this mode/dataset instead of the fixture. */
  readonly invalid?: { readonly mode: string; readonly dataset: string };
}

function etagFor(text: string): string {
  return `W/"${createHash("sha1").update(text).digest("hex")}"`;
}

/**
 * Serve `${root}/regular/<dataset>.json` (and its `_en` dictionary) for any
 * mode. Returns `304` when `If-None-Match` matches the payload's ETag.
 */
function fakeUpstream(
  root: string,
  options: FakeUpstreamOptions = {},
): typeof fetch {
  const cache = new Map<string, string>();

  async function bodyFor(url: string): Promise<string | null> {
    const path = new URL(url).pathname.split("/").filter((segment) => segment.length > 0);
    const mode = path[0] ?? "";
    const resource = path[1] ?? "";
    const dictionary = resource.endsWith("_en");
    const dataset = dictionary ? resource.slice(0, -3) : resource;

    if (
      !dictionary &&
      options.invalid !== undefined &&
      options.invalid.mode === mode &&
      options.invalid.dataset === dataset
    ) {
      return JSON.stringify({ data: null });
    }

    const key = `${mode}/${resource}`;
    const cached = cache.get(key);
    if (cached !== undefined) return cached;

    const file = dictionary
      ? join(root, "regular", `${dataset}_en.json`)
      : join(root, "regular", `${dataset}.json`);
    const text = await readFile(file, "utf8");
    cache.set(key, text);
    return text;
  }

  return async (input, init) => {
    const url =
      typeof input === "string"
        ? input
        : input instanceof URL
          ? input.href
          : input.url;
    const body = await bodyFor(url);
    if (body === null) return new Response("not found", { status: 404 });

    const etag = etagFor(body);
    const headers = new Headers(init?.headers);
    if (headers.get("if-none-match") === etag) {
      return new Response(null, { status: 304, headers: { etag } });
    }

    return new Response(body, {
      status: 200,
      headers: { etag, "last-modified": "Wed, 25 Nov 2026 12:00:00 GMT" },
    });
  };
}

interface Harness {
  readonly report: SyncReport;
  readonly client: MemoryReleaseClient | null;
  readonly cacheDir: string;
  readonly outDir: string;
  readonly normalizedDir: string;
  readonly logs: readonly string[];
}

async function runHarness(options: {
  readonly fetchImpl: typeof fetch;
  readonly modes?: readonly ("regular" | "pve" | "pvp-season")[];
  readonly client?: MemoryReleaseClient | null;
  readonly dryRun?: boolean;
  readonly force?: boolean;
  readonly cacheDir?: string;
  readonly logs?: string[];
}): Promise<Harness> {
  const cacheDir = options.cacheDir ?? (await tempDir("tarkov-sync-cache-"));
  const outDir = await tempDir("tarkov-sync-out-");
  const normalizedDir = join(cacheDir, "normalized");
  const logs = options.logs ?? [];
  const client =
    options.client === undefined ? new MemoryReleaseClient() : options.client;

  const provider = new UpstreamDatasetProvider({
    cache: new FileDatasetCacheStore({ dir: join(cacheDir, "upstream") }),
    baseUrl: BASE_URL,
    fetchImpl: options.fetchImpl,
    now: () => FIXED_TIME,
  });

  const report = await runSync({
    modes: options.modes ?? ["regular"],
    provider,
    normalizedCache: new FileNormalizedDatasetCacheStore({ dir: normalizedDir }),
    releaseClient: client,
    outDir,
    dryRun: options.dryRun ?? false,
    force: options.force ?? false,
    repository: "Tayuha/tarkov-companion",
    now: () => FIXED_TIME,
    log: (line) => logs.push(line),
  });

  return { report, client, cacheDir, outDir, normalizedDir, logs };
}

function clientOf(harness: Harness): MemoryReleaseClient {
  if (harness.client === null) throw new Error("harness runs without a release client");
  return harness.client;
}

function onlyMode(report: SyncReport): ModeSyncSummary {
  const [mode, ...rest] = report.modes;
  if (mode === undefined || rest.length > 0) throw new Error("expected exactly one mode");
  return mode;
}

function modeOf(report: SyncReport, name: "regular" | "pve" | "pvp-season"): ModeSyncSummary {
  const mode = report.modes.find((candidate) => candidate.mode === name);
  if (mode === undefined) throw new Error(`mode ${name} is missing from the report`);
  return mode;
}

function sha256(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

describe("runSync", () => {
  it("fetches, validates, normalizes and publishes every dataset on a cold run", async () => {
    const harness = await runHarness({ fetchImpl: fakeUpstream(FIXTURES_ROOT) });
    const mode = onlyMode(harness.report);

    expect(harness.report.exitCode).toBe(0);
    expect(mode.status).toBe("published");
    expect(mode.datasets.map((entry) => entry.outcome)).toEqual(Array(7).fill("fetched"));
    expect(mode.fetched).toBe(7);
    expect(mode.notModified).toBe(0);
    expect(mode.reused).toBe(0);
    expect(mode.refetched).toBe(0);
    expect(mode.totals?.records).toBe(1064);
    expect(mode.publication?.tag).toBe("data-regular-latest");
    expect(mode.publication?.mutations).toBeGreaterThan(0);
    expect(mode.publication?.uploads.at(-1)).toBe(MANIFEST_FILE);

    // Every normalized JSONL is persisted under its content checksum.
    const cached = await readdir(harness.normalizedDir);
    expect(cached).toHaveLength(7);
    expect(cached.every((name) => name.startsWith("v1__regular__"))).toBe(true);

    const release = await clientOf(harness).getRelease("data-regular-latest");
    expect(release).not.toBeNull();

    const bytes = await clientOf(harness).downloadAsset({
      tag: "data-regular-latest",
      name: MANIFEST_FILE,
    });
    expect(bytes).not.toBeNull();
    if (bytes === null) throw new Error("unreachable");
    const published = manifestSchema.parse(
      JSON.parse(Buffer.from(bytes).toString("utf8")),
    );

    expect(published.datasets).toHaveLength(7);
    for (const entry of published.datasets) {
      expect(entry.path).toMatch(new RegExp(`^${entry.dataset}-[0-9a-f]{12}\\.jsonl\\.zst$`));
      const asset = await clientOf(harness).downloadAsset({
        tag: "data-regular-latest",
        name: entry.path,
      });
      expect(asset).not.toBeNull();
      if (asset === null) throw new Error("unreachable");
      expect(sha256(asset)).toBe(entry.sha256);
      expect(asset.byteLength).toBe(entry.compressedBytes);
    }

    expect(existsSync(join(harness.outDir, "regular", MANIFEST_FILE))).toBe(true);
  });

  it("reuses the normalized cache on an all-304 run and publishes nothing", async () => {
    const fetchImpl = fakeUpstream(FIXTURES_ROOT);
    const first = await runHarness({ fetchImpl });
    const client = clientOf(first);
    const mutationsAfterFirst = client.mutations;
    const logs: string[] = [];

    const second = await runHarness({
      fetchImpl,
      client,
      cacheDir: first.cacheDir,
      logs,
    });
    const mode = onlyMode(second.report);

    expect(second.report.exitCode).toBe(0);
    expect(mode.status).toBe("noop");
    expect(mode.fetched).toBe(0);
    expect(mode.notModified).toBe(7);
    expect(mode.reused).toBe(7);
    expect(mode.refetched).toBe(0);
    expect(mode.publication?.mutations).toBe(0);
    expect(mode.publication?.uploads).toEqual([]);
    expect(mode.publication?.noop).toBe(true);
    expect(client.mutations).toBe(mutationsAfterFirst);
    expect(logs.some((line) => line.includes("304 Not Modified, reusing cached normalized JSONL"))).toBe(
      true,
    );
  });

  it("forces one unconditional re-fetch when a 304 has no normalized cache entry", async () => {
    const fetchImpl = fakeUpstream(FIXTURES_ROOT);
    const first = await runHarness({ fetchImpl });
    await rm(first.normalizedDir, { recursive: true, force: true });
    const logs: string[] = [];

    const second = await runHarness({
      fetchImpl,
      client: clientOf(first),
      cacheDir: first.cacheDir,
      logs,
    });
    const mode = onlyMode(second.report);

    expect(second.report.exitCode).toBe(0);
    expect(mode.status).toBe("noop");
    expect(mode.notModified).toBe(7);
    expect(mode.reused).toBe(0);
    expect(mode.refetched).toBe(7);
    expect(mode.fetched).toBe(7);
    expect(mode.publication?.mutations).toBe(0);
    expect(logs.some((line) => line.includes("normalized cache is missing"))).toBe(true);
    expect((await readdir(second.normalizedDir)).length).toBe(7);
  });

  it("never publishes a mode when a dataset fails validation", async () => {
    const harness = await runHarness({
      fetchImpl: fakeUpstream(FIXTURES_ROOT, { invalid: { mode: "regular", dataset: "items" } }),
    });
    const mode = onlyMode(harness.report);

    expect(harness.report.exitCode).toBe(1);
    expect(mode.status).toBe("failed");
    expect(mode.publication).toBeNull();
    expect(mode.errors).toHaveLength(1);
    expect(mode.errors[0]?.dataset).toBe("items");
    expect(mode.errors[0]?.message).toContain("validation failed");
    expect(clientOf(harness).operations).toEqual([]);
    expect(existsSync(join(harness.outDir, "regular", MANIFEST_FILE))).toBe(false);
  });

  it("processes every mode, publishes the healthy one and exits 1 for the failed one", async () => {
    const harness = await runHarness({
      fetchImpl: fakeUpstream(FIXTURES_ROOT, { invalid: { mode: "pve", dataset: "items" } }),
      modes: ["regular", "pve"],
    });

    expect(harness.report.exitCode).toBe(1);
    expect(modeOf(harness.report, "regular").status).toBe("published");
    const pve = modeOf(harness.report, "pve");
    expect(pve.status).toBe("failed");
    expect(pve.errors[0]?.dataset).toBe("items");
    expect(pve.publication).toBeNull();

    expect(await clientOf(harness).getRelease("data-regular-latest")).not.toBeNull();
    expect(await clientOf(harness).getRelease("data-pve-latest")).toBeNull();
  });

  it("makes zero release mutations in dry-run", async () => {
    const harness = await runHarness({
      fetchImpl: fakeUpstream(FIXTURES_ROOT),
      dryRun: true,
    });
    const mode = onlyMode(harness.report);

    expect(mode.status).toBe("dry-run");
    expect(mode.publication?.mutations).toBe(0);
    expect(mode.publication?.offlinePlan).toBe(false);
    expect(mode.publication?.uploads).toHaveLength(8);
    expect(clientOf(harness).mutations).toBe(0);
    expect(clientOf(harness).operations.filter((call) => call.operation === "create")).toEqual([]);
    expect(existsSync(join(harness.outDir, "regular", MANIFEST_FILE))).toBe(false);
  });

  it("builds an offline plan without reading or mutating a release", async () => {
    const harness = await runHarness({
      fetchImpl: fakeUpstream(FIXTURES_ROOT),
      client: null,
      dryRun: true,
    });
    const mode = onlyMode(harness.report);

    expect(mode.status).toBe("dry-run");
    expect(mode.publication?.offlinePlan).toBe(true);
    expect(mode.publication?.mutations).toBe(0);
    expect(mode.publication?.uploads).toHaveLength(8);
    expect(existsSync(join(harness.outDir, "regular", MANIFEST_FILE))).toBe(false);
  });

  it("bypasses the conditional cache when force is set", async () => {
    const fetchImpl = fakeUpstream(FIXTURES_ROOT);
    const first = await runHarness({ fetchImpl });
    const second = await runHarness({
      fetchImpl,
      client: clientOf(first),
      cacheDir: first.cacheDir,
      force: true,
    });
    const mode = onlyMode(second.report);

    expect(mode.fetched).toBe(7);
    expect(mode.notModified).toBe(0);
    expect(mode.status).toBe("noop");
    expect(mode.publication?.mutations).toBe(0);
  });
});

interface CliResult {
  readonly status: number | null;
  readonly stdout: string;
  readonly stderr: string;
}

function runSyncCli(args: readonly string[], env: NodeJS.ProcessEnv = process.env): CliResult {
  const result = spawnSync(process.execPath, ["--import", "tsx", SYNC_CLI, ...args], {
    cwd: PIPELINE_ROOT,
    encoding: "utf8",
    env,
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

describe("sync CLI with committed fixtures", () => {
  it("prints a full offline plan and mutates nothing", async () => {
    const outDir = join(await tempDir("tarkov-sync-cli-out-"), "bundles");
    const reportPath = join(await tempDir("tarkov-sync-cli-report-"), "report.json");

    const result = runSyncCli(
      [
        "--all",
        "--fixtures",
        FIXTURES_ROOT,
        "--dry-run",
        "--out",
        outDir,
        "--report",
        reportPath,
      ],
      { ...process.env, PATH: "" },
    );

    expect(result.status).toBe(0);
    expect(result.stdout).toContain("regular: dry-run");
    expect(result.stdout).toContain("data-regular-latest");
    expect(result.stdout).toContain("8 upload(s)");
    expect(result.stdout).toContain("data-pve-latest");
    expect(result.stdout).toContain("data-pvp-season-latest");
    expect(result.stdout).toContain("[offline plan]");
    expect(result.stdout).toContain("3 dry-run");
    expect(existsSync(outDir)).toBe(false);
    expect(existsSync(reportPath)).toBe(false);
  });

  it("refuses to publish fixture data without --dry-run", () => {
    const result = runSyncCli([
      "--all",
      "--fixtures",
      FIXTURES_ROOT,
      "--out",
      join(tmpdir(), "unused-sync-out"),
    ]);

    expect(result.status).toBe(1);
    expect(result.stderr).toContain("combine it with --dry-run");
  });
});
