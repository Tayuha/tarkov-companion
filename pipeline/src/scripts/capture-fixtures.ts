import { createHash } from "node:crypto";
import { mkdir, readdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import { basename, dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { localizeInPlace } from "../upstream/localize.js";
import {
  DEFAULT_BASE_URL,
  fetchDataset,
  UpstreamError,
  USER_AGENT,
  type GameMode,
} from "../upstream/fetch.js";
import {
  selectRecords,
  shapeSignature,
  sortKeysDeep,
  truncateArrays,
  trimPayload,
  type CollectionPlan,
  type TrimPlan,
} from "../fixtures/trim.js";

/**
 * Record a trimmed, fully localizable snapshot of json.tarkov.dev.
 *
 * The committed fixtures keep the upstream placeholder values plus only the
 * dictionary entries needed by the retained records, so the localization
 * resolver itself stays covered by tests. Run with `npm run fixtures`.
 */

const OUT_DIR = fileURLToPath(new URL("../../../test/fixtures/upstream/", import.meta.url));
const PRICE_ITEM_ID = "5447a9cd4bdc2dbd208b4567";
const MODE_MARKER_LIMIT = 3;
const PRICE_POINT_LIMIT = 120;
const BYTE_BUDGET = 2_000_000;

type JsonRecord = Record<string, unknown>;

interface ManifestFile {
  readonly role: string;
  readonly source: string;
  readonly dictionarySource: string | null;
  readonly etag: string | null;
  readonly lastModified: string | null;
  readonly fetchedAt: string;
  readonly sha256: string;
  readonly bytes: number;
  readonly records: number | null;
  readonly entries: number | null;
  readonly points: number | null;
  readonly translations: number;
  readonly unresolvedPointers: readonly string[];
  readonly failedPointers: readonly { path: string; error: string }[];
  readonly missingKeys: readonly string[];
}

interface SkippedSource {
  readonly source: string;
  readonly reason: string;
}

interface WriteResult {
  readonly files: Record<string, ManifestFile>;
  readonly counts: Record<string, number>;
  readonly bytes: number;
}

function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asRecord(value: unknown): JsonRecord | undefined {
  return isRecord(value) ? value : undefined;
}

function readStrings(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function readDictionary(body: unknown): Record<string, string> {
  const root = asRecord(body);
  const candidate = root !== undefined && isRecord(root.data) ? root.data : root;
  if (candidate === undefined) throw new Error("dictionary response is not an object");

  const dictionary: Record<string, string> = {};
  for (const [key, value] of Object.entries(candidate)) {
    if (typeof value === "string") dictionary[key] = value;
  }
  return dictionary;
}

function collectStrings(value: unknown, found: Set<string>): void {
  if (typeof value === "string") {
    found.add(value);
  } else if (Array.isArray(value)) {
    for (const item of value) collectStrings(item, found);
  } else if (isRecord(value)) {
    for (const child of Object.values(value)) collectStrings(child, found);
  }
}

/** Keep only dictionary entries that a retained record still points at. */
function filterDictionary(
  dictionary: Readonly<Record<string, string>>,
  trimmed: unknown,
): Record<string, string> {
  const strings = new Set<string>();
  collectStrings(trimmed, strings);

  const filtered: Record<string, string> = {};
  for (const key of Object.keys(dictionary).sort()) {
    if (strings.has(key)) filtered[key] = dictionary[key] as string;
  }
  return filtered;
}

function recordKeyShape(value: unknown): string {
  return isRecord(value) ? Object.keys(value).sort().join(",") : "";
}

function itemGroup(value: unknown): string {
  const record = asRecord(value);
  const properties = asRecord(record?.properties);
  const type = typeof properties?.propertiesType === "string" ? properties.propertiesType : "none";
  const keys = properties === undefined ? "" : Object.keys(properties).sort().join(",");
  return `${type}|${keys}`;
}

function taskFeatures(value: unknown): readonly string[] {
  const record = asRecord(value);
  const objectives = Array.isArray(record?.objectives) ? record.objectives : [];
  const features = new Set<string>();

  for (const objective of objectives) {
    const node = asRecord(objective);
    if (node === undefined) continue;
    const type = typeof node.type === "string" ? node.type : "unknown";
    features.add(`objective:${type}:${Object.keys(node).sort().join(",")}`);
  }

  for (const key of [
    "startRewards",
    "finishRewards",
    "failureOutcome",
    "taskRequirements",
    "traderRequirements",
    "failConditions",
  ] as const) {
    features.add(`${key}:${shapeSignature(record?.[key])}`);
  }

  return [...features].sort();
}

const REGULAR_PLANS: Readonly<Record<string, TrimPlan>> = {
  items: {
    nestedArrayLimit: 6,
    collections: {
      items: { kind: "records", limit: 60, perGroup: 1, groupKey: itemGroup },
      itemCategories: { kind: "keep" },
      handbookCategories: { kind: "keep" },
      fleaMarket: { kind: "keep" },
      armorMaterials: { kind: "keep" },
      playerLevels: { kind: "keep" },
      mastering: { kind: "keep" },
      skills: { kind: "keep" },
      specialItems: { kind: "keep" },
      settings: { kind: "keep" },
    },
  },
  tasks: {
    nestedArrayLimit: 8,
    collections: {
      tasks: {
        kind: "records",
        limit: 80,
        perGroup: 1,
        groupKey: recordKeyShape,
        featuresOf: taskFeatures,
      },
      questItems: { kind: "keep" },
      achievements: { kind: "keep" },
      prestige: { kind: "keep" },
    },
  },
  traders: { nestedArrayLimit: 10, collections: {} },
  hideout: { nestedArrayLimit: 8, collections: {} },
  maps: {
    nestedArrayLimit: 10,
    collections: {
      maps: { kind: "records", limit: 2, perGroup: 1, groupKey: recordKeyShape },
      mobs: { kind: "records", limit: 2, perGroup: 1, groupKey: recordKeyShape },
      lootContainers: { kind: "keep" },
      goonReports: { kind: "keep" },
      stationaryWeapons: { kind: "keep" },
    },
  },
};

const MODE_MARKER_PLAN: TrimPlan = {
  nestedArrayLimit: 6,
  collections: {
    items: { kind: "records", limit: MODE_MARKER_LIMIT },
    itemCategories: { kind: "records", limit: MODE_MARKER_LIMIT },
    handbookCategories: { kind: "records", limit: MODE_MARKER_LIMIT },
    fleaMarket: { kind: "keep" },
    armorMaterials: { kind: "records", limit: MODE_MARKER_LIMIT },
    playerLevels: { kind: "array", limit: MODE_MARKER_LIMIT },
    mastering: { kind: "array", limit: MODE_MARKER_LIMIT },
    skills: { kind: "array", limit: MODE_MARKER_LIMIT },
    specialItems: { kind: "array", limit: MODE_MARKER_LIMIT },
    settings: { kind: "keep" },
  },
};

const CRAFTS_PLAN: CollectionPlan = { kind: "array", limit: 20 };
const BARTERS_PLAN: CollectionPlan = { kind: "array", limit: 20 };

function trimForDataset(
  dataset: string,
  raw: unknown,
): { data: unknown; counts: Record<string, number>; records: number } {
  const plan = REGULAR_PLANS[dataset];
  if (plan !== undefined) {
    const result = trimPayload(raw, plan);
    const counts: Record<string, number> = {};
    for (const stat of result.stats) counts[stat.key] = stat.output;

    let records = 0;
    if (dataset === "items") records = counts.items ?? 0;
    else if (dataset === "tasks") records = counts.tasks ?? 0;
    else if (dataset === "maps") records = (counts.maps ?? 0) + (counts.mobs ?? 0);
    else if (isRecord(result.data)) records = Object.keys(result.data).length;

    return { data: result.data, counts, records };
  }

  if (dataset === "crafts" || dataset === "barters") {
    if (!Array.isArray(raw)) return { data: raw, counts: {}, records: 0 };
    const collectionPlan = dataset === "crafts" ? CRAFTS_PLAN : BARTERS_PLAN;
    const limit = collectionPlan.kind === "array" ? collectionPlan.limit : raw.length;
    const result = selectRecords(raw, { limit });
    return {
      data: result.selected.map((item) => truncateArrays(item, 6)),
      counts: { records: result.selected.length },
      records: result.selected.length,
    };
  }

  return { data: truncateArrays(raw, 8), counts: {}, records: 0 };
}

async function writeJson(path: string, value: unknown): Promise<{ sha256: string; bytes: number }> {
  const text = `${JSON.stringify(sortKeysDeep(value), null, 2)}\n`;
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, text, "utf8");
  return {
    sha256: createHash("sha256").update(text).digest("hex"),
    bytes: Buffer.byteLength(text),
  };
}

interface PairOptions {
  readonly dir: string;
  readonly fileBase: string;
  readonly source: string;
  readonly dictionarySource: string;
  readonly etag: string | null;
  readonly lastModified: string | null;
  readonly dictionaryEtag: string | null;
  readonly dictionaryLastModified: string | null;
  readonly fetchedAt: string;
  readonly rawData: unknown;
  readonly dictionary: Readonly<Record<string, string>>;
  readonly translations: readonly string[];
  readonly trim: (raw: unknown) => {
    data: unknown;
    counts: Record<string, number>;
    records: number;
  };
}

async function writePair(options: PairOptions): Promise<WriteResult> {
  const trimmed = options.trim(options.rawData);
  const dictionary = filterDictionary(options.dictionary, trimmed.data);
  const stats = localizeInPlace(
    { data: structuredClone(trimmed.data), translations: options.translations },
    dictionary,
  );

  const baseName = `${options.fileBase}.json`;
  const base = await writeJson(join(options.dir, baseName), {
    data: trimmed.data,
    translations: options.translations,
  });

  const files: Record<string, ManifestFile> = {
    [baseName]: {
      role: "dataset",
      source: options.source,
      dictionarySource: options.translations.length > 0 ? options.dictionarySource : null,
      etag: options.etag,
      lastModified: options.lastModified,
      fetchedAt: options.fetchedAt,
      sha256: base.sha256,
      bytes: base.bytes,
      records: trimmed.records,
      entries: null,
      points: null,
      translations: options.translations.length,
      unresolvedPointers: [...stats.unresolvedPaths].sort(),
      failedPointers: [...stats.failedPaths].sort((a, b) => a.path.localeCompare(b.path)),
      missingKeys: stats.missingKeys,
    },
  };

  let bytes = base.bytes;

  if (stats.missingKeys.length > 0) {
    console.warn(
      `missing keys  ${baseName}: ${stats.missingKeys.length} placeholder(s) without a translation`,
    );
  }
  if (stats.unresolvedPaths.length > 0) {
    console.log(
      `stale         ${baseName}: ${stats.unresolvedPaths.length} translation pointer(s) match nothing`,
    );
  }

  if (options.translations.length > 0) {
    const dictionaryName = `${options.fileBase}_en.json`;
    const written = await writeJson(join(options.dir, dictionaryName), { data: dictionary });
    files[dictionaryName] = {
      role: "dictionary",
      source: options.dictionarySource,
      dictionarySource: baseName,
      etag: options.dictionaryEtag,
      lastModified: options.dictionaryLastModified,
      fetchedAt: options.fetchedAt,
      sha256: written.sha256,
      bytes: written.bytes,
      records: null,
      entries: Object.keys(dictionary).length,
      points: null,
      translations: 0,
      unresolvedPointers: [],
      failedPointers: [],
      missingKeys: [],
    };
    bytes += written.bytes;
  }

  return { files, counts: trimmed.counts, bytes };
}

async function fetchJson(url: string): Promise<{
  body: unknown;
  etag: string | null;
  lastModified: string | null;
}> {
  const response = await fetch(url, {
    headers: { accept: "application/json", "user-agent": USER_AGENT },
    signal: AbortSignal.timeout(60_000),
    redirect: "follow",
  });

  if (!response.ok) {
    throw new UpstreamError(
      `GET ${url} returned ${response.status} ${response.statusText}`,
      url,
      response.status,
    );
  }

  const body: unknown = await response.json();
  return {
    body,
    etag: response.headers.get("etag"),
    lastModified: response.headers.get("last-modified"),
  };
}

async function captureDatasetPair(
  dir: string,
  mode: GameMode,
  dataset: string,
  baseUrl: string,
  fetchedAt: string,
): Promise<WriteResult> {
  const result = await fetchDataset({ mode, dataset, baseUrl });
  return writePair({
    dir,
    fileBase: dataset,
    source: result.sources.data,
    dictionarySource: result.sources.dictionary ?? `${baseUrl}/${mode}/${dataset}_en`,
    etag: result.meta.etag,
    lastModified: result.meta.lastModified,
    dictionaryEtag: result.dictionaryMeta?.etag ?? null,
    dictionaryLastModified: result.dictionaryMeta?.lastModified ?? null,
    fetchedAt,
    rawData: result.rawData,
    dictionary: result.dictionary,
    translations: result.translations,
    trim: (raw) => trimForDataset(dataset, raw),
  });
}

async function captureModeMarker(
  dir: string,
  mode: GameMode,
  baseUrl: string,
  fetchedAt: string,
): Promise<WriteResult> {
  const result = await fetchDataset({ mode, dataset: "items", baseUrl });
  return writePair({
    dir,
    fileBase: "items",
    source: result.sources.data,
    dictionarySource: result.sources.dictionary ?? `${baseUrl}/${mode}/items_en`,
    etag: result.meta.etag,
    lastModified: result.meta.lastModified,
    dictionaryEtag: result.dictionaryMeta?.etag ?? null,
    dictionaryLastModified: result.dictionaryMeta?.lastModified ?? null,
    fetchedAt,
    rawData: result.rawData,
    dictionary: result.dictionary,
    translations: result.translations,
    trim: (raw) => {
      const trimmed = trimPayload(raw, MODE_MARKER_PLAN);
      const records = trimmed.stats[0]?.output ?? 0;
      return { data: trimmed.data, counts: { items: records }, records };
    },
  });
}

async function captureSeason(
  dir: string,
  baseUrl: string,
  fetchedAt: string,
): Promise<WriteResult> {
  const source = `${baseUrl}/pvp-season/season`;
  const dictionarySource = `${baseUrl}/pvp-season/season_en`;
  const [payload, dictionaryPayload] = await Promise.all([
    fetchJson(source),
    fetchJson(dictionarySource),
  ]);

  const envelope = asRecord(payload.body);
  if (envelope === undefined || !("data" in envelope)) {
    throw new Error(`${source} has no "data" field`);
  }

  return writePair({
    dir,
    fileBase: "season",
    source,
    dictionarySource,
    etag: payload.etag,
    lastModified: payload.lastModified,
    dictionaryEtag: dictionaryPayload.etag,
    dictionaryLastModified: dictionaryPayload.lastModified,
    fetchedAt,
    rawData: envelope.data,
    dictionary: readDictionary(dictionaryPayload.body),
    translations: readStrings(envelope.translations),
    trim: (raw) => {
      const trimmed = truncateArrays(raw, 10);
      const perks = asRecord(trimmed)?.perks;
      const counts: Record<string, number> = {};
      if (isRecord(perks)) {
        for (const [group, items] of Object.entries(perks)) {
          if (Array.isArray(items)) counts[`perks.${group}`] = items.length;
        }
      }
      return { data: trimmed, counts, records: 1 };
    },
  });
}

async function captureStatus(
  outDir: string,
  baseUrl: string,
  fetchedAt: string,
): Promise<WriteResult> {
  const source = `${baseUrl}/status`;
  const payload = await fetchJson(source);
  const envelope = asRecord(payload.body);
  if (envelope === undefined || !("data" in envelope)) {
    throw new Error(`${source} has no "data" field`);
  }

  const name = "status.json";
  const written = await writeJson(join(outDir, "common", name), {
    data: envelope.data,
    translations: readStrings(envelope.translations),
  });

  return {
    files: {
      [name]: {
        role: "status",
        source,
        dictionarySource: null,
        etag: payload.etag,
        lastModified: payload.lastModified,
        fetchedAt,
        sha256: written.sha256,
        bytes: written.bytes,
        records: null,
        entries: null,
        points: null,
        translations: readStrings(envelope.translations).length,
        unresolvedPointers: [],
        failedPointers: [],
        missingKeys: [],
      },
    },
    counts: {},
    bytes: written.bytes,
  };
}

async function capturePriceHistory(
  dir: string,
  baseUrl: string,
  itemId: string,
  fetchedAt: string,
): Promise<WriteResult> {
  const source = `${baseUrl}/regular/prices/${itemId}`;
  const payload = await fetchJson(source);
  const envelope = asRecord(payload.body);
  const data = envelope?.data;

  if (!Array.isArray(data)) {
    throw new Error(`${source} did not return a price array`);
  }

  const points = data.slice(-PRICE_POINT_LIMIT);
  const relativePath = join("prices", `${itemId}.json`);
  const written = await writeJson(join(dir, relativePath), {
    data: points,
    translations: readStrings(envelope?.translations),
  });

  return {
    files: {
      [relativePath]: {
        role: "price-history",
        source,
        dictionarySource: null,
        etag: payload.etag,
        lastModified: payload.lastModified,
        fetchedAt,
        sha256: written.sha256,
        bytes: written.bytes,
        records: null,
        entries: null,
        points: points.length,
        translations: readStrings(envelope?.translations).length,
        unresolvedPointers: [],
        failedPointers: [],
        missingKeys: [],
      },
    },
    counts: { points: points.length },
    bytes: written.bytes,
  };
}

async function writeManifest(
  dir: string,
  fixtureSet: string,
  baseUrl: string,
  fetchedAt: string,
  files: Record<string, ManifestFile>,
  skipped: readonly SkippedSource[],
): Promise<{ bytes: number }> {
  const sortedFiles: Record<string, ManifestFile> = {};
  for (const name of Object.keys(files).sort()) {
    const entry = files[name];
    if (entry !== undefined) sortedFiles[name] = entry;
  }

  const fixtureBytes = Object.values(sortedFiles).reduce((sum, entry) => sum + entry.bytes, 0);
  const written = await writeJson(join(dir, "manifest.json"), {
    schemaVersion: 1,
    generatedBy: "pipeline/src/scripts/capture-fixtures.ts",
    fixtureSet,
    sourceBaseUrl: baseUrl,
    capturedAt: fetchedAt,
    byteBudget: BYTE_BUDGET,
    totals: { files: Object.keys(sortedFiles).length, bytes: fixtureBytes },
    files: sortedFiles,
    skipped,
  });

  console.log(
    `${fixtureSet.padEnd(12)} ${String(Object.keys(sortedFiles).length).padStart(2)} files  ${formatBytes(fixtureBytes)}`,
  );

  return { bytes: written.bytes };
}

function formatBytes(value: number): string {
  return value >= 1_000_000 ? `${(value / 1_000_000).toFixed(2)} MB` : `${(value / 1000).toFixed(1)} kB`;
}

async function walkFiles(dir: string): Promise<Array<{ path: string; bytes: number }>> {
  const entries = await readdir(dir, { withFileTypes: true });
  const files: Array<{ path: string; bytes: number }> = [];

  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walkFiles(path)));
    } else if (entry.isFile()) {
      files.push({ path, bytes: (await stat(path)).size });
    }
  }

  return files;
}

function mergeFiles(target: Record<string, ManifestFile>, source: Record<string, ManifestFile>): void {
  for (const [name, entry] of Object.entries(source)) {
    target[name] = entry;
  }
}

function mergeCounts(target: Record<string, number>, source: Record<string, number>, prefix = ""): void {
  for (const [name, count] of Object.entries(source)) {
    target[`${prefix}${name}`] = count;
  }
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      out: { type: "string" },
      "base-url": { type: "string" },
    },
  });

  const outDir = values.out ?? OUT_DIR;
  const baseUrl = values["base-url"] ?? DEFAULT_BASE_URL;
  const fetchedAt = new Date().toISOString();

  for (const name of ["common", "regular", "pve", "pvp-season"]) {
    await rm(join(outDir, name), { recursive: true, force: true });
  }
  await mkdir(outDir, { recursive: true });

  const skippedBySet = new Map<string, SkippedSource[]>();
  const skip = (fixtureSet: string, source: string, error: unknown): void => {
    const reason = error instanceof Error ? error.message : String(error);
    const list = skippedBySet.get(fixtureSet) ?? [];
    list.push({ source, reason });
    skippedBySet.set(fixtureSet, list);
    console.warn(`skipped      ${source}: ${reason}`);
  };

  const regularFiles: Record<string, ManifestFile> = {};
  const regularCounts: Record<string, number> = {};

  const regularDatasets = ["items", "tasks", "traders", "hideout", "crafts", "barters", "maps"];
  for (const dataset of regularDatasets) {
    try {
      const result = await captureDatasetPair(
        join(outDir, "regular"),
        "regular",
        dataset,
        baseUrl,
        fetchedAt,
      );
      mergeFiles(regularFiles, result.files);
      mergeCounts(regularCounts, result.counts, `${dataset}.`);
      console.log(`${`regular/${dataset}`.padEnd(20)} ${JSON.stringify(result.counts)}`);
    } catch (error) {
      skip("regular", `${baseUrl}/regular/${dataset}`, error);
    }
  }

  try {
    const result = await capturePriceHistory(
      join(outDir, "regular"),
      baseUrl,
      PRICE_ITEM_ID,
      fetchedAt,
    );
    mergeFiles(regularFiles, result.files);
    console.log(`${`regular/prices`.padEnd(20)} ${JSON.stringify(result.counts)}`);
  } catch (error) {
    skip("regular", `${baseUrl}/regular/prices/${PRICE_ITEM_ID}`, error);
  }

  const modeFiles = new Map<string, Record<string, ManifestFile>>();
  for (const mode of ["pve", "pvp-season"] as const) {
    const files: Record<string, ManifestFile> = {};
    try {
      const result = await captureModeMarker(join(outDir, mode), mode, baseUrl, fetchedAt);
      mergeFiles(files, result.files);
      console.log(`${`${mode}/items`.padEnd(20)} ${JSON.stringify(result.counts)}`);
    } catch (error) {
      skip(mode, `${baseUrl}/${mode}/items`, error);
    }
    modeFiles.set(mode, files);
  }

  try {
    const result = await captureSeason(join(outDir, "pvp-season"), baseUrl, fetchedAt);
    const files = modeFiles.get("pvp-season") ?? {};
    mergeFiles(files, result.files);
    modeFiles.set("pvp-season", files);
    console.log(`${"pvp-season/season".padEnd(20)} ${JSON.stringify(result.counts)}`);
  } catch (error) {
    skip("pvp-season", `${baseUrl}/pvp-season/season`, error);
  }

  const commonFiles: Record<string, ManifestFile> = {};
  try {
    const result = await captureStatus(outDir, baseUrl, fetchedAt);
    mergeFiles(commonFiles, result.files);
    console.log(`${"common/status".padEnd(20)} ok`);
  } catch (error) {
    skip("common", `${baseUrl}/status`, error);
  }

  await writeManifest(
    join(outDir, "regular"),
    "regular",
    baseUrl,
    fetchedAt,
    regularFiles,
    skippedBySet.get("regular") ?? [],
  );
  for (const mode of ["pve", "pvp-season"] as const) {
    await writeManifest(
      join(outDir, mode),
      mode,
      baseUrl,
      fetchedAt,
      modeFiles.get(mode) ?? {},
      skippedBySet.get(mode) ?? [],
    );
  }
  await writeManifest(
    join(outDir, "common"),
    "common",
    baseUrl,
    fetchedAt,
    commonFiles,
    skippedBySet.get("common") ?? [],
  );

  const allFiles = await walkFiles(outDir);
  const totalBytes = allFiles.reduce((sum, file) => sum + file.bytes, 0);
  console.log(`\nfixtures     ${allFiles.length} files, ${totalBytes} bytes (${formatBytes(totalBytes)})`);
  console.log(`budget       ${BYTE_BUDGET} bytes (${Math.round((totalBytes / BYTE_BUDGET) * 100)}% used)`);
  console.log("largest:");
  for (const file of allFiles.sort((a, b) => b.bytes - a.bytes).slice(0, 8)) {
    console.log(`  ${formatBytes(file.bytes).padStart(9)}  ${relative(outDir, file.path)}`);
  }

  console.log("\nper-file:");
  for (const file of allFiles.filter((entry) => basename(entry.path) === "manifest.json")) {
    const manifest = JSON.parse(await readFile(file.path, "utf8")) as {
      fixtureSet: string;
      files: Record<string, ManifestFile>;
    };
    for (const [name, entry] of Object.entries(manifest.files)) {
      const count =
        entry.records !== null
          ? `${entry.records} record${entry.records === 1 ? "" : "s"}`
          : entry.entries !== null
            ? `${entry.entries} entr${entry.entries === 1 ? "y" : "ies"}`
            : entry.points !== null
              ? `${entry.points} point${entry.points === 1 ? "" : "s"}`
              : "status";
      console.log(
        `  ${formatBytes(entry.bytes).padStart(9)}  ${`${manifest.fixtureSet}/${name}`.padEnd(58)} ${count}`,
      );
    }
  }

  if (totalBytes >= BYTE_BUDGET) {
    console.error(`fixture budget exceeded: ${totalBytes} >= ${BYTE_BUDGET}`);
    process.exitCode = 1;
  }
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
