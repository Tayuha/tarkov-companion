import type { z } from "zod";
import type { GameMode } from "../upstream/fetch.js";
import { bartersDataSchema } from "./barters.js";
import { craftsDataSchema } from "./crafts.js";
import { dictionarySchema, envelopeSchemaFor } from "./envelope.js";
import { hideoutDataSchema } from "./hideout.js";
import { itemsDataSchema } from "./items.js";
import { mapsDataSchema } from "./maps.js";
import { pricesDataSchema } from "./prices.js";
import { seasonDataSchema } from "./season.js";
import { statusDataSchema } from "./status.js";
import { tasksDataSchema } from "./tasks.js";
import { tradersDataSchema } from "./traders.js";

/**
 * Registry of upstream dataset schemas, keyed by `{mode, dataset}`.
 *
 * Every committed fixture must resolve to exactly one entry here, and every
 * entry must have at least one committed fixture; the registry test enforces
 * both directions so no recorded dataset can silently go unvalidated.
 *
 * Only fixtures that were actually captured are registered. `pve/tasks` has no
 * entry because no such fixture exists yet; adding one without a schema is a
 * test failure, not a silent pass.
 */

export type FixtureMode = GameMode | "common";

export interface DatasetDefinition {
  readonly mode: FixtureMode;
  readonly dataset: string;
  /** Validates the payload's `data` value. */
  readonly data: z.ZodType;
  /** Validates the full `{data, translations?}` response. */
  readonly envelope: z.ZodType;
}

function defineDataset(mode: FixtureMode, dataset: string, data: z.ZodType): DatasetDefinition {
  return {
    mode,
    dataset,
    data,
    envelope: envelopeSchemaFor(data),
  };
}

export const DATASET_DEFINITIONS: readonly DatasetDefinition[] = [
  defineDataset("regular", "items", itemsDataSchema),
  defineDataset("regular", "tasks", tasksDataSchema),
  defineDataset("regular", "traders", tradersDataSchema),
  defineDataset("regular", "hideout", hideoutDataSchema),
  defineDataset("regular", "crafts", craftsDataSchema),
  defineDataset("regular", "barters", bartersDataSchema),
  defineDataset("regular", "maps", mapsDataSchema),
  defineDataset("regular", "prices", pricesDataSchema),
  defineDataset("pve", "items", itemsDataSchema),
  defineDataset("pvp-season", "items", itemsDataSchema),
  defineDataset("pvp-season", "season", seasonDataSchema),
  defineDataset("common", "status", statusDataSchema),
];

const definitionsByKey = new Map(
  DATASET_DEFINITIONS.map((definition) => [
    `${definition.mode}/${definition.dataset}`,
    definition,
  ]),
);

export function getDatasetSchema(mode: string, dataset: string): DatasetDefinition | undefined {
  return definitionsByKey.get(`${mode}/${dataset}`);
}

/**
 * Map a base fixture file to its dataset id. Price history is a dataset with
 * one file per item id, so any path under `prices/` maps to `prices`.
 */
export function datasetForFixturePath(relativePath: string): string {
  if (relativePath.startsWith("prices/")) return "prices";
  return relativePath.replace(/\.json$/, "");
}

export function schemaForFixture(fixtureSet: string, relativePath: string): DatasetDefinition {
  const dataset = datasetForFixturePath(relativePath);
  const definition = getDatasetSchema(fixtureSet, dataset);
  if (definition === undefined) {
    throw new Error(`no schema registered for ${fixtureSet}/${dataset} (${relativePath})`);
  }
  return definition;
}

export function parseDatasetData(
  mode: string,
  dataset: string,
  data: unknown,
): z.ZodSafeParseResult<unknown> {
  const definition = getDatasetSchema(mode, dataset);
  if (definition === undefined) {
    throw new Error(`no schema registered for ${mode}/${dataset}`);
  }
  return definition.data.safeParse(data);
}

export function parseDatasetEnvelope(
  mode: string,
  dataset: string,
  payload: unknown,
): z.ZodSafeParseResult<unknown> {
  const definition = getDatasetSchema(mode, dataset);
  if (definition === undefined) {
    throw new Error(`no schema registered for ${mode}/${dataset}`);
  }
  return definition.envelope.safeParse(payload);
}

export function parseDictionary(payload: unknown): z.ZodSafeParseResult<unknown> {
  return dictionarySchema.safeParse(payload);
}

/** Human-readable `path: message` lines for a failed parse. */
export function formatIssues(error: z.ZodError): string {
  return error.issues
    .map((issue) => {
      const path = issue.path.length > 0 ? issue.path.join(".") : "<root>";
      return `${path}: ${issue.message}`;
    })
    .join("\n");
}

/**
 * Per-dataset record counts for the validate CLI. Counts describe the payload
 * shape, not the number of validated rows (an empty collection is valid).
 */
export function describeRecordCounts(
  dataset: string,
  data: unknown,
): Readonly<Record<string, number>> {
  const record = (value: unknown): Record<string, unknown> | null =>
    typeof value === "object" && value !== null && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  const size = (value: unknown): number => {
    if (Array.isArray(value)) return value.length;
    const object = record(value);
    return object === null ? 0 : Object.keys(object).length;
  };

  const root = record(data);

  switch (dataset) {
    case "items":
      return { items: size(root?.["items"]) };
    case "tasks": {
      return {
        tasks: size(root?.["tasks"]),
        questItems: size(root?.["questItems"]),
        achievements: size(root?.["achievements"]),
        prestige: size(root?.["prestige"]),
      };
    }
    case "maps":
      return {
        maps: size(root?.["maps"]),
        mobs: size(root?.["mobs"]),
        lootContainers: size(root?.["lootContainers"]),
      };
    case "traders":
    case "hideout":
      return { records: size(root) };
    case "crafts":
    case "barters":
    case "prices":
      return { records: size(data) };
    case "status":
      return { statuses: size(root?.["currentStatuses"]) };
    case "season":
      return { records: 1 };
    default:
      return { records: size(data) };
  }
}
