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

/**
 * `requiredQuestItems` is only `{item}` upstream: these entries are quest-item
 * references, not craft ingredients, so they carry no count or attributes.
 */
export const craftQuestItemSchema = z.looseObject({
  item: entityId,
  count: z.number().optional(),
  attributes: attributeBag.optional(),
});

export const craftSchema = z.looseObject({
  duration: z.number(),
  gameEditions: stringArray,
  id: entityId,
  level: z.number(),
  productItem: craftItemSchema,
  requiredItems: z.array(craftItemSchema),
  requiredQuestItems: z.array(craftQuestItemSchema),
  station: entityId,
  taskUnlock: entityId.optional(),
});

export const craftsDataSchema = z.array(craftSchema);

export type Craft = z.infer<typeof craftSchema>;
export type CraftItem = z.infer<typeof craftItemSchema>;
export type CraftsData = z.infer<typeof craftsDataSchema>;
