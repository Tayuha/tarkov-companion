/**
 * The narrow GitHub Releases surface the publisher needs.
 *
 * The interface is deliberately smaller than the GitHub API: the uploader only
 * ever reads a release, creates one, uploads immutable dataset assets, swaps
 * `manifest.json`, and (with `--prune`) deletes unreferenced dataset assets.
 * `GhReleaseClient` implements it with the `gh` CLI; `MemoryReleaseClient`
 * implements it in tests without network or subprocesses.
 */

export interface ReleaseAsset {
  /** GitHub asset id, needed to download the bytes. */
  readonly id: number;
  readonly name: string;
  readonly size: number;
}

export interface ReleaseInfo {
  readonly tag: string;
  readonly title: string;
  readonly url: string;
  readonly assets: readonly ReleaseAsset[];
}

export interface CreateReleaseInput {
  readonly tag: string;
  readonly title: string;
  readonly notes: string;
}

export interface AssetRef {
  readonly tag: string;
  readonly name: string;
}

export interface UploadAssetInput extends AssetRef {
  /** Local file whose bytes are uploaded as `name`. */
  readonly filePath: string;
}

export interface ReleaseClient {
  /** The release for `tag`, or `null` when it does not exist yet. */
  getRelease(tag: string): Promise<ReleaseInfo | null>;
  createRelease(input: CreateReleaseInput): Promise<ReleaseInfo>;
  uploadAsset(input: UploadAssetInput): Promise<void>;
  deleteAsset(input: AssetRef): Promise<void>;
  /**
   * Bytes of one asset, or `null` when it is absent. Used for the published
   * `manifest.json`; dataset bytes are never downloaded by the pipeline.
   */
  downloadAsset(input: AssetRef): Promise<Uint8Array | null>;
}
