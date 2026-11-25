import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { buildBundle, isBundleMode, writeBundle, type BundleMode } from "../bundle/index.js";
import { fixtureBundleModes, loadFixtureBundleInput } from "../fixtures/bundle-set.js";

/**
 * Build bundles from the committed fixtures, offline.
 *
 *   npm run bundle                        # regular
 *   npm run bundle -- --mode pve
 *   npm run bundle -- --all               # every mode with fixtures
 *   npm run bundle -- --out /tmp/bundles
 *
 * Output: `dist/bundles/<mode>/manifest.json` and
 * `dist/bundles/<mode>/<dataset>.jsonl.zst`.
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
    },
  });

  const modes = await selectedModes(values);
  const outDir = resolve(process.cwd(), values.out ?? DEFAULT_OUT_DIR);
  const generatedAt = new Date().toISOString();

  for (const mode of modes) {
    const input = await loadFixtureBundleInput(mode);
    if (Object.keys(input.datasets).length === 0) {
      throw new Error(`no bundle datasets have committed fixtures for mode "${mode}"`);
    }

    const bundle = buildBundle(input, generatedAt);
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
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
