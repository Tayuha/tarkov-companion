import {
  type BundleRecord,
  type FieldSpec,
  type NormalizeContext,
  integerValue,
  makeRecord,
  projectFields,
  projectList,
  projectMap,
  requireRecord,
  stringList,
} from "./contract.js";

/**
 * `/regular/hideout` -> `hideoutStation` records, keyed by station id.
 *
 * Levels, bonuses and requirements are embedded because they are owned by the
 * station. Item, skill, station and trader references are ids.
 */

const BONUS_SPEC: FieldSpec = {
  name: "name",
  type: "type",
  value: "value",
  passive: "passive",
  production: "production",
  skill: "skill",
  slotItems: { to: "slotItemIds", transform: stringList },
};

const ITEM_REQUIREMENT_SPEC: FieldSpec = {
  id: "id",
  item: "itemId",
  count: { to: "count", transform: integerValue },
  attributes: {
    to: "foundInRaid",
    transform: (value, ctx, path) =>
      projectFields(requireRecord(value, path), { foundInRaid: "foundInRaid" }, ctx, path)[
        "foundInRaid"
      ],
  },
};

const SKILL_REQUIREMENT_SPEC: FieldSpec = {
  id: "id",
  skill: "skill",
  level: { to: "level", transform: integerValue },
};

const STATION_LEVEL_REQUIREMENT_SPEC: FieldSpec = {
  id: "id",
  station: "stationId",
  level: { to: "level", transform: integerValue },
};

const TRADER_REQUIREMENT_SPEC: FieldSpec = {
  id: "id",
  trader: "traderId",
  requirementType: "requirementType",
  compareMethod: "compareMethod",
  value: "value",
};

const HIDEOUT_LEVEL_SPEC: FieldSpec = {
  id: "id",
  level: { to: "level", transform: integerValue },
  description: "description",
  constructionTime: { to: "constructionTime", transform: integerValue },
  bonuses: {
    to: "bonuses",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, BONUS_SPEC, context, entryPath),
      ),
  },
  itemRequirements: {
    to: "itemRequirements",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, ITEM_REQUIREMENT_SPEC, context, entryPath),
      ),
  },
  skillRequirements: {
    to: "skillRequirements",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, SKILL_REQUIREMENT_SPEC, context, entryPath),
      ),
  },
  stationLevelRequirements: {
    to: "stationLevelRequirements",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, STATION_LEVEL_REQUIREMENT_SPEC, context, entryPath),
      ),
  },
  traderRequirements: {
    to: "traderRequirements",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, TRADER_REQUIREMENT_SPEC, context, entryPath),
      ),
  },
};

const HIDEOUT_STATION_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
  areaType: { to: "areaType", transform: integerValue },
  imageLink: "imageLink",
  levels: {
    to: "levels",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, HIDEOUT_LEVEL_SPEC, context, entryPath),
      ),
  },
};

export function normalizeHideout(data: unknown, ctx: NormalizeContext): BundleRecord[] {
  return projectMap(data, ctx, "hideout", (entry, context, path) =>
    makeRecord("hideoutStation", projectFields(entry, HIDEOUT_STATION_SPEC, context, path)),
  );
}
