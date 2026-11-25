import { describe, expect, it, vi } from "vitest";
import { fetchDataset, UpstreamError } from "./fetch.js";

const BASE = "https://example.test";
const PRAPOR = "54cb50c76803fa8b248b4571";

type Handler = (url: string) => Response;

function mockFetch(handler: Handler): { calls: string[]; fetchImpl: typeof fetch } {
  const calls: string[] = [];
  const fn = vi.fn((input: string | URL | Request) => {
    const url = input instanceof URL ? input.href : typeof input === "string" ? input : input.url;
    calls.push(url);
    return Promise.resolve(handler(url));
  });
  return { calls, fetchImpl: fn };
}

function jsonResponse(body: unknown, init: { status?: number; headers?: Record<string, string> } = {}): Response {
  return new Response(JSON.stringify(body), {
    status: init.status ?? 200,
    headers: { "content-type": "application/json", ...init.headers },
  });
}

function basePayload() {
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

function dictionary() {
  return {
    data: {
      [`${PRAPOR} Nickname`]: "Prapor",
      [`${PRAPOR} Description`]: "Warrant officer.",
    },
  };
}

describe("fetchDataset", () => {
  it("fetches the dataset and its locale dictionary, then localizes", async () => {
    const { calls, fetchImpl } = mockFetch((url) =>
      jsonResponse(url.endsWith("_en") ? dictionary() : basePayload()),
    );

    const result = await fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl });

    expect(calls).toEqual([`${BASE}/regular/traders`, `${BASE}/regular/traders_en`]);
    expect((result.data as Record<string, { name: string }>)[PRAPOR]?.name).toBe("Prapor");
    expect(result.stats.translated).toBe(2);
    expect(result.stats.missingKeys).toEqual([]);
    expect(result.sources.dictionary).toBe(`${BASE}/regular/traders_en`);
    expect(result.warnings).toEqual([]);
  });

  it("exposes the unresolved payload, dictionary and pointers for fixture capture", async () => {
    const { fetchImpl } = mockFetch((url) =>
      jsonResponse(url.endsWith("_en") ? dictionary() : basePayload()),
    );

    const result = await fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl });

    expect((result.rawData as Record<string, { name: string }>)[PRAPOR]?.name).toBe(
      `${PRAPOR} Nickname`,
    );
    expect(result.dictionary[`${PRAPOR} Nickname`]).toBe("Prapor");
    expect(result.translations).toEqual(["$.data.*.name", "$.data.*.description"]);
  });

  it("retries a retryable status before succeeding", async () => {
    let attempts = 0;
    const { fetchImpl } = mockFetch((url) => {
      if (url.endsWith("_en")) return jsonResponse(dictionary());
      attempts += 1;
      if (attempts === 1) return jsonResponse({ error: "boom" }, { status: 503 });
      return jsonResponse(basePayload());
    });

    const result = await fetchDataset({
      mode: "regular",
      dataset: "traders",
      baseUrl: BASE,
      fetchImpl,
      retryDelayMs: 0,
    });

    expect(attempts).toBe(2);
    expect(result.stats.translated).toBe(2);
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
      url.endsWith("_en") ? jsonResponse({ error: "missing" }, { status: 404 }) : jsonResponse(basePayload()),
    );

    await expect(
      fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl }),
    ).rejects.toThrow(/traders_en.*404/);
  });

  it("keeps placeholders and warns when a missing dictionary is allowed", async () => {
    const { fetchImpl } = mockFetch((url) =>
      url.endsWith("_en") ? jsonResponse({ error: "missing" }, { status: 404 }) : jsonResponse(basePayload()),
    );

    const result = await fetchDataset({
      mode: "regular",
      dataset: "traders",
      baseUrl: BASE,
      fetchImpl,
      allowMissingDictionary: true,
    });

    expect((result.data as Record<string, { name: string }>)[PRAPOR]?.name).toBe(`${PRAPOR} Nickname`);
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

    const result = await fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl });

    expect(result.stats.translated).toBe(2);
  });

  it("rejects invalid JSON", async () => {
    const { fetchImpl } = mockFetch(
      () => new Response("<html>not json</html>", { status: 200, headers: { "content-type": "text/html" } }),
    );

    await expect(
      fetchDataset({ mode: "regular", dataset: "traders", baseUrl: BASE, fetchImpl, retries: 0 }),
    ).rejects.toThrow(/invalid JSON/);
  });

  it("makes a single request when there are no translations", async () => {
    const { calls, fetchImpl } = mockFetch(() => jsonResponse({ data: { ok: true }, translations: [] }));

    const result = await fetchDataset({ mode: "regular", dataset: "status", baseUrl: BASE, fetchImpl });

    expect(calls).toHaveLength(1);
    expect(result.sources.dictionary).toBeNull();
  });

  it("respects the game mode in both URLs", async () => {
    const { calls, fetchImpl } = mockFetch(() =>
      jsonResponse({ data: {}, translations: ["$.data.*.name"] }),
    );

    await fetchDataset({ mode: "pve", dataset: "traders", baseUrl: BASE, fetchImpl });

    expect(calls).toEqual([`${BASE}/pve/traders`, `${BASE}/pve/traders_en`]);
  });
});
