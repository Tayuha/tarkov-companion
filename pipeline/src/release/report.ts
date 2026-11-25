import type { BundleMode } from "../bundle/index.js";
import type { DatasetSkip, ManifestAction, PublicationPlan, UploadStep } from "./plan.js";
import type { PublicationResult } from "./publish.js";

/**
 * Stable reporting for the publish CLI.
 *
 * `--json` output is a separate, additive shape: it is meant for CI logs and
 * not for clients, which only ever consume the release manifest. Keeping the
 * report here (rather than in the CLI) lets tests assert the exact fields and
 * ordering without spawning the real `gh` client.
 */

export interface ReportUploadStep {
  readonly kind: UploadStep["kind"];
  readonly name: string;
  readonly size: number;
  readonly reason: string;
  readonly dataset?: string;
  readonly sha256?: string;
}

export interface PublicationReport {
  readonly mode: BundleMode;
  readonly tag: string;
  readonly repository: string;
  readonly manifestUrl: string;
  readonly dryRun: boolean;
  readonly release: {
    readonly existed: boolean;
    readonly created: boolean;
  };
  readonly uploads: readonly ReportUploadStep[];
  readonly uploadOrder: readonly string[];
  readonly skip: readonly DatasetSkip[];
  readonly manifestAction: ManifestAction;
  readonly manifestReason: string;
  readonly prune: readonly string[];
  readonly noop: boolean;
  readonly mutations: number;
}

function reportUpload(step: UploadStep): ReportUploadStep {
  if (step.kind === "manifest") {
    return { kind: step.kind, name: step.name, size: step.size, reason: step.reason };
  }
  return {
    kind: step.kind,
    name: step.name,
    size: step.size,
    reason: step.reason,
    dataset: step.dataset,
    sha256: step.sha256,
  };
}

export function planReport(
  plan: PublicationPlan,
  input: {
    readonly tag: string;
    readonly repository: string;
    readonly manifestUrl: string;
    readonly dryRun: boolean;
    readonly release: { readonly existed: boolean; readonly created: boolean };
    readonly mutations: number;
  },
): PublicationReport {
  return {
    mode: plan.mode,
    tag: input.tag,
    repository: input.repository,
    manifestUrl: input.manifestUrl,
    dryRun: input.dryRun,
    release: input.release,
    uploads: plan.uploads.map(reportUpload),
    uploadOrder: plan.uploads.map((step) => step.name),
    skip: plan.skip,
    manifestAction: plan.manifestAction,
    manifestReason: plan.manifestReason,
    prune: plan.prune,
    noop: plan.noop,
    mutations: input.mutations,
  };
}

export function publicationReport(result: PublicationResult): PublicationReport {
  return planReport(result.plan, {
    tag: result.tag,
    repository: result.repository,
    manifestUrl: result.manifestUrl,
    dryRun: result.dryRun,
    release: result.release,
    mutations: result.mutations,
  });
}

function formatBytes(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)} MB`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(2)} kB`;
  return `${value} B`;
}

/** Human-readable lines describing a result or a dry-run plan. */
export function describePublication(result: PublicationResult): string[] {
  const { plan } = result;
  const lines: string[] = [];

  lines.push(`tag      ${result.tag}`);
  lines.push(`manifest ${result.manifestUrl}`);
  lines.push(
    `release  ${result.release.existed ? "exists" : "does not exist"}` +
      (result.release.created ? " (created now)" : ""),
  );
  lines.push(
    `plan     ${String(plan.uploads.length)} upload(s), ${String(plan.skip.length)} skip(s), ` +
      `${String(plan.prune.length)} prune candidate(s)`,
  );

  for (const step of plan.uploads) {
    const label = step.kind === "manifest" ? "manifest" : step.dataset;
    lines.push(
      `  upload   ${step.name.padEnd(32)} ${formatBytes(step.size).padStart(10)}  ` +
        `${label}: ${step.reason}`,
    );
  }
  for (const entry of plan.skip) {
    lines.push(
      `  skip     ${entry.name.padEnd(32)} ${formatBytes(entry.size).padStart(10)}  ${entry.reason}`,
    );
  }
  for (const name of plan.prune) {
    lines.push(`  prune    ${name.padEnd(32)} ${"".padStart(10)}  not referenced by the new manifest`);
  }

  lines.push(`manifest ${plan.manifestAction}: ${plan.manifestReason}`);

  if (result.dryRun) {
    lines.push("dry-run: no API mutations performed");
  } else if (result.mutations === 0) {
    lines.push("no changes: nothing published");
  } else {
    lines.push(
      `published ${result.uploaded.length} upload(s), ${result.deleted.length} deletion(s)`,
    );
  }

  return lines;
}
