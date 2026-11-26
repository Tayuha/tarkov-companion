import {
  collectNodes,
  parseJsonPath,
  readNode,
  writeNode,
  type JsonPath,
  type NodeRef,
} from "./jsonpath.js";

/**
 * json.tarkov.dev serves unresolved localization keys in text fields and a
 * list of JSONPath pointers describing which fields those are:
 *
 *   { "data": { ... }, "translations": ["$.data.items.*.name", ...] }
 *
 * The matching `/{mode}/{dataset}_{lang}` document is a flat dictionary keyed
 * by the placeholder string itself:
 *
 *   { "data": { "5447a9cd4bdc2dbd208b4567 Name": "Colt M4A1 ..." } }
 *
 * Resolution therefore means: visit every node a pointer selects, and if it is
 * a string with a dictionary entry, replace it in place.
 */

export interface LocalizableEnvelope {
  data: unknown;
  translations?: readonly string[];
}

export interface LocalizationStats {
  /** Strings replaced using the dictionary. */
  translated: number;
  /** Nodes visited across every translation pointer. */
  visited: number;
  /** Placeholder-shaped strings that had no dictionary entry. */
  missingKeys: string[];
  /** Pointers that matched nothing, e.g. a stale path in the payload. */
  unresolvedPaths: string[];
  /** Pointers that could not be parsed, with the parser error. */
  failedPaths: Array<{ path: string; error: string }>;
  /** Selected strings with no dictionary entry that do not look like placeholders. */
  unmatched: number;
  /**
   * Strings the dictionary fallback resolved although no declared pointer
   * selected them. Only populated when the caller opts in.
   */
  resolvedOutsidePointers?: number;
}

const PLACEHOLDER = /^[0-9a-f]{24} \S/;

function parseAll(paths: readonly string[]): {
  parsed: Array<{ path: string; segments: JsonPath }>;
  failed: Array<{ path: string; error: string }>;
} {
  const parsed: Array<{ path: string; segments: JsonPath }> = [];
  const failed: Array<{ path: string; error: string }> = [];

  for (const path of paths) {
    try {
      parsed.push({ path, segments: parseJsonPath(path) });
    } catch (error) {
      failed.push({ path, error: error instanceof Error ? error.message : String(error) });
    }
  }

  return { parsed, failed };
}

function resolvePointer(
  payload: LocalizableEnvelope,
  segments: JsonPath,
  dictionary: Readonly<Record<string, string>>,
  stats: LocalizationStats,
): void {
  const refs: NodeRef[] = collectNodes(payload, segments);

  for (const ref of refs) {
    stats.visited += 1;
    const value = readNode(ref);
    if (typeof value !== "string") continue;

    const replacement = dictionary[value];
    if (replacement !== undefined) {
      writeNode(ref, replacement);
      stats.translated += 1;
    } else if (PLACEHOLDER.test(value)) {
      stats.missingKeys.push(value);
    } else {
      stats.unmatched += 1;
    }
  }
}

/**
 * Resolve every pointer in `payload.translations` against `dictionary`,
 * mutating `payload` in place. Returns counts for logging and tests; the
 * translated document stays at `payload.data`.
 */
export function localizeInPlace(
  payload: LocalizableEnvelope,
  dictionary: Readonly<Record<string, string>>,
): LocalizationStats {
  const stats: LocalizationStats = {
    translated: 0,
    visited: 0,
    missingKeys: [],
    unresolvedPaths: [],
    failedPaths: [],
    unmatched: 0,
  };

  const pointers = payload.translations ?? [];
  const { parsed, failed } = parseAll(pointers);
  stats.failedPaths = failed;

  for (const { path, segments } of parsed) {
    const before = stats.visited;
    resolvePointer(payload, segments, dictionary, stats);
    if (stats.visited === before) {
      stats.unresolvedPaths.push(path);
    }
  }

  stats.missingKeys = [...new Set(stats.missingKeys)].sort();
  return stats;
}

/** True when a string still looks like an unresolved localization key. */
export function isPlaceholder(value: string): boolean {
  return PLACEHOLDER.test(value);
}

/**
 * Resolve placeholder-shaped strings the dictionary covers even when no
 * declared translation pointer selects them.
 *
 * The dictionary is keyed by the full placeholder string (`"<id> Name"`), so an
 * exact match is a safe signal. Upstream occasionally adds a translatable field
 * before adding its pointer (observed on top-level task objective `effects`);
 * pointers alone would leave those keys in the payload and normalization would
 * reject the dataset. This fallback is opt-in so fixture localization and its
 * goldens keep the pointer-only contract.
 *
 * Mutates `data` in place and returns the number of replaced strings.
 */
export function resolveDictionaryFallback(
  data: unknown,
  dictionary: Readonly<Record<string, string>>,
): number {
  let resolved = 0;

  function visit(value: unknown): unknown {
    if (typeof value === "string") {
      // Only placeholder-shaped strings are candidates. The dictionary also
      // contains bare entity ids mapped to empty strings; a blind key lookup
      // would blank out identity fields.
      if (!PLACEHOLDER.test(value)) return value;
      const replacement = dictionary[value];
      if (replacement === undefined) return value;
      resolved += 1;
      return replacement;
    }
    if (Array.isArray(value)) {
      for (let index = 0; index < value.length; index += 1) {
        value[index] = visit(value[index]);
      }
      return value;
    }
    if (typeof value === "object" && value !== null) {
      const record = value as Record<string, unknown>;
      for (const key of Object.keys(record)) {
        record[key] = visit(record[key]);
      }
    }
    return value;
  }

  visit(data);
  return resolved;
}
