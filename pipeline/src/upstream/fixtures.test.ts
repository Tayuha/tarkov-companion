import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";
import { localizeInPlace } from "./localize.js";

async function readFixture(name: string): Promise<unknown> {
  const url = new URL(`../../../test/fixtures/upstream/${name}`, import.meta.url);
  return JSON.parse(await readFile(url, "utf8"));
}

describe("recorded upstream fixtures", () => {
  it("resolves traders names and descriptions completely", async () => {
    const base = (await readFixture("traders.json")) as {
      data: Record<string, { name: string; description: string }>;
      translations: string[];
    };
    const dictionary = (await readFixture("traders_en.json")) as {
      data: Record<string, string>;
    };

    const stats = localizeInPlace(base, dictionary.data);

    expect(stats.missingKeys).toEqual([]);
    expect(stats.unresolvedPaths).toEqual([]);
    expect(stats.failedPaths).toEqual([]);
    expect(stats.translated).toBe(4);

    expect(base.data["54cb50c76803fa8b248b4571"]?.name).toBe("Prapor");
    expect(base.data["54cb57776803fa99248b456e"]?.name).toBe("Therapist");
    expect(base.data["54cb50c76803fa8b248b4571"]?.description).toMatch(/Warrant officer/);
  });
});
