import { z } from "zod";
import type { LocalizationStats } from "../upstream/localize.js";
import {
  DATASET_FILE_SUFFIX,
  MANIFEST_FILE,
  serializeManifest,
  type BundleManifest,
} from "./manifest.js";
import { validateBundle } from "./validate.js";

/**
 * Publication gate.
 *
 * The gate is the last check between a built bundle and a release. It is pure:
 * the manifest and (optionally) the compressed files are already in memory, and
 * it never touches the network or the filesystem. `npm run sync` runs it after
 * building a mode and before `publishBundle`; `npm run gate` runs it against a
 * bundle directory (for example a downloaded release).
 *
 * Hard failures (a mode is not published):
 *
 *   - the compressed dataset bytes of one mode exceed the 10 MB budget;
 *   - any placeholder-shaped string survives in the JSONL (delegated to
 *     `validateBundle`, so the check is the same one the public validator runs);
 *   - dictionary keys are missing beyond the allowed threshold (0 by default);
 *   - translation pointers cannot be parsed, which means upstream metadata
 *     drifted out of the supported JSONPath grammar.
 *
 * Warnings only: stale/unresolved pointers, skipped datasets and unreferenced
 * local dataset files (inactive `--prune` candidates). Upstream metadata is
 * allowed to be stale; only coverage and unparsable pointers block a release.
 */

export const DEFAULT_MAX_COMPRESSED_BYTES = 10 * 1024 * 1024;
export const DEFAULT_MAX_MISSING_KEYS = 0;

export type GateIssueCode =
  | "compressed-size"
  | "placeholder"
  | "missing-keys"
  | "failed-path"
  | "invalid-bundle"
  | "validation-warning"
  | "stale-pointer"
  | "skipped-dataset"
  | "prune-candidate";

export interface GateIssue {
  readonly code: GateIssueCode;
  readonly message: string;
  /** Dataset name when the issue belongs to one; `null` for mode-wide issues. */
  readonly dataset: string | null;
}

/** Per-dataset localization diagnostics, as stored in the sync report. */
export const localizationPathFailureSchema = z.object({
  path: z.string(),
  error: z.string(),
});

export const datasetLocalizationMetricsSchema = z.object({
  dataset: z.string().min(1),
  translated: z.number().int().nonnegative(),
  visited: z.number().int().nonnegative(),
  missingKeys: z.number().int().nonnegative(),
  failedPaths: z.array(localizationPathFailureSchema),
  stalePointers: z.array(z.string()),
});

export type LocalizationPathFailure = z.infer<typeof localizationPathFailureSchema>;
export type DatasetLocalizationMetrics = z.infer<typeof datasetLocalizationMetricsSchema>;

/** Project the resolver's diagnostics onto the serializable report shape. */
export function localizationMetricsFromStats(
  dataset: string,
  stats: LocalizationStats,
): DatasetLocalizationMetrics {
  return {
    dataset,
    translated: stats.translated,
    visited: stats.visited,
    missingKeys: stats.missingKeys.length,
    failedPaths: stats.failedPaths.map((entry) => ({ path: entry.path, error: entry.error })),
    stalePointers: [...stats.unresolvedPaths].sort(),
  };
}

export interface GateMetrics {
  readonly mode: string;
  readonly datasets: number;
  /** Sum over the actual files when supplied, otherwise the manifest entries. */
  readonly compressedBytes: number;
  readonly maxCompressedBytes: number;
  readonly missingKeys: number;
  readonly maxMissingKeys: number;
  readonly failedPaths: number;
  readonly stalePointers: number;
  readonly skippedDatasets: number;
  readonly pruneCandidates: number;
}

export interface GateResult {
  readonly ok: boolean;
  readonly failures: readonly GateIssue[];
  readonly warnings: readonly GateIssue[];
  readonly metrics: GateMetrics;
}

export interface GateInput {
  readonly manifest: BundleManifest;
  /**
   * Compressed dataset bytes keyed by manifest `path`. When supplied the gate
   * also runs the full contract validator, sizes come from these bytes (a
   * wrong `totals` cannot hide an oversized mode) and extra dataset files are
   * reported as prune candidates.
   */
  readonly files?: ReadonlyMap<string, Uint8Array>;
  /** Directory entries that are not files; forwarded to the validator. */
  readonly extraFiles?: readonly string[];
  /** Localization diagnostics for this mode, one entry per fetched dataset. */
  readonly localization?: readonly DatasetLocalizationMetrics[];
  readonly maxCompressedBytes?: number;
  readonly maxMissingKeys?: number;
}

function issue(
  code: GateIssueCode,
  message: string,
  dataset: string | null = null,
): GateIssue {
  return { code, message, dataset };
}

function sumCompressedBytes(
  manifest: BundleManifest,
  files: ReadonlyMap<string, Uint8Array> | undefined,
): number {
  return manifest.datasets.reduce((sum, entry) => {
    const actual = files?.get(entry.path)?.byteLength;
    return sum + (actual ?? entry.compressedBytes);
  }, 0);
}

/** Unreferenced local dataset files; deleting them is what `--prune` would do. */
function pruneCandidates(
  manifest: BundleManifest,
  files: ReadonlyMap<string, Uint8Array> | undefined,
): string[] {
  if (files === undefined) return [];
  const referenced = new Set(manifest.datasets.map((entry) => entry.path));
  return [...files.keys()]
    .filter(
      (name) =>
        name !== MANIFEST_FILE &&
        name.endsWith(DATASET_FILE_SUFFIX) &&
        !referenced.has(name),
    )
    .sort();
}

/** Run every publication rule against an in-memory bundle. */
export function gateBundle(input: GateInput): GateResult {
  const maxCompressedBytes = input.maxCompressedBytes ?? DEFAULT_MAX_COMPRESSED_BYTES;
  const maxMissingKeys = input.maxMissingKeys ?? DEFAULT_MAX_MISSING_KEYS;
  const { manifest } = input;
  const failures: GateIssue[] = [];
  const warnings: GateIssue[] = [];

  const compressedBytes = sumCompressedBytes(manifest, input.files);
  if (compressedBytes > maxCompressedBytes) {
    failures.push(
      issue(
        "compressed-size",
        `${manifest.mode}: compressed datasets total ${String(compressedBytes)} bytes, ` +
          `above the ${String(maxCompressedBytes)}-byte budget`,
      ),
    );
  }

  if (input.files !== undefined) {
    const validation = validateBundle({
      manifestText: serializeManifest(manifest),
      files: input.files,
      ...(input.extraFiles === undefined ? {} : { extraFiles: input.extraFiles }),
    });

    for (const entry of validation.errors) {
      if (entry.code === "placeholder") {
        failures.push(issue("placeholder", entry.message, entry.dataset));
      } else {
        failures.push(
          issue("invalid-bundle", `[${entry.code}] ${entry.message}`, entry.dataset),
        );
      }
    }
    for (const entry of validation.warnings) {
      warnings.push(
        issue("validation-warning", `[${entry.code}] ${entry.message}`, entry.dataset),
      );
    }
  }

  const localization = input.localization ?? [];
  const missingKeys = localization.reduce((sum, entry) => sum + entry.missingKeys, 0);
  if (missingKeys > maxMissingKeys) {
    const affected = localization
      .filter((entry) => entry.missingKeys > 0)
      .map((entry) => `${entry.dataset} (${String(entry.missingKeys)})`)
      .join(", ");
    failures.push(
      issue(
        "missing-keys",
        `${manifest.mode}: ${String(missingKeys)} placeholder key(s) have no translation, ` +
          `above the ${String(maxMissingKeys)} allowed: ${affected}`,
      ),
    );
  }

  let failedPaths = 0;
  let stalePointers = 0;

  for (const entry of localization) {
    failedPaths += entry.failedPaths.length;
    if (entry.failedPaths.length > 0) {
      const sample = entry.failedPaths
        .slice(0, 3)
        .map((failure) => `${failure.path} (${failure.error})`)
        .join("; ");
      failures.push(
        issue(
          "failed-path",
          `${entry.dataset}: ${String(entry.failedPaths.length)} translation pointer(s) ` +
            `could not be parsed: ${sample}`,
          entry.dataset,
        ),
      );
    }

    stalePointers += entry.stalePointers.length;
    if (entry.stalePointers.length > 0) {
      const sample = entry.stalePointers.slice(0, 3).join(", ");
      warnings.push(
        issue(
          "stale-pointer",
          `${entry.dataset}: ${String(entry.stalePointers.length)} stale translation ` +
            `pointer(s): ${sample}`,
          entry.dataset,
        ),
      );
    }
  }

  for (const skipped of manifest.skipped) {
    warnings.push(
      issue(
        "skipped-dataset",
        `${skipped.dataset}: skipped (${skipped.reason}); no file is published for it`,
        skipped.dataset,
      ),
    );
  }

  const prunable = pruneCandidates(manifest, input.files);
  for (const name of prunable) {
    warnings.push(
      issue(
        "prune-candidate",
        `"${name}" is not referenced by the manifest; it would be deleted by --prune`,
      ),
    );
  }

  return {
    ok: failures.length === 0,
    failures,
    warnings,
    metrics: {
      mode: manifest.mode,
      datasets: manifest.datasets.length,
      compressedBytes,
      maxCompressedBytes,
      missingKeys,
      maxMissingKeys,
      failedPaths,
      stalePointers,
      skippedDatasets: manifest.skipped.length,
      pruneCandidates: prunable.length,
    },
  };
}
