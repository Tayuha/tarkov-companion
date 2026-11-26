import { describe, expect, it, vi } from "vitest";
import { MemoryDatasetCacheStore, type DatasetCacheEntry } from "./cache.js";
import {
  fetchDataset,
  UpstreamError,
  type FetchDatasetResult,
  type ModifiedDatasetResult,
} from "./fetch.js";

const BASE = "https://example.test";
const PRAPOR = "54cb50c76803fa8b248b4571";
const LAST_MODIFIED = "Wed, 25 Nov 2026 10:00:00 GMT";

interface RecordedRequest {
  readonly url: string;
  readonly headers: Headers;
}

/** 304 response that records accidental body reads. */
class NotModifiedResponse extends Response {
  bodyReads = 0;

  constructor() {
    super(null, { status: 304 });
  }

  override text = (): Promise<string> => {
    this.bodyReads += 1;
    return Promise.resolve("");
  };
}

type Handler = (
  url: string,
  headers: Headers,
  attempt: number,
) => Response | Promise<Response>;

function mockFetch(handler: Handler): {
  calls: RecordedRequest[];
  fetchImpl: typeof fetch;
} {
  const calls: RecordedRequest[] = [];
  const fn = vi.fn(
    async (input: Parameters<typeof fetch>[0], init?: Parameters<typeof fetch>[1]) => {
      const url = input instanceof URL ? input.href : typeof input === "string" ? input : input.url;
      const headers = new Headers(init?.headers);
      calls.push({ url, headers });
      return handler(url, headers, calls.length - 1);
    },
  );
  return { calls, fetchImpl: fn };
}

function jsonResponse(
  body: unknown,
  init: { status?: number; headers?: Record<string, string> } = {},
): Response {
  return new Response(JSON.stringify(body), {
    status: init.status ?? 200,
    headers: { "content-type": "application/json", ...init.headers },
  });
}

function basePayload(): unknown {
  return {
    data: {
      [PRAPOR]: {
        id: PRAPOR,
        name: `${PRAPOR} Nickname`,
        description: `${PRAPOR} Description`,
      },
    },
    translations: ["$.data.*.name", "$.data.*.description"],
  };
}

/** Same content as `basePayload` with every object's keys in a different order. */
function reorderedPayload(): unknown {
  return {
    translations: ["$.data.*.name", "$.data.*.description"],
    data: {
      [PRAPOR]: {
        description: `${PRAPOR} Description`,
        name: `${PRAPOR} Nickname`,
        id: PRAPOR,
      },
    },
  };
}

function dictionary(): unknown {
  return {
    data: {
      [`${PRAPOR} Nickname`]: "Prapor",
      [`${PRAPOR} Description`]: "Warrant officer.",
    },
  };
}

function makeEntry(overrides: Partial<DatasetCacheEntry> = {}): DatasetCacheEntry {
  const entry: DatasetCacheEntry = {
    mode: "regular",
    dataset: "traders",
    lang: "en",
    etag: '"etag-v1"',
    lastModified: LAST_MODIFIED,
    dictionaryEtag: '"dict-v1"',
    dictionaryLastModified: LAST_MODIFIED,
    checksum: "0".repeat(64),
    fetchedAt: "2026-11-25T10:00:00.000Z",
    byteSize: 1234,
    ...overrides,
  };
  return entry;
}

function modifiedOf(result: FetchDatasetResult): ModifiedDatasetResult {
  if (result.status !== "modified") {
    throw new Error(`expected a modified result, got ${result.status}`);
  }
  return result;
}

async function seed(
  store: MemoryDatasetCacheStore,
  overrides: Partial<DatasetCacheEntry> = {},
): Promise<DatasetCacheEntry> {
  const entry = makeEntry(overrides);
  await store.set(entry);
  return entry;
}

describe("fetchDataset", () => {
  it("fetches the dataset and its locale dictionary, then localizes", async () => {
    const { calls, fetchImpl } = mockFetch((url) =>
      jsonResponse(url.endsWith("_en") ? dictionary() : basePayload()),
    );

    const result = modifiedOf(
      await fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl }),
    );

    expect(calls.map((call) => call.url)).toEqual([
      `${BASE}/regular/traders`,
      `${BASE}/regular/traders_en`,
    ]);
    expect((result.data as Record<string, { name: string }>)[PRAPOR]?.name).toBe("Prapor");
    expect(result.stats.translated).toBe(2);
    expect(result.stats.missingKeys).toEqual([]);
    expect(result.sources.dictionary).toBe(`${BASE}/regular/traders_en`);
    expect(result.warnings).toEqual([]);
  });

  it("resolves dictionary keys outside the declared pointers when opted in", async () => {
    const payload = {
      data: {
        [PRAPOR]: {
          id: PRAPOR,
          name: `${PRAPOR} Nickname`,
          // No pointer selects this field, but the dictionary has its key.
          effects: [`${PRAPOR} Description`],
        },
      },
      translations: ["$.data.*.name"],
    };
    const { fetchImpl } = mockFetch((url) =>
      jsonResponse(url.endsWith("_en") ? dictionary() : payload),
    );

    const result = modifiedOf(
      await fetchDataset({
        mode: "regular",
        dataset: "traders",
        baseUrl: BASE,
        fetchImpl,
        resolveUncoveredPlaceholders: true,
      }),
    );

    expect(
      (result.data as Record<string, { effects: string[] }>)[PRAPOR]?.effects,
    ).toEqual(["Warrant officer."]);
    expect(result.stats.resolvedOutsidePointers).toBe(1);
  });

  it("exposes the unresolved payload, dictionary and pointers for fixture capture", async () => {
    const { fetchImpl } = mockFetch((url) =>
      jsonResponse(url.endsWith("_en") ? dictionary() : basePayload()),
    );

    const result = modifiedOf(
      await fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl }),
    );

    expect((result.rawData as Record<string, { name: string }>)[PRAPOR]?.name).toBe(
      `${PRAPOR} Nickname`,
    );
    expect(result.dictionary[`${PRAPOR} Nickname`]).toBe("Prapor");
    expect(result.translations).toEqual(["$.data.*.name", "$.data.*.description"]);
  });

  it("retries a 429 response before succeeding", async () => {
    let attempts = 0;
    const { fetchImpl } = mockFetch((url) => {
      if (url.endsWith("_en")) return jsonResponse(dictionary());
      attempts += 1;
      if (attempts === 1) return jsonResponse({ error: "slow down" }, { status: 429 });
      return jsonResponse(basePayload());
    });

    const result = modifiedOf(
      await fetchDataset({
        mode: "regular",
        dataset: "traders",
        baseUrl: BASE,
        fetchImpl,
        retryDelayMs: 0,
      }),
    );

    expect(attempts).toBe(2);
    expect(result.stats.translated).toBe(2);
  });

  it("retries a 500 response and then throws a typed UpstreamError", async () => {
    let attempts = 0;
    const { fetchImpl } = mockFetch(() => {
      attempts += 1;
      return jsonResponse({ error: "boom" }, { status: 500 });
    });

    const error = await fetchDataset({
      mode: "regular",
      dataset: "traders",
      baseUrl: BASE,
      fetchImpl,
      retries: 2,
      retryDelayMs: 0,
    }).catch((caught: unknown) => caught);

    expect(error).toBeInstanceOf(UpstreamError);
    expect(error).toMatchObject({ status: 500 });
    expect(attempts).toBe(3);
  });

  it("fails on a non-retryable dataset error", async () => {
    const { fetchImpl } = mockFetch(() => jsonResponse({ error: "not found" }, { status: 404 }));

    await expect(
      fetchDataset({
        mode: "regular",
        dataset: "nope",
        baseUrl: BASE,
        fetchImpl,
        retryDelayMs: 0,
      }),
    ).rejects.toBeInstanceOf(UpstreamError);
  });

  it("fails when the dictionary is missing by default", async () => {
    const { fetchImpl } = mockFetch((url) =>
      url.endsWith("_en")
        ? jsonResponse({ error: "missing" }, { status: 404 })
        : jsonResponse(basePayload()),
    );

    await expect(
      fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl }),
    ).rejects.toThrow(/traders_en.*404/);
  });

  it("keeps placeholders and warns when a missing dictionary is allowed", async () => {
    const { fetchImpl } = mockFetch((url) =>
      url.endsWith("_en")
        ? jsonResponse({ error: "missing" }, { status: 404 })
        : jsonResponse(basePayload()),
    );

    const result = modifiedOf(
      await fetchDataset({
        mode: "regular",
        dataset: "traders",
        baseUrl: BASE,
        fetchImpl,
        allowMissingDictionary: true,
      }),
    );

    expect((result.data as Record<string, { name: string }>)[PRAPOR]?.name).toBe(
      `${PRAPOR} Nickname`,
    );
    expect(result.stats.missingKeys).toHaveLength(2);
    expect(result.warnings[0]).toMatch(/Locale dictionary/);
  });

  it("accepts a flat dictionary without a data wrapper", async () => {
    const { fetchImpl } = mockFetch((url) =>
      url.endsWith("_en")
        ? jsonResponse({
            [`${PRAPOR} Nickname`]: "Prapor",
            [`${PRAPOR} Description`]: "Warrant officer.",
          })
        : jsonResponse(basePayload()),
    );

    const result = modifiedOf(
      await fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl }),
    );

    expect(result.stats.translated).toBe(2);
  });

  it("rejects invalid JSON", async () => {
    const { fetchImpl } = mockFetch(
      () =>
        new Response("<html>not json</html>", {
          status: 200,
          headers: { "content-type": "text/html" },
        }),
    );

    await expect(
      fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl, retries: 0 }),
    ).rejects.toThrow(/invalid JSON/);
  });

  it("makes a single request when there are no translations", async () => {
    const { calls, fetchImpl } = mockFetch(() =>
      jsonResponse({ data: { ok: true }, translations: [] }),
    );

    const result = modifiedOf(
      await fetchDataset({ mode: "regular", dataset: "status", baseUrl: BASE, fetchImpl }),
    );

    expect(calls).toHaveLength(1);
    expect(result.sources.dictionary).toBeNull();
  });

  it("respects the game mode in both URLs", async () => {
    const { calls, fetchImpl } = mockFetch(() =>
      jsonResponse({ data: {}, translations: ["$.data.*.name"] }),
    );

    await fetchDataset({ mode: "pve", dataset: "traders", baseUrl: BASE, fetchImpl });

    expect(calls.map((call) => call.url)).toEqual([
      `${BASE}/pve/traders`,
      `${BASE}/pve/traders_en`,
    ]);
  });

  describe("checksum cache", () => {
    it("reports changed on a new checksum and stores validators", async () => {
      const store = new MemoryDatasetCacheStore();
      const { fetchImpl } = mockFetch((url) =>
        jsonResponse(url.endsWith("_en") ? dictionary() : basePayload(), {
          headers: url.endsWith("_en")
            ? { etag: '"dict-v2"', "last-modified": LAST_MODIFIED }
            : { etag: '"data-v2"', "last-modified": LAST_MODIFIED },
        }),
      );

      const result = modifiedOf(
        await fetchDataset({
          mode: "regular",
          dataset: "traders",
          baseUrl: BASE,
          fetchImpl,
          cache: store,
          now: () => new Date("2026-11-25T12:00:00.000Z"),
        }),
      );

      expect(result.changed).toBe(true);
      expect(result.cache).toMatchObject({
        mode: "regular",
        dataset: "traders",
        lang: "en",
        etag: '"data-v2"',
        lastModified: LAST_MODIFIED,
        dictionaryEtag: '"dict-v2"',
        dictionaryLastModified: LAST_MODIFIED,
        fetchedAt: "2026-11-25T12:00:00.000Z",
      });
      expect(result.cache.checksum).toMatch(/^[0-9a-f]{64}$/);
      expect(result.cache.byteSize).toBeGreaterThan(0);

      expect(await store.get({ mode: "regular", dataset: "traders", lang: "en" })).toEqual(
        result.cache,
      );
    });

    it("reports unchanged when the localized content is identical", async () => {
      const store = new MemoryDatasetCacheStore();
      const first = modifiedOf(
        await fetchDataset({
          mode: "regular",
          dataset: "traders",
          baseUrl: BASE,
          fetchImpl: mockFetch((url) =>
            jsonResponse(url.endsWith("_en") ? dictionary() : basePayload(), {
              headers: { etag: '"v1"' },
            }),
          ).fetchImpl,
          cache: store,
          now: () => new Date("2026-11-25T12:00:00.000Z"),
        }),
      );

      const second = modifiedOf(
        await fetchDataset({
          mode: "regular",
          dataset: "traders",
          baseUrl: BASE,
          fetchImpl: mockFetch((url) =>
            jsonResponse(url.endsWith("_en") ? dictionary() : reorderedPayload(), {
              headers: { etag: '"v2"' },
            }),
          ).fetchImpl,
          cache: store,
          now: () => new Date("2026-11-25T13:00:00.000Z"),
        }),
      );

      expect(second.changed).toBe(false);
      expect(second.cache.checksum).toBe(first.cache.checksum);
      expect(second.cache.fetchedAt).toBe("2026-11-25T13:00:00.000Z");
      expect(second.cache.etag).toBe('"v2"');
      expect(await store.get({ mode: "regular", dataset: "traders", lang: "en" })).toEqual(
        second.cache,
      );
    });

    it("sends stored validators for both the dataset and its dictionary", async () => {
      const store = new MemoryDatasetCacheStore();
      await seed(store, { etag: 'W/"weak"', dictionaryEtag: "W/\"weak-dict\"" });

      const { calls, fetchImpl } = mockFetch((url) =>
        jsonResponse(url.endsWith("_en") ? dictionary() : basePayload()),
      );

      await fetchDataset({
        mode: "regular",
        dataset: "traders",
        baseUrl: BASE,
        fetchImpl,
        cache: store,
      });

      expect(calls).toHaveLength(2);
      expect(calls[0]?.headers.get("if-none-match")).toBe('W/"weak"');
      expect(calls[0]?.headers.get("if-modified-since")).toBe(LAST_MODIFIED);
      expect(calls[1]?.headers.get("if-none-match")).toBe('W/"weak-dict"');
      expect(calls[1]?.headers.get("if-modified-since")).toBe(LAST_MODIFIED);
    });

    it("forwards weak and strong ETags verbatim", async () => {
      for (const etag of ['W/"a1b2"', '"a1b2"']) {
        const store = new MemoryDatasetCacheStore();
        await seed(store, { dataset: "status", etag });
        const { calls, fetchImpl } = mockFetch(() =>
          jsonResponse({ data: {}, translations: [] }),
        );

        await fetchDataset({
          mode: "regular",
          dataset: "status",
          baseUrl: BASE,
          fetchImpl,
          cache: store,
        });

        expect(calls[0]?.headers.get("if-none-match")).toBe(etag);
      }
    });

    it("returns cached metadata on 304 without reading a body or the dictionary", async () => {
      const store = new MemoryDatasetCacheStore();
      const cached = await seed(store, {
        etag: '"cached"',
        checksum: "a".repeat(64),
        fetchedAt: "2026-11-25T08:00:00.000Z",
        byteSize: 4096,
      });

      let response: NotModifiedResponse | undefined;
      const { calls, fetchImpl } = mockFetch(() => {
        response = new NotModifiedResponse();
        return response;
      });

      const result = await fetchDataset({
        mode: "regular",
        dataset: "traders",
        baseUrl: BASE,
        fetchImpl,
        cache: store,
      });

      expect(result.status).toBe("not-modified");
      expect(result.cache).toEqual(cached);
      expect(result.meta).toMatchObject({
        fetchedAt: "2026-11-25T08:00:00.000Z",
        etag: '"cached"',
        lastModified: LAST_MODIFIED,
      });
      expect(result.warnings).toEqual([]);
      expect(response?.bodyReads).toBe(0);
      expect(calls).toHaveLength(1);
      expect(calls[0]?.headers.get("if-none-match")).toBe('"cached"');
    });

    it("fails when the upstream answers 304 without cached metadata", async () => {
      const { fetchImpl } = mockFetch(() => new Response(null, { status: 304 }));

      await expect(
        fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl }),
      ).rejects.toMatchObject({ status: 304 });
    });

    it("refetches a dictionary that answers 304 because bodies are not cached", async () => {
      const store = new MemoryDatasetCacheStore();
      await seed(store, { etag: '"old"' });

      let dictionaryCalls = 0;
      const { fetchImpl } = mockFetch((url) => {
        if (!url.endsWith("_en")) return jsonResponse(basePayload(), { headers: { etag: '"new"' } });
        dictionaryCalls += 1;
        return dictionaryCalls === 1
          ? new Response(null, { status: 304 })
          : jsonResponse(dictionary());
      });

      const result = modifiedOf(
        await fetchDataset({
          mode: "regular",
          dataset: "traders",
          baseUrl: BASE,
          fetchImpl,
          cache: store,
        }),
      );

      expect(dictionaryCalls).toBe(2);
      expect(result.stats.translated).toBe(2);
      expect(result.changed).toBe(true);
    });

    it("skips conditional headers when a refresh is forced", async () => {
      const store = new MemoryDatasetCacheStore();
      await seed(store);
      const { calls, fetchImpl } = mockFetch((url) =>
        jsonResponse(url.endsWith("_en") ? dictionary() : basePayload()),
      );

      await fetchDataset({
        mode: "regular",
        dataset: "traders",
        baseUrl: BASE,
        fetchImpl,
        cache: store,
        forceRefresh: true,
      });

      expect(calls).toHaveLength(2);
      for (const call of calls) {
        expect(call.headers.get("if-none-match")).toBeNull();
        expect(call.headers.get("if-modified-since")).toBeNull();
      }
    });

    it("does not consult the dictionary when the base is not modified", async () => {
      const store = new MemoryDatasetCacheStore();
      await seed(store);

      const { calls, fetchImpl } = mockFetch(() => new Response(null, { status: 304 }));

      const result = await fetchDataset({
        mode: "regular",
        dataset: "traders",
        baseUrl: BASE,
        fetchImpl,
        cache: store,
      });

      expect(result.status).toBe("not-modified");
      expect(calls).toHaveLength(1);
    });
  });
});
