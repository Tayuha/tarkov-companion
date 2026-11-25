import { sortKeysDeep } from "../util/canonical.js";
import type { BundleRecord } from "./contract.js";
import { compareRecords } from "./registry.js";

export { normalizeDataset, compareRecords, NORMALIZE_DATASETS, isNormalizeDataset } from "./registry.js";
export type { NormalizeDataset } from "./registry.js";
export type { BundleRecord, NormalizeResult, NormalizeStats } from "./contract.js";

/**
 * One JSON object per line, sorted by `kind` then `id`, with canonical key
 * order inside every line and a trailing newline. Identical input always
 * produces byte-identical output.
 */
export function serializeJsonl(records: readonly BundleRecord[]): string {
  if (records.length === 0) return "";
  const sorted = [...records].sort(compareRecords);
  const lines = sorted.map((record) => JSON.stringify(sortKeysDeep(record)));
  return `${lines.join("\n")}\n`;
}
