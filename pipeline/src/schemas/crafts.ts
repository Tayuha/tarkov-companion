import { z } from "zod";
import { attributeBag, entityId, stringArray } from "./primitives.js";

/**
 * `/regular/crafts`: a bare array under `data`, with no translation pointers
 * upstream.
 *
 * `taskUnlock` is absent from most crafts, while the remaining fields are
 * present on every recorded craft. Ingredient arrays may be empty.
 */

export const craftItemSchema = z.looseObject({
  attributes: attributeBag,
  count: z.number(),
  item: entityId,
});

export const craftSchema = z.looseObject({
  duration: z.number(),
  gameEditions: stringArray,
  id: entityId,
  level: z.number(),
  productItem: craftItemSchema,
  requiredItems: z.array(craftItemSchema),
  requiredQuestItems: z.array(craftItemSchema),
  station: entityId,
  taskUnlock: entityId.optional(),
});

export const craftsDataSchema = z.array(craftSchema);

export type Craft = z.infer<typeof craftSchema>;
export type CraftItem = z.infer<typeof craftItemSchema>;
export type CraftsData = z.infer<typeof craftsDataSchema>;
