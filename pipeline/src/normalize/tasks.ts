import {
  PLACEHOLDER_PATTERN,
  type BundleRecord,
  type FieldSpec,
  type JsonRecord,
  type NormalizeContext,
  integerValue,
  makeRecord,
  nullableNumber,
  numberValue,
  projectFields,
  projectList,
  projectMap,
  requireId,
  requireRecord,
  stringList,
  stringMatrix,
  vector3,
  vector3List,
} from "./contract.js";

/**
 * `/regular/tasks` -> bundle records.
 *
 * Kinds: `task`, `questItem`, `achievement`, `prestige`.
 *
 * Objectives, fail conditions and prestige conditions are discriminated by
 * `type`. Each type admits only its own fields, so the client never has to
 * guess whether a union field is meaningful for the objective it is reading.
 */

const UNNAMED_CUSTOMIZATION = "Unnamed customization";

const COMMON_CONDITION_FIELDS = new Set(["id", "type", "description", "optional", "maps"]);

/** Fields admitted per objective (also used for fail and prestige conditions). */
const CONDITION_FIELDS: Readonly<Record<string, readonly string[]>> = {
  buildWeapon: ["buildAttributes", "containsAll", "containsCategory", "count", "item", "zones"],
  dialogue: ["count", "traders", "zones"],
  experience: ["bodyParts", "count", "effects", "healthEffect", "zones"],
  extract: ["bodyParts", "count", "effects", "exitName", "exitStatus", "healthEffect"],
  findItem: ["count", "dogTagLevel", "foundInRaid", "items", "maxDurability", "minDurability", "zones"],
  findQuestItem: ["count", "possibleLocations", "questItem", "requiredKeys"],
  giveItem: ["count", "dogTagLevel", "foundInRaid", "items", "maxDurability", "minDurability"],
  giveQuestItem: ["count", "questItem"],
  globalVariable: ["count", "globalVariable", "zones"],
  haveItem: ["count", "dogTagLevel", "foundInRaid", "items", "maxDurability", "minDurability"],
  hideoutStation: ["count", "station", "stationLevel"],
  mark: ["count", "markerItem", "requiredKeys", "zones"],
  plantItem: [
    "count",
    "dogTagLevel",
    "foundInRaid",
    "items",
    "maxDurability",
    "minDurability",
    "requiredKeys",
    "zones",
  ],
  plantQuestItem: ["count", "questItem", "requiredKeys", "zones"],
  playerLevel: ["count", "playerLevel"],
  sellItem: ["count", "dogTagLevel", "foundInRaid", "items", "maxDurability", "minDurability", "zones"],
  shoot: [
    "bodyParts",
    "count",
    "distance",
    "effects",
    "enemyHealthEffect",
    "healthEffect",
    "notWearing",
    "playerHealthEffect",
    "shotType",
    "targetNames",
    "timeFromHour",
    "timeUntilHour",
    "usingWeapon",
    "usingWeaponMods",
    "wearing",
    "zones",
  ],
  skill: ["level", "skill", "zones"],
  taskStatus: ["count", "status", "task", "zones"],
  traderLevel: ["level", "trader"],
  traderStanding: ["compareMethod", "trader", "value"],
  useItem: ["compareMethod", "count", "useAny", "zones"],
  visit: ["requiredKeys", "zones"],
};

const COMPARISON_SPEC: FieldSpec = {
  compareMethod: "compareMethod",
  value: "value",
};

const HEALTH_EFFECT_SPEC: FieldSpec = {
  bodyParts: { to: "bodyParts", transform: stringList },
  effects: { to: "effects", transform: stringList },
  time: { to: "time", transform: projectComparison },
};

const POSSIBLE_LOCATION_SPEC: FieldSpec = {
  map: "mapId",
  positions: { to: "positions", transform: vector3List },
};

const ZONE_SPEC: FieldSpec = {
  id: "id",
  map: "mapId",
  name: "name",
  bottom: { to: "bottom", transform: numberValue },
  top: { to: "top", transform: numberValue },
  position: { to: "position", transform: vector3 },
  outline: { to: "outline", transform: vector3List },
  size: { to: "size", transform: vector3 },
  terrainElevation: { to: "terrainElevation", transform: numberValue },
};

const GLOBAL_VARIABLE_SPEC: FieldSpec = {
  id: "globalVariableId",
  compareMethod: "compareMethod",
  value: "value",
};

const CONDITION_SPEC: FieldSpec = {
  id: "id",
  type: "type",
  description: "description",
  optional: "optional",
  maps: { to: "mapIds", transform: stringList },
  count: { to: "count", transform: nullableNumber },
  item: "itemId",
  items: { to: "itemIds", transform: stringList },
  questItem: "questItemId",
  markerItem: "markerItemId",
  task: "taskId",
  trader: "traderId",
  traders: { to: "traderIds", transform: stringList },
  station: "stationId",
  usingWeapon: { to: "usingWeaponItemIds", transform: stringList },
  usingWeaponMods: { to: "usingWeaponModItemIds", transform: stringMatrix },
  requiredKeys: { to: "requiredKeyItemIds", transform: stringMatrix },
  notWearing: { to: "notWearingItemIds", transform: stringList },
  wearing: { to: "wearingItemIds", transform: projectWearing },
  possibleLocations: { to: "possibleLocations", transform: projectPossibleLocations },
  zones: { to: "zones", transform: projectZones },
  buildAttributes: { to: "buildAttributes", transform: projectComparisonMap },
  distance: { to: "distance", transform: nullableComparison },
  healthEffect: { to: "healthEffect", transform: nullableHealthEffect },
  playerHealthEffect: { to: "playerHealthEffect", transform: nullableHealthEffect },
  enemyHealthEffect: { to: "enemyHealthEffect", transform: nullableHealthEffect },
  globalVariable: { to: "globalVariable", transform: projectGlobalVariable },
  status: { to: "status", transform: stringList },
  exitStatus: { to: "exitStatus", transform: stringList },
  exitName: "exitName",
  skill: "skill",
  level: { to: "level", transform: numberValue },
  playerLevel: { to: "playerLevel", transform: numberValue },
  stationLevel: { to: "stationLevel", transform: numberValue },
  dogTagLevel: { to: "dogTagLevel", transform: numberValue },
  minDurability: { to: "minDurability", transform: numberValue },
  maxDurability: { to: "maxDurability", transform: numberValue },
  timeFromHour: { to: "timeFromHour", transform: nullableNumber },
  timeUntilHour: { to: "timeUntilHour", transform: nullableNumber },
  value: { to: "value", transform: numberValue },
  compareMethod: "compareMethod",
  shotType: "shotType",
  effects: { to: "effects", transform: stringList },
  bodyParts: { to: "bodyParts", transform: stringList },
  foundInRaid: "foundInRaid",
  targetNames: { to: "targetNames", transform: stringList },
  containsAll: { to: "containsAllItemIds", transform: stringList },
  containsCategory: { to: "containsCategoryIds", transform: stringList },
  useAny: { to: "useAnyItemIds", transform: stringList },
};

const CRAFT_UNLOCK_SPEC: FieldSpec = {
  count: { to: "count", transform: integerValue },
  item: "itemId",
  level: { to: "level", transform: integerValue },
  station: "stationId",
};

const CUSTOMIZATION_SPEC: FieldSpec = {
  customizationType: "customizationType",
  customizationTypeName: "customizationTypeName",
  id: "id",
  name: { to: "name", transform: customizationName },
  imageLink: "imageLink",
  items: { to: "itemIds", transform: stringList },
};

const REWARD_ITEM_SPEC: FieldSpec = {
  attributes: "attributes",
  count: "count",
  item: "itemId",
};

const OFFER_UNLOCK_SPEC: FieldSpec = {
  attributes: "attributes",
  contains: {
    to: "contains",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, REWARD_ITEM_SPEC, context, entryPath),
      ),
  },
  count: "count",
  id: "id",
  item: "itemId",
  level: "level",
  trader: "traderId",
};

const SKILL_LEVEL_REWARD_SPEC: FieldSpec = {
  level: { to: "level", transform: integerValue },
  skill: "skill",
};

const TRADER_STANDING_SPEC: FieldSpec = {
  standing: "standing",
  trader: "traderId",
};

const REWARDS_SPEC: FieldSpec = {
  achievement: { to: "achievementIds", transform: stringList },
  craftUnlock: { to: "craftUnlock", transform: projectCraftUnlocks },
  customization: { to: "customization", transform: projectCustomizations },
  items: { to: "items", transform: projectRewardItems },
  offerUnlock: { to: "offerUnlock", transform: projectOfferUnlocks },
  skillLevelReward: { to: "skillLevelReward", transform: projectSkillLevelRewards },
  traderStanding: { to: "traderStanding", transform: projectTraderStandings },
  traderUnlock: { to: "traderUnlockIds", transform: stringList },
  locationUnlock: { to: "locationUnlockIds", transform: stringList },
  traderDialogueUnlock: { to: "traderDialogueUnlockIds", transform: stringList },
};

const TASK_REQUIREMENT_SPEC: FieldSpec = {
  status: { to: "status", transform: stringList },
  task: "taskId",
  notes: "notes",
};

const TRADER_REQUIREMENT_SPEC: FieldSpec = {
  id: "id",
  compareMethod: "compareMethod",
  requirementType: "requirementType",
  trader: "traderId",
  value: "value",
};

const NEEDED_KEYS_SPEC: FieldSpec = {
  keys: { to: "keyItemIds", transform: stringList },
  map: "mapId",
};

const OTHER_REQUIREMENT_SPEC: FieldSpec = {
  id: "id",
  type: "type",
  compareMethod: "compareMethod",
  traders: { to: "traderIds", transform: stringList },
  value: "value",
  variableId: "variableId",
};

const TASK_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
  experience: { to: "experience", transform: integerValue },
  factionName: "factionName",
  kappaRequired: "kappaRequired",
  lightkeeperRequired: "lightkeeperRequired",
  restartable: "restartable",
  minPlayerLevel: { to: "minPlayerLevel", transform: integerValue },
  map: { to: "mapId", transform: nullableId },
  trader: "traderId",
  requiredPrestige: "requiredPrestigeId",
  taskImageLink: "taskImageLink",
  wikiLink: "wikiLink",
  gameMode: { to: "gameMode", transform: stringList },
  availableDelaySecondsMin: { to: "availableDelaySecondsMin", transform: integerValue },
  availableDelaySecondsMax: { to: "availableDelaySecondsMax", transform: integerValue },
  objectives: { to: "objectives", transform: projectConditions },
  failConditions: { to: "failConditions", transform: projectConditions },
  startRewards: { to: "startRewards", transform: projectRewards },
  finishRewards: { to: "finishRewards", transform: projectRewards },
  failureOutcome: { to: "failureOutcome", transform: projectRewards },
  taskRequirements: {
    to: "taskRequirements",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, TASK_REQUIREMENT_SPEC, context, entryPath),
      ),
  },
  traderRequirements: {
    to: "traderRequirements",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, TRADER_REQUIREMENT_SPEC, context, entryPath),
      ),
  },
  neededKeys: {
    to: "neededKeys",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, NEEDED_KEYS_SPEC, context, entryPath),
      ),
  },
  otherRequirements: {
    to: "otherRequirements",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, OTHER_REQUIREMENT_SPEC, context, entryPath),
      ),
  },
};

const QUEST_ITEM_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  shortName: "shortName",
  description: "description",
  normalizedName: "normalizedName",
  baseImageLink: "baseImageLink",
  gridImageLink: "gridImageLink",
  iconLink: "iconLink",
  image512pxLink: "image512pxLink",
  image8xLink: "image8xLink",
  inspectImageLink: "inspectImageLink",
  height: { to: "height", transform: integerValue },
  width: { to: "width", transform: integerValue },
};

const ACHIEVEMENT_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  description: "description",
  normalizedName: "normalizedName",
  hidden: "hidden",
  imageLink: "imageLink",
  rarity: "rarity",
  normalizedRarity: "normalizedRarity",
  side: "side",
  normalizedSide: "normalizedSide",
  playersCompletedPercent: "playersCompletedPercent",
  adjustedPlayersCompletedPercent: "adjustedPlayersCompletedPercent",
};

const TRANSFER_SETTING_SPEC: FieldSpec = {
  gridHeight: { to: "gridHeight", transform: integerValue },
  gridWidth: { to: "gridWidth", transform: integerValue },
  itemFilters: { to: "itemFilters", transform: projectItemFilters },
  name: "name",
  skillType: "skillType",
  transferRate: "transferRate",
};

const PRESTIGE_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  prestigeLevel: { to: "prestigeLevel", transform: integerValue },
  iconLink: "iconLink",
  imageLink: "imageLink",
  conditions: { to: "conditions", transform: projectConditions },
  rewards: { to: "rewards", transform: projectRewards },
  transferSettings: {
    to: "transferSettings",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, TRANSFER_SETTING_SPEC, context, entryPath),
      ),
  },
};

const ITEM_FILTER_SPEC: FieldSpec = {
  allowedCategories: { to: "allowedCategoryIds", transform: stringList },
  allowedItems: { to: "allowedItemIds", transform: stringList },
  excludedCategories: { to: "excludedCategoryIds", transform: stringList },
  excludedItems: { to: "excludedItemIds", transform: stringList },
};

export function normalizeTasks(data: unknown, ctx: NormalizeContext): BundleRecord[] {
  const root = requireRecord(data, "tasks");
  const records: BundleRecord[] = [];

  for (const [key, value] of Object.entries(root)) {
    switch (key) {
      case "tasks":
        records.push(
          ...projectMap(value, ctx, "tasks.tasks", (entry, context, path) =>
            makeRecord("task", projectFields(entry, TASK_SPEC, context, path)),
          ),
        );
        break;
      case "questItems":
        records.push(
          ...projectMap(value, ctx, "tasks.questItems", (entry, context, path) =>
            makeRecord("questItem", projectFields(entry, QUEST_ITEM_SPEC, context, path)),
          ),
        );
        break;
      case "achievements":
        records.push(
          ...projectMap(value, ctx, "tasks.achievements", (entry, context, path) =>
            makeRecord("achievement", projectFields(entry, ACHIEVEMENT_SPEC, context, path)),
          ),
        );
        break;
      case "prestige":
        records.push(
          ...(projectList(value, ctx, "tasks.prestige", (entry, context, path) =>
            makeRecord("prestige", projectFields(entry, PRESTIGE_SPEC, context, path)),
          ) ?? []),
        );
        break;
      default:
        ctx.stats.drop(`tasks.${key}`);
    }
  }

  return records;
}

function nullableId(
  value: unknown,
  _ctx: NormalizeContext,
  path: string,
): string | null | undefined {
  if (value === null) return null;
  if (typeof value !== "string") return undefined;
  return requireId(value, path);
}

function projectConditions(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectCondition(entry, context, entryPath),
  );
}

function projectCondition(
  source: JsonRecord,
  ctx: NormalizeContext,
  path: string,
): JsonRecord {
  const type = source["type"];
  if (typeof type !== "string") throw new Error(`${path}.type: expected a string`);

  const allowed = new Set(COMMON_CONDITION_FIELDS);
  for (const field of CONDITION_FIELDS[type] ?? []) allowed.add(field);

  const filtered: JsonRecord = {};
  for (const [key, value] of Object.entries(source)) {
    if (allowed.has(key)) filtered[key] = value;
    else ctx.stats.drop(`${path}.${key}`);
  }

  return projectFields(filtered, CONDITION_SPEC, ctx, path);
}

function projectComparison(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  return projectFields(requireRecord(value, path), COMPARISON_SPEC, ctx, path);
}

function projectComparisonMap(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  const map = requireRecord(value, path);
  const out: JsonRecord = {};
  for (const [key, entry] of Object.entries(map)) {
    out[key] = projectFields(requireRecord(entry, `${path}.${key}`), COMPARISON_SPEC, ctx, `${path}.${key}`);
  }
  return out;
}

function nullableComparison(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | null | undefined {
  if (value === null) return null;
  return projectComparison(value, ctx, path);
}

function projectHealthEffect(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  return projectFields(requireRecord(value, path), HEALTH_EFFECT_SPEC, ctx, path);
}

function nullableHealthEffect(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | null | undefined {
  if (value === null) return null;
  return projectHealthEffect(value, ctx, path);
}

function projectGlobalVariable(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  return projectFields(requireRecord(value, path), GLOBAL_VARIABLE_SPEC, ctx, path);
}

function projectPossibleLocations(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, POSSIBLE_LOCATION_SPEC, context, entryPath),
  );
}

function projectZones(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, ZONE_SPEC, context, entryPath),
  );
}

function projectWearing(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): string[][] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.map((row, rowIndex) => {
    if (!Array.isArray(row)) throw new Error(`${path}[${rowIndex}]: expected an array`);
    return row.map((entry, index) => {
      const worn = requireRecord(entry, `${path}[${rowIndex}][${index}]`);
      for (const key of Object.keys(worn)) {
        if (key !== "id") ctx.stats.drop(`${path}[${rowIndex}][${index}].${key}`);
      }
      return requireId(worn["id"], `${path}[${rowIndex}][${index}].id`);
    });
  });
}

function projectRewards(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  return projectFields(requireRecord(value, path), REWARDS_SPEC, ctx, path);
}

function projectCraftUnlocks(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, CRAFT_UNLOCK_SPEC, context, entryPath),
  );
}

function customizationName(value: unknown, ctx: NormalizeContext): unknown {
  if (typeof value !== "string") return value;
  if (!PLACEHOLDER_PATTERN.test(value)) return value;
  // Upstream has no dictionary entry for reward customization names. The design
  // renders them as a labelled placeholder, so normalization never publishes an
  // unresolved key. This is the one intentional display-name exception.
  ctx.stats.fallback("customizationName");
  return UNNAMED_CUSTOMIZATION;
}

function projectCustomizations(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, CUSTOMIZATION_SPEC, context, entryPath),
  );
}

function projectRewardItems(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, REWARD_ITEM_SPEC, context, entryPath),
  );
}

function projectOfferUnlocks(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, OFFER_UNLOCK_SPEC, context, entryPath),
  );
}

function projectSkillLevelRewards(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, SKILL_LEVEL_REWARD_SPEC, context, entryPath),
  );
}

function projectTraderStandings(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, TRADER_STANDING_SPEC, context, entryPath),
  );
}

function projectItemFilters(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  return projectFields(requireRecord(value, path), ITEM_FILTER_SPEC, ctx, path);
}
