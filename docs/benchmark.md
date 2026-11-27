# Ingestion benchmark

The full items dataset is the largest thing the client ingests. Task 4.8 added
an offline benchmark that proves one ingestion fits the design budgets on the
real published asset, and runs it on the Windows CI runner, which is the launch
target and the only place Windows code is exercised.

## What runs

`app/packages/data/test/sync/ingest_benchmark_test.dart`, tagged `benchmark`:

1. Reads the committed fixture manifest and the real `items` asset.
2. Asserts the compressed asset is at most **10 MiB** (`10 * 1024 * 1024`
   bytes) — design D7's per-mode download budget.
3. Counts the `kind == "item"` lines with the same streaming reader ingestion
   uses, before the timer starts.
4. Opens a file-backed drift database in a temporary directory.
5. Records `ProcessInfo.currentRss` and `ProcessInfo.maxRss`, runs
   `DatasetIngestor.ingest` on the full asset, and records them again.
6. Asserts the manifest's `records`, the ingest result and the stored
   `datasetState.records` all agree, and that the `items` table has exactly one
   row per `item` line.
7. Asserts FTS matches the M4A1 (`5447a9cd4bdc2dbd208b4567`) for `m4a1`.
8. Asserts the wall-clock ingest and the RSS growth stay under the budgets
   below.
9. Closes the database and deletes the temporary directory in `tearDown`.

The fixture is committed; the test opens no socket. Provenance, checksums and
refresh steps are in
[`app/packages/data/test/fixtures/benchmark/README.md`](../app/packages/data/test/fixtures/benchmark/README.md).

## Measured results

Fixture: `items-ed751dcd264d.jsonl.zst` from `data-regular-latest`, downloaded
2026-11-26 (see the fixture README). 1,433,154 compressed bytes, 17,417,643
uncompressed bytes, 6,015 records, 5,498 of them items.

Local development host (Linux x86_64, `dart test`, three consecutive runs):

| Metric | Run 1 | Run 2 | Run 3 |
|---|---|---|---|
| Ingest wall clock | 978 ms | 1,044 ms | 991 ms |
| `currentRss` delta | 30.9 MB | 32.4 MB | 32.2 MB |
| `maxRss` delta | 23.5 MB | 24.8 MB | 14.5 MB |

The measured window is the `DatasetIngestor.ingest` call only: streaming zstd
decode, JSONL parsing, batched inserts, FTS trigger maintenance, the
`datasetState` write and the commit. Opening the database and counting item
lines are outside it.

## Budgets and why

| Budget | Value | Rationale |
|---|---|---|
| Compressed asset | 10 MiB | Design D7. The full seven-dataset `regular` bundle is ~2.36 MB today; items alone is 1.37 MiB, so this fails only on a real regression. |
| Ingest wall clock | 4,000 ms | ~3.7x the ~1.06 s local median. `windows-latest` runners are slower and noisier than the development host, so a literal 1:1 budget would flake; 4 s still catches an order-of-magnitude regression. |
| RSS growth | 256 MiB | A coarse ceiling, not an allocator measurement. It catches an accidental whole-dataset materialisation (the streaming contract would be violated) without reacting to JIT, SQLite page cache or GC noise. Observed peak growth is ~15–25 MB. |

### The RSS number is deliberately coarse

`ProcessInfo.maxRss` is the process-lifetime resident-set high-water mark, not
"memory used by this ingest". The test runner, the pure-Dart zstd decoder,
drift, SQLite and the JIT all live in that one process, and the OS decides which
pages stay resident. The assertion therefore treats RSS growth as a bound, not
an exact figure: a pass proves ingestion did not allocate on the order of the
whole 17 MB payload many times over, which is what a one-shot decode or an
unbounded row buffer would do. It does not prove an exact peak.

`ProcessInfo.currentRss` is recorded in the log line as a secondary signal, but
the assertion uses `maxRss` because the current value can fall again after a
collection.

## Running it

Locally against the committed fixture:

```bash
cd app
dart test packages/data -t benchmark -j 1
```

The test prints one line with every measured value so CI logs are enough to
compare runs:

```
ingest-benchmark: compressed=1433154B records=6015 items=5498 ingest=991ms rssCurrentDelta=32153600 rssMaxDelta=14454784 (budgets: 10485760B, 4000ms, 268435456B)
```

The normal suite stays fast by excluding the tag:

```bash
cd app
dart test packages/data --exclude-tags benchmark
```

## CI

`.github/workflows/ci.yml`:

- **App (Windows)** runs `dart test packages/data -t benchmark -j 1` from `app/`
  after `flutter test`. This is the verification for task 4.8: the benchmark
  must pass on `windows-latest`, not only on the Linux development host.
- **App (Linux)** runs `dart test packages/data --exclude-tags benchmark`, so
  the fast feedback loop never pays for the full dataset.
- **Pipeline** is unaffected; the fixture is a client-side copy of a published
  asset.

`-j 1` keeps the measurement free of other test isolates competing for CPU and
memory, which would make the time and RSS numbers meaningless.

## Catalog query and first-render budget (task 5.9)

Task 5.9 adds two assertions against the same full items fixture (5,498 items):

* `app/packages/data/test/catalog/catalog_benchmark_test.dart`, tagged
  `benchmark`, ingests the published items asset, warms seven representative
  queries (unfiltered, paged, FTS, category, flea-sorted, weight-sorted,
  ammo+base-price) and measures 200 `CatalogRepository.query` calls. The
  assertion is **p95 under 50 ms**, far above the ~9 ms observed locally:
  `catalog query p95: 9.02 ms over 200 queries (5498 items)`
  (Linux x86_64, 2026-11-27).
* `app/packages/features/test/catalog/catalog_performance_test.dart` pumps the
  real `CatalogScreen` against the same ingested fixture and times the first
  page: `catalog first render: 591 ms` locally, against a **1.5 s** budget.

The query test is tagged `benchmark`, so it joins the existing Windows
`-t benchmark` job and is excluded from the fast `--exclude-tags benchmark`
run. The first-render test is not tagged: `flutter test packages/features`
runs it in both CI app jobs.
