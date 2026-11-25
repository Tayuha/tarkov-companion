import { z } from "zod";

/**
 * `/regular/prices/{itemId}`: a bare array of price observations under `data`.
 *
 * `timestamp` is epoch milliseconds, not an ISO string. All four numeric
 * fields are present on every recorded point, so none are optional.
 */

export const pricePointSchema = z.looseObject({
  offerCount: z.number(),
  price: z.number(),
  priceMin: z.number(),
  timestamp: z.number(),
});

export const pricesDataSchema = z.array(pricePointSchema);

export type PricePoint = z.infer<typeof pricePointSchema>;
export type PricesData = z.infer<typeof pricesDataSchema>;
