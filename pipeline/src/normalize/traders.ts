import {
  type BundleRecord,
  type FieldSpec,
  type NormalizeContext,
  integerValue,
  isoString,
  makeRecord,
  nullableNumber,
  projectFields,
  projectList,
  projectMap,
  requireRecord,
  stringList,
  vector3,
} from "./contract.js";

/**
 * `/regular/traders` -> `trader` records. `data` is keyed by trader id.
 *
 * Trader levels and reputation levels are embedded because they are owned by
 * the trader and have no upstream collection of their own. Everything else is
 * referenced by id.
 */

const BUY_LIST_SPEC: FieldSpec = {
  category: { to: "categoryIds", transform: stringList },
  items: { to: "itemIds", transform: stringList },
};

const TRADER_LEVEL_SPEC: FieldSpec = {
  id: "id",
  level: { to: "level", transform: integerValue },
  payRate: "payRate",
  insuranceRate: { to: "insuranceRate", transform: nullableNumber },
  repairCostMultiplier: { to: "repairCostMultiplier", transform: nullableNumber },
  requiredCommerce: { to: "requiredCommerce", transform: integerValue },
  requiredPlayerLevel: { to: "requiredPlayerLevel", transform: integerValue },
  requiredReputation: "requiredReputation",
};

const REPUTATION_LEVEL_SPEC: FieldSpec = {
  availableScavExtracts: { to: "availableScavExtracts", transform: integerValue },
  btrCoveringFireDiscount: "btrCoveringFireDiscount",
  btrDeliveryDiscount: "btrDeliveryDiscount",
  btrDeliveryGridSize: { to: "btrDeliveryGridSize", transform: vector3 },
  btrEnabled: "btrEnabled",
  btrTaxiDiscount: "btrTaxiDiscount",
  extractPriceModifier: "extractPriceModifier",
  hostileBosses: "hostileBosses",
  hostileScavs: "hostileScavs",
  minimumReputation: "minimumReputation",
  priceModifier: "priceModifier",
  scavAttackSupport: "scavAttackSupport",
  scavCaseTimeModifier: "scavCaseTimeModifier",
  scavCooldownModifier: "scavCooldownModifier",
  scavEquipmentSpawnChanceModifier: "scavEquipmentSpawnChanceModifier",
  scavFollowChance: "scavFollowChance",
};

const TRADER_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
  description: "description",
  imageLink: "imageLink",
  currency: "currency",
  discount: "discount",
  resetTime: { to: "resetTime", transform: isoString },
  levels: {
    to: "levels",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, TRADER_LEVEL_SPEC, context, entryPath),
      ),
  },
  reputationLevels: {
    to: "reputationLevels",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, REPUTATION_LEVEL_SPEC, context, entryPath),
      ),
  },
  buyAllowed: {
    to: "buyAllowed",
    transform: (value, ctx, path) =>
      projectFields(requireRecord(value, path), BUY_LIST_SPEC, ctx, path),
  },
  buyProhibited: {
    to: "buyProhibited",
    transform: (value, ctx, path) =>
      projectFields(requireRecord(value, path), BUY_LIST_SPEC, ctx, path),
  },
};

export function normalizeTraders(data: unknown, ctx: NormalizeContext): BundleRecord[] {
  return projectMap(data, ctx, "traders", (entry, context, path) =>
    makeRecord("trader", projectFields(entry, TRADER_SPEC, context, path)),
  );
}
