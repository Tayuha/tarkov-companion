import { z } from "zod";
import { assetUrl, entityId, idArray, nullableNumber, translatedText } from "./primitives.js";

/**
 * `/pvp-season/season`: one season record under `data`.
 *
 * `perks` is an object with `common` and `personal` groups; both arrays may be
 * empty. `points` is null for perks that cost nothing, which is why it stays
 * nullable rather than optional.
 */

export const seasonPerkSchema = z.looseObject({
  description: translatedText,
  exclusiveToPerks: idArray,
  id: entityId,
  imageLink: assetUrl,
  name: translatedText,
  points: nullableNumber,
});

export const seasonDataSchema = z.looseObject({
  end: z.number(),
  id: entityId,
  name: translatedText,
  perks: z.looseObject({
    common: z.array(seasonPerkSchema),
    personal: z.array(seasonPerkSchema),
  }),
  start: z.number(),
});

export type SeasonPerk = z.infer<typeof seasonPerkSchema>;
export type SeasonData = z.infer<typeof seasonDataSchema>;
