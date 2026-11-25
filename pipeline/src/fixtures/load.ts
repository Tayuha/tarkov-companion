import { FIXTURES_ROOT, readFixtureJson } from "../schemas/fixtures.js";
import {
  formatIssues,
  getDatasetSchema,
  parseDatasetData,
  parseDatasetEnvelope,
  parseDictionary,
} from "../schemas/registry.js";
import { localizeInPlace, type LocalizationStats } from "../upstream/localize.js";

/**
 * Load a committed fixture pair, localize it offline, and validate the
 * localized payload with the registered schemas.
 *
 * This is the only path the CLI and the golden tests use, so both normalize
 * exactly the same validated data. No network access.
 */

export interface LocalizedFixture {
  readonly mode: string;
  readonly dataset: string;
  readonly relativePath: string;
  /** Validated, fully localized `data` value. */
  readonly data: unknown;
  readonly stats: LocalizationStats;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function translationsOf(payload: unknown): string[] {
  if (!isRecord(payload) || !Array.isArray(payload["translations"])) return [];
  return payload["translations"].filter((entry): entry is string => typeof entry === "string");
}

function dictionaryOf(payload: unknown): Record<string, string> {
  const root = isRecord(payload) && isRecord(payload["data"]) ? payload["data"] : payload;
  if (!isRecord(root)) throw new Error("dictionary fixture has no data object");

  const dictionary: Record<string, string> = {};
  for (const [key, value] of Object.entries(root)) {
    if (typeof value === "string") dictionary[key] = value;
  }
  return dictionary;
}

export async function loadLocalizedFixture(
  mode: string,
  dataset: string,
): Promise<LocalizedFixture> {
  return loadLocalizedFixtureFrom(FIXTURES_ROOT, mode, dataset);
}

/**
 * Same loader as `loadLocalizedFixture`, but reading from an explicit fixture
 * root. Used by the offline sync provider so `--fixtures <dir>` can point at a
 * checkout or a test fixture set.
 */
export async function loadLocalizedFixtureFrom(
  root: string,
  mode: string,
  dataset: string,
): Promise<LocalizedFixture> {
  const definition = getDatasetSchema(mode, dataset);
  if (definition === undefined) throw new Error(`no schema registered for ${mode}/${dataset}`);

  const relativePath = `${mode}/${dataset}.json`;
  const payload = await readFixtureJson(relativePath, root);

  const envelope = parseDatasetEnvelope(mode, dataset, payload);
  if (!envelope.success) {
    throw new Error(`${relativePath}: ${formatIssues(envelope.error)}`);
  }

  const data = isRecord(payload) ? payload["data"] : undefined;
  const translations = translationsOf(payload);

  let dictionary: Record<string, string> = {};
  if (translations.length > 0) {
    const dictionaryPath = `${mode}/${dataset}_en.json`;
    const dictionaryPayload = await readFixtureJson(dictionaryPath, root);
    const parsed = parseDictionary(dictionaryPayload);
    if (!parsed.success) {
      throw new Error(`${dictionaryPath}: ${formatIssues(parsed.error)}`);
    }
    dictionary = dictionaryOf(dictionaryPayload);
  }

  const stats = localizeInPlace({ data, translations }, dictionary);
  if (stats.missingKeys.length > 0) {
    throw new Error(
      `${relativePath}: ${stats.missingKeys.length} placeholder(s) have no dictionary entry: ${stats.missingKeys
        .slice(0, 3)
        .join(", ")}`,
    );
  }

  const localized = parseDatasetData(mode, dataset, data);
  if (!localized.success) {
    throw new Error(`${relativePath} (localized): ${formatIssues(localized.error)}`);
  }

  return { mode, dataset, relativePath, data, stats };
}
