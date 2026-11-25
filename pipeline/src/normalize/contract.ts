/**
 * Shared helpers for the normalization stage.
 *
 * Normalization is the boundary between the validated upstream payload and the
 * bundle JSONL contract documented in `docs/data-bundles.md`. It is pure: no
 * I/O, no clock, no randomness. The same validated input always produces the
 * same records.
 *
 * Field rules used everywhere:
 *
 * - camelCase names; reference fields end in `Id` (`traderId`, `mapId`, ...);
 * - related entities are referenced by id, never embedded (an embedded name is
 *   an explicit, documented exception);
 * - money is an integer number of roubles, geometry uses `{x, y, z}`;
 * - timestamps are ISO 8601 UTC strings;
 * - `undefined` never reaches a record, and unknown upstream fields are
 *   dropped and counted instead of leaking into the bundle.
 */

/** A string that still looks like an unresolved upstream localization key. */
export const PLACEHOLDER_PATTERN = /^[0-9a-f]{24} \S/;

export type JsonRecord = Record<string, unknown>;

/** One line of a bundle. `kind` discriminates the payload, `id` identifies it. */
export interface BundleRecord {
  readonly kind: string;
  readonly id: string;
  readonly [key: string]: unknown;
}

export interface NormalizeStats {
  readonly dataset: string;
  readonly records: number;
  /** Record count per `kind`, sorted by kind. */
  readonly counts: Readonly<Record<string, number>>;
  /** Total number of upstream fields dropped because the contract omits them. */
  readonly droppedFields: number;
  /** Unique dotted paths of dropped fields, sorted. */
  readonly droppedFieldPaths: readonly string[];
  /** Documented fallbacks applied, e.g. an unresolved customization name. */
  readonly fallbacks: Readonly<Record<string, number>>;
}

export interface NormalizeResult {
  readonly dataset: string;
  readonly records: readonly BundleRecord[];
  readonly stats: NormalizeStats;
}

/** Collects dropped-field and fallback counters for one dataset. */
export class StatsCollector {
  private readonly dropped = new Map<string, number>();
  private readonly fallbackCounts = new Map<string, number>();

  drop(path: string): void {
    this.dropped.set(path, (this.dropped.get(path) ?? 0) + 1);
  }

  fallback(name: string): void {
    this.fallbackCounts.set(name, (this.fallbackCounts.get(name) ?? 0) + 1);
  }

  snapshot(dataset: string, records: readonly BundleRecord[]): NormalizeStats {
    const counts = new Map<string, number>();
    for (const record of records) {
      counts.set(record.kind, (counts.get(record.kind) ?? 0) + 1);
    }

    const sortedCounts: Record<string, number> = {};
    for (const kind of [...counts.keys()].sort()) {
      sortedCounts[kind] = counts.get(kind) ?? 0;
    }

    const sortedFallbacks: Record<string, number> = {};
    for (const name of [...this.fallbackCounts.keys()].sort()) {
      sortedFallbacks[name] = this.fallbackCounts.get(name) ?? 0;
    }

    let droppedFields = 0;
    for (const count of this.dropped.values()) droppedFields += count;

    return {
      dataset,
      records: records.length,
      counts: sortedCounts,
      droppedFields,
      droppedFieldPaths: [...this.dropped.keys()].sort(),
      fallbacks: sortedFallbacks,
    };
  }
}

export interface NormalizeContext {
  readonly stats: StatsCollector;
}

export function isRecord(value: unknown): value is JsonRecord {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function requireRecord(value: unknown, path: string): JsonRecord {
  if (!isRecord(value)) throw new Error(`${path}: expected an object`);
  return value;
}

export function requireString(value: unknown, path: string): string {
  if (typeof value !== "string") throw new Error(`${path}: expected a string`);
  return value;
}

/** An identifier is always a non-empty string in the bundle contract. */
export function requireId(value: unknown, path: string): string {
  const id = requireString(value, path);
  if (id.length === 0) throw new Error(`${path}: expected a non-empty id`);
  return id;
}

export function numberValue(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

export function integerValue(value: unknown): number | undefined {
  const number = numberValue(value);
  return number === undefined ? undefined : Math.round(number);
}

/** Money is normalized to an integer number of roubles. */
export function moneyValue(value: unknown): number | undefined {
  const number = numberValue(value);
  return number === undefined ? undefined : Math.round(number);
}

/** Preserves an explicit `null` while rejecting other non-numbers. */
export function nullableNumber(value: unknown): number | null | undefined {
  if (value === null) return null;
  return numberValue(value);
}

export function nullableInteger(value: unknown): number | null | undefined {
  if (value === null) return null;
  return integerValue(value);
}

export function stringList(value: unknown): string[] | undefined {
  if (!Array.isArray(value)) return undefined;
  const strings = value.filter((entry): entry is string => typeof entry === "string");
  return strings.length === value.length ? strings : undefined;
}

export function stringMatrix(value: unknown): string[][] | undefined {
  if (!Array.isArray(value)) return undefined;
  const rows: string[][] = [];
  for (const entry of value) {
    const row = stringList(entry);
    if (row === undefined) return undefined;
    rows.push(row);
  }
  return rows;
}

export function vector3(value: unknown): { x: number; y: number; z: number } | undefined {
  if (!isRecord(value)) return undefined;
  const x = numberValue(value["x"]);
  const y = numberValue(value["y"]);
  const z = numberValue(value["z"]);
  if (x === undefined || y === undefined || z === undefined) return undefined;
  return { x, y, z };
}

export function vector3List(value: unknown): Array<{ x: number; y: number; z: number }> | undefined {
  if (!Array.isArray(value)) return undefined;
  const vectors: Array<{ x: number; y: number; z: number }> = [];
  for (const entry of value) {
    const vector = vector3(entry);
    if (vector === undefined) return undefined;
    vectors.push(vector);
  }
  return vectors;
}

export function isoString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
}

export function nullableIsoString(value: unknown): string | null | undefined {
  if (value === null) return null;
  return isoString(value);
}

/** `goonReports.timestamp` arrives as epoch milliseconds in a string. */
export function isoFromEpochMillisString(value: unknown): string | undefined {
  if (typeof value !== "string" && typeof value !== "number") return undefined;
  const millis = Number(value);
  if (!Number.isFinite(millis)) return undefined;
  const date = new Date(millis);
  return Number.isNaN(date.getTime()) ? undefined : date.toISOString();
}

export interface FieldRule {
  /** Output key. Ignored when `omit` is set. */
  readonly to?: string;
  /** Transform the value. Returning `undefined` omits the field. */
  readonly transform?: (value: unknown, ctx: NormalizeContext, path: string) => unknown;
  /** Consume the field without emitting it (e.g. folded into a `price` object). */
  readonly omit?: boolean;
}

export type FieldSpec = Readonly<Record<string, string | FieldRule>>;

/**
 * Project a record onto an explicit field spec.
 *
 * Every source key missing from the spec is dropped and counted, so an
 * upstream field addition can never silently change the bundle contract.
 */
export function projectFields(
  source: JsonRecord,
  spec: FieldSpec,
  ctx: NormalizeContext,
  path: string,
): JsonRecord {
  const out: JsonRecord = {};

  for (const [key, value] of Object.entries(source)) {
    const rule = spec[key];
    if (rule === undefined) {
      ctx.stats.drop(`${path}.${key}`);
      continue;
    }

    if (typeof rule === "string") {
      out[rule] = value;
      continue;
    }
    if (rule.omit === true) continue;

    const target = rule.to ?? key;
    const result =
      rule.transform === undefined ? value : rule.transform(value, ctx, `${path}.${key}`);
    if (result !== undefined) out[target] = result;
  }

  return out;
}

/** Project an array of objects, keeping the array order. */
export function projectList<T extends JsonRecord>(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
  project: (entry: JsonRecord, ctx: NormalizeContext, path: string) => T,
): T[] | undefined {
  if (!Array.isArray(value)) return undefined;
  return value.map((entry, index) =>
    project(requireRecord(entry, `${path}[${index}]`), ctx, `${path}[${index}]`),
  );
}

/** Project an id-keyed upstream map into records. */
export function projectMap(
  value: unknown,
  ctx: NormalizeContext,
  path: string,
  project: (entry: JsonRecord, ctx: NormalizeContext, path: string) => BundleRecord,
): BundleRecord[] {
  const map = requireRecord(value, path);
  const records: BundleRecord[] = [];
  for (const [key, entry] of Object.entries(map)) {
    records.push(project(requireRecord(entry, `${path}.${key}`), ctx, `${path}.${key}`));
  }
  return records;
}

/** Build a bundle record, lifting `id` out of the payload fields. */
export function makeRecord(kind: string, fields: JsonRecord): BundleRecord {
  const id = requireId(fields["id"], `${kind}.id`);
  delete fields["id"];
  return { kind, id, ...fields };
}

/**
 * Fail normalization rather than publish a bundle that violates the contract:
 * a missing kind/id, a duplicate `kind`+`id`, a placeholder string, an
 * `undefined`, or a non-finite number.
 */
export function assertBundleRecords(
  dataset: string,
  records: readonly BundleRecord[],
): void {
  const seen = new Set<string>();

  for (const record of records) {
    const kind = requireString(record.kind, `${dataset}: record.kind`);
    const id = requireString(record.id, `${dataset}: record.id`);
    const key = `${kind}\u0000${id}`;
    if (seen.has(key)) throw new Error(`${dataset}: duplicate record ${kind}/${id}`);
    seen.add(key);
    walkBundleValue(record, `${dataset}:${kind}/${id}`, dataset);
  }
}

function walkBundleValue(value: unknown, path: string, dataset: string): void {
  if (value === undefined) throw new Error(`${path}: undefined value`);
  if (typeof value === "number" && !Number.isFinite(value)) {
    throw new Error(`${path}: non-finite number`);
  }
  if (typeof value === "string" && PLACEHOLDER_PATTERN.test(value)) {
    throw new Error(`${path}: unresolved localization placeholder "${value}" (${dataset})`);
  }
  if (Array.isArray(value)) {
    value.forEach((entry, index) => walkBundleValue(entry, `${path}[${index}]`, dataset));
    return;
  }
  if (isRecord(value)) {
    for (const [key, entry] of Object.entries(value)) {
      walkBundleValue(entry, `${path}.${key}`, dataset);
    }
  }
}
