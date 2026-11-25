import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  buildBundle,
  writeBundle,
  type BuiltBundle,
  type BundleDatasetSource,
  type BundleManifest,
  type BundleMode,
  type ManifestDatasetEntry,
  type ManifestTotals,
} from "../bundle/index.js";
import {
  defaultTag,
  planPublication,
  publishBundle,
  resolveRepository,
  stableManifestUrl,
  type PublicationPlan,
  type ReleaseClient,
} from "../release/index.js";
import {
  normalizeDataset,
  serializeJsonl,
  type BundleRecord,
  type NormalizeDataset,
} from "../normalize/index.js";
import { formatIssues, parseDatasetData } from "../schemas/registry.js";
import type {
  DatasetOutcome,
  DatasetProvider,
  DatasetSourceMeta,
  DatasetSyncSummary,
  ModePublication,
  ModeSyncSummary,
  SyncFailure,
  SyncReport,
} from "./types.js";
import type { NormalizedDatasetCacheStore } from "./normalized-cache.js";
import { parseJsonlRecords } from "./normalized-cache.js";

/**
 * Production sync orchestration: fetch -> validate -> normalize -> bundle ->
 * publish, for every requested mode.
 *
 * Failure policy:
 *
 * - A dataset that fails validation or normalization blocks its whole mode.
 *   Publishing the remaining datasets would silently remove the failed one from
 *   the manifest and make clients delete its rows.
 * - Every mode is attempted, even after another mode failed, and the report
 *   carries all errors so the workflow can exit 1 with a complete summary.
 * - Publication only starts after the whole mode is built. `publishBundle`
 *   uploads dataset assets first and the manifest last, so a failure before the
 *   swap can never leave a manifest that points at missing bytes.
 * - A mode whose content did not change still builds (locally) but the
 *   publisher makes zero API mutations, which is the documented no-op.
 */

export interface SyncOptions {
  readonly modes: readonly BundleMode[];
  readonly provider: DatasetProvider;
  readonly normalizedCache: NormalizedDatasetCacheStore;
  /**
   * Release client. Omit to use the real `gh` client, pass `null` for an
   * offline plan-only run (requires `dryRun`), or inject a test double.
   */
  readonly releaseClient?: ReleaseClient | null;
  /** Root for the written bundle. */
  readonly outDir: string;
  readonly dryRun?: boolean;
  /** Bypass stored conditional-request validators. */
  readonly force?: boolean;
  readonly lang?: string;
  readonly repository?: string;
  readonly now?: () => Date;
  /** Progress log sink; defaults to `console.log`. */
  readonly log?: (line: string) => void;
}

interface PreparedDataset {
  readonly records: readonly BundleRecord[];
  readonly meta: DatasetSourceMeta;
  readonly outcome: DatasetOutcome;
}

interface Counters {
  fetched: number;
  notModified: number;
  reused: number;
  refetched: number;
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function earliestTimestamp(values: readonly (string | null | undefined)[]): string | null {
  const present = values.filter((value): value is string => typeof value === "string");
  if (present.length === 0) return null;
  return present.reduce((min, value) => (value < min ? value : min));
}

async function prepareDataset(input: {
  readonly mode: BundleMode;
  readonly dataset: NormalizeDataset;
  readonly provider: DatasetProvider;
  readonly cache: NormalizedDatasetCacheStore;
  readonly lang: string;
  readonly force: boolean;
  readonly log: (line: string) => void;
}): Promise<PreparedDataset> {
  const { mode, dataset, provider, cache, lang, force, log } = input;

  let result = await provider.fetch({ mode, dataset, forceRefresh: force });
  let outcome: DatasetOutcome = "fetched";

  if (result.status === "not-modified") {
    const cached = await cache.get({ mode, dataset, lang, checksum: result.checksum });
    if (cached !== undefined) {
      const records = parseJsonlRecords(dataset, cached);
      log(
        `  ${mode}/${dataset}: 304 Not Modified, reusing cached normalized JSONL ` +
          `(${String(records.length)} records)`,
      );
      return { records, meta: result.meta, outcome: "reused" };
    }

    log(
      `  ${mode}/${dataset}: 304 Not Modified but the normalized cache is missing; ` +
        `retrying unconditionally`,
    );
    result = await provider.fetch({ mode, dataset, forceRefresh: true });
    if (result.status === "not-modified") {
      throw new Error(
        "upstream returned 304 for an unconditional request and no normalized cache exists",
      );
    }
    outcome = "refetched";
  }

  const parsed = parseDatasetData(mode, dataset, result.data);
  if (!parsed.success) {
    throw new Error(`validation failed: ${formatIssues(parsed.error)}`);
  }

  const normalized = normalizeDataset(dataset, parsed.data);
  const jsonl = serializeJsonl(normalized.records);
  await cache.set({ mode, dataset, lang, checksum: result.checksum }, jsonl);

  log(
    `  ${mode}/${dataset}: fetched and validated, ` +
      `${String(normalized.records.length)} records` +
      (outcome === "refetched" ? " (forced re-fetch)" : ""),
  );

  return { records: normalized.records, meta: result.meta, outcome };
}

function publicationFromResult(
  result: Awaited<ReturnType<typeof publishBundle>>,
): ModePublication {
  return {
    tag: result.tag,
    manifestUrl: result.manifestUrl,
    uploads: result.plan.uploads.map((step) => step.name),
    skips: result.plan.skip.length,
    mutations: result.mutations,
    noop: result.plan.noop,
    offlinePlan: false,
    releaseExisted: result.release.existed,
    releaseCreated: result.release.created,
  };
}

function offlinePublication(mode: BundleMode, manifest: BundleManifest, repository: string): {
  readonly publication: ModePublication;
} {
  const plan: PublicationPlan = planPublication(manifest, null, []);
  const tag = defaultTag(mode);
  return {
    publication: {
      tag,
      manifestUrl: stableManifestUrl(tag, repository),
      uploads: plan.uploads.map((step) => step.name),
      skips: plan.skip.length,
      mutations: 0,
      noop: false,
      offlinePlan: true,
      releaseExisted: false,
      releaseCreated: false,
    },
  };
}

async function publishMode(input: {
  readonly mode: BundleMode;
  readonly bundle: BuiltBundle;
  readonly dryRun: boolean;
  readonly outDir: string;
  readonly releaseClient: ReleaseClient | null | undefined;
  readonly repository: string;
}): Promise<ModePublication> {
  const { mode, bundle, dryRun, outDir, releaseClient, repository } = input;

  if (releaseClient === null) {
    if (!dryRun) {
      throw new Error("offline plan-only publication requires --dry-run");
    }
    return offlinePublication(mode, bundle.manifest, repository).publication;
  }

  const bundlesDir = dryRun ? await mkdtemp(join(tmpdir(), "tarkov-sync-")) : outDir;
  try {
    await writeBundle(bundle, { outDir: bundlesDir });
    const result = await publishBundle({
      bundlesDir,
      mode,
      dryRun,
      repository,
      ...(releaseClient === undefined ? {} : { client: releaseClient }),
    });
    return publicationFromResult(result);
  } finally {
    if (dryRun) {
      await rm(bundlesDir, { recursive: true, force: true });
    }
  }
}

function failedSummary(
  mode: BundleMode,
  datasets: readonly DatasetSyncSummary[],
  counters: Counters,
  errors: readonly SyncFailure[],
  totals: ManifestTotals | null = null,
  entries: readonly ManifestDatasetEntry[] = [],
): ModeSyncSummary {
  return {
    mode,
    status: "failed",
    datasets,
    fetched: counters.fetched,
    notModified: counters.notModified,
    reused: counters.reused,
    refetched: counters.refetched,
    totals,
    entries,
    publication: null,
    errors,
  };
}

export async function syncMode(input: {
  readonly mode: BundleMode;
  readonly provider: DatasetProvider;
  readonly normalizedCache: NormalizedDatasetCacheStore;
  readonly releaseClient: ReleaseClient | null | undefined;
  readonly outDir: string;
  readonly dryRun: boolean;
  readonly force: boolean;
  readonly lang: string;
  readonly repository: string;
  readonly generatedAt: string;
  readonly log: (line: string) => void;
}): Promise<ModeSyncSummary> {
  const {
    mode,
    provider,
    normalizedCache,
    releaseClient,
    outDir,
    dryRun,
    force,
    lang,
    repository,
    generatedAt,
    log,
  } = input;

  const datasets: DatasetSyncSummary[] = [];
  const errors: SyncFailure[] = [];
  const recordsByDataset: Record<string, readonly BundleRecord[]> = {};
  const sourceByDataset: Record<string, BundleDatasetSource> = {};
  const counters: Counters = { fetched: 0, notModified: 0, reused: 0, refetched: 0 };

  let modeDatasets: readonly NormalizeDataset[];
  try {
    modeDatasets = await provider.datasets(mode);
    if (modeDatasets.length === 0) {
      throw new Error("no bundlable datasets are available");
    }
  } catch (error) {
    errors.push({ mode, dataset: null, message: errorMessage(error) });
    return failedSummary(mode, datasets, counters, errors);
  }

  for (const dataset of modeDatasets) {
    try {
      const prepared = await prepareDataset({
        mode,
        dataset,
        provider,
        cache: normalizedCache,
        lang,
        force,
        log,
      });
      recordsByDataset[dataset] = prepared.records;
      sourceByDataset[dataset] = prepared.meta;
      datasets.push({ dataset, outcome: prepared.outcome, records: prepared.records.length });

      if (prepared.outcome === "reused") {
        counters.reused += 1;
        counters.notModified += 1;
      } else if (prepared.outcome === "refetched") {
        counters.refetched += 1;
        counters.notModified += 1;
        counters.fetched += 1;
      } else {
        counters.fetched += 1;
      }
    } catch (error) {
      const message = errorMessage(error);
      errors.push({ mode, dataset, message });
      log(`  ${mode}/${dataset}: FAILED — ${message}`);
    }
  }

  if (errors.length > 0) {
    log(
      `  ${mode}: build blocked by ${String(errors.length)} dataset failure(s); ` +
        "nothing published",
    );
    return failedSummary(mode, datasets, counters, errors);
  }

  const source = await provider.source(mode);
  const bundle = buildBundle(
    {
      mode,
      datasets: recordsByDataset,
      sourceMeta: {
        baseUrl: source.baseUrl,
        capturedAt:
          source.capturedAt ??
          earliestTimestamp(Object.values(sourceByDataset).map((meta) => meta.fetchedAt)),
        datasets: sourceByDataset,
      },
    },
    generatedAt,
  );

  let publication: ModePublication;
  try {
    publication = await publishMode({
      mode,
      bundle,
      dryRun,
      outDir,
      releaseClient,
      repository,
    });
  } catch (error) {
    const message = errorMessage(error);
    errors.push({ mode, dataset: null, message: `publication failed: ${message}` });
    log(`  ${mode}: publication failed — ${message}`);
    return failedSummary(
      mode,
      datasets,
      counters,
      errors,
      bundle.manifest.totals,
      bundle.manifest.datasets,
    );
  }

  const status = dryRun ? "dry-run" : publication.mutations === 0 ? "noop" : "published";
  log(
    `  ${mode}: ${status}, ${String(publication.uploads.length)} upload(s), ` +
      `${String(publication.skips)} skip(s), ${String(publication.mutations)} mutation(s)`,
  );

  return {
    mode,
    status,
    datasets,
    fetched: counters.fetched,
    notModified: counters.notModified,
    reused: counters.reused,
    refetched: counters.refetched,
    totals: bundle.manifest.totals,
    entries: bundle.manifest.datasets,
    publication,
    errors,
  };
}

export async function runSync(options: SyncOptions): Promise<SyncReport> {
  const now = options.now ?? (() => new Date());
  const log = options.log ?? ((line: string) => console.log(line));
  const dryRun = options.dryRun ?? false;
  const force = options.force ?? false;
  const lang = options.lang ?? "en";
  const repository = options.repository ?? resolveRepository();
  const generatedAt = now().toISOString();

  const modes: ModeSyncSummary[] = [];
  for (const mode of options.modes) {
    log(`${mode}: syncing`);
    modes.push(
      await syncMode({
        mode,
        provider: options.provider,
        normalizedCache: options.normalizedCache,
        releaseClient: options.releaseClient,
        outDir: options.outDir,
        dryRun,
        force,
        lang,
        repository,
        generatedAt,
        log,
      }),
    );
  }

  const failed = modes.filter((mode) => mode.status === "failed").length;
  return { generatedAt, modes, exitCode: failed > 0 ? 1 : 0 };
}
