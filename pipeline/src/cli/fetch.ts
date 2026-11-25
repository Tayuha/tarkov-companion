import { writeFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { fetchDataset, type GameMode } from "../upstream/fetch.js";

const GAME_MODES: readonly GameMode[] = ["regular", "pve", "pvp-season"];

function collectNames(value: unknown, found: string[] = [], limit = 5): string[] {
  if (found.length >= limit) return found;

  if (Array.isArray(value)) {
    for (const item of value) collectNames(item, found, limit);
  } else if (typeof value === "object" && value !== null) {
    for (const [key, child] of Object.entries(value)) {
      if (key === "name" && typeof child === "string" && !/^[0-9a-f]{24} /.test(child)) {
        found.push(child);
        if (found.length >= limit) return found;
      }
      collectNames(child, found, limit);
    }
  }

  return found;
}

function formatBytes(value: number): string {
  return `${(value / 1024 / 1024).toFixed(2)} MB`;
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      mode: { type: "string", default: "regular" },
      dataset: { type: "string", default: "traders" },
      lang: { type: "string", default: "en" },
      out: { type: "string" },
      "base-url": { type: "string" },
      sample: { type: "string", default: "5" },
    },
  });

  const mode = values.mode as GameMode;
  if (!GAME_MODES.includes(mode)) {
    throw new Error(`Unknown mode "${values.mode}". Use one of: ${GAME_MODES.join(", ")}`);
  }

  const dataset = values.dataset;
  if (!dataset) throw new Error("Missing --dataset");

  const started = performance.now();
  const result = await fetchDataset({
    mode,
    dataset,
    lang: values.lang,
    ...(values["base-url"] ? { baseUrl: values["base-url"] } : {}),
  });
  const elapsed = performance.now() - started;

  const payload = JSON.stringify(result.data);
  console.log(`dataset      ${mode}/${dataset} (${result.meta.lang})`);
  console.log(`data         ${result.sources.data}`);
  console.log(`dictionary   ${result.sources.dictionary ?? "(none)"}`);
  console.log(`payload      ${formatBytes(Buffer.byteLength(payload))}`);
  console.log(`elapsed      ${elapsed.toFixed(0)} ms`);
  console.log(
    `translated   ${result.stats.translated} strings across ${result.stats.visited} visited nodes`,
  );
  if (result.stats.missingKeys.length > 0) {
    console.log(`missing      ${result.stats.missingKeys.length} placeholder key(s) without a translation`);
    for (const key of result.stats.missingKeys.slice(0, 5)) console.log(`             ${key}`);
  }
  if (result.stats.unresolvedPaths.length > 0) {
    console.log(`stale paths  ${result.stats.unresolvedPaths.length}`);
    for (const path of result.stats.unresolvedPaths) console.log(`             ${path}`);
  }
  if (result.stats.failedPaths.length > 0) {
    console.log(`bad paths    ${result.stats.failedPaths.length}`);
    for (const failure of result.stats.failedPaths) console.log(`             ${failure.path}: ${failure.error}`);
  }
  for (const warning of result.warnings) console.log(`warning      ${warning}`);

  const names = collectNames(result.data, [], Number(values.sample ?? 5));
  if (names.length > 0) console.log(`sample       ${names.join(" | ")}`);

  if (values.out) {
    await writeFile(
      values.out,
      `${JSON.stringify({ meta: result.meta, stats: result.stats, data: result.data }, null, 2)}\n`,
    );
    console.log(`written      ${values.out}`);
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
