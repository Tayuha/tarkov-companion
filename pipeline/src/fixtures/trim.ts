/**
 * Deterministic trimming helpers for recorded upstream fixtures.
 *
 * Fixtures must stay small enough to commit while still containing every field
 * the normalization schemas care about. Trimming therefore never drops keys
 * from a retained record: it selects a deterministic subset of records and
 * truncates long arrays, keeping at least one element per structural shape.
 *
 * Everything here is pure so the selection policy can be unit-tested without
 * the network.
 */

import { canonicalJson } from "../util/canonical.js";

// Re-exported for existing fixture callers/tests; the implementation lives in
// `util/canonical.ts` so the upstream fetcher can hash payloads without a
// dependency on fixture-only code.
export { canonicalJson, sortKeysDeep } from "../util/canonical.js";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Stable structural signature used to make sure a truncation keeps at least
 * one representative of every nested shape. Primitive values collapse to their
 * type; object keys are sorted so key order cannot affect the result.
 */
export function shapeSignature(value: unknown, depth = 4): string {
  if (Array.isArray(value)) {
    const shapes = [...new Set(value.map((item) => shapeSignature(item, depth - 1)))].sort();
    return `[${shapes.join("|")}]`;
  }
  if (isRecord(value)) {
    if (depth <= 0) return "{}";
    return `{${Object.keys(value)
      .sort()
      .map((key) => `${key}:${shapeSignature(value[key], depth - 1)}`)
      .join(",")}}`;
  }
  if (value === null) return "null";
  return typeof value;
}

function defaultSortKey(value: unknown): string {
  if (isRecord(value)) {
    for (const key of ["id", "name", "normalizedName"]) {
      const candidate = value[key];
      if (typeof candidate === "string") return candidate;
    }
  }
  return canonicalJson(value);
}

export interface SelectOptions {
  /** Upper bound for the number of retained records. */
  readonly limit: number;
  /** Deterministic ordering key. Defaults to `id`, `name`, `normalizedName`, then canonical JSON. */
  readonly sortKey?: (value: unknown) => string;
  /** Records kept per structural group before the list is filled by sort order. */
  readonly perGroup?: number;
  /** Structural grouping key. When omitted no group-based selection happens. */
  readonly groupKey?: (value: unknown) => string;
  /**
   * Features that must be represented by at least one retained record, e.g.
   * every objective type present upstream. Feature coverage is prioritised
   * over the `limit`; callers set limits large enough to hold the selection.
   */
  readonly featuresOf?: (value: unknown) => readonly string[];
}

export interface SelectResult {
  readonly selected: readonly unknown[];
  readonly total: number;
  readonly featuresCovered: number;
  readonly featuresTotal: number;
}

/**
 * Select records deterministically:
 *
 * 1. sort by `sortKey` (ties keep their original relative order);
 * 2. take records that introduce a not-yet-covered feature;
 * 3. take the first `perGroup` record of every structural group;
 * 4. fill the remaining slots in sort order.
 *
 * The returned records stay in sort order.
 */
export function selectRecords(values: readonly unknown[], options: SelectOptions): SelectResult {
  const sortKey = options.sortKey ?? defaultSortKey;
  const decorated = values.map((value, index) => ({ value, index, key: sortKey(value) }));
  decorated.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : a.index - b.index));

  const chosen = new Set<number>();
  const features = new Set<string>();
  const allFeatures = new Set<string>();

  if (options.featuresOf) {
    for (const entry of decorated) {
      const found = options.featuresOf(entry.value);
      for (const feature of found) allFeatures.add(feature);
      if (found.some((feature) => !features.has(feature))) {
        chosen.add(entry.index);
        for (const feature of found) features.add(feature);
      }
    }
  }

  if (options.groupKey) {
    const perGroup = options.perGroup ?? 1;
    const counts = new Map<string, number>();
    for (const entry of decorated) {
      const group = options.groupKey(entry.value);
      const count = counts.get(group) ?? 0;
      if (count < perGroup) {
        counts.set(group, count + 1);
        chosen.add(entry.index);
      }
    }
  }

  for (const entry of decorated) {
    if (chosen.size >= options.limit) break;
    chosen.add(entry.index);
  }

  const selected = decorated
    .filter((entry) => chosen.has(entry.index))
    .map((entry) => entry.value);

  return {
    selected,
    total: values.length,
    featuresCovered: features.size,
    featuresTotal: allFeatures.size,
  };
}

/**
 * Recursively truncate every array to at most `limit` elements. The first
 * occurrence of each structural shape is kept, then the front of the array
 * fills the rest, so key shapes survive even when the long tail is dropped.
 * Element order is preserved.
 */
export function truncateArrays(value: unknown, limit: number): unknown {
  if (Array.isArray(value)) {
    const kept = new Set<number>();
    const seen = new Set<string>();

    for (let index = 0; index < value.length && kept.size < limit; index += 1) {
      const signature = shapeSignature(value[index]);
      if (!seen.has(signature)) {
        seen.add(signature);
        kept.add(index);
      }
    }

    for (let index = 0; index < value.length && kept.size < limit; index += 1) {
      kept.add(index);
    }

    return [...kept]
      .sort((a, b) => a - b)
      .map((index) => truncateArrays(value[index], limit));
  }

  if (isRecord(value)) {
    const trimmed: Record<string, unknown> = {};
    for (const key of Object.keys(value)) {
      trimmed[key] = truncateArrays(value[key], limit);
    }
    return trimmed;
  }

  return value;
}

export interface RecordsPlan {
  readonly kind: "records";
  readonly limit: number;
  readonly perGroup?: number;
  readonly groupKey?: (value: unknown) => string;
  readonly featuresOf?: (value: unknown) => readonly string[];
  /** Key used when rebuilding an object map. Defaults to the record's `id`. */
  readonly keyOf?: (value: unknown) => string;
}

export interface ArrayPlan {
  readonly kind: "array";
  readonly limit: number;
  /** Keep the newest rather than the oldest elements, then truncate. */
  readonly keep?: "first" | "last";
}

export interface KeepPlan {
  readonly kind: "keep";
}

export type CollectionPlan = RecordsPlan | ArrayPlan | KeepPlan;

export interface TrimPlan {
  readonly collections: Readonly<Record<string, CollectionPlan>>;
  /** Maximum length of arrays nested inside retained records. */
  readonly nestedArrayLimit: number;
}

export interface CollectionStat {
  readonly key: string;
  readonly input: number;
  readonly output: number;
  readonly featuresCovered: number;
  readonly featuresTotal: number;
}

export interface TrimPayloadResult {
  readonly data: unknown;
  readonly stats: readonly CollectionStat[];
}

function keyOfRecord(value: unknown): string {
  if (isRecord(value) && typeof value.id === "string") return value.id;
  return canonicalJson(value);
}

function trimCollection(key: string, value: unknown, plan: CollectionPlan, nestedArrayLimit: number): {
  readonly value: unknown;
  readonly stat: CollectionStat;
} {
  if (plan.kind === "keep") {
    const size = Array.isArray(value) ? value.length : isRecord(value) ? Object.keys(value).length : 1;
    return {
      value,
      stat: { key, input: size, output: size, featuresCovered: 0, featuresTotal: 0 },
    };
  }

  if (plan.kind === "array") {
    if (!Array.isArray(value)) {
      return {
        value: truncateArrays(value, nestedArrayLimit),
        stat: { key, input: 0, output: 0, featuresCovered: 0, featuresTotal: 0 },
      };
    }
    const window = plan.keep === "last" ? value.slice(-plan.limit) : value;
    const selected = window.slice(0, plan.limit).map((item) => truncateArrays(item, nestedArrayLimit));
    return {
      value: selected,
      stat: {
        key,
        input: value.length,
        output: selected.length,
        featuresCovered: 0,
        featuresTotal: 0,
      },
    };
  }

  if (!isRecord(value)) {
    return {
      value: truncateArrays(value, nestedArrayLimit),
      stat: { key, input: 0, output: 0, featuresCovered: 0, featuresTotal: 0 },
    };
  }

  const entries = Object.entries(value);
  const result = selectRecords(
    entries.map(([, record]) => record),
    {
      limit: plan.limit,
      ...(plan.groupKey ? { groupKey: plan.groupKey } : {}),
      ...(plan.perGroup !== undefined ? { perGroup: plan.perGroup } : {}),
      ...(plan.featuresOf ? { featuresOf: plan.featuresOf } : {}),
    },
  );

  const keyOf = plan.keyOf ?? keyOfRecord;
  const rebuilt: Record<string, unknown> = {};
  for (const record of result.selected) {
    rebuilt[keyOf(record)] = truncateArrays(record, nestedArrayLimit);
  }

  return {
    value: rebuilt,
    stat: {
      key,
      input: entries.length,
      output: result.selected.length,
      featuresCovered: result.featuresCovered,
      featuresTotal: result.featuresTotal,
    },
  };
}

/**
 * Apply a per-top-level-key trimming plan. Keys without a plan are kept whole
 * (their nested arrays are still truncated to `nestedArrayLimit`).
 */
export function trimPayload(data: unknown, plan: TrimPlan): TrimPayloadResult {
  if (!isRecord(data)) {
    return {
      data: truncateArrays(data, plan.nestedArrayLimit),
      stats: [],
    };
  }

  const trimmed: Record<string, unknown> = {};
  const stats: CollectionStat[] = [];

  for (const key of Object.keys(data)) {
    const collectionPlan = plan.collections[key];
    if (collectionPlan === undefined) {
      trimmed[key] = truncateArrays(data[key], plan.nestedArrayLimit);
      continue;
    }

    const result = trimCollection(key, data[key], collectionPlan, plan.nestedArrayLimit);
    trimmed[key] = result.value;
    stats.push(result.stat);
  }

  return { data: trimmed, stats };
}
