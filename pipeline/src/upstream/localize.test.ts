import { describe, expect, it } from "vitest";
import { localizeInPlace } from "./localize.js";

const A = "54cb50c76803fa8b248b4571";
const B = "54cb57776803fa99248b456e";

function envelope() {
  return {
    data: {
      items: {
        [A]: { name: `${A} Name`, shortName: `${A} ShortName`, properties: { fireModes: ["single"] } },
        [B]: { name: `${B} Name`, shortName: `${B} ShortName`, properties: { fireModes: ["burst"] } },
      },
      skills: [{ name: "AimDrills" }],
    },
    translations: [
      "$.data.items.*.name",
      "$.data.items.*.shortName",
      "$.data.items.*.properties.fireModes[*]",
      "$.data.skills.*.name",
    ],
  };
}

describe("localizeInPlace", () => {
  it("replaces placeholders from a flat dictionary", () => {
    const payload = envelope();
    const stats = localizeInPlace(payload, {
      [`${A} Name`]: "Colt M4A1",
      [`${A} ShortName`]: "M4A1",
      [`${B} Name`]: "AK-74",
      [`${B} ShortName`]: "AK-74",
      single: "Single",
      burst: "Burst",
      AimDrills: "Aim Drills",
    });

    expect(payload.data.items[A]?.name).toBe("Colt M4A1");
    expect(payload.data.items[B]?.name).toBe("AK-74");
    expect(payload.data.items[A]?.properties.fireModes[0]).toBe("Single");
    expect(payload.data.skills[0]?.name).toBe("Aim Drills");
    expect(stats.translated).toBe(7);
    expect(stats.missingKeys).toEqual([]);
    expect(stats.unresolvedPaths).toEqual([]);
    expect(stats.unmatched).toBe(0);
  });

  it("reports placeholder-shaped strings with no dictionary entry", () => {
    const payload = envelope();
    const stats = localizeInPlace(payload, {
      [`${A} Name`]: "Colt M4A1",
      [`${B} Name`]: "AK-74",
      single: "Single",
      burst: "Burst",
      AimDrills: "Aim Drills",
    });

    expect(stats.missingKeys).toEqual([`${A} ShortName`, `${B} ShortName`]);
    expect(payload.data.items[A]?.shortName).toBe(`${A} ShortName`);
  });

  it("counts already-final strings as unmatched rather than missing", () => {
    const payload = {
      data: { item: { name: "Already English" } },
      translations: ["$.data.item.name"],
    };
    const stats = localizeInPlace(payload, {});
    expect(stats.unmatched).toBe(1);
    expect(stats.missingKeys).toEqual([]);
  });

  it("records stale pointers instead of throwing", () => {
    const payload = {
      data: { armorMaterials: { steel: { name: "Steel" } } },
      translations: ["$.data.armorMaterial.*.name"],
    };
    const stats = localizeInPlace(payload, { Steel: "Aço" });
    expect(stats.unresolvedPaths).toEqual(["$.data.armorMaterial.*.name"]);
  });

  it("records unparsable pointers without aborting the rest", () => {
    const payload = {
      data: { item: { name: `${A} Name` } },
      translations: ["$.data.item[?(@.name)]", "$.data.item.name"],
    };
    const stats = localizeInPlace(payload, { [`${A} Name`]: "Colt M4A1" });
    expect(stats.failedPaths).toHaveLength(1);
    expect(payload.data.item.name).toBe("Colt M4A1");
  });

  it("does nothing when a payload declares no translations", () => {
    const payload = { data: { value: `${A} Name` } };
    const stats = localizeInPlace(payload, { [`${A} Name`]: "X" });
    expect(payload.data.value).toBe(`${A} Name`);
    expect(stats.translated).toBe(0);
    expect(stats.visited).toBe(0);
  });
});
