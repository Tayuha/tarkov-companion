import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { loadLocalizedFixture } from "../fixtures/load.js";
import {
  NORMALIZE_DATASETS,
  normalizeDataset,
  serializeJsonl,
  type NormalizeDataset,
  type NormalizeResult,
} from "./index.js";

/**
 * Golden and invariant tests for the normalized bundle contract.
 *
 * The goldens are derived from the trimmed fixtures and are committed, so the
 * suite proves the exact bytes a bundle would contain without any network
 * access. A failure here means the contract changed: update the goldens only
 * after reviewing the diff.
 */

const GOLDEN_DIR = fileURLToPath(new URL("../../../test/fixtures/normalized/", import.meta.url));
const PLACEHOLDER = /^[0-9a-f]{24} \S/;

const RESULTS = new Map<NormalizeDataset, NormalizeResult>();

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseLine(line: string): Record<string, unknown> {
  const value: unknown = JSON.parse(line);
  if (!isRecord(value)) throw new Error("bundle line is not a JSON object");
  return value;
}

function walk(value: unknown, path: string, visit: (value: unknown, path: string) => void): void {
  visit(value, path);
  if (Array.isArray(value)) {
    value.forEach((entry, index) => walk(entry, `${path}[${index}]`, visit));
    return;
  }
  if (isRecord(value)) {
    for (const [key, entry] of Object.entries(value)) walk(entry, `${path}.${key}`, visit);
  }
}

async function normalized(dataset: NormalizeDataset): Promise<NormalizeResult> {
  const cached = RESULTS.get(dataset);
  if (cached !== undefined) return cached;

  const fixture = await loadLocalizedFixture("regular", dataset);
  const result = normalizeDataset(dataset, fixture.data);
  RESULTS.set(dataset, result);
  return result;
}

describe("bundle JSONL goldens", () => {
  it("registers every bundle dataset", () => {
    expect([...NORMALIZE_DATASETS]).toEqual([
      "items",
      "tasks",
      "traders",
      "hideout",
      "crafts",
      "barters",
      "maps",
    ]);
  });

  for (const dataset of NORMALIZE_DATASETS) {
    it(`normalizes ${dataset} to its committed golden byte for byte`, async () => {
      const result = await normalized(dataset);
      const golden = await readFile(join(GOLDEN_DIR, `${dataset}.jsonl`), "utf8");
      expect(serializeJsonl(result.records)).toBe(golden);
    });
  }

  it("re-normalizing the same fixture is deterministic", async () => {
    for (const dataset of NORMALIZE_DATASETS) {
      const first = await normalized(dataset);
      const fixture = await loadLocalizedFixture("regular", dataset);
      const second = normalizeDataset(dataset, fixture.data);

      expect(serializeJsonl(second.records)).toBe(serializeJsonl(first.records));
      expect(second.stats.counts).toEqual(first.stats.counts);
      expect(second.stats.droppedFields).toBe(first.stats.droppedFields);
    }
  });
});

describe("bundle JSONL invariants", () => {
  it("emits parseable lines with a unique kind and id", async () => {
    for (const dataset of NORMALIZE_DATASETS) {
      const result = await normalized(dataset);
      const text = serializeJsonl(result.records);
      expect(text.endsWith("\n")).toBe(true);

      const lines = text.slice(0, -1).split("\n");
      expect(lines).toHaveLength(result.records.length);

      const seen = new Set<string>();
      for (const line of lines) {
        const record = parseLine(line);
        expect(typeof record["kind"], `${dataset}: ${line.slice(0, 80)}`).toBe("string");
        expect(typeof record["id"], `${dataset}: ${line.slice(0, 80)}`).toBe("string");

        const key = `${String(record["kind"])}\u0000${String(record["id"])}`;
        expect(seen.has(key), `${dataset}: duplicate ${key}`).toBe(false);
        seen.add(key);
      }

      // Kind order then id order, by code unit.
      const order = result.records.map((record) => `${record.kind}\u0000${record.id}`);
      expect([...order].sort()).toEqual(order);
    }
  });

  it("never emits placeholders, undefined or non-finite numbers", async () => {
    for (const dataset of NORMALIZE_DATASETS) {
      const result = await normalized(dataset);

      for (const record of result.records) {
        walk(record, `${record.kind}/${record.id}`, (value, path) => {
          expect(value, `${dataset} ${path}: undefined`).not.toBeUndefined();
          if (typeof value === "number") {
            expect(Number.isFinite(value), `${dataset} ${path}: non-finite number`).toBe(true);
          }
          if (typeof value === "string") {
            expect(PLACEHOLDER.test(value), `${dataset} ${path}: placeholder "${value}"`).toBe(
              false,
            );
          }
        });
      }
    }
  });

  it("keeps price fields numeric and observed times ISO 8601 UTC", async () => {
    const result = await normalized("items");
    const priceFields = [
      "lastLow",
      "avg24h",
      "low24h",
      "high24h",
      "change48h",
      "change48hPercent",
      "lastOfferCount",
    ] as const;

    let items = 0;
    for (const record of result.records) {
      if (record.kind !== "item") continue;
      items += 1;

      const price = record["price"];
      expect(isRecord(price), `item ${record.id}: missing price`).toBe(true);
      if (!isRecord(price)) continue;

      for (const field of priceFields) {
        const value = price[field];
        const valid = value === null || (typeof value === "number" && Number.isFinite(value));
        expect(valid, `item ${record.id}: ${field} is not numeric`).toBe(true);
      }

      const observedAt = price["observedAt"];
      if (observedAt !== null) {
        expect(typeof observedAt, `item ${record.id}: observedAt`).toBe("string");
        if (typeof observedAt === "string") {
          expect(observedAt.endsWith("Z"), `item ${record.id}: observedAt not UTC`).toBe(true);
          expect(Number.isNaN(Date.parse(observedAt))).toBe(false);
        }
      }
    }

    expect(items).toBeGreaterThan(0);
  });

  it("gives every task objective a type discriminator", async () => {
    const result = await normalized("tasks");
    let objectives = 0;

    for (const record of result.records) {
      const groups =
        record.kind === "task"
          ? ["objectives", "failConditions"]
          : record.kind === "prestige"
            ? ["conditions"]
            : [];

      for (const group of groups) {
        const conditions = record[group];
        if (!Array.isArray(conditions)) continue;
        for (const condition of conditions) {
          objectives += 1;
          expect(isRecord(condition), `${record.kind}/${record.id}.${group}`).toBe(true);
          if (!isRecord(condition)) continue;
          expect(typeof condition["type"], `${record.kind}/${record.id}.${group}`).toBe("string");
        }
      }
    }

    expect(objectives).toBeGreaterThan(0);
  });

  it("accounts for every record in the per-kind stats", async () => {
    for (const dataset of NORMALIZE_DATASETS) {
      const result = await normalized(dataset);
      const sum = Object.values(result.stats.counts).reduce((total, count) => total + count, 0);

      expect(result.stats.dataset).toBe(dataset);
      expect(sum).toBe(result.records.length);
      expect(result.stats.droppedFields).toBeGreaterThanOrEqual(0);
      expect(result.stats.droppedFieldPaths).toHaveLength(
        new Set(result.stats.droppedFieldPaths).size,
      );
    }
  });
});
