import {
  type BundleRecord,
  type FieldSpec,
  type NormalizeContext,
  integerValue,
  makeRecord,
  projectFields,
  projectList,
  requireRecord,
} from "./contract.js";

/**
 * `/regular/barters` -> `barter` records. `data` is already an array.
 *
 * `taskUnlock` is nullable upstream and stays `taskUnlockId: null` so "no task
 * requirement" is explicit instead of missing.
 */

const BARTER_ITEM_SPEC: FieldSpec = {
  item: "itemId",
  count: { to: "count", transform: integerValue },
  attributes: "attributes",
};

const BARTER_SPEC: FieldSpec = {
  id: "id",
  trader: "traderId",
  buyLimit: { to: "buyLimit", transform: integerValue },
  minTraderLevel: { to: "minTraderLevel", transform: integerValue },
  restockAmount: { to: "restockAmount", transform: integerValue },
  taskUnlock: "taskUnlockId",
  offeredItem: {
    to: "offeredItem",
    transform: (value, ctx, path) =>
      projectFields(requireRecord(value, path), BARTER_ITEM_SPEC, ctx, path),
  },
  requiredItems: {
    to: "requiredItems",
    transform: (value, ctx, path) =>
      projectList(value, ctx, path, (entry, context, entryPath) =>
        projectFields(entry, BARTER_ITEM_SPEC, context, entryPath),
      ),
  },
};

export function normalizeBarters(data: unknown, ctx: NormalizeContext): BundleRecord[] {
  if (!Array.isArray(data)) throw new Error("barters: expected an array");
  return data.map((entry, index) =>
    makeRecord(
      "barter",
      projectFields(requireRecord(entry, `barters[${index}]`), BARTER_SPEC, ctx, `barters[${index}]`),
    ),
  );
}
