import { z } from "zod";
import { stringArray } from "./primitives.js";

/**
 * Envelope schemas for the two upstream document shapes.
 *
 * A dataset response is `{ data, translations? }`; `translations` is a list of
 * JSONPath pointers and may be absent or empty. The locale dictionary is
 * `{ data: Record<placeholder, text> }` and is keyed by the placeholder string
 * itself, not by path.
 *
 * The envelope is loose so upstream can add diagnostic fields (pagination,
 * generation timestamps) without breaking the pipeline. Only `data` and the
 * translation pointer shape are enforced.
 */

export const translationsSchema = stringArray;

export const dictionarySchema = z.looseObject({
  data: z.record(z.string(), z.string()),
});

export type Dictionary = z.infer<typeof dictionarySchema>;

/** Build the `{ data, translations? }` envelope for one dataset schema. */
export function envelopeSchemaFor<T extends z.ZodType>(data: T) {
  return z.looseObject({
    data,
    translations: translationsSchema.optional(),
  });
}
