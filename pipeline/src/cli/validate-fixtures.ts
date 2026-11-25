import { listFixtureFiles, readFixtureJson, type FixtureFile } from "../schemas/fixtures.js";
import {
  describeRecordCounts,
  formatIssues,
  parseDatasetEnvelope,
  parseDictionary,
  schemaForFixture,
} from "../schemas/registry.js";

/**
 * Validate every committed upstream fixture offline.
 *
 * This is the CI-friendly "did upstream drift?" command: it runs the same
 * registered schemas the pipeline uses, prints per-dataset record counts and
 * exits non-zero if any payload or dictionary is rejected. No network access.
 */

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function countLabel(counts: Readonly<Record<string, number>>): string {
  return Object.entries(counts)
    .map(([name, count]) => `${name}=${count}`)
    .join(" ");
}

async function validateBase(file: FixtureFile): Promise<{ ok: boolean; label: string }> {
  const definition = schemaForFixture(file.fixtureSet, file.pathWithinSet);
  const payload = await readFixtureJson(file.relativePath);
  const result = parseDatasetEnvelope(
    definition.mode,
    definition.dataset,
    payload,
  );

  if (!result.success) {
    console.error(`FAIL ${file.relativePath}`);
    console.error(formatIssues(result.error));
    return { ok: false, label: `${definition.mode}/${definition.dataset}` };
  }

  const data = isObject(payload) ? payload["data"] : undefined;
  const counts = describeRecordCounts(definition.dataset, data);
  return {
    ok: true,
    label: `${file.relativePath.padEnd(34)} ${definition.mode}/${definition.dataset} ${countLabel(counts)}`,
  };
}

async function validateDictionary(file: FixtureFile): Promise<boolean> {
  const payload = await readFixtureJson(file.relativePath);
  const result = parseDictionary(payload);

  if (!result.success) {
    console.error(`FAIL ${file.relativePath}`);
    console.error(formatIssues(result.error));
    return false;
  }

  return true;
}

async function main(): Promise<void> {
  const files = await listFixtureFiles();
  const bases = files.filter((file) => file.kind === "base");
  const dictionaries = files.filter((file) => file.kind === "dictionary");

  let failures = 0;
  const rows: string[] = [];

  for (const file of bases) {
    try {
      const outcome = await validateBase(file);
      if (outcome.ok) rows.push(outcome.label);
      else failures += 1;
    } catch (error) {
      failures += 1;
      console.error(`FAIL ${file.relativePath}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  for (const file of dictionaries) {
    try {
      if (!(await validateDictionary(file))) failures += 1;
    } catch (error) {
      failures += 1;
      console.error(`FAIL ${file.relativePath}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  // A dictionary without a base dataset would be dead weight nobody validates.
  const basePaths = new Set(bases.map((file) => file.relativePath));
  for (const file of dictionaries) {
    const base = file.relativePath.replace(/_en\.json$/, ".json");
    if (!basePaths.has(base)) {
      console.error(`FAIL ${file.relativePath}: no base fixture ${base}`);
      failures += 1;
    }
  }

  for (const row of rows) console.log(row);

  const plural = (count: number, singular: string, pluralForm: string): string =>
    `${count} ${count === 1 ? singular : pluralForm}`;

  console.log("");
  console.log(
    `${plural(bases.length, "dataset file", "dataset files")}, ` +
      `${plural(dictionaries.length, "dictionary", "dictionaries")}: ` +
      (failures === 0 ? "PASS" : `FAIL (${failures})`),
  );

  if (failures > 0) process.exitCode = 1;
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
