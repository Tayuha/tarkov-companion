import { resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  ManifestError,
  buildBundle,
  compareBundles,
  describeComparison,
  isBundleMode,
  loadPreviousManifest,
  writeBundle,
  type BundleMode,
} from "../bundle/index.js";
import { fixtureBundleModes, loadFixtureBundleInput } from "../fixtures/bundle-set.js";

/**
 * Build bundles from the committed fixtures, offline.
 *
 *   npm run bundle                        # regular
 *   npm run bundle -- --mode pve
 *   npm run bundle -- --all               # every mode with fixtures
 *   npm run bundle -- --out /tmp/bundles
 *   npm run bundle -- --previous /tmp/bundles
 *   npm run bundle -- --previous /tmp/bundles/regular/manifest.json
 *
 * Output: `dist/bundles/<mode>/manifest.json` and
 * `dist/bundles/<mode>/<dataset>.jsonl.zst`.
 *
 * With `--previous`, the bundle is built in memory and compared with the
 * previous manifest first. When every dataset checksum matches (and the client
 * contract versions agree), nothing is written, `no changes` is printed and
 * the process exits 0. `--previous` accepts a manifest file, a bundles root
 * (`<root>/<mode>/manifest.json`) or a mode directory (`<dir>/manifest.json`).
 */

const DEFAULT_OUT_DIR = "dist/bundles";

function formatBytes(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)} MB`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(2)} kB`;
  return `${value} B`;
}

function formatRatio(uncompressed: number, compressed: number): string {
  if (compressed === 0) return "-";
  return `${(uncompressed / compressed).toFixed(2)}x`;
}

async function selectedModes(values: { mode?: string; all: boolean }): Promise<BundleMode[]> {
  if (values.all && values.mode !== undefined) {
    throw new Error("use either --mode or --all, not both");
  }
  if (values.mode !== undefined) {
    if (!isBundleMode(values.mode)) {
      throw new Error(`unknown mode "${values.mode}"; expected regular, pve or pvp-season`);
    }
    return [values.mode];
  }
  return values.all ? fixtureBundleModes() : ["regular"];
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      mode: { type: "string" },
      all: { type: "boolean", default: false },
      out: { type: "string" },
      previous: { type: "string" },
    },
  });

  const modes = await selectedModes(values);
  const outDir = resolve(process.cwd(), values.out ?? DEFAULT_OUT_DIR);
  const previousInput =
    values.previous === undefined ? undefined : resolve(process.cwd(), values.previous);
  const generatedAt = new Date().toISOString();

  for (const mode of modes) {
    const input = await loadFixtureBundleInput(mode);
    if (Object.keys(input.datasets).length === 0) {
      throw new Error(`no bundle datasets have committed fixtures for mode "${mode}"`);
    }

    const bundle = buildBundle(input, generatedAt);

    if (previousInput !== undefined) {
      const previous = await loadPreviousManifest(previousInput, mode);
      const comparison = compareBundles(previous.manifest, bundle.manifest);
      if (!comparison.hasChanges) {
        console.log(
          `${mode}: no changes against ${previous.path} ` +
            `(${bundle.manifest.totals.datasets} dataset(s)); nothing written`,
        );
        continue;
      }

      console.log(`${mode}: changes against ${previous.path}`);
      for (const line of describeComparison(comparison)) console.log(line);
    }

    const written = await writeBundle(bundle, { outDir });
    const { totals } = bundle.manifest;

    console.log(
      `${mode}: ${totals.datasets} dataset(s), ${totals.records} records, ` +
        `${formatBytes(totals.uncompressedBytes)} -> ${formatBytes(totals.compressedBytes)} ` +
        `(${formatRatio(totals.uncompressedBytes, totals.compressedBytes)})`,
    );

    for (const entry of bundle.manifest.datasets) {
      console.log(
        `  ${entry.dataset.padEnd(9)} ${String(entry.records).padStart(5)} records  ` +
          `${formatBytes(entry.uncompressedBytes).padStart(10)} -> ` +
          `${formatBytes(entry.compressedBytes).padStart(10)}  ` +
          `${formatRatio(entry.uncompressedBytes, entry.compressedBytes).padStart(6)}  ` +
          `sha256 ${entry.sha256.slice(0, 12)}`,
      );
    }

    if (bundle.manifest.skipped.length > 0) {
      const names = bundle.manifest.skipped.map((entry) => entry.dataset).join(", ");
      console.log(`  skipped (not supplied): ${names}`);
    }

    console.log(`  manifest ${written.manifestPath}`);
  }
}

main().catch((error: unknown) => {
  if (error instanceof ManifestError) {
    console.error(`${error.kind}: ${error.message}`);
  } else {
    console.error(error instanceof Error ? error.message : error);
  }
  process.exitCode = 1;
});
