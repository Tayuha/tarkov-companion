import { createHash } from "node:crypto";
import { PLACEHOLDER_PATTERN } from "../normalize/contract.js";
import { manifestSchema, type BundleManifest, type ManifestDatasetEntry } from "./manifest.js";
import { decompressZstd } from "./zstd.js";

/**
 * Bundle validation.
 *
 * `validateBundle` is pure: it takes the manifest text and the mode directory's
 * files as bytes, and never touches the filesystem or the network. The CLI in
 * `src/cli/validate-bundle.ts` is the only code that reads a directory.
 *
 * It enforces the contract a client relies on:
 *
 *   - the manifest matches the Zod schema;
 *   - every dataset path is a flat, traversal-free file name;
 *   - the referenced file exists, has the manifest's compressed size and
 *     SHA-256, and decompresses as zstd;
 *   - the payload is UTF-8 JSONL with one object per line, a non-empty `kind`
 *     and `id`, no duplicate `kind`+`id`, and the manifest's record count;
 *   - no value is an unresolved localization placeholder.
 *
 * Unknown extra files are reported as warnings, not errors: a directory may
 * hold notes or a plain JSONL copy without making the bundle unusable.
 */

export type BundleValidationCode =
  | "invalid-json"
  | "invalid-manifest"
  | "duplicate-dataset"
  | "min-app-schema-mismatch"
  | "unsafe-path"
  | "missing-file"
  | "size-mismatch"
  | "sha256-mismatch"
  | "zstd-error"
  | "uncompressed-size-mismatch"
  | "invalid-utf8"
  | "invalid-jsonl"
  | "invalid-record"
  | "duplicate-record"
  | "record-count-mismatch"
  | "placeholder"
  | "empty-dataset"
  | "missing-trailing-newline"
  | "totals-mismatch"
  | "skipped-with-file"
  | "extra-file";

export interface BundleValidationIssue {
  readonly code: BundleValidationCode;
  readonly message: string;
  /** Dataset name when the issue belongs to one; `null` for manifest-wide issues. */
  readonly dataset: string | null;
  /** File or record location, when useful for the message. */
  readonly path: string | null;
}

export interface DatasetValidation {
  readonly dataset: string;
  readonly path: string;
  readonly ok: boolean;
  /** Record count found in the payload, or `null` when it could not be read. */
  readonly records: number | null;
  readonly compressedBytes: number | null;
  readonly sha256: string | null;
}

export interface BundleValidationResult {
  readonly ok: boolean;
  readonly mode: string | null;
  readonly generatedAt: string | null;
  readonly datasets: readonly DatasetValidation[];
  readonly errors: readonly BundleValidationIssue[];
  readonly warnings: readonly BundleValidationIssue[];
}

export interface BundleValidationInput {
  readonly manifestText: string;
  /** File name -> bytes, exactly as found in the manifest's directory. */
  readonly files: ReadonlyMap<string, Uint8Array>;
  /** Names present in the directory that the manifest does not reference. */
  readonly extraFiles?: readonly string[];
}

interface IssueLocation {
  readonly dataset?: string;
  readonly path?: string;
}

function issue(
  code: BundleValidationCode,
  message: string,
  location: IssueLocation = {},
): BundleValidationIssue {
  return {
    code,
    message,
    dataset: location.dataset ?? null,
    path: location.path ?? null,
  };
}

function sha256Hex(data: Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * True for a flat file name that cannot escape the manifest's directory.
 *
 * Both the local writer and the release publisher emit flat names; a client
 * concatenates the name onto the manifest URL, so a directory component,
 * absolute path, backslash or `.`/`..` would be a traversal or a wrong URL.
 */
export function isSafeBundlePath(path: string): boolean {
  if (path.length === 0) return false;
  if (path === "." || path === "..") return false;
  if (path.includes("/") || path.includes("\\")) return false;
  if (path.includes("\0")) return false;
  return true;
}

function describeZodIssues(error: {
  readonly issues: ReadonlyArray<{ readonly path: ReadonlyArray<PropertyKey>; readonly message: string }>;
}): string {
  return error.issues
    .map((entry) => `${entry.path.map(String).join(".") || "<root>"}: ${entry.message}`)
    .join("; ");
}

interface ParsedJsonl {
  readonly records: number;
  readonly issues: readonly BundleValidationIssue[];
  readonly warnings: readonly BundleValidationIssue[];
}

function walkPlaceholders(
  value: unknown,
  path: string,
  dataset: string,
  errors: BundleValidationIssue[],
): void {
  if (typeof value === "string") {
    if (PLACEHOLDER_PATTERN.test(value)) {
      errors.push(
        issue(
          "placeholder",
          `${path}: unresolved localization placeholder "${value}"`,
          { dataset, path },
        ),
      );
    }
    return;
  }
  if (Array.isArray(value)) {
    value.forEach((entry, index) => {
      walkPlaceholders(entry, `${path}[${index}]`, dataset, errors);
    });
    return;
  }
  if (isRecord(value)) {
    for (const [key, entry] of Object.entries(value)) {
      walkPlaceholders(entry, `${path}.${key}`, dataset, errors);
    }
  }
}

function parseJsonl(text: string, dataset: string): ParsedJsonl {
  const errors: BundleValidationIssue[] = [];
  const warnings: BundleValidationIssue[] = [];

  if (text.length === 0) {
    errors.push(issue("empty-dataset", `${dataset}: dataset file is empty`, { dataset }));
    return { records: 0, issues: errors, warnings };
  }

  const lines = text.split("\n");
  if (lines[lines.length - 1] === "") {
    lines.pop();
  } else {
    warnings.push(
      issue(
        "missing-trailing-newline",
        `${dataset}: payload does not end with a newline`,
        { dataset },
      ),
    );
  }

  const seen = new Set<string>();

  for (const [index, line] of lines.entries()) {
    const lineNumber = index + 1;
    const location = `${dataset}:${lineNumber}`;

    if (line.trim().length === 0) {
      errors.push(issue("invalid-jsonl", `${location}: blank line`, { dataset, path: location }));
      continue;
    }

    let parsed: unknown;
    try {
      parsed = JSON.parse(line) as unknown;
    } catch (error) {
      errors.push(
        issue(
          "invalid-jsonl",
          `${location}: not valid JSON (${error instanceof Error ? error.message : String(error)})`,
          { dataset, path: location },
        ),
      );
      continue;
    }

    if (!isRecord(parsed)) {
      errors.push(
        issue("invalid-record", `${location}: expected a JSON object`, { dataset, path: location }),
      );
      continue;
    }

    const kind = parsed["kind"];
    const id = parsed["id"];
    if (typeof kind !== "string" || kind.length === 0) {
      errors.push(
        issue("invalid-record", `${location}: missing non-empty string "kind"`, {
          dataset,
          path: location,
        }),
      );
      continue;
    }
    if (typeof id !== "string" || id.length === 0) {
      errors.push(
        issue("invalid-record", `${location}: missing non-empty string "id"`, {
          dataset,
          path: location,
        }),
      );
      continue;
    }

    const key = `${kind}\u0000${id}`;
    if (seen.has(key)) {
      errors.push(
        issue("duplicate-record", `${location}: duplicate record ${kind}/${id}`, {
          dataset,
          path: location,
        }),
      );
    }
    seen.add(key);

    walkPlaceholders(parsed, location, dataset, errors);
  }

  return { records: lines.length, issues: errors, warnings };
}

function validateDataset(
  entry: ManifestDatasetEntry,
  files: ReadonlyMap<string, Uint8Array>,
  errors: BundleValidationIssue[],
  warnings: BundleValidationIssue[],
): DatasetValidation {
  const firstError = errors.length;
  const base = {
    dataset: entry.dataset,
    path: entry.path,
    sha256: entry.sha256,
    compressedBytes: entry.compressedBytes,
  };

  if (!isSafeBundlePath(entry.path)) {
    errors.push(
      issue(
        "unsafe-path",
        `${entry.dataset}: path "${entry.path}" must be a flat file name without "/" or "\\", and not "." or ".."`,
        { dataset: entry.dataset, path: entry.path },
      ),
    );
    return { ...base, ok: false, records: null };
  }

  const bytes = files.get(entry.path);
  if (bytes === undefined) {
    errors.push(
      issue("missing-file", `${entry.dataset}: file "${entry.path}" is missing`, {
        dataset: entry.dataset,
        path: entry.path,
      }),
    );
    return { ...base, ok: false, records: null };
  }

  if (bytes.byteLength !== entry.compressedBytes) {
    errors.push(
      issue(
        "size-mismatch",
        `${entry.dataset}: "${entry.path}" is ${String(bytes.byteLength)} bytes, manifest says ${String(entry.compressedBytes)}`,
        { dataset: entry.dataset, path: entry.path },
      ),
    );
  }

  const actualSha = sha256Hex(bytes);
  if (actualSha !== entry.sha256) {
    errors.push(
      issue(
        "sha256-mismatch",
        `${entry.dataset}: "${entry.path}" sha256 is ${actualSha}, manifest says ${entry.sha256}`,
        { dataset: entry.dataset, path: entry.path },
      ),
    );
  }

  let raw: Buffer;
  try {
    raw = decompressZstd(bytes);
  } catch (error) {
    errors.push(
      issue(
        "zstd-error",
        `${entry.dataset}: "${entry.path}" is not a readable zstd frame (${error instanceof Error ? error.message : String(error)})`,
        { dataset: entry.dataset, path: entry.path },
      ),
    );
    return { ...base, ok: false, records: null };
  }

  if (raw.byteLength !== entry.uncompressedBytes) {
    errors.push(
      issue(
        "uncompressed-size-mismatch",
        `${entry.dataset}: payload is ${String(raw.byteLength)} bytes, manifest says ${String(entry.uncompressedBytes)}`,
        { dataset: entry.dataset, path: entry.path },
      ),
    );
  }

  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true }).decode(raw);
  } catch {
    errors.push(
      issue("invalid-utf8", `${entry.dataset}: payload is not valid UTF-8`, {
        dataset: entry.dataset,
        path: entry.path,
      }),
    );
    return { ...base, ok: false, records: null };
  }

  const parsed = parseJsonl(text, entry.dataset);
  errors.push(...parsed.issues);
  warnings.push(...parsed.warnings);

  if (parsed.records !== entry.records) {
    errors.push(
      issue(
        "record-count-mismatch",
        `${entry.dataset}: payload has ${String(parsed.records)} records, manifest says ${String(entry.records)}`,
        { dataset: entry.dataset, path: entry.path },
      ),
    );
  }

  return {
    ...base,
    ok: errors.length === firstError,
    records: parsed.records,
  };
}

function totalsWarnings(manifest: BundleManifest): BundleValidationIssue[] {
  const warnings: BundleValidationIssue[] = [];
  const datasets = manifest.datasets.length;
  const records = manifest.datasets.reduce((sum, entry) => sum + entry.records, 0);
  const uncompressedBytes = manifest.datasets.reduce(
    (sum, entry) => sum + entry.uncompressedBytes,
    0,
  );
  const compressedBytes = manifest.datasets.reduce((sum, entry) => sum + entry.compressedBytes, 0);

  const fields: ReadonlyArray<[string, number, number]> = [
    ["datasets", manifest.totals.datasets, datasets],
    ["records", manifest.totals.records, records],
    ["uncompressedBytes", manifest.totals.uncompressedBytes, uncompressedBytes],
    ["compressedBytes", manifest.totals.compressedBytes, compressedBytes],
  ];

  for (const [name, declared, computed] of fields) {
    if (declared !== computed) {
      warnings.push(
        issue(
          "totals-mismatch",
          `totals.${name} is ${String(declared)}, datasets sum to ${String(computed)}`,
        ),
      );
    }
  }

  return warnings;
}

/**
 * Validate a bundle from its manifest text and files. Pure and deterministic:
 * the result depends only on the input.
 */
export function validateBundle(input: BundleValidationInput): BundleValidationResult {
  const errors: BundleValidationIssue[] = [];
  const warnings: BundleValidationIssue[] = [];

  let parsedJson: unknown;
  try {
    parsedJson = JSON.parse(input.manifestText) as unknown;
  } catch (error) {
    errors.push(
      issue(
        "invalid-json",
        `manifest.json is not valid JSON (${error instanceof Error ? error.message : String(error)})`,
        { path: "manifest.json" },
      ),
    );
    return {
      ok: false,
      mode: null,
      generatedAt: null,
      datasets: [],
      errors,
      warnings,
    };
  }

  const parsed = manifestSchema.safeParse(parsedJson);
  if (!parsed.success) {
    errors.push(
      issue("invalid-manifest", `manifest.json is not a valid bundle manifest: ${describeZodIssues(parsed.error)}`, {
        path: "manifest.json",
      }),
    );
    return {
      ok: false,
      mode: null,
      generatedAt: null,
      datasets: [],
      errors,
      warnings,
    };
  }

  const manifest = parsed.data;
  warnings.push(...totalsWarnings(manifest));

  const highestDatasetSchema = manifest.datasets.reduce(
    (highest, entry) => Math.max(highest, entry.schemaVersion),
    0,
  );
  if (manifest.minAppSchemaVersion < highestDatasetSchema) {
    errors.push(
      issue(
        "min-app-schema-mismatch",
        `minAppSchemaVersion ${String(manifest.minAppSchemaVersion)} is lower than a dataset schemaVersion ${String(highestDatasetSchema)}`,
        { path: "manifest.json" },
      ),
    );
  }

  const seenDatasets = new Set<string>();
  const datasets: DatasetValidation[] = [];
  const referenced = new Set<string>();

  for (const entry of manifest.datasets) {
    if (seenDatasets.has(entry.dataset)) {
      errors.push(
        issue(
          "duplicate-dataset",
          `${entry.dataset}: listed more than once in datasets[]`,
          { dataset: entry.dataset, path: entry.path },
        ),
      );
      continue;
    }
    seenDatasets.add(entry.dataset);
    referenced.add(entry.path);

    const summary = validateDataset(entry, input.files, errors, warnings);
    datasets.push(summary);
  }

  for (const skipped of manifest.skipped) {
    if (input.files.has(`${skipped.dataset}.jsonl.zst`)) {
      warnings.push(
        issue(
          "skipped-with-file",
          `${skipped.dataset}: listed under skipped but "${skipped.dataset}.jsonl.zst" exists`,
          { dataset: skipped.dataset, path: `${skipped.dataset}.jsonl.zst` },
        ),
      );
    }
  }

  for (const name of input.extraFiles ?? []) {
    if (name === "manifest.json" || referenced.has(name)) continue;
    warnings.push(
      issue("extra-file", `"${name}" is not referenced by the manifest`, { path: name }),
    );
  }

  return {
    ok: errors.length === 0,
    mode: manifest.mode,
    generatedAt: manifest.generatedAt,
    datasets,
    errors,
    warnings,
  };
}
