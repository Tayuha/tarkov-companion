import { z } from "zod";
import {
  assetUrl,
  attributeBag,
  entityId,
  idArray,
  isoDateTime,
  itemFilters,
  nullableNumber,
  stringArray,
  translatedText,
  webUrl,
} from "./primitives.js";

/**
 * `/regular/items` (and the `pve` / `pvp-season` mode markers).
 *
 * Unlike the other datasets, `data` is an object of named collections rather
 * than an id-keyed map: `items`, `itemCategories`, `handbookCategories`,
 * `fleaMarket`, `armorMaterials`, `playerLevels`, `mastering`, `skills`,
 * `specialItems`, `settings`.
 *
 * Strictness policy: every object is a loose object, so a new upstream field
 * is preserved and ignored instead of failing a build. Known fields are
 * type-checked. Item property payloads are a union keyed by `propertiesType`;
 * every known per-type field is validated when present, because the committed
 * fixture does not prove that every field is present for every item of a given
 * type. `propertiesType` itself is optional because some PvE properties blocks
 * omit it. Item-level flat combat fields (`damage`, `penetrationPower`, ...)
 * are optional for the same reason: upstream only emits them for the relevant
 * item types.
 *
 * `playerLevels`, `mastering`, `skills` and `specialItems` are arrays upstream
 * (not id-keyed maps), and the mode markers carry the same shapes as the
 * regular fixture.
 */

const imageLinks = {
  baseImageLink: assetUrl,
  gridImageLink: assetUrl,
  iconLink: assetUrl,
  image512pxLink: assetUrl,
  image8xLink: assetUrl,
  inspectImageLink: assetUrl,
};

const containedItem = z.looseObject({
  attributes: attributeBag,
  count: z.number(),
  item: entityId,
});

const buyOffer = z.looseObject({
  // Upstream serves `null` for "no limit" on some offers.
  buyLimit: z.number().nullable(),
  currency: z.string(),
  currencyItem: entityId,
  minTraderLevel: z.number(),
  price: z.number(),
  priceRUB: z.number(),
  restockAmount: z.number(),
  taskUnlock: z.string().nullable(),
  trader: entityId,
});

const sellOffer = z.looseObject({
  currency: z.string(),
  currencyItem: entityId,
  price: z.number(),
  priceRUB: z.number(),
  trader: entityId,
});

const stimEffect = z.looseObject({
  chance: z.number(),
  delay: z.number(),
  duration: z.number(),
  percent: z.boolean(),
  type: z.string(),
  value: z.number(),
  skill: z.string().optional(),
});

const itemGrid = z.looseObject({
  filters: itemFilters,
  height: z.number(),
  width: z.number(),
});

const itemSlot = z.looseObject({
  id: entityId,
  name: z.string(),
  nameId: z.string(),
  required: z.boolean(),
  filters: itemFilters.optional(),
});

const armorSlot = z.looseObject({
  name: z.string(),
  nameId: z.string(),
  zones: stringArray,
  allowedPlates: idArray.optional(),
  armorMaterial: z.string().optional(),
  armorType: z.string().optional(),
  baseValue: z.number().optional(),
  bluntThroughput: z.number().optional(),
  class: z.number().optional(),
  durability: z.number().optional(),
  ergoPenalty: z.number().optional(),
  repairCost: z.number().optional(),
  ricochetX: z.number().optional(),
  ricochetY: z.number().optional(),
  ricochetZ: z.number().optional(),
  speedPenalty: z.number().optional(),
  turnPenalty: z.number().optional(),
});

/**
 * Common `properties` envelope. Type-specific keys are listed as optional
 * primitives/arrays; see the module header for why they are not required per
 * `propertiesType`.
 */
const itemProperties = z.looseObject({
  propertiesType: z.string().optional(),
  accuracyModifier: z.number().optional(),
  allowedAmmo: idArray.optional(),
  ambientVolume: z.number().optional(),
  ammoCheckModifier: z.number().optional(),
  ammoType: z.string().optional(),
  armorDamage: z.number().optional(),
  armorSlots: z.array(armorSlot).optional(),
  armorType: z.string().optional(),
  ballisticCoeficient: z.number().optional(),
  baseItem: entityId.optional(),
  blindnessProtection: z.number().optional(),
  blocksEyewear: z.boolean().optional(),
  blocksHeadset: z.boolean().optional(),
  blocksHeadwear: z.boolean().optional(),
  bluntThroughput: z.number().optional(),
  bulletDiameterMilimeters: z.number().optional(),
  bulletMassGrams: z.number().optional(),
  caliber: z.string().optional(),
  cameraSnap: z.number().optional(),
  capacity: z.number().optional(),
  centerOfImpact: z.number().optional(),
  class: z.number().optional(),
  compressorAttack: z.number().optional(),
  compressorGain: z.number().optional(),
  compressorRelease: z.number().optional(),
  compressorThreshold: z.number().optional(),
  content: idArray.optional(),
  contusionRadius: z.number().optional(),
  coolingFactor: z.number().optional(),
  cures: stringArray.optional(),
  damage: z.number().optional(),
  deafening: z.string().optional(),
  default: z.boolean().optional(),
  defaultAmmo: entityId.nullish(),
  defaultErgonomics: nullableNumber.optional(),
  defaultHeight: z.number().nullish(),
  defaultPreset: entityId.nullish(),
  defaultRecoilHorizontal: nullableNumber.optional(),
  defaultRecoilVertical: nullableNumber.optional(),
  defaultWeight: nullableNumber.optional(),
  defaultWidth: z.number().nullish(),
  deviationCurve: z.number().optional(),
  deviationMax: z.number().optional(),
  diffuseIntensity: z.number().optional(),
  distanceModifier: z.number().optional(),
  distortion: z.number().optional(),
  dryVolume: z.number().optional(),
  durability: z.number().optional(),
  durabilityBurnFactor: z.number().optional(),
  effectiveDistance: z.number().optional(),
  energy: z.number().optional(),
  energyImpact: z.number().optional(),
  ergoPenalty: z.number().optional(),
  ergonomics: z.number().optional(),
  failureToFeedChance: z.number().optional(),
  fireModes: stringArray.optional(),
  fireRate: z.number().optional(),
  fragmentationChance: z.number().optional(),
  fragments: z.number().optional(),
  fuse: z.number().optional(),
  grids: z.array(itemGrid).optional(),
  heatFactor: z.number().optional(),
  heavyBleedModifier: z.number().optional(),
  hitpoints: z.number().optional(),
  hpCostHeavyBleeding: z.number().nullish(),
  hpCostLightBleeding: z.number().nullish(),
  hydration: z.number().optional(),
  hydrationImpact: z.number().optional(),
  increaseSize: z
    .looseObject({
      down: z.number().optional(),
      left: z.number().optional(),
      right: z.number().optional(),
      up: z.number().optional(),
    })
    .optional(),
  increaseSizeForced: z.boolean().optional(),
  initialSpeed: z.number().optional(),
  intensity: z.number().optional(),
  lightBleedModifier: z.number().optional(),
  loadModifier: z.number().optional(),
  locale: z.record(z.string(), z.unknown()).optional(),
  malfunctionChance: z.number().optional(),
  material: z.string().optional(),
  maxDurability: z.number().optional(),
  maxExplosionDistance: z.number().optional(),
  maxHealPerUse: z.number().optional(),
  maxLimbHealth: z.number().optional(),
  minExplosionDistance: z.number().optional(),
  minLimbHealth: z.number().optional(),
  misfireChance: z.number().optional(),
  moa: z.number().nullish(),
  noiseIntensity: z.number().optional(),
  noiseScale: z.number().optional(),
  painkillerDuration: z.number().optional(),
  penetrationChance: z.number().optional(),
  penetrationPower: z.number().optional(),
  penetrationPowerDeviation: z.number().optional(),
  presets: idArray.optional(),
  projectileCount: z.number().optional(),
  recoilAngle: z.number().optional(),
  recoilDispersion: z.number().optional(),
  recoilHorizontal: z.number().optional(),
  recoilModifier: z.number().optional(),
  recoilVertical: z.number().optional(),
  repairCost: z.number().optional(),
  ricochetChance: z.number().optional(),
  ricochetX: z.number().optional(),
  ricochetY: z.number().optional(),
  ricochetZ: z.number().optional(),
  sightModes: z.array(z.number()).optional(),
  sightingRange: z.number().optional(),
  slots: z.array(itemSlot).optional(),
  speedPenalty: z.number().optional(),
  stackMaxSize: z.number().optional(),
  staminaBurnPerDamage: z.number().optional(),
  stimEffects: z.array(stimEffect).optional(),
  tracer: z.boolean().optional(),
  tracerColor: z.string().optional(),
  turnPenalty: z.number().optional(),
  type: z.string().optional(),
  units: z.number().optional(),
  useTime: z.number().optional(),
  uses: z.number().optional(),
  zeroingDistances: z.array(z.array(z.number())).optional(),
  zones: stringArray.optional(),
  zoomLevels: z.array(z.array(z.number())).optional(),
});

export const itemSchema = z.looseObject({
  ...imageLinks,
  id: entityId,
  name: translatedText,
  shortName: translatedText,
  normalizedName: z.string(),
  description: translatedText.optional(),
  backgroundColor: z.string(),
  basePrice: z.number(),
  buyFromTrader: z.array(buyOffer),
  categories: idArray,
  conflictingCategories: idArray,
  conflictingItems: idArray,
  conflictingSlotIds: idArray,
  containsItems: z.array(containedItem),
  discardLimit: z.number(),
  handbookCategories: idArray,
  height: z.number(),
  width: z.number(),
  weight: z.number(),
  minLevelForFlea: z.number(),
  link: webUrl,
  // Some items have no wiki page and upstream sends an empty string.
  wikiLink: z.union([webUrl, z.literal("")]),
  types: stringArray,
  updated: isoDateTime,
  sellToTrader: z.array(sellOffer),
  properties: itemProperties.nullable(),
  avg24hPrice: nullableNumber.nullish(),
  changeLast48h: nullableNumber.nullish(),
  changeLast48hPercent: nullableNumber.nullish(),
  lastLowPrice: nullableNumber.nullish(),
  lastOfferCount: nullableNumber.nullish(),
  lastScan: isoDateTime.nullish(),
  // Present in some records and null in others: both states are recorded.
  high24hPrice: z.number().nullish(),
  // Absent from some records but never null.
  low24hPrice: z.number().optional(),
  hasGrid: z.boolean().optional(),
  stackMaxSize: z.number().optional(),
  // Flat combat fields copied out of `properties` for some item types.
  accuracyModifier: z.number().optional(),
  ammoType: z.string().optional(),
  armorClass: z.union([z.number(), z.string()]).optional(),
  armorDamage: z.number().optional(),
  blocksHeadphones: z.boolean().optional(),
  damage: z.number().optional(),
  ergonomicsModifier: z.number().optional(),
  fragmentationChance: z.number().optional(),
  loudness: z.number().optional(),
  maxDurability: z.number().optional(),
  penetrationPower: z.number().optional(),
  projectileCount: z.number().optional(),
  recoil: z.number().optional(),
  recoilModifier: z.number().optional(),
  ricochetChance: z.number().optional(),
  tracer: z.boolean().optional(),
  tracerColor: z.string().optional(),
  velocity: z.number().optional(),
});

export const itemCategorySchema = z.looseObject({
  children: idArray,
  id: entityId,
  name: translatedText,
  normalizedName: z.string(),
  parent: z.string(),
});

export const handbookCategorySchema = z.looseObject({
  children: idArray,
  id: entityId,
  imageLink: assetUrl.nullable(),
  minLevelForFlea: z.number().nullable(),
  name: translatedText,
  normalizedName: z.string(),
  parent: z.string().nullable(),
});

const fleaReputationLevel = z.looseObject({
  maxRep: z.number(),
  minRep: z.number(),
  offers: z.number(),
  offersSpecialEditions: z.number(),
});

export const fleaMarketSchema = z.looseObject({
  enabled: z.boolean(),
  foundInRaidRequired: z.boolean(),
  minPlayerLevel: z.number(),
  name: z.string(),
  normalizedName: z.string(),
  reputationLevels: z.array(fleaReputationLevel),
  sellOfferFeeRate: z.number(),
  sellRequirementFeeRate: z.number(),
});

export const armorMaterialSchema = z.looseObject({
  destructibility: z.number(),
  explosionDestructibility: z.number(),
  id: entityId,
  maxRepairDegradation: z.number(),
  maxRepairKitDegradation: z.number(),
  minRepairDegradation: z.number(),
  minRepairKitDegradation: z.number(),
  name: z.string(),
});

export const playerLevelSchema = z.looseObject({
  exp: z.number(),
  level: z.number(),
  levelBadgeImageLink: assetUrl,
});

export const masteringSchema = z.looseObject({
  id: entityId,
  level2: z.number(),
  level3: z.number(),
  weapons: idArray,
});

export const skillSchema = z.looseObject({
  id: entityId,
  imageLink: assetUrl,
  name: z.string(),
  normalizedName: z.string(),
  wikiLink: webUrl,
});

export const itemSettingsSchema = z.looseObject({
  globalMaxTraders: z.boolean(),
  gpCoinValue: z.number(),
  scavCooldownSeconds: z.number(),
});

const itemsCollections = {
  items: z.record(entityId, itemSchema),
  itemCategories: z.record(entityId, itemCategorySchema),
  handbookCategories: z.record(entityId, handbookCategorySchema),
  fleaMarket: fleaMarketSchema,
  armorMaterials: z.record(entityId, armorMaterialSchema),
  playerLevels: z.array(playerLevelSchema),
  mastering: z.array(masteringSchema),
  skills: z.array(skillSchema),
  specialItems: idArray,
  settings: itemSettingsSchema,
};

export const itemsDataSchema = z.looseObject(itemsCollections);

export type Item = z.infer<typeof itemSchema>;
export type ItemsData = z.infer<typeof itemsDataSchema>;
export type ItemProperties = z.infer<typeof itemProperties>;
