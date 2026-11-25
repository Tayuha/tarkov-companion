import { mkdir, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { BUNDLE_MODES, isBundleMode, type BundleMode } from "../bundle/index.js";
import {
  FixtureDatasetProvider,
  FileNormalizedDatasetCacheStore,
  MemoryNormalizedDatasetCacheStore,
  UpstreamDatasetProvider,
  describeSyncReport,
  runSync,
} from "../sync/index.js";
import { DEFAULT_CACHE_DIR, FileDatasetCacheStore } from "../upstream/cache.js";

/**
 * Production data sync: fetch the live upstream for every mode and dataset,
 * validate and normalize, build the bundle and publish it to the rolling
 * `data-<mode>-latest` release.
 *
 *   npm run sync                        # every mode, live, publish
 *   npm run sync -- --mode regular
 *   npm run sync -- --all --dry-run     # read the release, mutate nothing
 *   npm run sync -- --all --force       # ignore conditional-request validators
 *   npm run sync -- --all --fixtures ../test/fixtures/upstream --dry-run
 *
 * The fixtures path is offline by construction and refuses anything but
 * `--dry-run`: publishing a fixture bundle to a real release is never intended.
 */

const DEFAULT_OUT_DIR = "dist/bundles";
const DEFAULT_REPORT_FILE = "dist/sync-report.json";

function selectedModes(mode: string | undefined, all: boolean): BundleMode[] {
  if (mode !== undefined) {
    if (all) {
      throw new Error("use either --mode or --all, not both");
    }
    if (!isBundleMode(mode)) {
      throw new Error(`unknown mode "${mode}"; expected regular, pve or pvp-season`);
    }
    return [mode];
  }
  return [...BUNDLE_MODES];
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      mode: { type: "string" },
      all: { type: "boolean", default: false },
      "dry-run": { type: "boolean", default: false },
      force: { type: "boolean", default: false },
      "cache-dir": { type: "string" },
      out: { type: "string" },
      fixtures: { type: "string" },
      report: { type: "string" },
    },
  });

  const dryRun = values["dry-run"];
  const offline = values.fixtures !== undefined;
  if (offline && !dryRun) {
    throw new Error(
      "--fixtures is an offline source; combine it with --dry-run " +
        "(fixture bundles must never be published)",
    );
  }

  const selected = selectedModes(values.mode, values.all);
  const cacheDir = resolve(process.cwd(), values["cache-dir"] ?? DEFAULT_CACHE_DIR);
  const outDir = resolve(process.cwd(), values.out ?? DEFAULT_OUT_DIR);
  const reportPath = resolve(process.cwd(), values.report ?? DEFAULT_REPORT_FILE);

  const provider = offline
    ? new FixtureDatasetProvider({ root: resolve(process.cwd(), values.fixtures ?? "") })
    : new UpstreamDatasetProvider({ cache: new FileDatasetCacheStore({ dir: cacheDir }) });

  const normalizedCache = offline
    ? new MemoryNormalizedDatasetCacheStore()
    : new FileNormalizedDatasetCacheStore({ dir: join(cacheDir, "normalized") });

  const available = await provider.modes();
  const modes = selected.filter((mode) => available.includes(mode));
  if (modes.length === 0) {
    throw new Error(
      `no selected mode has a dataset source (available: ${available.join(", ") || "none"})`,
    );
  }

  const report = await runSync({
    modes,
    provider,
    normalizedCache,
    outDir,
    dryRun,
    force: values.force,
    ...(offline ? { releaseClient: null } : {}),
  });

  for (const line of describeSyncReport(report)) console.log(line);

  if (!dryRun) {
    await mkdir(dirname(reportPath), { recursive: true });
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, "utf8");
    console.log(`report   ${reportPath}`);
  }

  process.exitCode = report.exitCode;
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
