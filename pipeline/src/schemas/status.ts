import { z } from "zod";
import { entityId, opaqueArray } from "./primitives.js";

/**
 * `/status`: the API health snapshot under `common/`.
 *
 * Entries in `currentStatuses` omit `_id` or `message` depending on the
 * component, so both are optional; `generalStatus` carries `message` instead
 * of `_id`. `messages` is empty in the fixture and its element shape is not
 * observable, so it is an opaque array.
 */

export const statusEntrySchema = z.looseObject({
  name: z.string(),
  status: z.number(),
  statusCode: z.string(),
  _id: entityId.optional(),
  message: z.string().optional(),
});

export const statusDataSchema = z.looseObject({
  currentStatuses: z.array(statusEntrySchema),
  generalStatus: statusEntrySchema,
  messages: opaqueArray,
});

export type StatusEntry = z.infer<typeof statusEntrySchema>;
export type StatusData = z.infer<typeof statusDataSchema>;
