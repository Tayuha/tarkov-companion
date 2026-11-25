import { readdir, readFile } from "node:fs/promises";
import { join, relative, sep } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Filesystem helpers for the committed upstream fixtures.
 *
 * Shared by the schema tests and `npm run validate:fixtures` so both walk the
 * same files with the same classification. Nothing here performs network I/O.
 */

export const FIXTURES_ROOT = fileURLToPath(
  new URL("../../../test/fixtures/upstream/", import.meta.url),
);

export type FixtureKind = "base" | "dictionary" | "manifest";

export interface FixtureFile {
  /** Path relative to the fixtures root, using `/` separators. */
  readonly relativePath: string;
  /** Path relative to the fixture set directory, e.g. `prices/<id>.json`. */
  readonly pathWithinSet: string;
  /** Top-level directory: `common`, `regular`, `pve`, `pvp-season`. */
  readonly fixtureSet: string;
  readonly fileName: string;
  readonly kind: FixtureKind;
}

function classify(fileName: string): FixtureKind {
  if (fileName === "manifest.json") return "manifest";
  if (fileName.endsWith("_en.json")) return "dictionary";
  return "base";
}

async function walk(dir: string): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const files: string[] = [];

  for (const entry of entries) {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...(await walk(path)));
    else if (entry.isFile()) files.push(path);
  }

  return files;
}

/** Every JSON file under the fixtures root, sorted by relative path. */
export async function listFixtureFiles(): Promise<FixtureFile[]> {
  const files = await walk(FIXTURES_ROOT);

  return files
    .filter((path) => path.endsWith(".json"))
    .map((path) => {
      const relativePath = relative(FIXTURES_ROOT, path).split(sep).join("/");
      const segments = relativePath.split("/");
      const fixtureSet = segments[0] ?? "";
      const fileName = segments[segments.length - 1] ?? "";
      const pathWithinSet = segments.slice(1).join("/");
      return { relativePath, pathWithinSet, fixtureSet, fileName, kind: classify(fileName) };
    })
    .sort((a, b) => a.relativePath.localeCompare(b.relativePath));
}

/** The `_en` dictionary path for a base fixture, e.g. `items.json` -> `items_en.json`. */
export function dictionaryPathFor(baseRelativePath: string): string {
  return `${baseRelativePath.replace(/\.json$/, "")}_en.json`;
}

export async function readFixtureJson(relativePath: string): Promise<unknown> {
  const text = await readFile(join(FIXTURES_ROOT, relativePath), "utf8");
  return JSON.parse(text) as unknown;
}
