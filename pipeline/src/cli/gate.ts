import { readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { z } from "zod";
import {
  MANIFEST_FILE,
  datasetLocalizationMetricsSchema,
  gateBundle,
  manifestSchema,
  type DatasetLocalizationMetrics,
  type GateIssue,
  type GateMetrics,
} from "../bundle/index.js";

/**
 * Publication gate CLI.
 *
 *   npm run gate -- --dir dist/bundles/regular
 *   npm run gate -- --dir ../test/fixtures/handbuilt-bundle --json
 *   npm run gate -- --dir dist/bundles/regular --report dist/sync-report.json
 *   npm run gate -- --dir dist/bundles/regular --max-bytes 12582912
 *
 * Exit codes: 0 gate passed, 1 gate failed, 2 invalid input (missing or
 * unreadable directory/manifest/report, malformed flag). No network access.
 */

const syncReportSchema = z.object({
  modes: z.array(
    z.object({
      mode: z.string(),
      localization: z.array(datasetLocalizationMetricsSchema).optional(),
    }),
  ),
});

interface GateJson {
  readonly dir: string;
  readonly manifest: string;
  readonly report: string | null;
  readonly mode: string;
  readonly ok: boolean;
  readonly failures: readonly GateIssue[];
  readonly warnings: readonly GateIssue[];
  readonly metrics: GateMetrics;
}

class InputError extends Error {}

/** The budget is binary (10 MiB); label it explicitly so 10.49 MB is not confusing. */
function formatBudgetBytes(value: number): string {
  if (value >= 1024 * 1024) return `${(value / (1024 * 1024)).toFixed(2)} MiB`;
  if (value >= 1024) return `${(value / 1024).toFixed(2)} kB`;
  return `${value} B`;
}

function formatIssue(issue: GateIssue): string {
  return `[${issue.code}] ${issue.message}`;
}

function describeZodIssues(error: {
  readonly issues: ReadonlyArray<{ readonly path: ReadonlyArray<PropertyKey>; readonly message: string }>;
}): string {
  return error.issues
    .map((entry) => `${entry.path.map(String).join(".") || "<root>"}: ${entry.message}`)
    .join("; ");
}

function parseMaxBytes(value: string | undefined): number | undefined {
  if (value === undefined) return undefined;
  const parsed = Number(value);
  if (!Number.isSafeInteger(parsed) || parsed <= 0) {
    throw new InputError(`--max-bytes expects a positive integer, got "${value}"`);
  }
  return parsed;
}

async function readManifest(dir: string) {
  const manifestPath = join(dir, MANIFEST_FILE);
  let text: string;
  try {
    text = await readFile(manifestPath, "utf8");
  } catch (error) {
    const code = (error as { readonly code?: unknown }).code;
    throw new InputError(
      code === "ENOENT"
        ? `manifest.json not found: ${manifestPath}`
        : `cannot read manifest.json: ${manifestPath}`,
    );
  }

  let json: unknown;
  try {
    json = JSON.parse(text) as unknown;
  } catch (error) {
    throw new InputError(
      `manifest.json is not valid JSON: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  const parsed = manifestSchema.safeParse(json);
  if (!parsed.success) {
    throw new InputError(
      `manifest.json is not a valid bundle manifest: ${describeZodIssues(parsed.error)}`,
    );
  }
  return { manifestPath, manifest: parsed.data };
}

async function readLocalization(
  reportPath: string | undefined,
  mode: string,
): Promise<readonly DatasetLocalizationMetrics[]> {
  if (reportPath === undefined) return [];

  let text: string;
  try {
    text = await readFile(reportPath, "utf8");
  } catch {
    throw new InputError(`cannot read sync report: ${reportPath}`);
  }

  let json: unknown;
  try {
    json = JSON.parse(text) as unknown;
  } catch (error) {
    throw new InputError(
      `sync report is not valid JSON: ${error instanceof Error ? error.message : String(error)}`,
    );
  }

  const parsed = syncReportSchema.safeParse(json);
  if (!parsed.success) {
    throw new InputError(
      `sync report has an unexpected shape: ${describeZodIssues(parsed.error)}`,
    );
  }

  const entry = parsed.data.modes.find((candidate) => candidate.mode === mode);
  if (entry === undefined) {
    throw new InputError(`sync report has no entry for mode "${mode}"`);
  }
  return entry.localization ?? [];
}

function humanReport(dir: string, json: GateJson): string[] {
  const { metrics } = json;
  const lines = [
    `bundle ${dir}`,
    `  gate     ${metrics.mode}  ${formatBudgetBytes(metrics.compressedBytes)} / ` +
      `${formatBudgetBytes(metrics.maxCompressedBytes)} compressed  ` +
      `missing ${String(metrics.missingKeys)}/${String(metrics.maxMissingKeys)}  ` +
      `stale ${String(metrics.stalePointers)}  failed ${String(metrics.failedPaths)}`,
    `  datasets ${String(metrics.datasets)}, skipped ${String(metrics.skippedDatasets)}, ` +
      `prune candidates ${String(metrics.pruneCandidates)}`,
  ];

  if (json.failures.length > 0) {
    lines.push(`failures (${String(json.failures.length)}):`);
    for (const entry of json.failures) lines.push(`  ${formatIssue(entry)}`);
  }

  if (json.warnings.length > 0) {
    lines.push(`warnings (${String(json.warnings.length)}):`);
    for (const entry of json.warnings) lines.push(`  ${formatIssue(entry)}`);
  }

  lines.push(
    `${json.ok ? "PASS" : "FAIL"}: ${String(json.failures.length)} failure(s), ` +
      `${String(json.warnings.length)} warning(s)`,
  );
  return lines;
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      dir: { type: "string" },
      report: { type: "string" },
      "max-bytes": { type: "string" },
      json: { type: "boolean", default: false },
    },
  });

  if (values.dir === undefined) {
    throw new InputError("--dir <bundle-dir> is required");
  }

  const maxCompressedBytes = parseMaxBytes(values["max-bytes"]);
  const dir = resolve(process.cwd(), values.dir);
  const { manifestPath, manifest } = await readManifest(dir);

  let entries;
  try {
    entries = await readdir(dir, { withFileTypes: true });
  } catch {
    throw new InputError(`cannot read bundle directory: ${dir}`);
  }

  const files = new Map<string, Uint8Array>();
  const extraFiles: string[] = [];
  for (const entry of entries) {
    if (!entry.isFile()) {
      extraFiles.push(`${entry.name}/`);
      continue;
    }
    if (entry.name === MANIFEST_FILE) continue;
    files.set(entry.name, await readFile(join(dir, entry.name)));
  }

  const reportPath =
    values.report === undefined ? null : resolve(process.cwd(), values.report);
  const localization =
    reportPath === null ? [] : await readLocalization(reportPath, manifest.mode);

  const result = gateBundle({
    manifest,
    files,
    extraFiles,
    localization,
    ...(maxCompressedBytes === undefined ? {} : { maxCompressedBytes }),
  });

  const json: GateJson = {
    dir,
    manifest: manifestPath,
    report: reportPath,
    mode: manifest.mode,
    ok: result.ok,
    failures: result.failures,
    warnings: result.warnings,
    metrics: result.metrics,
  };

  if (values.json) {
    console.log(JSON.stringify(json, null, 2));
  } else {
    for (const line of humanReport(dir, json)) console.log(line);
  }

  process.exitCode = result.ok ? 0 : 1;
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 2;
});
