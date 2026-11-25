import type { BundleRecord, NormalizeContext, NormalizeResult } from "./contract.js";
import { StatsCollector, assertBundleRecords } from "./contract.js";
import { normalizeBarters } from "./barters.js";
import { normalizeCrafts } from "./crafts.js";
import { normalizeHideout } from "./hideout.js";
import { normalizeItems } from "./items.js";
import { normalizeMaps } from "./maps.js";
import { normalizeTasks } from "./tasks.js";
import { normalizeTraders } from "./traders.js";

/**
 * Dataset registry for the normalization stage.
 *
 * The key is the upstream dataset name from `{mode}/{dataset}`. Only datasets
 * with a defined bundle shape are registered; everything the app ingests comes
 * from this list.
 */

export type NormalizeDataset =
  | "items"
  | "tasks"
  | "traders"
  | "hideout"
  | "crafts"
  | "barters"
  | "maps";

export const NORMALIZE_DATASETS: readonly NormalizeDataset[] = [
  "items",
  "tasks",
  "traders",
  "hideout",
  "crafts",
  "barters",
  "maps",
];

type Normalizer = (data: unknown, ctx: NormalizeContext) => BundleRecord[];

const NORMALIZERS: Readonly<Record<NormalizeDataset, Normalizer>> = {
  items: normalizeItems,
  tasks: normalizeTasks,
  traders: normalizeTraders,
  hideout: normalizeHideout,
  crafts: normalizeCrafts,
  barters: normalizeBarters,
  maps: normalizeMaps,
};

export function isNormalizeDataset(value: string): value is NormalizeDataset {
  return Object.prototype.hasOwnProperty.call(NORMALIZERS, value);
}

/** Deterministic order: `kind`, then `id`, by code unit. */
export function compareRecords(a: BundleRecord, b: BundleRecord): number {
  if (a.kind !== b.kind) return a.kind < b.kind ? -1 : 1;
  if (a.id !== b.id) return a.id < b.id ? -1 : 1;
  return 0;
}

/**
 * Normalize one already-validated dataset into bundle records.
 *
 * The result is sorted and contract-checked, so callers can serialize it
 * directly. Normalization never throws for schema-valid input; it throws only
 * when the input violates the bundle contract (a placeholder, a duplicate
 * `kind`+`id`, a missing id, or a non-finite number).
 */
export function normalizeDataset(dataset: NormalizeDataset, data: unknown): NormalizeResult {
  const normalizer = NORMALIZERS[dataset];
  const stats = new StatsCollector();
  const records = normalizer(data, { stats }).sort(compareRecords);

  assertBundleRecords(dataset, records);

  return {
    dataset,
    records,
    stats: stats.snapshot(dataset, records),
  };
}
