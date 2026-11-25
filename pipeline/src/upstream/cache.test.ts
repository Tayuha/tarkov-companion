import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it } from "vitest";
import {
  FileDatasetCacheStore,
  MemoryDatasetCacheStore,
  type DatasetCacheEntry,
} from "./cache.js";

const KEY = { mode: "regular", dataset: "items", lang: "en" } as const;

function makeEntry(overrides: Partial<DatasetCacheEntry> = {}): DatasetCacheEntry {
  return {
    mode: "regular",
    dataset: "items",
    lang: "en",
    etag: 'W/"abc"',
    lastModified: "Wed, 25 Nov 2026 10:00:00 GMT",
    dictionaryEtag: '"dict"',
    dictionaryLastModified: "Wed, 25 Nov 2026 10:00:00 GMT",
    checksum: "b".repeat(64),
    fetchedAt: "2026-11-25T12:00:00.000Z",
    byteSize: 2048,
    ...overrides,
  };
}

const tempDirs: string[] = [];

async function tempDir(): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "tarkov-cache-"));
  tempDirs.push(dir);
  return dir;
}

afterEach(async () => {
  await Promise.all(tempDirs.splice(0).map((dir) => rm(dir, { recursive: true, force: true })));
});

describe("MemoryDatasetCacheStore", () => {
  it("round-trips an entry and misses unknown keys", async () => {
    const store = new MemoryDatasetCacheStore();
    const entry = makeEntry();

    expect(await store.get(KEY)).toBeUndefined();
    await store.set(entry);
    expect(await store.get(KEY)).toEqual(entry);
    expect(await store.get({ mode: "pve", dataset: "items", lang: "en" })).toBeUndefined();
  });
});

describe("FileDatasetCacheStore", () => {
  it("writes one JSON file per dataset under the configured directory", async () => {
    const dir = await tempDir();
    const store = new FileDatasetCacheStore({ dir });
    const entry = makeEntry();

    await store.set(entry);

    expect(store.pathFor(KEY)).toBe(join(dir, "regular__items__en.json"));
    expect(await new FileDatasetCacheStore({ dir }).get(KEY)).toEqual(entry);
  });

  it("separates languages and game modes", async () => {
    const store = new FileDatasetCacheStore({ dir: await tempDir() });
    await store.set(makeEntry({ checksum: "1".repeat(64) }));
    await store.set(makeEntry({ mode: "pve", checksum: "2".repeat(64) }));
    await store.set(makeEntry({ lang: "de", checksum: "3".repeat(64) }));

    expect((await store.get(KEY))?.checksum).toBe("1".repeat(64));
    expect((await store.get({ ...KEY, mode: "pve" }))?.checksum).toBe("2".repeat(64));
    expect((await store.get({ ...KEY, lang: "de" }))?.checksum).toBe("3".repeat(64));
  });

  it("treats a missing or malformed file as a cache miss", async () => {
    const dir = await tempDir();
    const store = new FileDatasetCacheStore({ dir });

    expect(await store.get(KEY)).toBeUndefined();

    await writeFile(store.pathFor(KEY), "{not json", "utf8");
    expect(await store.get(KEY)).toBeUndefined();

    await writeFile(store.pathFor(KEY), JSON.stringify({ mode: "regular" }), "utf8");
    expect(await store.get(KEY)).toBeUndefined();
  });

  it("keeps cache filenames path-traversal free", async () => {
    const dir = await tempDir();
    const store = new FileDatasetCacheStore({ dir });

    const path = store.pathFor({ mode: "regular", dataset: "../../etc/passwd", lang: "en" });

    expect(path.startsWith(dir)).toBe(true);
    expect(path).not.toContain("..");
  });
});
