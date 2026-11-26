import { describe, expect, it } from "vitest";
import { isRecord } from "../normalize/contract.js";
import { normalizeDataset } from "../normalize/index.js";
import { craftsDataSchema } from "./crafts.js";
import { itemSchema } from "./items.js";
import {
  mapBossSchema,
  mapExtractSchema,
  mapHazardSchema,
  mapSwitchSchema,
} from "./maps.js";
import { taskConditionSchema } from "./tasks.js";

/**
 * Shapes observed in the live API on 2026-11-25 that the trimmed fixture set
 * did not carry. Each case pins one deliberate relaxation so a future schema
 * change cannot silently reject the live payload again.
 */

const position = { x: 0, y: 0, z: 0 };

describe("items live shape", () => {
  it("accepts an empty wiki link, a null buy limit and absent flea prices", () => {
    const parsed = itemSchema.parse({
      baseImageLink: "https://assets.tarkov.dev/x.webp",
      gridImageLink: "https://assets.tarkov.dev/x.webp",
      iconLink: "https://assets.tarkov.dev/x.webp",
      image512pxLink: "https://assets.tarkov.dev/x.webp",
      image8xLink: "https://assets.tarkov.dev/x.webp",
      inspectImageLink: "https://assets.tarkov.dev/x.webp",
      id: "item1",
      name: "Item",
      shortName: "Itm",
      normalizedName: "item",
      backgroundColor: "default",
      basePrice: 1,
      buyFromTrader: [
        {
          buyLimit: null,
          currency: "RUB",
          currencyItem: "roubles",
          minTraderLevel: 1,
          price: 1,
          priceRUB: 1,
          restockAmount: 1,
          taskUnlock: null,
          trader: "trader1",
        },
      ],
      categories: [],
      conflictingCategories: [],
      conflictingItems: [],
      conflictingSlotIds: [],
      containsItems: [],
      discardLimit: 1,
      handbookCategories: [],
      height: 1,
      width: 1,
      weight: 1,
      minLevelForFlea: 1,
      link: "https://tarkov.dev/item/item1",
      wikiLink: "",
      types: ["gun"],
      updated: "2026-11-25T17:08:03.000Z",
      sellToTrader: [],
      // PvE records can omit `propertiesType` and every price field.
      properties: {},
    });

    expect(parsed.wikiLink).toBe("");
    expect(parsed.buyFromTrader[0]?.buyLimit).toBeNull();
    expect(parsed.avg24hPrice).toBeUndefined();
  });
});

describe("tasks live shape", () => {
  it("accepts notWearing as objects and normalizes it to item ids", () => {
    const condition = {
      id: "objective1",
      description: "Do not wear armor",
      optional: false,
      type: "shoot",
      notWearing: [{ id: "armor1", name: "Armor" }],
    };
    expect(() => taskConditionSchema.parse(condition)).not.toThrow();

    const normalized = normalizeDataset("tasks", {
      tasks: { task1: { id: "task1", objectives: [condition] } },
    });
    const task = normalized.records.find((record) => record.kind === "task");
    expect(task).toBeDefined();
    const objectives = task?.["objectives"];
    if (!Array.isArray(objectives)) throw new Error("task has no objectives");
    const objective: unknown = objectives[0];
    if (!isRecord(objective)) throw new Error("objective is not an object");
    expect(objective["notWearingItemIds"]).toEqual(["armor1"]);
    expect(objective["notWearing"]).toBeUndefined();
  });
});

describe("crafts live shape", () => {
  it("accepts requiredQuestItems with only an item id and keeps the id reference", () => {
    const craft = {
      id: "craft1",
      duration: 10,
      level: 1,
      station: "station1",
      gameEditions: [],
      productItem: { item: "product1", count: 1, attributes: {} },
      requiredItems: [],
      requiredQuestItems: [{ item: "questItem1" }],
    };

    expect(() => craftsDataSchema.parse([craft])).not.toThrow();

    const normalized = normalizeDataset("crafts", [craft]);
    const record = normalized.records[0];
    expect(record?.["requiredQuestItems"]).toEqual([{ itemId: "questItem1" }]);
  });
});

describe("maps live shape", () => {
  it("accepts a hazard without top/bottom", () => {
    expect(() =>
      mapHazardSchema.parse({
        id: "hazard1",
        hazardType: "minefield",
        name: "Landmine",
        position,
        outline: [],
      }),
    ).not.toThrow();
  });

  it("accepts a boss without spawnTimeRandom and an extract without faction", () => {
    expect(() =>
      mapBossSchema.parse({
        escorts: [],
        mob: "boss",
        spawnChance: 1,
        spawnLocations: [],
        spawnTime: -1,
        spawnTrigger: null,
        supports: [],
      }),
    ).not.toThrow();

    expect(() =>
      mapExtractSchema.parse({
        bottom: -1,
        id: "extract1",
        name: "Cellars",
        outline: [],
        position,
        switch: false,
        switches: [],
        top: 1,
      }),
    ).not.toThrow();
  });

  it("accepts an object activation graph and normalizes switch references", () => {
    const mapSwitch = {
      id: "switch1",
      name: "switch_power",
      switchType: "Open",
      activatedBy: "switch0",
      activates: [{ operation: "Unlock", switch: "switch2" }],
      door: null,
      bottom: -1,
      top: 1,
      position,
      size: { x: 1, y: 1, z: 1 },
      outline: [],
    };

    expect(() => mapSwitchSchema.parse(mapSwitch)).not.toThrow();

    const normalized = normalizeDataset("maps", {
      maps: { map1: { id: "map1", switches: [mapSwitch] } },
    });
    const map = normalized.records.find((record) => record.kind === "map");
    const switches = map?.["switches"];
    if (!Array.isArray(switches)) throw new Error("map has no switches");
    const entry: unknown = switches[0];
    if (!isRecord(entry)) throw new Error("switch is not an object");
    expect(entry["activatedBy"]).toBe("switch0");
    expect(entry["activates"]).toEqual([{ operation: "Unlock", switchId: "switch2" }]);
  });
});
