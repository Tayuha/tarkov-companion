import { resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  ManifestError,
  compareBundles,
  describeComparison,
  readManifestFile,
  type BundleComparison,
  type BundleManifest,
} from "../bundle/index.js";

/**
 * Compare two bundle manifests without building anything.
 *
 *   npm run compare -- --previous old/regular/manifest.json --current new/regular/manifest.json
 *   npm run compare -- --previous old/regular/manifest.json --current new/regular/manifest.json --json
 *
 * Exit codes: `0` whenever both manifests are valid and comparable, whether or
 * not there are changes (this command only reports); `1` on invalid input, so
 * a scheduled job can tell "same data" from "could not read the baseline".
 */

interface CompareJson {
  readonly mode: string;
  readonly hasChanges: boolean;
  readonly added: readonly string[];
  readonly changed: readonly string[];
  readonly unchanged: readonly string[];
  readonly removed: readonly string[];
  readonly reasons: Readonly<Record<string, string>>;
  readonly previous: { readonly path: string; readonly generatedAt: string };
  readonly current: { readonly path: string; readonly generatedAt: string };
}

function jsonReport(
  previousPath: string,
  previous: BundleManifest,
  currentPath: string,
  current: BundleManifest,
  comparison: BundleComparison,
): CompareJson {
  return {
    mode: current.mode,
    hasChanges: comparison.hasChanges,
    added: comparison.added,
    changed: comparison.changed,
    unchanged: comparison.unchanged,
    removed: comparison.removed,
    reasons: comparison.reasons,
    previous: { path: previousPath, generatedAt: previous.generatedAt },
    current: { path: currentPath, generatedAt: current.generatedAt },
  };
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      previous: { type: "string" },
      current: { type: "string" },
      json: { type: "boolean", default: false },
    },
  });

  if (values.previous === undefined || values.current === undefined) {
    throw new Error("both --previous <manifest path> and --current <manifest path> are required");
  }

  const previousPath = resolve(process.cwd(), values.previous);
  const currentPath = resolve(process.cwd(), values.current);

  const previous = await readManifestFile(previousPath);
  const current = await readManifestFile(currentPath);
  const comparison = compareBundles(previous, current);

  if (values.json) {
    console.log(
      JSON.stringify(jsonReport(previousPath, previous, currentPath, current, comparison), null, 2),
    );
    return;
  }

  console.log(`previous ${previousPath} (generated ${previous.generatedAt})`);
  console.log(`current  ${currentPath} (generated ${current.generatedAt})`);
  console.log(`mode: ${current.mode}`);
  for (const line of describeComparison(comparison)) console.log(line);
}

main().catch((error: unknown) => {
  if (error instanceof ManifestError) {
    console.error(`${error.kind}: ${error.message}`);
  } else {
    console.error(error instanceof Error ? error.message : error);
  }
  process.exitCode = 1;
});
