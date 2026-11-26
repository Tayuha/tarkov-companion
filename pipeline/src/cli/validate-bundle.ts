import { readdir, readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { MANIFEST_FILE } from "../bundle/index.js";
import {
  validateBundle,
  type BundleValidationIssue,
  type BundleValidationResult,
} from "../bundle/validate.js";

/**
 * Validate a bundle directory against the contract in `docs/data-bundles.md`.
 *
 *   npm run validate:bundle -- --dir dist/bundles/regular
 *   npm run validate:bundle -- --dir test/fixtures/handbuilt-bundle --json
 *
 * Reads `<dir>/manifest.json` and every file next to it. No network access.
 * Exits 1 on any error; unknown extra files are warnings only.
 */

interface ValidationJson {
  readonly dir: string;
  readonly manifest: string;
  readonly ok: boolean;
  readonly mode: string | null;
  readonly generatedAt: string | null;
  readonly datasets: BundleValidationResult["datasets"];
  readonly errors: readonly BundleValidationIssue[];
  readonly warnings: readonly BundleValidationIssue[];
}

function shortChecksum(sha256: string | null): string {
  return sha256 === null ? "-" : sha256.slice(0, 12);
}

function formatIssue(issue: BundleValidationIssue): string {
  return `[${issue.code}] ${issue.message}`;
}

function humanReport(dir: string, result: BundleValidationResult): string[] {
  const lines: string[] = [];
  lines.push(`bundle ${dir}`);
  lines.push(`  mode ${result.mode ?? "<invalid>"}  generatedAt ${result.generatedAt ?? "<invalid>"}`);

  for (const dataset of result.datasets) {
    lines.push(
      `  ${dataset.ok ? "ok  " : "FAIL"} ${dataset.dataset.padEnd(9)} ` +
        `${String(dataset.records ?? "?").padStart(5)} records  ` +
        `${String(dataset.compressedBytes ?? "?").padStart(8)} B  ` +
        `sha256 ${shortChecksum(dataset.sha256)}  ${dataset.path}`,
    );
  }

  if (result.errors.length > 0) {
    lines.push(`errors (${String(result.errors.length)}):`);
    for (const entry of result.errors) lines.push(`  ${formatIssue(entry)}`);
  }

  if (result.warnings.length > 0) {
    lines.push(`warnings (${String(result.warnings.length)}):`);
    for (const entry of result.warnings) lines.push(`  ${formatIssue(entry)}`);
  }

  lines.push(
    `${result.ok ? "PASS" : "FAIL"}: ${String(result.datasets.length)} dataset(s), ` +
      `${String(result.errors.length)} error(s), ${String(result.warnings.length)} warning(s)`,
  );

  return lines;
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      dir: { type: "string" },
      json: { type: "boolean", default: false },
    },
  });

  if (values.dir === undefined) {
    throw new Error("--dir <bundle-dir> is required");
  }

  const dir = resolve(process.cwd(), values.dir);
  const manifestPath = join(dir, MANIFEST_FILE);

  let manifestText: string;
  try {
    manifestText = await readFile(manifestPath, "utf8");
  } catch (error) {
    const code = (error as { readonly code?: unknown }).code;
    const reason = code === "ENOENT" ? "manifest.json not found" : "cannot read manifest.json";
    console.error(`${reason}: ${manifestPath}`);
    process.exitCode = 1;
    return;
  }

  const entries = await readdir(dir, { withFileTypes: true });
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

  const result = validateBundle({ manifestText, files, extraFiles });

  if (values.json) {
    const report: ValidationJson = {
      dir,
      manifest: manifestPath,
      ok: result.ok,
      mode: result.mode,
      generatedAt: result.generatedAt,
      datasets: result.datasets,
      errors: result.errors,
      warnings: result.warnings,
    };
    console.log(JSON.stringify(report, null, 2));
  } else {
    for (const line of humanReport(dir, result)) console.log(line);
  }

  if (!result.ok) process.exitCode = 1;
}

main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
