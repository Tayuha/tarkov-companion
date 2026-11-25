import { z } from "zod";
import { assetUrl, entityId, idArray, translatedText } from "./primitives.js";

/**
 * `/regular/hideout`: `data` is keyed directly by station id, and each station
 * carries its own `levels` array.
 *
 * Bonus names/descriptions are locale keys (`hideout_EnergyRegeneration`) that
 * the upstream translation pointers do not always cover, so they are plain
 * strings here. Every requirement array may be empty.
 */

const bonus = z.looseObject({
  name: z.string(),
  passive: z.boolean(),
  production: z.boolean(),
  type: z.string(),
  value: z.number(),
  skill: z.string().optional(),
  slotItems: idArray.optional(),
});

const itemRequirement = z.looseObject({
  attributes: z.looseObject({ foundInRaid: z.boolean() }),
  count: z.number(),
  id: entityId,
  item: entityId,
});

const skillRequirement = z.looseObject({
  id: entityId,
  level: z.number(),
  skill: z.string(),
});

const stationLevelRequirement = z.looseObject({
  id: entityId,
  level: z.number(),
  station: entityId,
});

const traderRequirement = z.looseObject({
  compareMethod: z.string(),
  id: entityId,
  requirementType: z.string(),
  trader: entityId,
  value: z.number(),
});

export const hideoutLevelSchema = z.looseObject({
  bonuses: z.array(bonus),
  constructionTime: z.number(),
  description: translatedText,
  id: entityId,
  itemRequirements: z.array(itemRequirement),
  level: z.number(),
  skillRequirements: z.array(skillRequirement),
  stationLevelRequirements: z.array(stationLevelRequirement),
  traderRequirements: z.array(traderRequirement),
});

export const hideoutStationSchema = z.looseObject({
  areaType: z.number(),
  id: entityId,
  imageLink: assetUrl,
  levels: z.array(hideoutLevelSchema),
  name: translatedText,
  normalizedName: z.string(),
});

export const hideoutDataSchema = z.record(entityId, hideoutStationSchema);

export type HideoutStation = z.infer<typeof hideoutStationSchema>;
export type HideoutLevel = z.infer<typeof hideoutLevelSchema>;
export type HideoutData = z.infer<typeof hideoutDataSchema>;
