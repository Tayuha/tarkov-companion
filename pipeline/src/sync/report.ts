import type { ModeSyncSummary, SyncReport } from "./types.js";

/**
 * Human-readable sync summary.
 *
 * Kept out of the CLI so tests can assert the exact per-mode counters
 * (`fetched` / `304` / `reused`), the budget line and the publish outcome
 * without capturing console output.
 */

function formatBytes(value: number): string {
  if (value >= 1_000_000) return `${(value / 1_000_000).toFixed(2)} MB`;
  if (value >= 1_000) return `${(value / 1_000).toFixed(2)} kB`;
  return `${value} B`;
}

function formatBudget(value: number): string {
  if (value >= 1024 * 1024) return `${(value / (1024 * 1024)).toFixed(2)} MiB`;
  if (value >= 1024) return `${(value / 1024).toFixed(2)} kB`;
  return `${value} B`;
}

function describeMode(mode: ModeSyncSummary): string[] {
  const lines: string[] = [];

  if (mode.status === "failed") {
    lines.push(
      `${mode.mode}: FAILED — ${String(mode.datasets.length)} dataset(s) prepared, ` +
        `${String(mode.errors.length)} error(s), nothing published`,
    );
  } else {
    lines.push(
      `${mode.mode}: ${mode.status} — ${String(mode.datasets.length)} dataset(s)`,
    );
  }

  lines.push(
    `  sources  fetched ${String(mode.fetched)} ` +
      `(${String(mode.refetched)} forced re-fetch), ` +
      `304 ${String(mode.notModified)}, reused ${String(mode.reused)}`,
  );

  for (const entry of mode.entries) {
    lines.push(
      `  ${entry.dataset.padEnd(8)} ${String(entry.records).padStart(6)} records  ` +
        `${formatBytes(entry.uncompressedBytes).padStart(9)} -> ` +
        `${formatBytes(entry.compressedBytes).padStart(9)}  ` +
        `sha256 ${entry.sha256.slice(0, 12)}`,
    );
  }

  if (mode.totals !== null) {
    lines.push(
      `  totals   ${String(mode.totals.records).padStart(6)} records  ` +
        `${formatBytes(mode.totals.uncompressedBytes).padStart(9)} -> ` +
        `${formatBytes(mode.totals.compressedBytes).padStart(9)}`,
    );
  }

  for (const entry of mode.localization) {
    lines.push(
      `  localize ${entry.dataset.padEnd(8)} missing ${String(entry.missingKeys)}, ` +
        `failed ${String(entry.failedPaths.length)}, ` +
        `stale ${String(entry.stalePointers.length)}`,
    );
  }

  if (mode.gate !== null) {
    lines.push(
      `  gate     ${mode.gate.ok ? "passed" : "FAILED"} — ` +
        `${formatBudget(mode.gate.metrics.compressedBytes)} compressed ` +
        `(budget ${formatBudget(mode.gate.metrics.maxCompressedBytes)}), ` +
        `${String(mode.gate.metrics.missingKeys)} missing key(s), ` +
        `${String(mode.gate.metrics.stalePointers)} stale pointer(s)`,
    );
  }

  if (mode.publication !== null) {
    const publication = mode.publication;
    const tags = [
      publication.offlinePlan ? "offline plan" : null,
      publication.noop ? "no changes" : null,
      publication.releaseCreated ? "release created" : null,
    ].filter((tag): tag is string => tag !== null);
    lines.push(
      `  publish  ${publication.tag}  ${String(publication.uploads.length)} upload(s), ` +
        `${String(publication.skips)} skip(s), ` +
        `${String(publication.mutations)} mutation(s)` +
        (tags.length === 0 ? "" : ` [${tags.join(", ")}]`),
    );
    lines.push(`  manifest ${publication.manifestUrl}`);
  }

  for (const failure of mode.errors) {
    const target = failure.dataset === null ? mode.mode : `${mode.mode}/${failure.dataset}`;
    lines.push(`  error    ${target}: ${failure.message}`);
  }

  return lines;
}

export function describeSyncReport(report: SyncReport): string[] {
  const lines: string[] = [`sync ${report.generatedAt}`];

  for (const mode of report.modes) {
    lines.push(...describeMode(mode));
  }

  const count = (status: ModeSyncSummary["status"]): number =>
    report.modes.filter((mode) => mode.status === status).length;

  const parts: string[] = [
    `${String(report.modes.length)} mode(s)`,
    `${String(count("published"))} published`,
    `${String(count("noop"))} no-op`,
    `${String(count("dry-run"))} dry-run`,
    `${String(count("failed"))} failed`,
  ];
  lines.push(`summary ${parts.join(", ")}`);

  return lines;
}
