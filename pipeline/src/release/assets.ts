import {
  MANIFEST_FILE,
  manifestSchema,
  serializeManifest,
  type BundleManifest,
  type BundleMode,
  type ManifestDatasetEntry,
} from "../bundle/index.js";
import { ReleaseError } from "./errors.js";

/**
 * Publication layout helpers.
 *
 * GitHub release assets are flat: an asset name cannot contain `/`. The bundle
 * directories written by task 2.6 therefore cannot be uploaded as-is. Each
 * release holds:
 *
 *   manifest.json
 *   <dataset>-<sha12>.jsonl.zst    (one per dataset, content-addressed)
 *
 * The manifest's dataset `path` is rewritten to the versioned asset name before
 * upload, so a client resolves it relative to the stable manifest URL:
 *
 *   https://github.com/<owner>/<repo>/releases/download/data-<mode>-latest/manifest.json
 *   https://github.com/<owner>/<repo>/releases/download/data-<mode>-latest/<dataset>-<sha12>.jsonl.zst
 */

export const DATASET_ASSET_SUFFIX = ".jsonl.zst";

/** The part of a dataset entry needed to derive its immutable asset name. */
export type AssetDataset = Pick<ManifestDatasetEntry, "dataset" | "sha256">;

/** First 12 hex characters of the dataset SHA-256. */
export function checksumPrefix(sha256: string): string {
  return sha256.slice(0, 12);
}

/** `<dataset>-<sha12>.jsonl.zst`, the immutable asset name for one dataset. */
export function datasetAssetName(entry: AssetDataset): string {
  return `${entry.dataset}-${checksumPrefix(entry.sha256)}${DATASET_ASSET_SUFFIX}`;
}

/** True for any release asset that claims to hold a dataset payload. */
export function isDatasetAsset(name: string): boolean {
  return name.endsWith(DATASET_ASSET_SUFFIX);
}

export function defaultTag(mode: BundleMode): string {
  return `data-${mode}-latest`;
}

const TAG_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;
const STABLE_TAG_PATTERN = /^data-(regular|pve|pvp-season)-latest$/;

/**
 * Reject a tag GitHub cannot store or that would be ambiguous in shell output.
 *
 * The stable tags are `data-<mode>-latest`; a custom tag (for example the
 * manual test's `data-test-regular-latest`) is allowed as long as it is a plain
 * ref name. A tag that *is* another mode's stable tag is refused separately, so
 * a mistyped `--tag` cannot overwrite the pointer for the wrong mode.
 */
export function validateTag(tag: string): string {
  if (tag.length === 0 || tag.length > 100) {
    throw new ReleaseError("invalid-tag", "tag must be between 1 and 100 characters");
  }
  if (!TAG_PATTERN.test(tag) || tag.includes("..") || tag.endsWith(".lock")) {
    throw new ReleaseError(
      "invalid-tag",
      `invalid tag "${tag}": use letters, digits, ".", "_" and "-", starting with a letter or digit`,
    );
  }
  return tag;
}

/** Refuse publishing a mode onto another mode's stable tag. */
export function assertTagMatchesMode(tag: string, mode: BundleMode): void {
  const match = STABLE_TAG_PATTERN.exec(tag);
  if (match !== null && match[1] !== mode) {
    throw new ReleaseError(
      "tag-mismatch",
      `tag "${tag}" belongs to mode "${match[1]}", not "${mode}"`,
    );
  }
}

export function validateMode(value: string): BundleMode {
  if (value !== "regular" && value !== "pve" && value !== "pvp-season") {
    throw new ReleaseError(
      "invalid-mode",
      `unknown mode "${value}"; expected regular, pve or pvp-season`,
    );
  }
  return value;
}

export const DEFAULT_REPOSITORY = "Tayuha/tarkov-companion";

/** `owner/repo` used to build the stable URL; CI sets `GITHUB_REPOSITORY`. */
export function resolveRepository(env: NodeJS.ProcessEnv = process.env): string {
  const value = env["GITHUB_REPOSITORY"];
  if (value !== undefined && /^[^/\s]+\/[^/\s]+$/.test(value)) return value;
  return DEFAULT_REPOSITORY;
}

/** The single stable pointer a client reads for one mode. */
export function stableManifestUrl(tag: string, repository: string = DEFAULT_REPOSITORY): string {
  return `https://github.com/${repository}/releases/download/${tag}/${MANIFEST_FILE}`;
}

export function releaseTitle(mode: BundleMode): string {
  return `Tarkov Companion data — ${mode}`;
}

export function releaseNotes(input: {
  readonly mode: BundleMode;
  readonly manifestUrl: string;
  readonly generatedAt: string;
}): string {
  return [
    `Rolling data release for game mode \`${input.mode}\`.`,
    "",
    `Stable manifest: ${input.manifestUrl}`,
    `Built at ${input.generatedAt}.`,
    "",
    "Dataset assets are content-addressed and immutable. `manifest.json` is",
    "replaced last; do not edit release assets by hand.",
  ].join("\n");
}

export interface PreparedManifest {
  /** The manifest with every dataset `path` rewritten to its asset name. */
  readonly manifest: BundleManifest;
  readonly json: string;
  readonly bytes: Uint8Array;
}

/**
 * Rewrite dataset paths to the flat, versioned asset names.
 *
 * Everything else (checksums, sizes, record counts, source metadata, totals)
 * is preserved, so the uploaded document is still the same manifest contract a
 * local bundle has; only the resolution target moves from a file next to the
 * manifest to a sibling asset in the same release.
 */
export function preparePublishedManifest(manifest: BundleManifest): PreparedManifest {
  const rewritten = manifestSchema.parse({
    ...manifest,
    datasets: manifest.datasets.map((entry) => ({
      ...entry,
      path: datasetAssetName(entry),
    })),
  });
  const json = serializeManifest(rewritten);
  return { manifest: rewritten, json, bytes: new Uint8Array(Buffer.from(json, "utf8")) };
}

/** Reject an asset name that GitHub would flatten or that escapes the release. */
export function assertAssetName(name: string): void {
  if (
    name.length === 0 ||
    name.length > 255 ||
    name === "." ||
    name === ".." ||
    name.includes("/") ||
    name.includes("\\")
  ) {
    throw new ReleaseError(
      "invalid-asset-name",
      `invalid release asset name "${name}": assets are flat file names`,
    );
  }
}

/** Refuse a manifest path that is not a plain file in the mode directory. */
export function isFlatFileName(name: string): boolean {
  return (
    name.length > 0 && name !== "." && name !== ".." && !name.includes("/") && !name.includes("\\")
  );
}
