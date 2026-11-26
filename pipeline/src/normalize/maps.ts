import {
  type BundleRecord,
  type FieldSpec,
  type JsonRecord,
  type NormalizeContext,
  integerValue,
  isoFromEpochMillisString,
  makeRecord,
  numberValue,
  projectFields,
  projectList,
  projectMap,
  requireId,
  requireRecord,
  requireString,
  stringList,
  vector3,
  vector3List,
} from "./contract.js";

/**
 * `/regular/maps` -> `map`, `mob`, `lootContainer`, `stationaryWeapon` and
 * `goonReport` records.
 *
 * Geometry (positions, outlines, sizes) is normalized to `{x, y, z}`. The
 * `btrStops` array has no observed element shape, so it is copied verbatim as
 * an opaque array and documented as such.
 */

const ARTILLERY_ZONE_SPEC: FieldSpec = {
  id: "id",
  // Upstream spells this `botom`; the contract keeps the upstream key.
  botom: { to: "botom", transform: numberValue },
  top: { to: "top", transform: numberValue },
  position: { to: "position", transform: vector3 },
  outline: { to: "outline", transform: vector3List },
  size: { to: "size", transform: vector3 },
};

const ARTILLERY_SPEC: FieldSpec = {
  zones: {
    to: "zones",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, ARTILLERY_ZONE_SPEC, context, entryPath),
      ),
  },
};

const ESCORT_AMOUNT_SPEC: FieldSpec = {
  chance: "chance",
  count: { to: "count", transform: integerValue },
};

const ESCORT_SPEC: FieldSpec = {
  mob: "mobId",
  amount: {
    to: "amount",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, ESCORT_AMOUNT_SPEC, context, entryPath),
      ),
  },
};

const SPAWN_LOCATION_SPEC: FieldSpec = {
  chance: "chance",
  name: "name",
  positions: { to: "positions", transform: vector3List },
  spawnKey: "spawnKey",
};

const BOSS_SPEC: FieldSpec = {
  mob: "mobId",
  escorts: {
    to: "escorts",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, ESCORT_SPEC, context, entryPath),
      ),
  },
  spawnChance: "spawnChance",
  spawnLocations: {
    to: "spawnLocations",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, SPAWN_LOCATION_SPEC, context, entryPath),
      ),
  },
  spawnTime: { to: "spawnTime", transform: numberValue },
  spawnTimeRandom: "spawnTimeRandom",
  spawnTrigger: "spawnTrigger",
  supports: { to: "supports", transform: stringList },
};

const EXTRACT_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  faction: "faction",
  bottom: { to: "bottom", transform: numberValue },
  top: { to: "top", transform: numberValue },
  position: { to: "position", transform: vector3 },
  outline: { to: "outline", transform: vector3List },
  switch: "switch",
  switches: { to: "switches", transform: stringList },
  transferItem: {
    to: "transferItem",
    transform: (value, ctx, path) =>
      projectFields(
        requireRecord(value, path),
        { count: { to: "count", transform: integerValue }, item: "itemId" },
        ctx,
        path,
      ),
  },
};

const HAZARD_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  hazardType: "hazardType",
  bottom: { to: "bottom", transform: numberValue },
  top: { to: "top", transform: numberValue },
  position: { to: "position", transform: vector3 },
  outline: { to: "outline", transform: vector3List },
};

const LOCK_SPEC: FieldSpec = {
  id: "id",
  key: "keyId",
  lockType: "lockType",
  needsPower: "needsPower",
  position: { to: "position", transform: vector3 },
};

const LOOT_CONTAINER_POINT_SPEC: FieldSpec = {
  lootContainer: "lootContainerId",
  position: { to: "position", transform: vector3 },
};

const LOOSE_LOOT_SPEC: FieldSpec = {
  items: { to: "itemIds", transform: stringList },
  position: { to: "position", transform: vector3 },
};

const SPAWN_SPEC: FieldSpec = {
  categories: { to: "categories", transform: stringList },
  sides: { to: "sides", transform: stringList },
  position: { to: "position", transform: vector3 },
  zoneName: "zoneName",
};

const STATIONARY_WEAPON_POINT_SPEC: FieldSpec = {
  stationaryWeapon: "stationaryWeaponId",
  position: { to: "position", transform: vector3 },
};

function projectActivations(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.map((entry, index) => {
    const activation = requireRecord(entry, `${path}[${index}]`);
    for (const key of Object.keys(activation)) {
      if (key !== "operation" && key !== "switch") {
        ctx.stats.drop(`${path}[${index}].${key}`);
      }
    }
    return {
      operation: requireString(activation["operation"], `${path}[${index}].operation`),
      switchId: requireId(activation["switch"], `${path}[${index}].switch`),
    };
  });
}

const SWITCH_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  switchType: "switchType",
  activatedBy: "activatedBy",
  activates: { to: "activates", transform: projectActivations },
  // `door` is opaque upstream (null or an unmodelled payload); copy it as-is.
  door: "door",
  bottom: { to: "bottom", transform: numberValue },
  top: { to: "top", transform: numberValue },
  position: { to: "position", transform: vector3 },
  outline: { to: "outline", transform: vector3List },
  size: { to: "size", transform: vector3 },
};

const TRANSIT_SPEC: FieldSpec = {
  id: "id",
  map: "mapId",
  description: "description",
  conditions: "conditions",
  bottom: { to: "bottom", transform: numberValue },
  top: { to: "top", transform: numberValue },
  position: { to: "position", transform: vector3 },
  outline: { to: "outline", transform: vector3List },
};

const MAP_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
  nameId: "nameId",
  description: "description",
  wiki: "wikiLink",
  players: "players",
  enemies: { to: "enemies", transform: stringList },
  raidDuration: { to: "raidDuration", transform: integerValue },
  minPlayerLevel: { to: "minPlayerLevel", transform: integerValue },
  maxPlayerLevel: { to: "maxPlayerLevel", transform: integerValue },
  accessKeysMinPlayerLevel: { to: "accessKeysMinPlayerLevel", transform: integerValue },
  accessKeys: { to: "accessKeyIds", transform: stringList },
  coordinateToCardinalRotation: { to: "coordinateToCardinalRotation", transform: numberValue },
  scenePath: "scenePath",
  btrStops: "btrStops",
  artillery: { to: "artillery", transform: projectArtillery },
  bosses: { to: "bosses", transform: projectBosses },
  extracts: { to: "extracts", transform: projectExtracts },
  hazards: { to: "hazards", transform: projectHazards },
  locks: { to: "locks", transform: projectLocks },
  lootContainers: { to: "lootContainers", transform: projectLootContainerPoints },
  lootLoose: { to: "lootLoose", transform: projectLooseLoot },
  spawns: { to: "spawns", transform: projectSpawns },
  stationaryWeapons: { to: "stationaryWeapons", transform: projectStationaryWeaponPoints },
  switches: { to: "switches", transform: projectSwitches },
  transits: { to: "transits", transform: projectTransits },
};

const MOB_CONTAINED_SPEC: FieldSpec = {
  attributes: "attributes",
  count: { to: "count", transform: integerValue },
  item: "itemId",
};

const MOB_EQUIPMENT_SPEC: FieldSpec = {
  attributes: {
    to: "slot",
    transform: (value, ctx, path) =>
      projectFields(requireRecord(value, path), { slot: "slot" }, ctx, path)["slot"],
  },
  contains: {
    to: "contains",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, MOB_CONTAINED_SPEC, context, entryPath),
      ),
  },
  count: { to: "count", transform: integerValue },
  item: "itemId",
};

const MOB_ITEM_SPEC: FieldSpec = {
  id: "itemId",
  attributes: {
    to: "attributes",
    transform: (value, ctx, path) =>
      projectFields(
        requireRecord(value, path),
        { difficulty: "difficulty", prevalence: "prevalence" },
        ctx,
        path,
      ),
  },
};

const MOB_HEALTH_SPEC: FieldSpec = {
  bodyPart: "bodyPart",
  id: "bodyPartId",
  max: { to: "max", transform: integerValue },
};

const MOB_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
  imagePortraitLink: "imagePortraitLink",
  imagePosterLink: "imagePosterLink",
  equipment: {
    to: "equipment",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, MOB_EQUIPMENT_SPEC, context, entryPath),
      ),
  },
  items: {
    to: "items",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, MOB_ITEM_SPEC, context, entryPath),
      ),
  },
  health: {
    to: "health",
    transform: (value, ctx, path) => projectMobHealth(value, ctx, path),
  },
};

const LOOT_CONTAINER_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  normalizedName: "normalizedName",
};

const STATIONARY_WEAPON_SPEC: FieldSpec = {
  id: "id",
  name: "name",
  shortName: "shortName",
  normalizedName: "normalizedName",
};

export function normalizeMaps(data: unknown, ctx: NormalizeContext): BundleRecord[] {
  const root = requireRecord(data, "maps");
  const records: BundleRecord[] = [];

  for (const [key, value] of Object.entries(root)) {
    switch (key) {
      case "maps":
        records.push(
          ...projectMap(value, ctx, "maps.maps", (entry, context, path) =>
            makeRecord("map", projectFields(entry, MAP_SPEC, context, path)),
          ),
        );
        break;
      case "mobs":
        records.push(
          ...projectMap(value, ctx, "maps.mobs", (entry, context, path) =>
            makeRecord("mob", projectFields(entry, MOB_SPEC, context, path)),
          ),
        );
        break;
      case "lootContainers":
        records.push(
          ...projectMap(value, ctx, "maps.lootContainers", (entry, context, path) =>
            makeRecord("lootContainer", projectFields(entry, LOOT_CONTAINER_SPEC, context, path)),
          ),
        );
        break;
      case "stationaryWeapons":
        records.push(
          ...projectMap(value, ctx, "maps.stationaryWeapons", (entry, context, path) =>
            makeRecord(
              "stationaryWeapon",
              projectFields(entry, STATIONARY_WEAPON_SPEC, context, path),
            ),
          ),
        );
        break;
      case "goonReports":
        records.push(...normalizeGoonReports(value, ctx));
        break;
      default:
        ctx.stats.drop(`maps.${key}`);
    }
  }

  return records;
}

function projectArtillery(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord | undefined {
  return projectFields(requireRecord(value, path), ARTILLERY_SPEC, ctx, path);
}

function projectBosses(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, BOSS_SPEC, context, entryPath),
  );
}

function projectExtracts(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, EXTRACT_SPEC, context, entryPath),
  );
}

function projectHazards(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, HAZARD_SPEC, context, entryPath),
  );
}

function projectLocks(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, LOCK_SPEC, context, entryPath),
  );
}

function projectLootContainerPoints(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, LOOT_CONTAINER_POINT_SPEC, context, entryPath),
  );
}

function projectLooseLoot(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, LOOSE_LOOT_SPEC, context, entryPath),
  );
}

function projectSpawns(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, SPAWN_SPEC, context, entryPath),
  );
}

function projectStationaryWeaponPoints(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, STATIONARY_WEAPON_POINT_SPEC, context, entryPath),
  );
}

function projectSwitches(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, SWITCH_SPEC, context, entryPath),
  );
}

function projectTransits(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): JsonRecord[] | undefined {
  return projectList(value, ctx, path, (entry, context, entryPath) =>
    projectFields(entry, TRANSIT_SPEC, context, entryPath),
  );
}

function projectMobHealth(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
): Array<JsonRecord | null> | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.map((entry, index) => {
    if (entry === null) return null;
    return projectFields(
      requireRecord(entry, `${path}[${index}]`),
      MOB_HEALTH_SPEC,
      ctx,
      `${path}[${index}]`,
    );
  });
}

function normalizeGoonReports(value: unknown, ctx: NormalizeContext): BundleRecord[] {
  if (!Array.isArray(value)) return [];

  return value.map((entry, index) => {
    const report = requireRecord(entry, `maps.goonReports[${index}]`);
    const mapId = requireId(report["map"], `maps.goonReports[${index}].map`);
    const observedAt = isoFromEpochMillisString(report["timestamp"]);
    if (observedAt === undefined) {
      throw new Error(`maps.goonReports[${index}].timestamp: expected epoch milliseconds`);
    }
    for (const key of Object.keys(report)) {
      if (key !== "map" && key !== "timestamp") {
        ctx.stats.drop(`maps.goonReports[${index}].${key}`);
      }
    }
    return { kind: "goonReport", id: `${mapId}@${observedAt}`, mapId, observedAt };
  });
}
