import {
  type BundleRecord,
  type FieldSpec,
  type NormalizeContext,
  integerValue,
  makeRecord,
  projectFields,
  projectList,
  requireRecord,
  stringList,
} from "./contract.js";

/**
 * `/regular/crafts` -> `craft` records. `data` is already an array.
 *
 * Durations are seconds and stay integers. `productItem` keeps its count and
 * attributes because a craft can yield more than one product; the item itself
 * is referenced by `itemId`.
 */

const CRAFT_ITEM_SPEC: FieldSpec = {
  item: "itemId",
  count: { to: "count", transform: integerValue },
  attributes: "attributes",
};

const CRAFT_SPEC: FieldSpec = {
  id: "id",
  duration: { to: "duration", transform: integerValue },
  level: { to: "level", transform: integerValue },
  station: "stationId",
  taskUnlock: "taskUnlockId",
  gameEditions: { to: "gameEditions", transform: stringList },
  productItem: {
    to: "productItem",
    transform: (value, ctx, path) =>
      projectFields(requireRecord(value, path), CRAFT_ITEM_SPEC, ctx, path),
  },
  requiredItems: {
    to: "requiredItems",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, CRAFT_ITEM_SPEC, context, entryPath),
      ),
  },
  requiredQuestItems: {
    to: "requiredQuestItems",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, CRAFT_ITEM_SPEC, context, entryPath),
      ),
  },
};

export function normalizeCrafts(data: unknown, ctx: NormalizeContext): BundleRecord[] {
  if (!Array.isArray(data)) throw new Error("crafts: expected an array");
  return data.map((entry, index) =>
    makeRecord(
      "craft",
      projectFields(requireRecord(entry, `crafts[${index}]`), CRAFT_SPEC, ctx, `crafts[${index}]`),
    ),
  );
}
