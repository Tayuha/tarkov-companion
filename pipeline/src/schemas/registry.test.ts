import { describe, expect, it } from "vitest";
import { listFixtureFiles, readFixtureJson, type FixtureFile } from "./fixtures.js";
import {
  DATASET_DEFINITIONS,
  datasetForFixturePath,
  formatIssues,
  getDatasetSchema,
  parseDatasetData,
  parseDatasetEnvelope,
  parseDictionary,
  schemaForFixture,
  type DatasetDefinition,
} from "./registry.js";

/**
 * Schema acceptance and drift tests over the committed fixtures.
 *
 * Everything here runs offline. The point is symmetric: every recorded payload
 * must be accepted, and a removed or retyped known field must be rejected with
 * a path that names the field, while an added unknown field stays harmless.
 */

type JsonObject = Record<string, unknown>;

const FILES_PROMISE = listFixtureFiles();

function isObject(value: unknown): value is JsonObject {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function asObject(value: unknown, label: string): JsonObject {
  if (!isObject(value)) throw new Error(`${label} is not an object`);
  return value;
}

function isUnknownArray(value: unknown): value is unknown[] {
  return Array.isArray(value);
}

/** First record of an id-keyed map or of an array. */
function firstRecord(collection: unknown, label: string): JsonObject {
  const values = isUnknownArray(collection) ? collection : Object.values(asObject(collection, label));
  const first = values[0];
  if (first === undefined) throw new Error(`${label} is empty`);
  return asObject(first, `${label}[0]`);
}

function firstValue(collection: unknown, label: string): unknown {
  const values = isUnknownArray(collection) ? collection : Object.values(asObject(collection, label));
  const first = values[0];
  if (first === undefined) throw new Error(`${label} is empty`);
  return first;
}

function payloadData(payload: unknown): unknown {
  return asObject(payload, "payload")["data"];
}

function findByPath(files: readonly FixtureFile[], relativePath: string): FixtureFile {
  const file = files.find((candidate) => candidate.relativePath === relativePath);
  if (file === undefined) throw new Error(`fixture not found: ${relativePath}`);
  return file;
}

function definitionFor(file: FixtureFile): DatasetDefinition {
  return schemaForFixture(file.fixtureSet, file.pathWithinSet);
}

function describeParseFailure(result: ReturnType<typeof parseDatasetEnvelope>): string {
  return result.success ? "" : formatIssues(result.error);
}

function issueTailPaths(result: ReturnType<typeof parseDatasetEnvelope>): PropertyKey[] {
  if (result.success) return [];
  return result.error.issues.map((issue) => issue.path[issue.path.length - 1] ?? "<root>");
}

function issuePaths(result: ReturnType<typeof parseDatasetEnvelope>): string[] {
  if (result.success) return [];
  return result.error.issues.map((issue) => issue.path.join("."));
}

interface MutationCase {
  readonly fixture: string;
  /** Path segment that must appear in the reported error. */
  readonly field: string;
  readonly remove: (data: unknown) => void;
  readonly retype: (data: unknown) => void;
}

const MUTATION_CASES: readonly MutationCase[] = [
  {
    fixture: "regular/items.json",
    field: "weight",
    remove: (data) => {
      const item = firstRecord(asObject(data, "items data")["items"], "items");
      delete item["weight"];
    },
    retype: (data) => {
      firstRecord(asObject(data, "items data")["items"], "items")["weight"] = "heavy";
    },
  },
  {
    fixture: "pve/items.json",
    field: "properties",
    remove: (data) => {
      const item = firstRecord(asObject(data, "items data")["items"], "items");
      delete item["properties"];
    },
    retype: (data) => {
      firstRecord(asObject(data, "items data")["items"], "items")["properties"] = "not-an-object";
    },
  },
  {
    fixture: "pvp-season/items.json",
    field: "types",
    remove: (data) => {
      const item = firstRecord(asObject(data, "items data")["items"], "items");
      delete item["types"];
    },
    retype: (data) => {
      firstRecord(asObject(data, "items data")["items"], "items")["types"] = "gun";
    },
  },
  {
    fixture: "regular/tasks.json",
    field: "objectives",
    remove: (data) => {
      const task = firstRecord(asObject(data, "tasks data")["tasks"], "tasks");
      delete task["objectives"];
    },
    retype: (data) => {
      firstRecord(asObject(data, "tasks data")["tasks"], "tasks")["objectives"] = {};
    },
  },
  {
    fixture: "regular/traders.json",
    field: "levels",
    remove: (data) => {
      delete firstRecord(data, "traders")["levels"];
    },
    retype: (data) => {
      firstRecord(data, "traders")["levels"] = 1;
    },
  },
  {
    fixture: "regular/hideout.json",
    field: "areaType",
    remove: (data) => {
      delete firstRecord(data, "stations")["areaType"];
    },
    retype: (data) => {
      firstRecord(data, "stations")["areaType"] = "five";
    },
  },
  {
    fixture: "regular/crafts.json",
    field: "duration",
    remove: (data) => {
      delete firstRecord(data, "crafts")["duration"];
    },
    retype: (data) => {
      firstRecord(data, "crafts")["duration"] = "6200";
    },
  },
  {
    fixture: "regular/barters.json",
    field: "offeredItem",
    remove: (data) => {
      delete firstRecord(data, "barters")["offeredItem"];
    },
    retype: (data) => {
      firstRecord(data, "barters")["offeredItem"] = [];
    },
  },
  {
    fixture: "regular/maps.json",
    field: "spawns",
    remove: (data) => {
      const map = firstRecord(asObject(data, "maps data")["maps"], "maps");
      delete map["spawns"];
    },
    retype: (data) => {
      firstRecord(asObject(data, "maps data")["maps"], "maps")["spawns"] = "none";
    },
  },
  {
    fixture: "regular/prices/5447a9cd4bdc2dbd208b4567.json",
    field: "price",
    remove: (data) => {
      delete firstRecord(data, "price points")["price"];
    },
    retype: (data) => {
      firstRecord(data, "price points")["price"] = "expensive";
    },
  },
  {
    fixture: "common/status.json",
    field: "name",
    remove: (data) => {
      delete asObject(asObject(data, "status data")["generalStatus"], "generalStatus")["name"];
    },
    retype: (data) => {
      asObject(asObject(data, "status data")["generalStatus"], "generalStatus")["name"] = 0;
    },
  },
  {
    fixture: "pvp-season/season.json",
    field: "perks",
    remove: (data) => {
      delete asObject(data, "season")["perks"];
    },
    retype: (data) => {
      asObject(data, "season")["perks"] = [];
    },
  },
];

function expectFailureNaming(
  result: ReturnType<typeof parseDatasetEnvelope>,
  field: string,
  fixture: string,
): void {
  expect(result.success, `${fixture} should have been rejected`).toBe(false);
  expect(issueTailPaths(result), `${fixture} error paths`).toContain(field);
}

describe("upstream schema registry", () => {
  it("covers every fixture and only registers datasets with fixtures", async () => {
    const files = await FILES_PROMISE;
    const fixtureKeys = [
      ...new Set(
        files
          .filter((file) => file.kind === "base")
          .map((file) => `${file.fixtureSet}/${datasetForFixturePath(file.pathWithinSet)}`),
      ),
    ].sort();
    const schemaKeys = DATASET_DEFINITIONS.map(
      (definition) => `${definition.mode}/${definition.dataset}`,
    ).sort();

    expect(fixtureKeys).toEqual(schemaKeys);
  });

  it("validates every game mode through the regular contract when a mode has no fixture", () => {
    for (const dataset of ["items", "tasks", "traders", "hideout", "crafts", "barters", "maps", "prices"]) {
      const regular = getDatasetSchema("regular", dataset);
      expect(regular, `regular/${dataset} must be registered`).toBeDefined();

      for (const mode of ["pve", "pvp-season"]) {
        const definition = getDatasetSchema(mode, dataset);
        expect(definition, `${mode}/${dataset} must resolve`).toBeDefined();
        expect(definition?.data).toBe(regular?.data);
      }
    }

    expect(getDatasetSchema("pvp-season", "season")).toBeDefined();
    expect(getDatasetSchema("common", "status")).toBeDefined();
  });

  it("accepts every base fixture through its registered envelope and data schema", async () => {
    const files = await FILES_PROMISE;
    const bases = files.filter((file) => file.kind === "base");
    expect(bases.length).toBeGreaterThan(0);

    for (const file of bases) {
      const definition = definitionFor(file);
      const payload = await readFixtureJson(file.relativePath);

      const envelope = parseDatasetEnvelope(definition.mode, definition.dataset, payload);
      expect(envelope.success, `${file.relativePath}: ${describeParseFailure(envelope)}`).toBe(true);

      const data = parseDatasetData(definition.mode, definition.dataset, payloadData(payload));
      expect(
        data.success,
        `${file.relativePath} data: ${data.success ? "" : formatIssues(data.error)}`,
      ).toBe(true);
    }
  });

  it("accepts every dictionary fixture and pairs it with a base fixture", async () => {
    const files = await FILES_PROMISE;
    const dictionaries = files.filter((file) => file.kind === "dictionary");
    expect(dictionaries.length).toBeGreaterThan(0);

    const basePaths = new Set(
      files.filter((file) => file.kind === "base").map((file) => file.relativePath),
    );

    for (const file of dictionaries) {
      const payload = await readFixtureJson(file.relativePath);
      const result = parseDictionary(payload);
      expect(
        result.success,
        `${file.relativePath}: ${result.success ? "" : formatIssues(result.error)}`,
      ).toBe(true);

      const base = file.relativePath.replace(/_en\.json$/, ".json");
      expect(basePaths.has(base), `${file.relativePath} has no base fixture`).toBe(true);
    }
  });

  it("tolerates unknown fields at the envelope and record level", async () => {
    const files = await FILES_PROMISE;
    const bases = files.filter((file) => file.kind === "base");

    for (const file of bases) {
      const definition = definitionFor(file);
      const payload = structuredClone(await readFixtureJson(file.relativePath));
      const root = asObject(payload, file.relativePath);
      root["__syntheticEnvelope"] = { added: "upstream" };

      const data = root["data"];
      if (isUnknownArray(data)) {
        root["data"] = data.map((entry) =>
          isObject(entry) ? { ...entry, __syntheticRecord: true } : entry,
        );
      } else {
        injectIntoFirstRecord(definition.dataset, asObject(data, `${file.relativePath} data`));
      }

      const result = parseDatasetEnvelope(definition.mode, definition.dataset, payload);
      expect(
        result.success,
        `${file.relativePath} rejected an unknown field: ${describeParseFailure(result)}`,
      ).toBe(true);
    }
  });

  for (const mutation of MUTATION_CASES) {
    it(`rejects ${mutation.fixture} with a required field removed`, async () => {
      const files = await FILES_PROMISE;
      const file = findByPath(files, mutation.fixture);
      const definition = definitionFor(file);
      const payload = structuredClone(await readFixtureJson(file.relativePath));

      mutation.remove(payloadData(payload));

      const result = parseDatasetEnvelope(definition.mode, definition.dataset, payload);
      expectFailureNaming(result, mutation.field, mutation.fixture);
      expect(issuePaths(result).some((path) => path.endsWith(mutation.field))).toBe(true);
    });

    it(`rejects ${mutation.fixture} with a known field retyped`, async () => {
      const files = await FILES_PROMISE;
      const file = findByPath(files, mutation.fixture);
      const definition = definitionFor(file);
      const payload = structuredClone(await readFixtureJson(file.relativePath));

      mutation.retype(payloadData(payload));

      const result = parseDatasetEnvelope(definition.mode, definition.dataset, payload);
      expectFailureNaming(result, mutation.field, mutation.fixture);
    });
  }
});

/**
 * Add a synthetic key inside the first record of a dataset's primary
 * collection so the test exercises the record schema, not only the data root.
 */
function injectIntoFirstRecord(dataset: string, data: JsonObject): void {
  switch (dataset) {
    case "items": {
      asObject(firstValue(data["items"], "items"), "first item")["__syntheticRecord"] = true;
      return;
    }
    case "tasks": {
      asObject(firstValue(data["tasks"], "tasks"), "first task")["__syntheticRecord"] = true;
      return;
    }
    case "maps": {
      asObject(firstValue(data["maps"], "maps"), "first map")["__syntheticRecord"] = true;
      return;
    }
    case "status": {
      asObject(data["generalStatus"], "generalStatus")["__syntheticRecord"] = true;
      return;
    }
    case "season": {
      data["__syntheticRecord"] = true;
      return;
    }
    default: {
      if (isObject(data)) {
        // Id-keyed maps (traders, hideout): annotate the first entity.
        const first = Object.values(data)[0];
        if (isObject(first)) first["__syntheticRecord"] = true;
        else data["__syntheticRecord"] = true;
      }
    }
  }
}
