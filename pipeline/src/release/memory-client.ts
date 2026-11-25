import { readFile } from "node:fs/promises";
import type {
  AssetRef,
  CreateReleaseInput,
  ReleaseAsset,
  ReleaseClient,
  ReleaseInfo,
  UploadAssetInput,
} from "./client.js";
import { ReleaseError } from "./errors.js";

/**
 * In-memory `ReleaseClient` for offline tests.
 *
 * It models the parts of a GitHub release the publisher depends on: a tag
 * exists or it does not, assets are keyed by their flat name and have a byte
 * size, and uploads/deletes are recorded in call order. `mutations` counts only
 * create/upload/delete, so a dry run or an identical re-publication can assert
 * zero mutations directly.
 */

export interface MemoryReleaseAssetSeed {
  readonly name: string;
  readonly size?: number;
  readonly data?: Uint8Array;
}

export interface MemoryReleaseSeed {
  readonly tag: string;
  readonly title?: string;
  readonly assets?: readonly MemoryReleaseAssetSeed[];
}

export type MemoryOperation = "get" | "download" | "create" | "upload" | "delete";

export interface MemoryCall {
  readonly operation: MemoryOperation;
  readonly tag: string;
  readonly name?: string;
}

interface StoredAsset {
  readonly id: number;
  readonly size: number;
  readonly data: Uint8Array | null;
}

interface StoredRelease {
  readonly tag: string;
  readonly title: string;
  readonly notes: string;
  readonly assets: Map<string, StoredAsset>;
}

function copy(bytes: Uint8Array): Uint8Array {
  return new Uint8Array(bytes);
}

export class MemoryReleaseClient implements ReleaseClient {
  private readonly releases = new Map<string, StoredRelease>();
  private readonly calls: MemoryCall[] = [];
  private nextAssetId = 1;

  /** Create or replace a seeded release without counting it as a mutation. */
  seedRelease(seed: MemoryReleaseSeed): void {
    const assets = new Map<string, StoredAsset>();
    for (const asset of seed.assets ?? []) {
      const data = asset.data === undefined ? null : copy(asset.data);
      assets.set(asset.name, {
        id: this.nextAssetId++,
        size: asset.size ?? data?.byteLength ?? 0,
        data,
      });
    }
    this.releases.set(seed.tag, {
      tag: seed.tag,
      title: seed.title ?? seed.tag,
      notes: "",
      assets,
    });
  }

  /** Every API call in order; reads included. */
  get operations(): readonly MemoryCall[] {
    return this.calls;
  }

  /** Create/upload/delete calls only. */
  get mutations(): number {
    return this.calls.filter(
      (call) =>
        call.operation === "create" ||
        call.operation === "upload" ||
        call.operation === "delete",
    ).length;
  }

  get mutationCalls(): readonly MemoryCall[] {
    return this.calls.filter(
      (call) =>
        call.operation === "create" ||
        call.operation === "upload" ||
        call.operation === "delete",
    );
  }

  getRelease(tag: string): Promise<ReleaseInfo | null> {
    this.calls.push({ operation: "get", tag });
    const release = this.releases.get(tag);
    if (release === undefined) return Promise.resolve(null);
    return Promise.resolve(this.info(release));
  }

  createRelease(input: CreateReleaseInput): Promise<ReleaseInfo> {
    this.calls.push({ operation: "create", tag: input.tag });
    if (this.releases.has(input.tag)) {
      return Promise.reject(
        new ReleaseError("gh-failed", `release "${input.tag}" already exists`),
      );
    }
    const release: StoredRelease = {
      tag: input.tag,
      title: input.title,
      notes: input.notes,
      assets: new Map(),
    };
    this.releases.set(input.tag, release);
    return Promise.resolve(this.info(release));
  }

  async uploadAsset(input: UploadAssetInput): Promise<void> {
    this.calls.push({ operation: "upload", tag: input.tag, name: input.name });
    const release = this.releases.get(input.tag);
    if (release === undefined) {
      throw new ReleaseError("not-found", `release "${input.tag}" does not exist`);
    }
    const data = new Uint8Array(await readFile(input.filePath));
    const existing = release.assets.get(input.name);
    release.assets.set(input.name, {
      id: existing?.id ?? this.nextAssetId++,
      size: data.byteLength,
      data,
    });
  }

  deleteAsset(input: AssetRef): Promise<void> {
    this.calls.push({ operation: "delete", tag: input.tag, name: input.name });
    const release = this.releases.get(input.tag);
    if (release === undefined || !release.assets.has(input.name)) {
      return Promise.reject(
        new ReleaseError(
          "not-found",
          `asset "${input.name}" does not exist on "${input.tag}"`,
        ),
      );
    }
    release.assets.delete(input.name);
    return Promise.resolve();
  }

  downloadAsset(input: AssetRef): Promise<Uint8Array | null> {
    this.calls.push({ operation: "download", tag: input.tag, name: input.name });
    const asset = this.releases.get(input.tag)?.assets.get(input.name);
    if (asset === undefined || asset.data === null) return Promise.resolve(null);
    return Promise.resolve(copy(asset.data));
  }

  private info(release: StoredRelease): ReleaseInfo {
    const assets: ReleaseAsset[] = [...release.assets.entries()]
      .map(([name, asset]) => ({ id: asset.id, name, size: asset.size }))
      .sort((left, right) => left.name.localeCompare(right.name));
    return {
      tag: release.tag,
      title: release.title,
      url: `https://example.invalid/releases/tag/${release.tag}`,
      assets,
    };
  }
}
