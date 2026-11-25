import { z } from "zod";
import {
  assetUrl,
  entityId,
  idArray,
  isoDateTime,
  nullableNumber,
  translatedText,
  vector3,
} from "./primitives.js";

/**
 * `/regular/traders`: `data` is keyed directly by trader id.
 *
 * `levels` and `reputationLevels` may be empty arrays. Insurance and repair
 * multipliers are nullable upstream for traders that do not offer those
 * services.
 */

const buyList = z.looseObject({
  category: idArray,
  items: idArray,
});

export const traderLevelSchema = z.looseObject({
  id: entityId,
  insuranceRate: nullableNumber,
  level: z.number(),
  payRate: z.number(),
  repairCostMultiplier: nullableNumber,
  requiredCommerce: z.number(),
  requiredPlayerLevel: z.number(),
  requiredReputation: z.number(),
});

export const traderReputationLevelSchema = z.looseObject({
  availableScavExtracts: z.number(),
  btrCoveringFireDiscount: z.number(),
  btrDeliveryDiscount: z.number(),
  btrDeliveryGridSize: vector3,
  btrEnabled: z.boolean(),
  btrTaxiDiscount: z.number(),
  extractPriceModifier: z.number(),
  hostileBosses: z.boolean(),
  hostileScavs: z.boolean(),
  minimumReputation: z.number(),
  priceModifier: z.number(),
  scavAttackSupport: z.boolean(),
  scavCaseTimeModifier: z.number(),
  scavCooldownModifier: z.number(),
  scavEquipmentSpawnChanceModifier: z.number(),
  scavFollowChance: z.number(),
});

export const traderSchema = z.looseObject({
  buyAllowed: buyList,
  buyProhibited: buyList,
  currency: z.string(),
  description: translatedText,
  discount: z.number(),
  id: entityId,
  imageLink: assetUrl,
  levels: z.array(traderLevelSchema),
  name: translatedText,
  normalizedName: z.string(),
  reputationLevels: z.array(traderReputationLevelSchema),
  resetTime: isoDateTime,
});

export const tradersDataSchema = z.record(entityId, traderSchema);

export type Trader = z.infer<typeof traderSchema>;
export type TradersData = z.infer<typeof tradersDataSchema>;
