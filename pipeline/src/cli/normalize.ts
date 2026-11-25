import { mkdir, writeFile } from "node:fs/promises";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { loadLocalizedFixture } from "../fixtures/load.js";
import {
  NORMALIZE_DATASETS,
  isNormalizeDataset,
  normalizeDataset,
  serializeJsonl,
  type NormalizeDataset,
} from "../normalize/index.js";

/**
 * Normalize committed fixtures into bundle JSONL, offline.
 *
 *   npm run normalize -- --all
 *   npm run normalize -- --dataset items --out /tmp/normalized
 *
 * Default output: `dist/normalized/<dataset>.jsonl`.
 */

const DEFAULT_OUT_DIR = "dist/normalized";

function formatBytes(value: number): string {
  return value >= 1_000_000 ? `${(value / 1_000_000).toFixed(2)} MB` : `${value} bytes`;
}

function selectedDatasets(values: { dataset?: string; all?: boolean }): NormalizeDataset[] {
  if (values.all === true && values.dataset !== undefined) {
    throw new Error("use either --dataset or --all, not both");
  }
  if (values.dataset !== undefined) {
    if (!isNormalizeDataset(values.dataset)) {
      throw new Error(
        `unknown dataset "${values.dataset}"; expected one of ${NORMALIZE_DATASETS.join(", ")}`,
      );
    }
    return [values.dataset];
  }
  return [...NORMALIZE_DATASETS];
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      dataset: { type: "string" },
      all: { type: "boolean", default: false },
      out: { type: "string" },
    },
  });

  const datasets = selectedDatasets(values);
  const outDir = resolve(process.cwd(), values.out ?? DEFAULT_OUT_DIR);
  let totalBytes = 0;

  for (const dataset of datasets) {
    const fixture = await loadLocalizedFixture("regular", dataset);
    const result = normalizeDataset(dataset, fixture.data);
    const text = serializeJsonl(result.records);
    const bytes = Buffer.byteLength(text, "utf8");
    const path = join(outDir, `${dataset}.jsonl`);

    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, text, "utf8");
    totalBytes += bytes;

    const counts = Object.entries(result.stats.counts)
      .map(([kind, count]) => `${kind}=${count}`)
      .join(" ");
    const fallbacks = Object.entries(result.stats.fallbacks)
      .map(([name, count]) => `${name}=${count}`)
      .join(" ");
    const dropped = result.stats.droppedFields;

    console.log(
      `${dataset.padEnd(9)} ${String(result.records.length).padStart(5)} records  ${formatBytes(bytes).padStart(10)}  ${path}`,
    );
    console.log(`  kinds: ${counts}`);
    console.log(
      `  dropped fields: ${dropped}${fallbacks.length > 0 ? `  fallbacks: ${fallbacks}` : ""}`,
    );
  }

  console.log("");
  console.log(
    `${datasets.length} dataset(s), ${formatBytes(totalBytes)} total -> ${isAbsolute(outDir) ? outDir : resolve(outDir)}`,
  );
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
