import { describe, expect, it } from "vitest";
import { collectNodes, parseJsonPath, readNode, writeNode } from "./jsonpath.js";

describe("parseJsonPath", () => {
  it("parses dotted keys and wildcards", () => {
    expect(parseJsonPath("$.data.items.*.name")).toEqual([
      { kind: "key", key: "data" },
      { kind: "key", key: "items" },
      { kind: "wildcard" },
      { kind: "key", key: "name" },
    ]);
  });

  it("parses array wildcards and indices", () => {
    expect(parseJsonPath("$.a[*].b[0]")).toEqual([
      { kind: "key", key: "a" },
      { kind: "anyIndex" },
      { kind: "key", key: "b" },
      { kind: "index", index: 0 },
    ]);
  });

  it("parses recursive descent and key unions", () => {
    expect(parseJsonPath("$.data.*.objectives[*]..bodyParts[*]")).toEqual([
      { kind: "key", key: "data" },
      { kind: "wildcard" },
      { kind: "key", key: "objectives" },
      { kind: "anyIndex" },
      { kind: "descendant", key: "bodyParts" },
      { kind: "anyIndex" },
    ]);

    expect(parseJsonPath("$.data.tasks.*['startRewards','finishRewards'][*]")).toEqual([
      { kind: "key", key: "data" },
      { kind: "key", key: "tasks" },
      { kind: "wildcard" },
      { kind: "union", keys: ["startRewards", "finishRewards"] },
      { kind: "anyIndex" },
    ]);
  });

  it("rejects paths that do not start at the root", () => {
    expect(() => parseJsonPath("data.items")).toThrow(/start with/);
  });

  it("rejects unsupported selectors", () => {
    expect(() => parseJsonPath("$.items[?(@.id)]")).toThrow(/Unsupported/);
    expect(() => parseJsonPath("$.items[name]")).toThrow(/Unsupported/);
  });
});

describe("collectNodes", () => {
  const root = {
    data: {
      items: {
        a: { name: "A", slots: [{ name: "slot-a" }] },
        b: { name: "B", slots: [] },
      },
      array: [{ name: "first" }, { name: "second" }],
    },
  };

  it("matches object wildcards", () => {
    const refs = collectNodes(root, parseJsonPath("$.data.items.*.name"));
    expect(refs.map(readNode)).toEqual(["A", "B"]);
  });

  it("matches wildcards over arrays, not just objects", () => {
    const refs = collectNodes(root, parseJsonPath("$.data.array.*.name"));
    expect(refs.map(readNode)).toEqual(["first", "second"]);
  });

  it("matches array wildcards inside objects", () => {
    const refs = collectNodes(root, parseJsonPath("$.data.items.*.slots[*].name"));
    expect(refs.map(readNode)).toEqual(["slot-a"]);
  });

  it("returns nothing for a stale path", () => {
    expect(collectNodes(root, parseJsonPath("$.data.armorMaterial.*.name"))).toEqual([]);
  });

  it("matches recursive descent at any depth", () => {
    const nested = {
      data: {
        objectives: [
          { healthEffect: { bodyParts: ["Head", "Chest"] } },
          { nested: { deeper: { bodyParts: ["LeftLeg"] } } },
        ],
      },
    };
    const refs = collectNodes(nested, parseJsonPath("$.data.objectives[*]..bodyParts[*]"));
    expect(refs.map(readNode)).toEqual(expect.arrayContaining(["Head", "Chest", "LeftLeg"]));
    expect(refs).toHaveLength(3);
  });

  it("matches a union of keys", () => {
    const union = {
      data: {
        tasks: {
          a: { startRewards: [{ customization: [{ name: "X" }] }] },
          b: { finishRewards: [{ customization: [{ name: "Y" }] }] },
          c: { unrelated: [{ customization: [{ name: "Z" }] }] },
        },
      },
    };
    const refs = collectNodes(
      union,
      parseJsonPath("$.data.tasks[*]['startRewards','finishRewards'][*].customization[*].name"),
    );
    expect(refs.map(readNode).sort()).toEqual(["X", "Y"]);
  });

  it("mutates the matched node in place", () => {
    const copy = structuredClone(root);
    const [ref] = collectNodes(copy, parseJsonPath("$.data.items.a.name"));
    expect(ref).toBeDefined();
    writeNode(ref!, "Renamed");
    expect(copy.data.items.a.name).toBe("Renamed");
  });
});
