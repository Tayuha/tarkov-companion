import { describe, expect, it } from "vitest";
import {
  canonicalJson,
  selectRecords,
  sortKeysDeep,
  truncateArrays,
  trimPayload,
} from "./trim.js";

const RECORDS = [
  { id: "c", name: "Charlie", kind: "b", nested: { keep: 1, drop: [1, 2, 3, 4, 5, 6] } },
  { id: "a", name: "Alpha", kind: "a", nested: { keep: 1, drop: [1, 2, 3, 4, 5, 6] } },
  { id: "b", name: "Bravo", kind: "a", nested: { keep: 1, drop: [1, 2, 3, 4, 5, 6] } },
  { id: "d", name: "Delta", kind: "b", nested: { keep: 1, drop: [1, 2, 3, 4, 5, 6] } },
] as const;

describe("selectRecords", () => {
  it("sorts by id and takes the first N regardless of input order", () => {
    const first = selectRecords(RECORDS, { limit: 2 });
    const second = selectRecords([...RECORDS].reverse(), { limit: 2 });

    expect(first.selected.map((record) => (record as { id: string }).id)).toEqual(["a", "b"]);
    expect(second.selected).toEqual(first.selected);
    expect(first.total).toBe(4);
  });

  it("keeps the first record of every structural group before filling", () => {
    const result = selectRecords(RECORDS, {
      limit: 2,
      perGroup: 1,
      groupKey: (value) => (value as { kind: string }).kind,
    });

    expect(result.selected.map((record) => (record as { id: string }).id)).toEqual(["a", "c"]);
  });

  it("prioritises records that introduce a requested feature", () => {
    const result = selectRecords(RECORDS, {
      limit: 2,
      featuresOf: (value) => [(value as { kind: string }).kind],
    });

    expect(result.selected.map((record) => (record as { id: string }).id)).toEqual(["a", "c"]);
    expect(result.featuresCovered).toBe(2);
    expect(result.featuresTotal).toBe(2);
  });
});

describe("truncateArrays", () => {
  it("caps arrays while preserving one element per shape", () => {
    const input = {
      scalar: "x",
      list: [
        { shape: "a", value: 1 },
        { shape: "a", value: 2 },
        { kind: "b", value: 3 },
        { shape: "a", value: 4 },
        { shape: "a", value: 5 },
      ],
      nested: [{ deep: [1, 2, 3, 4, 5, 6, 7] }],
    };

    const trimmed = truncateArrays(input, 2) as typeof input;
    expect(trimmed.list).toEqual([
      { shape: "a", value: 1 },
      { kind: "b", value: 3 },
    ]);
    expect(trimmed.scalar).toBe("x");
    expect(trimmed.nested[0]?.deep).toHaveLength(2);
    expect(truncateArrays(trimmed, 2)).toEqual(trimmed);
  });

  it("never removes object keys from a retained record", () => {
    const record = { id: "a", name: "A", properties: { type: "x", values: [1, 2, 3, 4] } };
    const trimmed = truncateArrays(record, 2) as Record<string, unknown>;

    expect(Object.keys(trimmed).sort()).toEqual(["id", "name", "properties"]);
    expect(trimmed.id).toBe("a");
    expect(trimmed.name).toBe("A");
    expect(trimmed.properties).toEqual({ type: "x", values: [1, 2] });
  });
});

describe("trimPayload", () => {
  it("is deterministic and keeps the complete key shape of retained records", () => {
    const payload = {
      items: Object.fromEntries(RECORDS.map((record) => [record.id, record])),
      settings: { keep: true },
    };

    const first = trimPayload(payload, {
      nestedArrayLimit: 3,
      collections: {
        items: { kind: "records", limit: 2, perGroup: 1, groupKey: (value) => (value as { kind: string }).kind },
      },
    });
    const second = trimPayload(payload, {
      nestedArrayLimit: 3,
      collections: {
        items: { kind: "records", limit: 2, perGroup: 1, groupKey: (value) => (value as { kind: string }).kind },
      },
    });

    expect(second).toEqual(first);
    expect(Object.keys(first.data as object).sort()).toEqual(["items", "settings"]);
    expect(Object.keys((first.data as { items: object }).items).sort()).toEqual(["a", "c"]);
    expect(first.stats).toEqual([
      { key: "items", input: 4, output: 2, featuresCovered: 0, featuresTotal: 0 },
    ]);

    const retained = (first.data as { items: Record<string, { nested: { drop: number[] } }> }).items;
    expect(retained.a?.nested.drop).toEqual([1, 2, 3]);
  });

  it("keeps planned collections whole", () => {
    const payload = { aux: [1, 2, 3, 4, 5], items: { a: { id: "a", list: [1, 2, 3, 4] } } };
    const result = trimPayload(payload, {
      nestedArrayLimit: 2,
      collections: { aux: { kind: "keep" }, items: { kind: "keep" } },
    });

    expect((result.data as { aux: number[] }).aux).toEqual([1, 2, 3, 4, 5]);
    expect((result.data as { items: { a: { list: number[] } } }).items.a.list).toEqual([
      1, 2, 3, 4,
    ]);
  });
});

describe("sortKeysDeep", () => {
  it("produces canonical JSON independent of key order", () => {
    const one = { b: 1, a: { d: 2, c: [{ z: 1, y: 2 }] } };
    const two = { a: { c: [{ y: 2, z: 1 }], d: 2 }, b: 1 };

    expect(canonicalJson(one)).toBe(canonicalJson(two));
    expect(JSON.stringify(sortKeysDeep(one))).toContain('"a"');
  });
});
