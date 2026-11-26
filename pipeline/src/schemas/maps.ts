import { z } from "zod";
import {
  assetUrl,
  entityId,
  idArray,
  opaqueArray,
  stringArray,
  translatedText,
  vector3,
  webUrl,
} from "./primitives.js";

/**
 * `/regular/maps`: named collections under `data` (`maps`, `mobs`,
 * `lootContainers`, `stationaryWeapons`, `goonReports`).
 *
 * Nested map arrays (spawns, extracts, locks, transits, hazards, switches) are
 * validated field-by-field. Arrays whose element shape is not observable in
 * the fixture (`btrStops`, which is empty for both retained maps) use the
 * shared opaque array so future populated data is still accepted.
 *
 * `artillery.zones[*].botom` keeps the upstream misspelling; a schema that
 * "fixes" it would reject the recorded payload.
 */

const outline = z.array(vector3);

const extractTransferItem = z.looseObject({
  count: z.number(),
  item: entityId,
});

export const mapExtractSchema = z.looseObject({
  bottom: z.number(),
  faction: z.string().nullish(),
  id: entityId,
  name: z.string(),
  outline,
  position: vector3,
  switch: z.union([z.boolean(), z.string()]),
  switches: stringArray,
  top: z.number(),
  transferItem: extractTransferItem.optional(),
});

const bossEscortAmount = z.looseObject({
  chance: z.number(),
  count: z.number(),
});

const bossEscort = z.looseObject({
  amount: z.array(bossEscortAmount),
  mob: z.string(),
});

const bossSpawnLocation = z.looseObject({
  chance: z.number(),
  name: z.string(),
  positions: z.array(vector3),
  spawnKey: z.string(),
});

export const mapBossSchema = z.looseObject({
  escorts: z.array(bossEscort),
  mob: z.string(),
  spawnChance: z.number(),
  spawnLocations: z.array(bossSpawnLocation),
  spawnTime: z.number(),
  spawnTimeRandom: z.boolean().nullish(),
  spawnTrigger: z.string().nullable(),
  supports: stringArray,
});

const lootContainerPoint = z.looseObject({
  lootContainer: entityId,
  position: vector3,
});

const looseLoot = z.looseObject({
  items: idArray,
  position: vector3,
});

const mapLock = z.looseObject({
  id: entityId,
  key: entityId,
  lockType: z.string(),
  needsPower: z.boolean(),
  position: vector3,
});

const mapSpawn = z.looseObject({
  categories: stringArray,
  position: vector3,
  sides: stringArray,
  zoneName: z.string(),
});

const mapTransit = z.looseObject({
  bottom: z.number(),
  description: translatedText,
  id: entityId,
  map: entityId,
  outline,
  position: vector3,
  top: z.number(),
  conditions: z.string().optional(),
});

export const mapHazardSchema = z.looseObject({
  bottom: z.number().nullish(),
  hazardType: z.string(),
  id: entityId,
  name: z.string(),
  outline,
  position: vector3,
  top: z.number().nullish(),
});

export const mapSwitchActivationSchema = z.looseObject({
  operation: z.string(),
  switch: entityId,
});

export const mapSwitchSchema = z.looseObject({
  activatedBy: z.union([z.boolean(), entityId]),
  activates: z.array(mapSwitchActivationSchema),
  bottom: z.number(),
  door: z.unknown(),
  id: entityId,
  name: z.string(),
  outline,
  position: vector3,
  size: vector3,
  switchType: z.string(),
  top: z.number(),
});

const mapStationaryWeapon = z.looseObject({
  position: vector3,
  stationaryWeapon: entityId,
});

const artilleryZone = z.looseObject({
  // Upstream spells this `botom`; do not correct it here.
  botom: z.number(),
  id: entityId,
  outline,
  position: vector3,
  size: vector3,
  top: z.number(),
});

const artillery = z.looseObject({
  zones: z.array(artilleryZone),
});

export const mapSchema = z.looseObject({
  accessKeys: idArray,
  accessKeysMinPlayerLevel: z.number(),
  artillery: artillery.optional(),
  bosses: z.array(mapBossSchema),
  btrStops: opaqueArray,
  coordinateToCardinalRotation: z.number(),
  description: translatedText,
  enemies: stringArray,
  extracts: z.array(mapExtractSchema),
  hazards: z.array(mapHazardSchema),
  id: entityId,
  locks: z.array(mapLock),
  lootContainers: z.array(lootContainerPoint),
  lootLoose: z.array(looseLoot),
  maxPlayerLevel: z.number(),
  minPlayerLevel: z.number(),
  name: translatedText,
  nameId: z.string(),
  normalizedName: z.string(),
  players: z.string(),
  raidDuration: z.number(),
  scenePath: z.string(),
  spawns: z.array(mapSpawn),
  stationaryWeapons: z.array(mapStationaryWeapon),
  switches: z.array(mapSwitchSchema),
  transits: z.array(mapTransit),
  wiki: webUrl,
});

const lootContainer = z.looseObject({
  id: entityId,
  name: translatedText,
  normalizedName: z.string(),
});

const goonReport = z.looseObject({
  map: entityId,
  timestamp: z.string(),
});

const stationaryWeapon = z.looseObject({
  id: entityId,
  name: translatedText,
  normalizedName: z.string(),
  shortName: translatedText,
});

const mobEquipment = z.looseObject({
  attributes: z.looseObject({ slot: z.string() }),
  contains: z.array(
    z.looseObject({
      attributes: z.record(z.string(), z.unknown()),
      count: z.number(),
      item: entityId,
    }),
  ),
  count: z.number(),
  item: entityId,
});

const mobHealth = z.looseObject({
  bodyPart: z.string(),
  id: z.string(),
  max: z.number(),
});

const mobItem = z.looseObject({
  attributes: z.looseObject({
    difficulty: z.string(),
    prevalence: z.number(),
  }),
  id: entityId,
});

export const mobSchema = z.looseObject({
  equipment: z.array(mobEquipment),
  // Upstream emits explicit `null` body-part entries for some mobs and omits
  // the field entirely for mobs without a configured health pool.
  health: z.array(mobHealth.nullable()).optional(),
  id: entityId,
  imagePortraitLink: assetUrl,
  imagePosterLink: assetUrl,
  items: z.array(mobItem),
  name: z.string(),
  normalizedName: z.string(),
});

export const mapsDataSchema = z.looseObject({
  goonReports: z.array(goonReport),
  lootContainers: z.record(entityId, lootContainer),
  maps: z.record(entityId, mapSchema),
  mobs: z.record(entityId, mobSchema),
  stationaryWeapons: z.record(entityId, stationaryWeapon),
});

export type TarkovMap = z.infer<typeof mapSchema>;
export type Mob = z.infer<typeof mobSchema>;
export type MapsData = z.infer<typeof mapsDataSchema>;
