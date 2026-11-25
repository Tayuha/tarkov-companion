import { readFile, stat } from "node:fs/promises";
import { join } from "node:path";
import type { z } from "zod";
import {
  MANIFEST_FILE,
  manifestSchema,
  type BundleManifest,
  type BundleMode,
} from "./manifest.js";

/**
 * Bundle comparison and no-op gating.
 *
 * A build only publishes when the content a client would download actually
 * differs from what it already has. `compareBundles` is pure: it looks at the
 * dataset set and each dataset's content checksum, never at wall-clock or
 * upstream-validator metadata, so two runs over identical upstream content
 * produce `hasChanges: false` even though their manifests differ in
 * `generatedAt` (and possibly in `source.fetchedAt`, `etag` or
 * `lastModified`).
 *
 * The client contract versions (`bundleSchemaVersion`, `minAppSchemaVersion`)
 * are the exception: a difference there means the app must reconsider every
 * dataset even when no checksum moved, so every dataset present in both
 * manifests is classified as changed with a reason naming the version bump.
 */

export type ManifestErrorKind =
  | "not-found"
  | "unreadable"
  | "invalid-json"
  | "invalid-schema"
  | "mode-mismatch";

/**
 * Typed failure for an unusable manifest. `source` is a file path when the
 * manifest came from disk, or a label such as `previous manifest` when the
 * value was passed in memory.
 */
export class ManifestError extends Error {
  readonly kind: ManifestErrorKind;
  readonly source: string;

  constructor(kind: ManifestErrorKind, source: string, message: string) {
    super(message);
    this.name = "ManifestError";
    this.kind = kind;
    this.source = source;
  }
}

/** Comparison outcome for one pair of manifests of the same mode. */
export interface BundleComparison {
  /** True when at least one dataset is added, changed or removed. */
  readonly hasChanges: boolean;
  readonly added: readonly string[];
  readonly changed: readonly string[];
  readonly unchanged: readonly string[];
  readonly removed: readonly string[];
  /** One human-readable explanation per dataset in the union of both sides. */
  readonly reasons: Readonly<Record<string, string>>;
}

function formatManifestIssues(error: z.ZodError): string {
  return error.issues
    .map((issue) => `${issue.path.map(String).join(".") || "<root>"}: ${issue.message}`)
    .join("; ");
}

/**
 * Validate an already-parsed manifest document with the shared Zod schema.
 * `source` names the input in the error message (`previous manifest`, a path).
 */
export function parseManifest(value: unknown, source: string): BundleManifest {
  const parsed = manifestSchema.safeParse(value);
  if (!parsed.success) {
    throw new ManifestError(
      "invalid-schema",
      source,
      `${source} is not a valid bundle manifest: ${formatManifestIssues(parsed.error)}`,
    );
  }
  return parsed.data;
}

/** Read, parse, and validate one manifest file. */
export async function readManifestFile(path: string): Promise<BundleManifest> {
  let text: string;
  try {
    text = await readFile(path, "utf8");
  } catch (error) {
    const code = (error as { readonly code?: unknown }).code;
    if (code === "ENOENT") {
      throw new ManifestError("not-found", path, `manifest not found: ${path}`);
    }
    throw new ManifestError(
      "unreadable",
      path,
      `cannot read manifest ${path}: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  let json: unknown;
  try {
    json = JSON.parse(text) as unknown;
  } catch (error) {
    throw new ManifestError(
      "invalid-json",
      path,
      `manifest ${path} is not valid JSON: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  return parseManifest(json, path);
}

/**
 * Resolve a `--previous` argument to a manifest file path.
 *
 * Accepted forms:
 *
 *   - a manifest file:            `release-2026-11-25/regular/manifest.json`
 *   - a bundles root:             `release-2026-11-25` -> `<root>/<mode>/manifest.json`
 *   - a mode directory:           `release-2026-11-25/regular` -> `<dir>/manifest.json`
 *
 * Directories are resolved for `mode`; nothing is read or validated here.
 */
export async function resolveManifestPath(input: string, mode: BundleMode): Promise<string> {
  const candidates = [join(input, mode, MANIFEST_FILE), join(input, MANIFEST_FILE), input];

  for (const candidate of candidates) {
    try {
      const info = await stat(candidate);
      if (info.isFile()) return candidate;
    } catch (error) {
      const code = (error as { readonly code?: unknown }).code;
      if (code !== "ENOENT" && code !== "ENOTDIR") {
        throw new ManifestError(
          "unreadable",
          candidate,
          `cannot inspect ${candidate}: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }
  }

  throw new ManifestError(
    "not-found",
    input,
    `no manifest for mode "${mode}" at ${input} ` +
      `(looked for ${join(input, mode, MANIFEST_FILE)} and ${join(input, MANIFEST_FILE)})`,
  );
}

/** Resolve `input` for `mode`, read it, and reject a manifest of another mode. */
export async function loadPreviousManifest(
  input: string,
  mode: BundleMode,
): Promise<{ readonly path: string; readonly manifest: BundleManifest }> {
  const path = await resolveManifestPath(input, mode);
  const manifest = await readManifestFile(path);
  if (manifest.mode !== mode) {
    throw new ManifestError(
      "mode-mismatch",
      path,
      `previous manifest ${path} is for mode "${manifest.mode}", not "${mode}"`,
    );
  }
  return { path, manifest };
}

function shortChecksum(sha256: string): string {
  return sha256.slice(0, 12);
}

/**
 * Compare two manifests of the same mode.
 *
 * Classification rules:
 *
 *   - only in current  -> added
 *   - only in previous -> removed
 *   - `sha256` differs -> changed
 *   - `sha256` matches -> unchanged, unless a contract version differs, in
 *     which case every dataset present on both sides is changed.
 *
 * Ignored: `generatedAt`, `source.capturedAt`, per-dataset `source.*`
 * (`url`, `etag`, `lastModified`, `fetchedAt`), `path`, sizes, record counts
 * and totals. Those are either wall-clock values or metadata derived from
 * content the checksum already covers.
 */
export function compareBundles(
  previous: BundleManifest,
  current: BundleManifest,
): BundleComparison {
  const previousManifest = parseManifest(previous, "previous manifest");
  const currentManifest = parseManifest(current, "current manifest");

  if (previousManifest.mode !== currentManifest.mode) {
    throw new ManifestError(
      "mode-mismatch",
      "current manifest",
      `cannot compare mode "${previousManifest.mode}" with mode "${currentManifest.mode}"`,
    );
  }

  const contractChanges: string[] = [];
  if (previousManifest.bundleSchemaVersion !== currentManifest.bundleSchemaVersion) {
    contractChanges.push(
      `bundleSchemaVersion ${previousManifest.bundleSchemaVersion} -> ${currentManifest.bundleSchemaVersion}`,
    );
  }
  if (previousManifest.minAppSchemaVersion !== currentManifest.minAppSchemaVersion) {
    contractChanges.push(
      `minAppSchemaVersion ${previousManifest.minAppSchemaVersion} -> ${currentManifest.minAppSchemaVersion}`,
    );
  }
  const contractReason =
    contractChanges.length === 0 ? undefined : `client contract changed (${contractChanges.join(", ")})`;

  const previousByName = new Map(
    previousManifest.datasets.map((entry) => [entry.dataset, entry] as const),
  );
  const currentByName = new Map(
    currentManifest.datasets.map((entry) => [entry.dataset, entry] as const),
  );

  const names = [...new Set([...previousByName.keys(), ...currentByName.keys()])].sort();

  const added: string[] = [];
  const changed: string[] = [];
  const unchanged: string[] = [];
  const removed: string[] = [];
  const reasons: Record<string, string> = {};

  for (const name of names) {
    const before = previousByName.get(name);
    const after = currentByName.get(name);

    if (before === undefined) {
      added.push(name);
      reasons[name] = "not present in previous manifest";
      continue;
    }
    if (after === undefined) {
      removed.push(name);
      reasons[name] = "not present in current manifest";
      continue;
    }

    if (before.sha256 !== after.sha256) {
      changed.push(name);
      reasons[name] =
        `sha256 ${shortChecksum(before.sha256)} -> ${shortChecksum(after.sha256)}` +
        (contractReason === undefined ? "" : `; ${contractReason}`);
      continue;
    }

    if (contractReason !== undefined) {
      changed.push(name);
      reasons[name] = `sha256 unchanged; ${contractReason}`;
      continue;
    }

    unchanged.push(name);
    reasons[name] = `sha256 ${shortChecksum(after.sha256)} matches`;
  }

  return {
    hasChanges: added.length > 0 || changed.length > 0 || removed.length > 0,
    added,
    changed,
    unchanged,
    removed,
    reasons,
  };
}

/** Human-readable lines for a comparison, one per non-unchanged dataset plus a summary. */
export function describeComparison(comparison: BundleComparison): string[] {
  const lines: string[] = [];

  lines.push(
    comparison.hasChanges
      ? `changes: ${comparison.added.length} added, ${comparison.changed.length} changed, ` +
          `${comparison.unchanged.length} unchanged, ${comparison.removed.length} removed`
      : `no changes: all ${comparison.unchanged.length} dataset(s) unchanged`,
  );

  const groups: readonly [string, readonly string[]][] = [
    ["added", comparison.added],
    ["changed", comparison.changed],
    ["removed", comparison.removed],
    ["unchanged", comparison.unchanged],
  ];

  for (const [label, names] of groups) {
    for (const name of names) {
      lines.push(`  ${label.padEnd(9)} ${name.padEnd(9)} ${comparison.reasons[name] ?? ""}`.trimEnd());
    }
  }

  return lines;
}
