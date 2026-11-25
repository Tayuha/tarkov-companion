import { z } from "zod";

/**
 * Shared primitives for the upstream schemas.
 *
 * The upstream API mixes numeric and string identifiers (24-hex entity ids,
 * numeric level keys, mob ids such as `ExUsec`, transit ids such as `12`), so
 * identifiers are non-empty strings rather than a hex pattern. Numeric fields
 * are validated as numbers, not integers, because the API returns fractions
 * for prices, weights and modifiers.
 *
 * `nullish` is only used where a recorded fixture shows a field that is both
 * absent from some records and `null` in others; `nullable` and `optional`
 * are preferred elsewhere so a missing value is not confused with an explicit
 * null.
 */

/** Any upstream identifier. Not checked for existence against other datasets. */
export const entityId = z.string().min(1);

/** A translatable text field: either a placeholder key or already-resolved text. */
export const translatedText = z.string();

/** ISO-8601 timestamp as served by the API (`2026-11-25T17:08:03.000Z`). */
export const isoDateTime = z.iso.datetime();

/** Absolute URL for an image hosted by assets.tarkov.dev. */
export const assetUrl = z.url();

/** Absolute URL for an external page (tarkov.dev, the wiki). */
export const webUrl = z.url();

export const stringArray = z.array(z.string());

export const idArray = z.array(entityId);

export const nullableNumber = z.number().nullable();

export const nullableText = z.string().nullable();

/** `{x, y, z}` position used by maps, spawn points and outlines. */
export const vector3 = z.looseObject({
  x: z.number(),
  y: z.number(),
  z: z.number(),
});

/**
 * `attributes` is an untyped bag upstream: usually `{}`, sometimes `[]`, and
 * sometimes carries a flag such as `{tool: true}` or `{foundInRaid: false}`.
 * Keys are intentionally not validated; consumers read the flags they know.
 */
export const attributeBag = z.union([
  z.record(z.string(), z.unknown()),
  z.array(z.unknown()),
]);

/**
 * Item filter block shared by grids, slots, barter offers and prestige
 * transfer settings. Every list is always present, but empty lists are valid.
 */
export const itemFilters = z.looseObject({
  allowedCategories: idArray,
  allowedItems: idArray,
  excludedCategories: idArray,
  excludedItems: idArray,
});

/** An array whose element shape is not observable in the committed fixtures. */
export const opaqueArray = z.array(z.unknown());
