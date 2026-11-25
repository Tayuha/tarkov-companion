import { createHash } from "node:crypto";
import { readdir, readFile, stat } from "node:fs/promises";
import { dirname, join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { localizeInPlace } from "./localize.js";

const ROOT = fileURLToPath(new URL("../../../test/fixtures/upstream/", import.meta.url));
const BYTE_BUDGET = 2_000_000;

interface Envelope {
  data: unknown;
  translations?: string[];
}

interface DictionaryEnvelope {
  data: Record<string, string>;
}

interface ManifestEntry {
  source: string;
  bytes: number;
  sha256: string;
  records: number | null;
  entries: number | null;
  points: number | null;
  unresolvedPointers: string[];
  missingKeys: string[];
}

interface Manifest {
  totals: { files: number; bytes: number };
  files: Record<string, ManifestEntry>;
}

async function listFiles(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const files: string[] = [];

  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...(await listFiles(path)));
    else if (entry.isFile()) files.push(path);
  }

  return files.sort();
}

async function readJson(path: string): Promise<unknown> {
  return JSON.parse(await readFile(path, "utf8")) as unknown;
}

function fixtureSetOf(path: string): string | null {
  const [first] = relative(ROOT, path).split(sep);
  return first === undefined || first === ".." ? null : first;
}

function manifestPathFor(path: string): string {
  const fixtureSet = fixtureSetOf(path);
  if (fixtureSet === null) throw new Error(`fixture outside a set: ${path}`);
  return join(ROOT, fixtureSet, "manifest.json");
}

function manifestKeyFor(path: string): string {
  return relative(dirname(manifestPathFor(path)), path).split(sep).join("/");
}

function isBaseFixture(path: string): boolean {
  const name = path.split(sep).at(-1) ?? "";
  return name.endsWith(".json") && !name.endsWith("_en.json") && name !== "manifest.json";
}

function dictionaryPathFor(path: string): string {
  return `${path.slice(0, -".json".length)}_en.json`;
}

async function readManifest(path: string): Promise<Manifest> {
  return (await readJson(manifestPathFor(path))) as Manifest;
}

const filesPromise = listFiles(ROOT);
const jsonFilesPromise = filesPromise.then((files) => files.filter((file) => file.endsWith(".json")));

describe("recorded upstream fixtures", () => {
  it("parses every fixture and matches its manifest entry", async () => {
    const files = await filesPromise;
    const jsonFiles = await jsonFilesPromise;
    expect(files.length).toBeGreaterThan(0);

    for (const file of jsonFiles) {
      await expect(readJson(file)).resolves.not.toBeUndefined();
    }

    for (const file of files) {
      if (!file.endsWith(".json") || file.endsWith(`${sep}manifest.json`)) continue;

      const manifest = await readManifest(file);
      const key = manifestKeyFor(file);
      const entry = manifest.files[key];
      expect(entry, `${key} is missing from ${manifestPathFor(file)}`).toBeDefined();

      const content = await readFile(file);
      expect(entry?.bytes).toBe(content.byteLength);
      expect(entry?.sha256).toBe(createHash("sha256").update(content).digest("hex"));
      expect(entry?.source, key).toMatch(/^https:\/\/json\.tarkov\.dev\//);
    }

    const sets = new Set(jsonFiles.map((file) => fixtureSetOf(file)));
    for (const set of sets) {
      if (set === null) continue;
      const manifest = (await readJson(join(ROOT, set, "manifest.json"))) as Manifest;
      const entries = Object.values(manifest.files);
      expect(manifest.totals.files).toBe(entries.length);
      expect(manifest.totals.bytes).toBe(entries.reduce((sum, entry) => sum + entry.bytes, 0));
    }
  });

  it("localizes every retained base+dictionary pair without missing keys", async () => {
    const jsonFiles = await jsonFilesPromise;
    const bases = jsonFiles.filter(isBaseFixture);
    expect(bases.length).toBeGreaterThan(0);

    for (const basePath of bases) {
      const base = (await readJson(basePath)) as Envelope;
      expect(base, basePath).toHaveProperty("data");
      expect(Array.isArray(base.translations ?? []), basePath).toBe(true);

      const manifest = await readManifest(basePath);
      const entry = manifest.files[manifestKeyFor(basePath)];
      expect(entry, manifestKeyFor(basePath)).toBeDefined();

      const translations = base.translations ?? [];
      if (translations.length === 0) {
        expect(entry?.unresolvedPointers, basePath).toEqual([]);
        continue;
      }

      const dictionaryPath = dictionaryPathFor(basePath);
      const dictionary = (await readJson(dictionaryPath)) as DictionaryEnvelope;
      const stats = localizeInPlace(structuredClone(base), dictionary.data);

      expect(stats.missingKeys, `${manifestKeyFor(basePath)} missing keys`).toEqual([]);
      expect(stats.failedPaths, `${manifestKeyFor(basePath)} unparsable pointers`).toEqual([]);
      expect([...stats.unresolvedPaths].sort(), `${manifestKeyFor(basePath)} stale pointers`).toEqual(
        entry?.unresolvedPointers,
      );
      expect(stats.missingKeys).toEqual(entry?.missingKeys);
      expect(stats.translated).toBeGreaterThan(0);

      const dictionaryEntry = manifest.files[manifestKeyFor(dictionaryPath)];
      expect(dictionaryEntry?.entries).toBe(Object.keys(dictionary.data).length);
    }
  });

  it("stays under the 2 MB fixture budget", async () => {
    const files = await filesPromise;
    const sizes = await Promise.all(files.map(async (file) => (await stat(file)).size));
    const total = sizes.reduce((sum, size) => sum + size, 0);

    expect(total).toBeLessThan(BYTE_BUDGET);
  });

  it("resolves traders names and descriptions completely", async () => {
    const base = (await readJson(join(ROOT, "regular", "traders.json"))) as {
      data: Record<string, { name: string; description: string }>;
      translations: string[];
    };
    const dictionary = (await readJson(join(ROOT, "regular", "traders_en.json"))) as {
      data: Record<string, string>;
    };

    const stats = localizeInPlace(base, dictionary.data);

    expect(stats.missingKeys).toEqual([]);
    expect(stats.unresolvedPaths).toEqual([]);
    expect(stats.failedPaths).toEqual([]);
    expect(stats.translated).toBe(32);

    expect(base.data["54cb50c76803fa8b248b4571"]?.name).toBe("Prapor");
    expect(base.data["54cb57776803fa99248b456e"]?.name).toBe("Therapist");
    expect(base.data["54cb50c76803fa8b248b4571"]?.description).toMatch(/Warrant officer/);
  });

  it("keeps small mode markers that actually differ from regular", async () => {
    const regular = (await readJson(join(ROOT, "regular", "items.json"))) as {
      data: { items: Record<string, unknown> };
    };
    const pve = (await readJson(join(ROOT, "pve", "items.json"))) as {
      data: { items: Record<string, unknown> };
    };
    const pvp = (await readJson(join(ROOT, "pvp-season", "items.json"))) as {
      data: { items: Record<string, unknown> };
    };

    expect(Object.keys(pve.data.items)).toHaveLength(3);
    expect(Object.keys(pvp.data.items)).toHaveLength(3);

    const pveIds = Object.keys(pve.data.items);
    const pvpIds = Object.keys(pvp.data.items);
    expect(pveIds).toEqual(pvpIds);

    for (const id of pveIds) {
      expect(regular.data.items[id]).toBeDefined();
      expect(pve.data.items[id]).not.toEqual(regular.data.items[id]);
      expect(pvp.data.items[id]).not.toEqual(regular.data.items[id]);
      expect(pve.data.items[id]).not.toEqual(pvp.data.items[id]);
    }

    const pveDictionary = (await readJson(join(ROOT, "pve", "items_en.json"))) as DictionaryEnvelope;
    expect(Object.keys(pveDictionary.data).length).toBeLessThan(100);
  });

  it("captures the non-dataset endpoints", async () => {
    const status = (await readJson(join(ROOT, "common", "status.json"))) as Envelope;
    const season = (await readJson(join(ROOT, "pvp-season", "season.json"))) as Envelope & {
      data: { id: string; perks: Record<string, unknown[]> };
    };
    const price = (await readJson(
      join(ROOT, "regular", "prices", "5447a9cd4bdc2dbd208b4567.json"),
    )) as { data: Array<{ priceMin: number; price: number; timestamp: number }> };

    expect(status.data).toHaveProperty("generalStatus");
    expect(season.data.id).toMatch(/^[0-9a-f]{24}$/);
    expect(Object.keys(season.data.perks)).toEqual(["common", "personal"]);
    expect(price.data).toHaveLength(120);
    expect(price.data[0]).toHaveProperty("timestamp");
    expect(price.data[0]).toHaveProperty("priceMin");
    expect(price.data[0]).toHaveProperty("price");
  });

  it("retains a representative shape for every item property type", async () => {
    const items = (await readJson(join(ROOT, "regular", "items.json"))) as {
      data: { items: Record<string, Record<string, unknown>> };
    };
    const records = Object.values(items.data.items);
    const propertyTypes = new Set(
      records.map((record) => {
        const properties = record.properties as { propertiesType?: string } | null;
        return properties?.propertiesType ?? "null";
      }),
    );

    expect(records).toHaveLength(60);
    expect(propertyTypes.size).toBeGreaterThanOrEqual(24);

    const retainedKeys = new Set(records.flatMap((record) => Object.keys(record)));
    for (const key of [
      "id",
      "name",
      "shortName",
      "normalizedName",
      "description",
      "width",
      "height",
      "weight",
      "types",
      "properties",
      "buyFromTrader",
      "sellToTrader",
      "lastLowPrice",
      "avg24hPrice",
      "changeLast48h",
    ]) {
      expect(retainedKeys, key).toContain(key);
    }
  });

  it("retains every task objective type and both map shapes", async () => {
    const tasks = (await readJson(join(ROOT, "regular", "tasks.json"))) as {
      data: { tasks: Record<string, { objectives: Array<{ type: string }> }> };
    };
    const maps = (await readJson(join(ROOT, "regular", "maps.json"))) as {
      data: { maps: Record<string, Record<string, unknown>> };
    };

    const objectiveTypes = new Set(
      Object.values(tasks.data.tasks).flatMap((task) => task.objectives.map((objective) => objective.type)),
    );
    expect(objectiveTypes.size).toBeGreaterThanOrEqual(20);

    const mapRecords = Object.values(maps.data.maps);
    expect(mapRecords).toHaveLength(2);
    expect(mapRecords.some((map) => "artillery" in map)).toBe(true);
    expect(mapRecords.some((map) => !("artillery" in map))).toBe(true);

    for (const map of mapRecords) {
      for (const key of ["id", "name", "spawns", "extracts", "lootContainers", "lootLoose"]) {
        expect(map, key).toHaveProperty(key);
      }
    }
  });
});
