import {
  type BundleRecord,
  type FieldSpec,
  type JsonRecord,
  type NormalizeContext,
  integerValue,
  isoString,
  makeRecord,
  moneyValue,
  nullableInteger,
  nullableIsoString,
  nullableNumber,
  projectFields,
  projectList,
  projectMap,
  requireId,
  requireRecord,
  requireString,
  stringList,
} from "./contract.js";

/**
 * `/regular/items` (and the `pve` / `pvp-season` mode markers) -> bundle records.
 *
 * A record kind per upstream collection: `item`, `itemCategory`,
 * `handbookCategory`, `fleaMarket`, `armorMaterial`, `playerLevel`, `mastering`,
 * `skill`, `specialItem`, `setting`.
 */

const IMAGE_FIELDS = [
  "baseImageLink",
  "gridImageLink",
  "iconLink",
  "image512pxLink",
  "image8xLink",
  "inspectImageLink",
] as const;

/** Flat combat fields upstream copies out of `properties` for some types. */
const FLAT_ITEM_FIELDS = [
  "accuracyModifier",
  "ammoType",
  "armorClass",
  "armorDamage",
  "blocksHeadphones",
  "damage",
  "ergonomicsModifier",
  "fragmentationChance",
  "loudness",
  "maxDurability",
  "penetrationPower",
  "projectileCount",
  "recoil",
  "recoilModifier",
  "ricochetChance",
  "tracer",
  "tracerColor",
  "velocity",
] as const;

/** Item scalars copied verbatim after schema validation. */
const ITEM_SCALAR_FIELDS = [
  "name",
  "shortName",
  "normalizedName",
  "description",
  "backgroundColor",
  "types",
  "conflictingSlotIds",
  "link",
  "wikiLink",
] as const;

/** Consumed into the `price` object instead of being emitted again. */
const PRICE_SOURCE_FIELDS = [
  "avg24hPrice",
  "changeLast48h",
  "changeLast48hPercent",
  "high24hPrice",
  "lastLowPrice",
  "lastOfferCount",
  "lastScan",
  "low24hPrice",
] as const;

const ITEM_SPEC: FieldSpec = {
  id: "id",
  ...Object.fromEntries(ITEM_SCALAR_FIELDS.map((field) => [field, field])),
  ...Object.fromEntries(IMAGE_FIELDS.map((field) => [field, field])),
  ...Object.fromEntries(FLAT_ITEM_FIELDS.map((field) => [field, field])),
  basePrice: { to: "basePrice", transform: moneyValue },
  weight: "weight",
  width: { to: "width", transform: integerValue },
  height: { to: "height", transform: integerValue },
  hasGrid: "hasGrid",
  stackMaxSize: { to: "stackMaxSize", transform: integerValue },
  discardLimit: { to: "discardLimit", transform: integerValue },
  minLevelForFlea: { to: "minLevelForFlea", transform: integerValue },
  categories: { to: "categoryIds", transform: stringList },
  handbookCategories: { to: "handbookCategoryIds", transform: stringList },
  conflictingCategories: { to: "conflictingCategoryIds", transform: stringList },
  conflictingItems: { to: "conflictingItemIds", transform: stringList },
  containsItems: { to: "containsItems", transform: projectContainedItems },
  buyFromTrader: { to: "buyFromTrader", transform: projectBuyOffers },
  sellToTrader: { to: "sellToTrader", transform: projectSellOffers },
  properties: { to: "properties", transform: projectProperties },
  updated: { to: "updated", transform: isoString },
  ...Object.fromEntries(PRICE_SOURCE_FIELDS.map((field) => [field, { omit: true }])),
};

const CONTAINED_ITEM_SPEC: FieldSpec = {
  item: "itemId",
  count: "count",
  attributes: "attributes",
};

const BUY_OFFER_CONSUMED = new Set([
  "trader",
  "price",
  "priceRUB",
  "currency",
  "currencyItem",
  "minTraderLevel",
  "buyLimit",
  "restockAmount",
  "taskUnlock",
]);

const SELL_OFFER_CONSUMED = new Set(["trader", "price", "priceRUB", "currency", "currencyItem"]);

/** Item property scalars copied verbatim after schema validation. */
const PROPERTY_SCALAR_FIELDS = [
  "propertiesType",
  "accuracyModifier",
  "ambientVolume",
  "ammoCheckModifier",
  "ammoType",
  "armorDamage",
  "armorType",
  "ballisticCoeficient",
  "blindnessProtection",
  "blocksEyewear",
  "blocksHeadset",
  "blocksHeadwear",
  "bluntThroughput",
  "bulletDiameterMilimeters",
  "bulletMassGrams",
  "caliber",
  "cameraSnap",
  "capacity",
  "centerOfImpact",
  "class",
  "compressorAttack",
  "compressorGain",
  "compressorRelease",
  "compressorThreshold",
  "contusionRadius",
  "coolingFactor",
  "cures",
  "damage",
  "deafening",
  "default",
  "defaultErgonomics",
  "defaultHeight",
  "defaultRecoilHorizontal",
  "defaultRecoilVertical",
  "defaultWeight",
  "defaultWidth",
  "deviationCurve",
  "deviationMax",
  "diffuseIntensity",
  "distanceModifier",
  "distortion",
  "dryVolume",
  "durability",
  "durabilityBurnFactor",
  "effectiveDistance",
  "energy",
  "energyImpact",
  "ergoPenalty",
  "ergonomics",
  "failureToFeedChance",
  "fireModes",
  "fireRate",
  "fragmentationChance",
  "fragments",
  "fuse",
  "heatFactor",
  "heavyBleedModifier",
  "hitpoints",
  "hpCostHeavyBleeding",
  "hpCostLightBleeding",
  "hydration",
  "hydrationImpact",
  "increaseSizeForced",
  "initialSpeed",
  "intensity",
  "lightBleedModifier",
  "loadModifier",
  "locale",
  "malfunctionChance",
  "material",
  "maxDurability",
  "maxExplosionDistance",
  "maxHealPerUse",
  "maxLimbHealth",
  "minExplosionDistance",
  "minLimbHealth",
  "misfireChance",
  "moa",
  "noiseIntensity",
  "noiseScale",
  "painkillerDuration",
  "penetrationChance",
  "penetrationPower",
  "penetrationPowerDeviation",
  "projectileCount",
  "recoilAngle",
  "recoilDispersion",
  "recoilHorizontal",
  "recoilModifier",
  "recoilVertical",
  "repairCost",
  "ricochetChance",
  "ricochetX",
  "ricochetY",
  "ricochetZ",
  "sightModes",
  "sightingRange",
  "speedPenalty",
  "stackMaxSize",
  "staminaBurnPerDamage",
  "tracer",
  "tracerColor",
  "turnPenalty",
  "type",
  "units",
  "useTime",
  "uses",
  "zeroingDistances",
  "zones",
  "zoomLevels",
] as const;

const ITEM_FILTER_SPEC: FieldSpec = {
  allowedCategories: { to: "allowedCategoryIds", transform: stringList },
  allowedItems: { to: "allowedItemIds", transform: stringList },
  excludedCategories: { to: "excludedCategoryIds", transform: stringList },
  excludedItems: { to: "excludedItemIds", transform: stringList },
};

const SLOT_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  nameId: "nameId",
  required: "required",
  filters: { to: "filters", transform: projectItemFilters },
};

const GRID_SPEC: FieldSpec = {
  filters: { to: "filters", transform: projectItemFilters },
  height: { to: "height", transform: integerValue },
  width: { to: "width", transform: integerValue },
};

const ARMOR_SLOT_SPEC: FieldSpec = {
  name: "name",
  nameId: "nameId",
  zones: { to: "zones", transform: stringList },
  allowedPlates: { to: "allowedPlateItemIds", transform: stringList },
  armorMaterial: "armorMaterialId",
  armorType: "armorType",
  baseValue: "baseValue",
  bluntThroughput: "bluntThroughput",
  class: "class",
  durability: "durability",
  ergoPenalty: "ergoPenalty",
  repairCost: "repairCost",
  ricochetX: "ricochetX",
  ricochetY: "ricochetY",
  ricochetZ: "ricochetZ",
  speedPenalty: "speedPenalty",
  turnPenalty: "turnPenalty",
};

const STIM_EFFECT_SPEC: FieldSpec = {
  chance: "chance",
  delay: "delay",
  duration: "duration",
  percent: "percent",
  type: "type",
  value: "value",
  skill: "skill",
};

const INCREASE_SIZE_SPEC: FieldSpec = {
  down: "down",
  left: "left",
  right: "right",
  up: "up",
};

const PROPERTY_SPEC: FieldSpec = {
  ...Object.fromEntries(PROPERTY_SCALAR_FIELDS.map((field) => [field, field])),
  allowedAmmo: { to: "allowedAmmoItemIds", transform: stringList },
  baseItem: "baseItemId",
  content: { to: "contentItemIds", transform: stringList },
  defaultAmmo: "defaultAmmoItemId",
  defaultPreset: "defaultPresetItemId",
  presets: { to: "presetItemIds", transform: stringList },
  slots: { to: "slots", transform: projectSlots },
  grids: { to: "grids", transform: projectGrids },
  armorSlots: { to: "armorSlots", transform: projectArmorSlots },
  stimEffects: { to: "stimEffects", transform: projectStimEffects },
  increaseSize: { to: "increaseSize", transform: projectIncreaseSize },
};

export function normalizeItems(data: unknown, ctx: NormalizeContext): BundleRecord[] {
  const root = requireRecord(data, "items");
  const records: BundleRecord[] = [];

  for (const [key, value] of Object.entries(root)) {
    switch (key) {
      case "items":
        records.push(
          ...projectMap(value, ctx, "items.items", (entry, context, path) =>
            normalizeItem(entry, context, path),
          ),
        );
        break;
      case "itemCategories":
        records.push(
          ...projectMap(value, ctx, "items.itemCategories", (entry, context, path) =>
            normalizeItemCategory(entry, context, path),
          ),
        );
        break;
      case "handbookCategories":
        records.push(
          ...projectMap(value, ctx, "items.handbookCategories", (entry, context, path) =>
            normalizeHandbookCategory(entry, context, path),
          ),
        );
        break;
      case "fleaMarket":
        records.push(normalizeFleaMarket(requireRecord(value, "items.fleaMarket"), ctx));
        break;
      case "armorMaterials":
        records.push(
          ...projectMap(value, ctx, "items.armorMaterials", (entry, context, path) =>
            normalizeArmorMaterial(entry, context, path),
          ),
        );
        break;
      case "playerLevels":
        records.push(
          ...projectList(value, ctx, "items.playerLevels", (entry, context, path) =>
            normalizePlayerLevel(entry, context, path),
          ) ?? [],
        );
        break;
      case "mastering":
        records.push(
          ...projectList(value, ctx, "items.mastering", (entry, context, path) =>
            normalizeMastering(entry, context, path),
          ) ?? [],
        );
        break;
      case "skills":
        records.push(
          ...projectList(value, ctx, "items.skills", (entry, context, path) =>
            normalizeSkill(entry, context, path),
          ) ?? [],
        );
        break;
      case "specialItems":
        records.push(...normalizeSpecialItems(value));
        break;
      case "settings":
        records.push(normalizeSettings(requireRecord(value, "items.settings"), ctx));
        break;
      default:
        ctx.stats.drop(`items.${key}`);
    }
  }

  return records;
}

function normalizeItem(source: JsonRecord, ctx: NormalizeContext, path: string): BundleRecord {
  const fields = projectFields(source, ITEM_SPEC, ctx, path);
  fields["price"] = buildPrice(source);
  return makeRecord("item", fields);
}

function buildPrice(source: JsonRecord): JsonRecord {
  return {
    lastLow: nullableNumber(source["lastLowPrice"]) ?? null,
    avg24h: nullableNumber(source["avg24hPrice"]) ?? null,
    low24h: nullableNumber(source["low24hPrice"]) ?? null,
    high24h: nullableNumber(source["high24hPrice"]) ?? null,
    change48h: moneyValue(nullableNumber(source["changeLast48h"])) ?? null,
    change48hPercent: nullableNumber(source["changeLast48hPercent"]) ?? null,
    lastOfferCount: nullableInteger(source["lastOfferCount"]) ?? null,
    observedAt: nullableIsoString(source["lastScan"]) ?? null,
  };
}

function projectContainedItems(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, CONTAINED_ITEM_SPEC, context, entryPath),
  );
}

function projectBuyOffers(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  if (!Array.isArray(value)) return undefined;

  return value.map((entry, index) => {
    const offer = requireRecord(entry, `${path}[${index}]`);
    const price = moneyValue(offer["priceRUB"] ?? offer["price"]);
    if (price === undefined) throw new Error(`${path}[${index}].price: expected a number`);
    const restockAmount = integerValue(offer["restockAmount"]);
    if (restockAmount === undefined) {
      throw new Error(`${path}[${index}].restockAmount: expected a number`);
    }
    const taskUnlock = offer["taskUnlock"];
    const out: JsonRecord = {
      traderId: requireId(offer["trader"], `${path}[${index}].trader`),
      price,
      currency: requireString(offer["currency"], `${path}[${index}].currency`),
      currencyItemId: requireId(offer["currencyItem"], `${path}[${index}].currencyItem`),
      restockAmount,
      taskUnlockId:
        taskUnlock === null
          ? null
          : requireId(taskUnlock, `${path}[${index}].taskUnlock`),
    };
    if (typeof offer["minTraderLevel"] === "number") {
      out["loyaltyLevel"] = offer["minTraderLevel"];
    }
    if (typeof offer["buyLimit"] === "number") out["buyLimit"] = offer["buyLimit"];
    for (const key of Object.keys(offer)) {
      if (!BUY_OFFER_CONSUMED.has(key)) ctx.stats.drop(`${path}[${index}].${key}`);
    }
    return out;
  });
}

function projectSellOffers(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  if (!Array.isArray(value)) return undefined;

  return value.map((entry, index) => {
    const offer = requireRecord(entry, `${path}[${index}]`);
    const price = moneyValue(offer["priceRUB"] ?? offer["price"]);
    if (price === undefined) throw new Error(`${path}[${index}].price: expected a number`);
    const out: JsonRecord = {
      traderId: requireId(offer["trader"], `${path}[${index}].trader`),
      price,
      currency: requireString(offer["currency"], `${path}[${index}].currency`),
      currencyItemId: requireId(offer["currencyItem"], `${path}[${index}].currencyItem`),
    };
    for (const key of Object.keys(offer)) {
      if (!SELL_OFFER_CONSUMED.has(key)) ctx.stats.drop(`${path}[${index}].${key}`);
    }
    return out;
  });
}

function projectProperties(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | null | undefined {
  if (value === null) return null;
  return projectFields(requireRecord(value, path), PROPERTY_SPEC, ctx, path);
}

function projectItemFilters(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  return projectFields(requireRecord(value, path), ITEM_FILTER_SPEC, ctx, path);
}

function projectSlots(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, SLOT_SPEC, context, entryPath),
  );
}

function projectGrids(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, GRID_SPEC, context, entryPath),
  );
}

function projectArmorSlots(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, ARMOR_SLOT_SPEC, context, entryPath),
  );
}

function projectStimEffects(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, STIM_EFFECT_SPEC, context, entryPath),
  );
}

function projectIncreaseSize(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  return projectFields(requireRecord(value, path), INCREASE_SIZE_SPEC, ctx, path);
}

const ITEM_CATEGORY_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
  parent: "parentId",
  children: { to: "childIds", transform: stringList },
};

function normalizeItemCategory(
  source: JsonRecord,
  ctx: NormalizeContext,
  path: string,
): BundleRecord {
  return makeRecord("itemCategory", projectFields(source, ITEM_CATEGORY_SPEC, ctx, path));
}

const HANDBOOK_CATEGORY_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
  parent: "parentId",
  children: { to: "childIds", transform: stringList },
  imageLink: "imageLink",
  minLevelForFlea: { to: "minLevelForFlea", transform: nullableInteger },
};

function normalizeHandbookCategory(
  source: JsonRecord,
  ctx: NormalizeContext,
  path: string,
): BundleRecord {
  return makeRecord("handbookCategory", projectFields(source, HANDBOOK_CATEGORY_SPEC, ctx, path));
}

const FLEA_REPUTATION_SPEC: FieldSpec = {
  maxRep: "maxRep",
  minRep: "minRep",
  offers: "offers",
  offersSpecialEditions: "offersSpecialEditions",
};

const FLEA_MARKET_SPEC: FieldSpec = {
  enabled: "enabled",
  foundInRaidRequired: "foundInRaidRequired",
  minPlayerLevel: { to: "minPlayerLevel", transform: integerValue },
  name: "name",
  normalizedName: "normalizedName",
  reputationLevels: {
    to: "reputationLevels",
    transform: (value, context, path) =>
      projectList(value, context, path, (entry, entryContext, entryPath) =>
        projectFields(entry, FLEA_REPUTATION_SPEC, entryContext, entryPath),
      ),
  },
  sellOfferFeeRate: "sellOfferFeeRate",
  sellRequirementFeeRate: "sellRequirementFeeRate",
};

function normalizeFleaMarket(source: JsonRecord, ctx: NormalizeContext): BundleRecord {
  const fields = projectFields(source, FLEA_MARKET_SPEC, ctx, "items.fleaMarket");
  return { kind: "fleaMarket", id: "fleaMarket", ...fields };
}

const ARMOR_MATERIAL_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  destructibility: "destructibility",
  explosionDestructibility: "explosionDestructibility",
  minRepairDegradation: "minRepairDegradation",
  minRepairKitDegradation: "minRepairKitDegradation",
  maxRepairDegradation: "maxRepairDegradation",
  maxRepairKitDegradation: "maxRepairKitDegradation",
};

function normalizeArmorMaterial(
  source: JsonRecord,
  ctx: NormalizeContext,
  path: string,
): BundleRecord {
  return makeRecord("armorMaterial", projectFields(source, ARMOR_MATERIAL_SPEC, ctx, path));
}

const PLAYER_LEVEL_SPEC: FieldSpec = {
  level: { to: "level", transform: integerValue },
  exp: { to: "exp", transform: integerValue },
  levelBadgeImageLink: "levelBadgeImageLink",
};

function normalizePlayerLevel(
  source: JsonRecord,
  ctx: NormalizeContext,
  path: string,
): BundleRecord {
  const fields = projectFields(source, PLAYER_LEVEL_SPEC, ctx, path);
  const level = integerValue(source["level"]);
  if (level === undefined) throw new Error(`${path}.level: expected a number`);
  return { kind: "playerLevel", id: String(level), ...fields };
}

const MASTERING_SPEC: FieldSpec = {
  id: "id",
  level2: { to: "level2", transform: integerValue },
  level3: { to: "level3", transform: integerValue },
  weapons: { to: "weaponItemIds", transform: stringList },
};

function normalizeMastering(
  source: JsonRecord,
  ctx: NormalizeContext,
  path: string,
): BundleRecord {
  return makeRecord("mastering", projectFields(source, MASTERING_SPEC, ctx, path));
}

const SKILL_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
  imageLink: "imageLink",
  wikiLink: "wikiLink",
};

function normalizeSkill(source: JsonRecord, ctx: NormalizeContext, path: string): BundleRecord {
  return makeRecord("skill", projectFields(source, SKILL_SPEC, ctx, path));
}

function normalizeSpecialItems(value: unknown): BundleRecord[] {
  if (!Array.isArray(value)) return [];
  return value.map((entry, index) => {
    const itemId = requireId(entry, `items.specialItems[${index}]`);
    return { kind: "specialItem", id: itemId, itemId };
  });
}

const SETTINGS_SPEC: FieldSpec = {
  globalMaxTraders: "globalMaxTraders",
  gpCoinValue: { to: "gpCoinValue", transform: moneyValue },
  scavCooldownSeconds: { to: "scavCooldownSeconds", transform: integerValue },
};

function normalizeSettings(source: JsonRecord, ctx: NormalizeContext): BundleRecord {
  const fields = projectFields(source, SETTINGS_SPEC, ctx, "items.settings");
  return { kind: "setting", id: "settings", ...fields };
}
