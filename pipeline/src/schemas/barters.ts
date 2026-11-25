import { z } from "zod";
import { attributeBag, entityId } from "./primitives.js";

/**
 * `/regular/barters`: a bare array under `data`, with no translation pointers
 * upstream.
 *
 * `taskUnlock` is explicitly null for most barters, so it stays nullable
 * rather than optional. `requiredItems` is never empty in the fixture but is
 * still an array, not a tuple.
 */

export const barterItemSchema = z.looseObject({
  attributes: attributeBag,
  count: z.number(),
  item: entityId,
});

export const barterSchema = z.looseObject({
  buyLimit: z.number(),
  id: entityId,
  minTraderLevel: z.number(),
  offeredItem: barterItemSchema,
  requiredItems: z.array(barterItemSchema),
  restockAmount: z.number(),
  taskUnlock: z.string().nullable(),
  trader: entityId,
});

export const bartersDataSchema = z.array(barterSchema);

export type Barter = z.infer<typeof barterSchema>;
export type BarterItem = z.infer<typeof barterItemSchema>;
export type BartersData = z.infer<typeof bartersDataSchema>;
