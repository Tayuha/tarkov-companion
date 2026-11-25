import { resolve } from "node:path";
import { parseArgs } from "node:util";
import { ManifestError } from "../bundle/index.js";
import { validateMode } from "../release/assets.js";
import { ReleaseError } from "../release/errors.js";
import { publishBundle } from "../release/publish.js";
import { describePublication, publicationReport } from "../release/report.js";

/**
 * Publish a built bundle to its rolling GitHub release.
 *
 *   npm run bundle -- --all
 *   npm run publish -- --mode regular --dry-run
 *   npm run publish -- --mode regular
 *   npm run publish -- --mode regular --tag data-test-regular-latest
 *   npm run publish -- --mode regular --prune
 *
 * `--dry-run` still reads the release (so the plan is accurate) but performs no
 * create/upload/delete. `--prune` deletes dataset assets the new manifest does
 * not reference; it removes rollback capability and is off by default.
 */

const DEFAULT_BUNDLES_DIR = "dist/bundles";

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      mode: { type: "string" },
      bundles: { type: "string" },
      tag: { type: "string" },
      "dry-run": { type: "boolean", default: false },
      prune: { type: "boolean", default: false },
      json: { type: "boolean", default: false },
    },
  });

  if (values.mode === undefined) {
    throw new ReleaseError(
      "invalid-mode",
      "--mode is required (regular, pve or pvp-season)",
    );
  }
  const mode = validateMode(values.mode);
  const bundlesDir = resolve(process.cwd(), values.bundles ?? DEFAULT_BUNDLES_DIR);

  const result = await publishBundle({
    bundlesDir,
    mode,
    dryRun: values["dry-run"],
    prune: values.prune,
    ...(values.tag === undefined ? {} : { tag: values.tag }),
  });

  if (values.json) {
    console.log(JSON.stringify(publicationReport(result), null, 2));
    return;
  }

  for (const line of describePublication(result)) console.log(line);
}

main().catch((error: unknown) => {
  if (error instanceof ReleaseError) {
    console.error(`${error.kind}: ${error.message}`);
  } else if (error instanceof ManifestError) {
    console.error(`${error.kind}: ${error.message}`);
  } else {
    console.error(error instanceof Error ? error.message : error);
  }
  process.exitCode = 1;
});
