/**
 * Canonical JSON helpers shared by the fixture recorder and the upstream
 * fetcher. Keeping them here (instead of under `fixtures/`) lets the fetcher
 * hash payloads without depending on fixture-recordings code.
 */

import { createHash } from "node:crypto";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** Recursively sort object keys; array order is left untouched. */
export function sortKeysDeep(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeysDeep);
  if (!isRecord(value)) return value;

  const sorted: Record<string, unknown> = {};
  for (const key of Object.keys(value).sort()) {
    sorted[key] = sortKeysDeep(value[key]);
  }
  return sorted;
}

/** Canonical JSON with sorted keys and no insignificant whitespace. */
export function canonicalJson(value: unknown): string {
  return JSON.stringify(sortKeysDeep(value));
}

/**
 * SHA-256 (lowercase hex) over the canonical JSON form of `value`, so object
 * key order cannot change the digest.
 */
export function canonicalSha256(value: unknown): string {
  return createHash("sha256").update(canonicalJson(value), "utf8").digest("hex");
}
