import { z } from "zod";
import {
  assetUrl,
  attributeBag,
  entityId,
  idArray,
  itemFilters,
  stringArray,
  translatedText,
  vector3,
  webUrl,
} from "./primitives.js";

/**
 * `/regular/tasks`, including the auxiliary `questItems`, `achievements` and
 * `prestige` collections.
 *
 * Objectives, fail conditions and prestige conditions share one loose object
 * schema: upstream selects fields by `type`, and the fixture shows that no
 * field other than `id`, `type`, `description` and `optional` is present for
 * every type. Making type-specific fields required would reject currently
 * valid records, so they are typed but optional. Nulls are allowed only where
 * the fixture records them.
 *
 * Rewards are a fixed object of arrays. `startRewards`, `finishRewards` and
 * `failureOutcome` are all the same shape; `customization` is an array (the
 * stale upstream translation pointer assumed a different shape).
 * `locationUnlock` and `traderDialogueUnlock` are absent from some reward
 * blocks, so they are optional; the remaining arrays are always present, even
 * when empty.
 */

const zone = z.looseObject({
  bottom: z.number(),
  id: entityId,
  map: entityId,
  outline: z.array(vector3),
  position: vector3,
  top: z.number(),
  name: z.string().optional(),
  size: vector3.optional(),
  terrainElevation: z.number().optional(),
});

const comparison = z.looseObject({
  compareMethod: z.string(),
  value: z.number(),
});

const healthEffect = z.looseObject({
  bodyParts: stringArray,
  effects: stringArray,
  time: comparison,
});

const possibleLocation = z.looseObject({
  map: entityId,
  positions: z.array(vector3),
});

const wornItem = z.looseObject({
  id: entityId,
  name: z.string(),
});

/**
 * One objective, fail condition or prestige condition. Required fields are
 * the only ones present for every `type` in the fixture.
 */
export const taskConditionSchema = z.looseObject({
  id: entityId,
  description: translatedText,
  optional: z.boolean(),
  type: z.string(),
  bodyParts: stringArray.optional(),
  buildAttributes: z.record(z.string(), comparison).optional(),
  compareMethod: z.string().optional(),
  containsAll: idArray.optional(),
  containsCategory: idArray.optional(),
  count: z.number().nullish(),
  distance: comparison.nullish(),
  dogTagLevel: z.number().optional(),
  effects: stringArray.optional(),
  enemyHealthEffect: z.null().optional(),
  exitName: z.string().optional(),
  exitStatus: stringArray.optional(),
  foundInRaid: z.boolean().optional(),
  globalVariable: z
    .looseObject({
      compareMethod: z.string(),
      id: entityId,
      value: z.number(),
    })
    .optional(),
  healthEffect: healthEffect.nullish(),
  item: entityId.optional(),
  items: idArray.optional(),
  level: z.number().optional(),
  maps: stringArray.optional(),
  markerItem: entityId.optional(),
  maxDurability: z.number().optional(),
  minDurability: z.number().optional(),
  notWearing: stringArray.optional(),
  playerHealthEffect: healthEffect.nullish(),
  playerLevel: z.number().optional(),
  possibleLocations: z.array(possibleLocation).optional(),
  questItem: entityId.optional(),
  requiredKeys: z.array(stringArray).optional(),
  shotType: z.string().optional(),
  skill: z.string().optional(),
  station: entityId.optional(),
  stationLevel: z.number().optional(),
  status: stringArray.optional(),
  task: entityId.optional(),
  timeFromHour: z.number().nullish(),
  timeUntilHour: z.number().nullish(),
  trader: entityId.optional(),
  traders: idArray.optional(),
  useAny: idArray.optional(),
  usingWeapon: idArray.optional(),
  usingWeaponMods: z.array(stringArray).optional(),
  value: z.number().optional(),
  wearing: z.array(z.array(wornItem)).optional(),
  zones: z.array(zone).optional(),
});

const rewardItem = z.looseObject({
  attributes: attributeBag,
  count: z.number(),
  item: entityId,
});

const craftUnlock = z.looseObject({
  count: z.number(),
  item: entityId,
  level: z.number(),
  station: entityId,
});

const customization = z.looseObject({
  customizationType: z.string(),
  customizationTypeName: z.string(),
  id: entityId,
  name: translatedText,
  imageLink: assetUrl.optional(),
  items: idArray.optional(),
});

const offerContained = z.looseObject({
  attributes: attributeBag,
  count: z.number(),
  item: entityId,
});

const offerUnlock = z.looseObject({
  attributes: attributeBag,
  contains: z.array(offerContained),
  count: z.number(),
  id: entityId,
  item: entityId,
  level: z.number(),
  trader: entityId,
});

const skillLevelReward = z.looseObject({
  level: z.number(),
  skill: z.string(),
});

const traderStanding = z.looseObject({
  standing: z.number(),
  trader: entityId,
});

export const taskRewardsSchema = z.looseObject({
  achievement: idArray,
  craftUnlock: z.array(craftUnlock),
  customization: z.array(customization),
  items: z.array(rewardItem),
  offerUnlock: z.array(offerUnlock),
  skillLevelReward: z.array(skillLevelReward),
  traderStanding: z.array(traderStanding),
  traderUnlock: stringArray,
  locationUnlock: idArray.optional(),
  traderDialogueUnlock: stringArray.optional(),
});

const taskRequirement = z.looseObject({
  status: stringArray,
  task: entityId,
  notes: z.string().optional(),
});

const traderRequirement = z.looseObject({
  compareMethod: z.string(),
  id: entityId,
  requirementType: z.string(),
  trader: entityId,
  value: z.number(),
});

const neededKeys = z.looseObject({
  keys: idArray,
  map: entityId,
});

const otherRequirement = z.looseObject({
  id: entityId,
  type: z.string(),
  compareMethod: z.string().optional(),
  traders: idArray.optional(),
  value: z.number().optional(),
  variableId: entityId.optional(),
});

export const taskSchema = z.looseObject({
  availableDelaySecondsMax: z.number().optional(),
  availableDelaySecondsMin: z.number().optional(),
  experience: z.number(),
  factionName: z.string(),
  failConditions: z.array(taskConditionSchema),
  failureOutcome: taskRewardsSchema,
  finishRewards: taskRewardsSchema,
  gameMode: stringArray.optional(),
  id: entityId,
  kappaRequired: z.boolean(),
  lightkeeperRequired: z.boolean(),
  map: z.string().nullable(),
  minPlayerLevel: z.number(),
  name: translatedText,
  neededKeys: z.array(neededKeys).optional(),
  normalizedName: z.string(),
  objectives: z.array(taskConditionSchema),
  otherRequirements: z.array(otherRequirement).optional(),
  requiredPrestige: entityId.optional(),
  restartable: z.boolean(),
  startRewards: taskRewardsSchema,
  taskImageLink: assetUrl,
  taskRequirements: z.array(taskRequirement),
  trader: entityId,
  traderRequirements: z.array(traderRequirement),
  wikiLink: webUrl,
});

export const questItemSchema = z.looseObject({
  baseImageLink: assetUrl,
  description: translatedText,
  gridImageLink: assetUrl,
  height: z.number(),
  iconLink: assetUrl,
  id: entityId,
  image512pxLink: assetUrl,
  image8xLink: assetUrl,
  inspectImageLink: assetUrl,
  name: translatedText,
  normalizedName: z.string(),
  shortName: translatedText,
  width: z.number(),
});

export const achievementSchema = z.looseObject({
  adjustedPlayersCompletedPercent: z.number(),
  description: translatedText,
  hidden: z.boolean(),
  id: entityId,
  imageLink: assetUrl,
  name: translatedText,
  normalizedName: z.string(),
  normalizedRarity: z.string(),
  normalizedSide: z.string(),
  playersCompletedPercent: z.number(),
  rarity: z.string(),
  side: z.string(),
});

const transferSetting = z.looseObject({
  gridHeight: z.number().optional(),
  gridWidth: z.number().optional(),
  itemFilters: itemFilters.optional(),
  name: z.string().optional(),
  skillType: z.string().optional(),
  transferRate: z.number().optional(),
});

export const prestigeSchema = z.looseObject({
  conditions: z.array(taskConditionSchema),
  iconLink: assetUrl,
  id: entityId,
  imageLink: assetUrl,
  name: translatedText,
  prestigeLevel: z.number(),
  rewards: taskRewardsSchema,
  transferSettings: z.array(transferSetting),
});

export const tasksDataSchema = z.looseObject({
  tasks: z.record(entityId, taskSchema),
  questItems: z.record(entityId, questItemSchema),
  achievements: z.record(entityId, achievementSchema),
  prestige: z.array(prestigeSchema),
});

export type Task = z.infer<typeof taskSchema>;
export type TaskCondition = z.infer<typeof taskConditionSchema>;
export type TaskRewards = z.infer<typeof taskRewardsSchema>;
export type TasksData = z.infer<typeof tasksDataSchema>;
export type Prestige = z.infer<typeof prestigeSchema>;
