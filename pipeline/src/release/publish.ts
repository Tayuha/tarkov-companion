import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";
import {
  MANIFEST_FILE,
  ManifestError,
  parseManifest,
  readManifestFile,
  type BundleManifest,
  type BundleMode,
} from "../bundle/index.js";
import {
  assertTagMatchesMode,
  defaultTag,
  isFlatFileName,
  preparePublishedManifest,
  releaseNotes,
  releaseTitle,
  resolveRepository,
  stableManifestUrl,
  validateMode,
  validateTag,
} from "./assets.js";
import type { ReleaseClient } from "./client.js";
import { ReleaseError } from "./errors.js";
import { GhReleaseClient } from "./gh-client.js";
import { planPublication, type PublicationPlan } from "./plan.js";

/**
 * Publish one mode's bundle to its rolling GitHub release.
 *
 * Steps, in order:
 *
 *   1. read and validate the local manifest, and verify every dataset file's
 *      size and SHA-256 against it;
 *   2. read the release and its published manifest (missing means publish all);
 *   3. plan dataset uploads, the manifest swap and prune candidates;
 *   4. in dry-run, stop here with zero mutations;
 *   5. create the release if needed, upload immutable dataset assets, replace
 *      `manifest.json` last, then (only with `prune`) delete unreferenced
 *      dataset assets.
 *
 * A re-publication of unchanged content performs no create/upload/delete calls
 * and returns `mutations: 0`.
 */

export interface PublishBundleOptions {
  /** Bundles root, e.g. `dist/bundles`. The mode directory is read inside it. */
  readonly bundlesDir: string;
  readonly mode: BundleMode;
  /** Defaults to `data-<mode>-latest`. */
  readonly tag?: string;
  /** Plan only: read the release, make no mutation. */
  readonly dryRun?: boolean;
  /** Delete dataset assets the new manifest does not reference, after the swap. */
  readonly prune?: boolean;
  /** Injected client for tests; defaults to `GhReleaseClient`. */
  readonly client?: ReleaseClient;
  /** `owner/repo` for the stable URL; defaults to `GITHUB_REPOSITORY` or the project repo. */
  readonly repository?: string;
}

export interface PublicationResult {
  readonly plan: PublicationPlan;
  readonly mode: BundleMode;
  readonly tag: string;
  readonly repository: string;
  readonly manifestUrl: string;
  readonly dryRun: boolean;
  readonly release: {
    readonly existed: boolean;
    readonly created: boolean;
  };
  readonly uploaded: readonly string[];
  readonly deleted: readonly string[];
  /** Create + upload + delete calls performed; always 0 in dry-run. */
  readonly mutations: number;
}

function sha256Hex(bytes: Uint8Array): string {
  return createHash("sha256").update(bytes).digest("hex");
}

async function verifyLocalBundle(modeDir: string, manifest: BundleManifest): Promise<void> {
  for (const entry of manifest.datasets) {
    if (!isFlatFileName(entry.path) || isAbsolute(entry.path)) {
      throw new ReleaseError(
        "dataset-missing",
        `manifest path "${entry.path}" is not a file name in ${modeDir}`,
      );
    }

    const path = join(modeDir, entry.path);
    let bytes: Buffer;
    try {
      bytes = await readFile(path);
    } catch (error) {
      throw new ReleaseError(
        "dataset-missing",
        `dataset "${entry.dataset}" is missing at ${path}: ` +
          (error instanceof Error ? error.message : String(error)),
      );
    }

    if (bytes.byteLength !== entry.compressedBytes || sha256Hex(bytes) !== entry.sha256) {
      throw new ReleaseError(
        "dataset-mismatch",
        `dataset "${entry.dataset}" at ${path} does not match the manifest ` +
          `(expected ${String(entry.compressedBytes)} bytes, sha256 ${entry.sha256.slice(0, 12)})`,
      );
    }
  }
}

function parseRemoteManifest(bytes: Uint8Array, tag: string, mode: BundleMode): BundleManifest {
  let json: unknown;
  try {
    json = JSON.parse(Buffer.from(bytes).toString("utf8")) as unknown;
  } catch (error) {
    throw new ReleaseError(
      "remote-manifest-invalid",
      `manifest.json on release "${tag}" is not valid JSON: ` +
        (error instanceof Error ? error.message : String(error)),
    );
  }

  let manifest: BundleManifest;
  try {
    manifest = parseManifest(json, `manifest.json on release "${tag}"`);
  } catch (error) {
    if (error instanceof ManifestError) {
      throw new ReleaseError("remote-manifest-invalid", error.message);
    }
    throw error;
  }

  if (manifest.mode !== mode) {
    throw new ReleaseError(
      "remote-manifest-invalid",
      `manifest.json on release "${tag}" is for mode "${manifest.mode}", not "${mode}"`,
    );
  }
  return manifest;
}

export async function publishBundle(options: PublishBundleOptions): Promise<PublicationResult> {
  const mode = validateMode(options.mode);
  const tag = validateTag(options.tag ?? defaultTag(mode));
  assertTagMatchesMode(tag, mode);

  const dryRun = options.dryRun ?? false;
  const prune = options.prune ?? false;
  const repository = options.repository ?? resolveRepository();
  const manifestUrl = stableManifestUrl(tag, repository);
  const modeDir = join(options.bundlesDir, mode);
  const localManifest = await readManifestFile(join(modeDir, MANIFEST_FILE));

  if (localManifest.mode !== mode) {
    throw new ReleaseError(
      "manifest-mismatch",
      `local manifest ${join(modeDir, MANIFEST_FILE)} is for mode "${localManifest.mode}", not "${mode}"`,
    );
  }
  if (localManifest.datasets.length === 0) {
    throw new ReleaseError(
      "empty-manifest",
      `local manifest for mode "${mode}" has no datasets; refusing to publish an empty bundle`,
    );
  }

  await verifyLocalBundle(modeDir, localManifest);
  const prepared = preparePublishedManifest(localManifest);

  let client = options.client;
  if (client === undefined) {
    const gh = new GhReleaseClient();
    await gh.ready();
    client = gh;
  }

  const release = await client.getRelease(tag);
  const remoteBytes =
    release === null ? null : await client.downloadAsset({ tag, name: MANIFEST_FILE });
  const remoteManifest =
    remoteBytes === null ? null : parseRemoteManifest(remoteBytes, tag, mode);

  const plan = planPublication(localManifest, remoteManifest, release?.assets ?? [], { prune });

  const existed = release !== null;
  const base = {
    plan,
    mode,
    tag,
    repository,
    manifestUrl,
    dryRun,
    release: { existed, created: false },
    uploaded: [] as string[],
    deleted: [] as string[],
    mutations: 0,
  };

  if (dryRun) return base;

  if (release === null) {
    await client.createRelease({
      tag,
      title: releaseTitle(mode),
      notes: releaseNotes({ mode, manifestUrl, generatedAt: localManifest.generatedAt }),
    });
  }

  const uploaded: string[] = [];
  const deleted: string[] = [];
  let stagingDir: string | undefined;

  try {
    for (const step of plan.uploads) {
      if (step.kind === "dataset") {
        await client.uploadAsset({
          tag,
          name: step.name,
          filePath: join(modeDir, step.sourcePath),
        });
      } else {
        stagingDir ??= await mkdtemp(join(tmpdir(), "tarkov-publish-"));
        const manifestPath = join(stagingDir, MANIFEST_FILE);
        await writeFile(manifestPath, prepared.bytes);
        await client.uploadAsset({ tag, name: MANIFEST_FILE, filePath: manifestPath });
      }
      uploaded.push(step.name);
    }

    // Pruning is opt-in and always happens after the manifest swap. The
    // manifest itself is never a prune candidate (it is not a dataset asset).
    if (prune) {
      for (const name of plan.prune) {
        await client.deleteAsset({ tag, name });
        deleted.push(name);
      }
    }
  } finally {
    if (stagingDir !== undefined) {
      await rm(stagingDir, { recursive: true, force: true });
    }
  }

  return {
    ...base,
    release: { existed, created: release === null },
    uploaded,
    deleted,
    mutations: (release === null ? 1 : 0) + uploaded.length + deleted.length,
  };
}
