# Client sync protocol

This page specifies how the installed app keeps its local game data current:
what it requests, in which order, what becomes visible when, and what happens
when a step fails. It is the client-side counterpart of the pipeline
operations in [`data-sync.md`](data-sync.md).

Companion documents:

| Document | Covers |
|---|---|
| [`data-bundles.md`](data-bundles.md) | Byte-level bundle contract: layout, manifest fields, checksums, asset naming, version policy. |
| [`client-sync.md`](client-sync.md) | Field-by-field implementation notes for the manifest cache, downloader, and ingestor. |
| [`network.md`](network.md) | Host allowlist, TLS, redirects, and the HTTP client policy. |
| [`schema.md`](schema.md) | Local tables, migrations, recovery mode, and the no-cascade guarantee. |
| [`freshness.md`](freshness.md) | Price-freshness labelling, which is independent of catalog freshness. |
| [`sync-scheduler.md`](sync-scheduler.md) | When automatic checks may run and how failures back off. |

The spec is
[`specs/data-sync/spec.md`](../openspec/changes/bootstrap-tarkov-companion/specs/data-sync/spec.md)
(plus the startup/offline clauses of
[`specs/app-shell/spec.md`](../openspec/changes/bootstrap-tarkov-companion/specs/app-shell/spec.md)).

## Implementation boundary

The data package implements the four sync stages and the scheduling policy as
independent, injectable pieces:

| Stage | Type | Writes |
|---|---|---|
| Manifest fetch | `ManifestFetcher` + `ManifestRepository` | `remoteManifest` only |
| Dataset download | `DatasetDownloader` | `<destination>.part`, then the dataset file |
| Decompression + ingestion | `JsonlLineReader` + `DatasetIngestor` | Game-data rows and `datasetState`, in one transaction |
| Scheduling | `SyncScheduler` | calls an injected `SyncRunner`; no I/O itself |

The shell composes them (fetch → compatibility → select → download → ingest)
and owns the first-run and offline screens. Those shell tasks (8.1–8.4) are not
part of this change yet. This document describes the contract that composition
must follow and the states the data layer already guarantees. Every state in
[State → test map](#state--test-map) is reproducible from a committed test;
states owned by an unimplemented shell screen are identified as such rather
than claimed as behavior.

Everything below is per game mode (`regular`, `pve`, `pvp-season`). Modes have
separate manifest URLs, cache rows, dataset files, and `datasetState` rows; one
mode's `304`, `404`, or invalid document never touches another.

## Startup and the local read path

The local SQLite database is the only read path. Startup does not depend on the
network:

1. **Open the database.** `openAppDatabase` runs the versioned migrations (with
   a pre-migration copy when a migration is needed) and returns either a
   writable `DatabaseOpened` or a read-only `DatabaseRecovery`. Reopening an
   existing file is idempotent and keeps every row, including the FTS index
   (`P1`).
2. **Serve what is applied.** Screens query `items`, `tasks`, `traders`,
   `hideoutStations`, `crafts`, `barters`, `maps`, `gameRecords`, FTS, and
   player tables. No sync stage is consulted by a query. On a fresh database
   there is simply no applied dataset (`P2`).
3. **Check in the background.** `SyncScheduler.start()` reads the last
   successful check time, subscribes to network and visibility changes, and
   arms one timer. It never performs a request itself; a `SyncRunner` does the
   work when the policy allows it (`P4`). With no recorded check, the due time
   is "now", so the check is scheduled immediately but still asynchronously.
4. **Render first, update later.** A dataset update is written by the download
   and ingest stages, never by the read path. The current view therefore keeps
   working while a check runs; the shell must not await the check before its
   first frame (task 8.2).
5. **First run with no data.** There is no applied dataset and no cached
   manifest (`P3`). The shell must show the bootstrap flow, not an empty
   catalog (task 8.1). If the first run is also offline, the fetch produces no
   cache and no applied data, so the bootstrap flow must offer retry (`P5`).

## One sync pass

```
background check (scheduler allows it)
  |
  v
ManifestFetcher.fetch(mode)
  |  GET data-<mode>-latest/manifest.json
  |  If-None-Match / If-Modified-Since when cached
  |
  +-- 304 Not Modified
  |     markChecked(mode, now)
  |     parse the cached body
  |     no dataset request
  |
  +-- 200 OK
        strict UTF-8 -> JSON -> BundleManifest.parse
        mode must match the requested mode
        recordCheck(...)
        BundleManifest.checkCompatibility()
          |
          +-- incompatible -> keep current data, ask for an app update
          |
          +-- compatible -> select datasets whose applied checksum,
                            schema version, or record count differs
                              |
                              v
                        for each selected dataset:
                          DatasetDownloader.download(...)
                            resolve entry.path against the manifest URL
                            GET -> stream to <destination>.part
                            verify compressedBytes + SHA-256
                            rename over <destination>
                              |
                              v
                          DatasetIngestor.ingest(...)
                            one transaction: delete, stream, insert,
                            verify record count, write datasetState
                            commit
```

The manifest is authoritative for which datasets exist and which bytes they
are. `generatedAt`, `source.*`, sizes, record counts, and `totals` are
diagnostics; a rebuild that only moves `generatedAt` must not trigger a
download.

### Manifest fetch

The only URL the fetcher builds is the stable release asset:

```
https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json
```

It never builds a dataset URL. Rules:

- The cached `ETag` and `Last-Modified` are sent as `If-None-Match` and
  `If-Modified-Since`. Missing validators are omitted rather than sent empty.
- A `304` moves only `lastCheckedAt`, parses the cached body, and reports
  `ManifestNotModified`. It never starts a dataset request (`MF2`).
- A `200` is decoded as strict UTF-8, parsed as JSON, validated by
  `BundleManifest.parse`, and rejected if its declared `mode` differs from the
  requested mode. A valid document replaces the cache row (`MF1`).
- Change detection is the SHA-256 of the raw body, not the `ETag`. A `200`
  whose body is identical but whose validator moved updates the validators and
  `lastCheckedAt` without moving `lastChangedAt` (`MF4`). A changed body moves
  both (`MF3`).
- The cache is one row per mode (`remoteManifest`), isolated per mode
  (`MF5`), and no ingestion path writes it.

The cache row is a convenience for conditional requests and diagnostics. It is
not the source of truth for what the app can display; `datasetState` is.

### Compatibility gate

After a `200` (and after parsing a `304` cache), the caller must run
`BundleManifest.checkCompatibility()` **before** downloading anything. The
result is one of:

| Status | Condition | Client action |
|---|---|---|
| `compatible` | `bundleSchemaVersion` and `minAppSchemaVersion` are both within this client's support. | Continue (`CP1`). |
| `bundleUnsupported` | `bundleSchemaVersion` is newer than the client implements. | Keep the current database, report that the app must be updated, download nothing (`CP2`). |
| `appUpdateRequired` | `minAppSchemaVersion` is newer than the client's data schema. | Keep the current database, report that the app must be updated (`CP3`). |

`bundleUnsupported` takes precedence when both conditions hold (`CP4`). A
newer per-dataset `schemaVersion` is refused at ingestion even when the
aggregate gate passes; see `IN11`.

Compatibility is evaluated before any byte is downloaded, so an incompatible
bundle never partially applies and never deletes current rows.

### Dataset selection

For every `datasets[]` entry, compare the dataset's `sha256` with the checksum
recorded in `datasetState` for that mode and dataset. The comparison also
takes the record schema version and the record count into account
(`DatasetStateRepository.isCurrent`). Equal content means no download and no
ingest (`DS1`); a changed checksum means the dataset is selected and applied
(`DS2`). Re-ingesting a dataset that is already current is a no-op (`DS3`).

Rules:

- `skipped` datasets and datasets absent from the manifest are not deleted:
  their existing rows are kept. Absence is not a delete instruction.
- Datasets are independent. A pass may update `items` while leaving `tasks`
  untouched; a failure in one dataset does not invalidate another dataset's
  committed transaction.

### Download

`DatasetDownloader` implements steps 4–5 of the client resolution algorithm in
[`data-bundles.md`](data-bundles.md#client-resolution).

1. **Resolve, do not concatenate.** `manifestUri.resolve(entry.path)`; the
   asset is a sibling of the manifest in the same release.
2. **Apply the network policy.** The request goes through
   `AllowlistedHttpClient.send`, so HTTPS, the host allowlist, and redirect
   rules apply exactly as for the manifest. A disallowed host is rejected
   before any request (`DL6`).
3. **Stream to a partial file.** Each chunk is written and flushed to
   `<destination>.part`. Memory is bounded by the chunk, not the dataset. A
   multi-chunk download writes the exact bytes and reports monotonic progress
   ending at `1.0` (`DL1`); parent directories are created as needed (`DL2`).
4. **Verify while writing.** SHA-256 is computed over the bytes on disk. When
   the body ends, the byte count must equal `compressedBytes` (`DL4`) and the
   digest must equal `sha256` (`DL3`). Neither check decompresses the payload.
5. **Cancel cooperatively.** Cancellation is checked before the request and
   between chunks, cancels the body subscription, deletes the `.part`, and
   throws `DownloadCancelled`. Cancelling before the request sends nothing
   (`DL8`); cancelling after the first chunk leaves no files (`DL7`).
6. **Replace atomically.** Only after verification is the temp file renamed
   onto the destination. POSIX `rename` replaces atomically. On Windows, where
   rename cannot overwrite, the old file is deleted immediately before the
   rename; that is the only window in which the destination is absent, and it
   opens only after verification.
7. **Keep the old file on failure.** A checksum error, size error, transport
   error, timeout, or cancellation leaves the previous verified dataset
   untouched (and a first download leaves no destination). A verified update
   replaces it (`DL9`). A stalled body read times out as
   `HttpTimeoutException` and removes the `.part` (`DL10`).

A leftover `.part` from a crash is truncated by the next `openWrite`; it can
never be mistaken for a finished dataset.

### Ingestion

`DatasetIngestor` runs only on a file the downloader has verified.

- **Streaming decode.** `JsonlLineReader` uses the pure-Dart
  `ZstdDecoder.decodeLazy` over the file and splits 64 KiB chunks on `0x0A`
  before strict UTF-8 decoding. Neither the compressed frame nor the decoded
  payload is held whole (`IN10`).
- **Record routing.** Every line must be a JSON object with a non-empty string
  `kind` and `id`. Dedicated kinds map to their tables (`item`, `task`,
  `trader`, `hideoutStation`, `craft`, `barter`, `map`); every other kind goes
  to `gameRecords(kind, id, payload)` with canonical JSON. Unknown kinds are
  still replaced atomically and re-ingest without duplicates (`IN9`).
  A task's `objectives` become `taskObjectives` rows and cascade when the old
  task is deleted (`IN8`).
- **Batching.** Rows are buffered and flushed with `insertAll` every 500 rows
  (and once at the end). Tasks are flushed before objectives so the immediate
  foreign key holds.
- **One transaction per dataset.** The sequence is: delete the rows this
  dataset owns (dedicated tables plus its auxiliary `gameRecords` kinds),
  stream and insert, compare the processed line count with `datasets[].records`,
  write `datasetState`, commit. Nothing is visible to readers until the commit.
- **Whole-dataset replacement.** There is no field-level merge and no diff
  format. The previous rows are replaced; collections that disappeared
  upstream are removed rather than left behind.
- **Idempotence.** Re-applying the same dataset version leaves row counts and
  `appliedAt` unchanged (`IN2`). `datasetState` records checksum, schema
  version, record count, `sourceUpdatedAt`, and `appliedAt`.
- **Player data is never touched.** Player tables have no foreign key onto game
  data, and ingestion writes neither player rows, price history, nor the FTS
  index directly. The item FTS triggers maintain search while item rows are
  replaced; an accented name is searchable without diacritics (`IN3`).

The success path with the committed fixture asserts rows, mapped columns,
canonical payloads, FTS, auxiliary `gameRecords`, and the `datasetState` row
(`IN1`).

A throw at any point — malformed line (`IN4`), record-count mismatch (`IN5`),
decompression failure (`IN6`), missing file (`IN7`), newer schema (`IN11`),
duplicate `kind`+`id` (`IN12`), invalid UTF-8 (`IN13`), or a missing required
field (`IN14`) — rolls back the deletes, every inserted row, and the
`datasetState` write together. The previous dataset and its applied version
remain exactly as they were.

### Activation and "current data"

There are two visibility points, and they are deliberately separate:

1. **File activation.** The verified `.part` is renamed over the old dataset
   file. A crash before this point leaves the old file; a crash after it leaves
   a complete, verified file that the next pass may re-download (the checksum
   still differs from `datasetState` until ingestion commits).
2. **Database activation.** The dataset's rows and its `datasetState` row
   become visible at the transaction commit. Before the commit, readers see the
   previous committed rows.

Consequences the UI must respect:

- **No mixed dataset.** A screen never sees half of an update: either the old
  rows or the new rows are visible.
- **Per-dataset, not per-bundle.** Datasets commit independently, so `items`
  and `tasks` can legitimately be one bundle apart after a partial pass. The UI
  must not assume a bundle-wide version and must tolerate a reference to an
  entity that the other dataset has already removed (show it as unavailable
  upstream rather than dropping player progress).
- **"Current" means the `datasetState` row.** `appliedAt` is when this client
  applied the dataset; `sourceUpdatedAt` is when upstream produced it. Both are
  catalog metadata, not price metadata.
- **No update lock.** A check or an ingest does not require a restart or a
  modal: the current view can stay responsive and later queries see the new
  rows after the commit. The shell owns the non-modal indicator (task 8.3).
- **No "applying" read state.** The data layer does not expose a partially
  applied dataset, so the UI never has to render one. It may show the previous
  data plus a sync-in-progress indicator until the pass completes.

## Failure semantics

All failures below are non-destructive unless explicitly stated: current data
stays readable and the last good manifest/dataset/version is kept. `SC` IDs are
the scheduler decisions; `MF`, `DL`, and `IN` IDs are the stage failures and
are expanded in the [state → test map](#state--test-map).

| ID | Failure | Detected by | Effect on local data | Recovery |
|---|---|---|---|---|
| `MF11` | Offline, DNS failure, TLS failure, connection reset | Transport exception from the HTTP client | Cache and datasets unchanged | Retriable. If the monitor reports offline the scheduler skips before any request (`SC3`, `SC13`); a failure detected mid-request counts as a failed check and backs off (`SC9`). |
| `MF13` | Request or body timeout | `HttpTimeoutException` | Cache unchanged | Retriable; counts as a failed check and enters backoff (`SC9`). |
| `MF12` | Upstream `5xx` | `HttpStatusException` | Cache unchanged | Retriable; counts as a failed check and enters backoff (`SC9`). |
| `MF6` | Manifest `404` (no bundle published for the mode) | `ManifestNotFound` | Last known manifest and all rows kept | Retriable; never reported as "unchanged". |
| `MF7` | Manifest is not UTF-8 or not JSON | `ManifestInvalid` | Cache unchanged | Retriable; a publishing bug, not a reason to discard data. |
| `MF8` | Manifest fails schema validation | `ManifestInvalid` | Cache unchanged | Retriable after a fixed publication. |
| `MF9` | Document declares another mode | `ManifestModeMismatch` | Cache unchanged | Refuse; mixing modes would corrupt references. |
| `MF10` | `304` with no cached manifest | `ManifestNotModifiedWithoutCache` | Nothing written | Treat as a failed check; a first sync must download the document. |
| `CP2` | Newer bundle schema | `checkCompatibility` returns `bundleUnsupported` | Current database kept | Ask for an app update; no download, no partial apply. |
| `CP3` | Newer `minAppSchemaVersion` | `checkCompatibility` returns `appUpdateRequired` | Current database kept | Ask for an app update. |
| `DL5` | Dataset asset `404` | `HttpStatusException` | Previous dataset file kept | Retriable; the manifest still points at a missing asset. |
| `DL3` | SHA-256 mismatch | `DownloadChecksumMismatchException` | Previous file kept; `.part` deleted | Retriable; re-download next pass. |
| `DL4` | Byte count mismatch | `DownloadSizeMismatchException` | Previous file kept; `.part` deleted | Retriable. |
| `DL7` / `DL8` | User cancellation | `DownloadCancelled` | Previous file kept; no files left | User may retry; not an error condition. |
| `DL10` | Stalled body | `HttpTimeoutException` | `.part` deleted; previous file kept | Retriable. |
| `IN4`–`IN7`, `IN11`–`IN14` | Ingest failure (malformed data, count, decompression, missing file, schema, duplicate, encoding, invalid record) | Typed `IngestError` | Rollback: previous rows and previous `datasetState` intact | Retriable; the stored checksum still differs from the manifest, so the next pass retries. |
| `RC1` / `RC2` | Database cannot be opened or a migration fails | `DatabaseRecovery` | Original file preserved; read-only handle | Recovery mode: export/diagnostics only, no sync or writes. |
| `SC1` | Automatic checks disabled | `skippedAutoUpdateDisabled` | None | Waiting for a manual check. |
| `SC2` | App in background | `skippedBackground` | None | Waiting for foreground (`SC14`). |
| `SC3` | Offline | `skippedOffline` | None | Waiting for a network change (`SC13`). |
| `SC4` | Metered connection, metered updates disallowed | `skippedMetered` | None | Waiting for a connection change; manual action remains available. |
| `SC5` | Check not due | `skippedNotDue` | None | Next check at `lastCheckedAt + 6 h` (`SC6`). |
| `SC9` / `SC10` | Previous check failed | `failed` then `skippedBackoff` | Previous failure changed no data | Retry after 15, 30, 60 minutes, then the normal 6-hour interval; a success resets the sequence (`SC11`). |
| `SC12` | Check already running | `skippedInFlight` | None | The second call returns immediately; no queue. |

A failed check does **not** move `lastCheckedAt`, so the "not due" rule can
never hide a retry. The backoff counter is in memory: after a restart the
scheduler reads the last successful check and resumes the normal policy, which
is safe because a failed check changed no data.

### Backoff and retry

| Consecutive failures | Next attempt after |
|---|---|
| 1 | 15 minutes |
| 2 | 30 minutes |
| 3 | 60 minutes |
| 4 and later | the normal 6-hour interval |

A manual check bypasses the preferences, the interval, and an active backoff,
but still requires connectivity (`SC7`, `SC8`, `SC17`). Backoff applies to
automatic checks only.

## Offline behavior

With no connection and a previously applied dataset, the app remains usable
for everything that reads local data:

| Feature | Offline behavior |
|---|---|
| Item catalog, filters, search | Works from the last applied `items`/`gameRecords` rows and FTS. |
| Item detail, prices | Works; prices carry their observation time and stale label from the bundle. |
| Quest tracker, objectives | Works from the last applied `tasks` rows; player progress is local. |
| Traders, hideout, crafts, barters, maps | Work from their last applied datasets. |
| Dataset age and last sync time | Read from `datasetState.appliedAt`/`sourceUpdatedAt` and `remoteManifest.lastCheckedAt`. |
| Manifest check and dataset download | Not possible; the scheduler reports `skippedOffline` and waits for a network change (`SC3`). |
| Price history charts | Needs the network unless cached; the on-demand history cache is task 5.7 and is not part of this change. |
| Item images | Served from the disk cache when present; the cache is task 5.6 and is not part of this change. |

Rules:

- Offline never deletes or invalidates local data. A failed check leaves the
  manifest cache and `datasetState` untouched.
- The app must not present an empty or broken catalog on a launch that has an
  applied dataset. It serves the last applied data and labels its age.
- A first launch with no dataset and no connection cannot browse. The shell
  must explain that the initial download is required and offer retry (task
  8.1); the data layer's contribution is that no cache and no applied data
  exist (`P5`).
- Returning online or to the foreground triggers a due check immediately
  rather than waiting for the next timer tick (`SC13`, `SC14`). The event still
  passes through the full policy, so a metered, background, or not-yet-due
  state still blocks it.
- Automatic checks are pausable through the auto-update preference (`SC1`);
  a manual check remains available. A metered connection is skipped unless the
  user allowed metered updates (`SC4`); an unmetered connection is never
  blocked by that restriction (`SC16`).

## Catalog freshness versus price freshness

Two independent clocks:

| Clock | Stored in | Meaning |
|---|---|---|
| Catalog freshness | `datasetState.appliedAt`, `datasetState.sourceUpdatedAt` | When this client applied the dataset and when upstream produced it. |
| Price freshness | `items.priceObservedAt` (from the bundle's `price.observedAt`) | When the newest price snapshot was observed upstream. |

A fresh bundle can carry an old price (upstream had no new scan), and an old
catalog can still hold the newest observation upstream ever produced. The app
must never derive price age from the dataset's apply time.

`FreshnessPolicy.evaluate(observedAt, now)` returns `fresh`, `stale`, or
`unknown`. The comparison is strictly greater: an observation exactly at the
threshold is fresh (`FR1`); one second past it is stale (`FR2`); a missing
observation is `unknown`, not stale (`FR3`), and must render as an explicit
missing-data state rather than an unqualified price. A future timestamp is
treated as fresh with age clamped to zero. Changing the
`dataFreshnessHours` setting changes the verdict immediately without a
re-download.

## Recovery mode

If the database cannot be opened or a migration fails, `openAppDatabase`
returns `DatabaseRecovery` with a read-only handle and keeps the original file
and any pre-migration backup (`RC1`). A corrupt file enters the same mode
without being deleted or overwritten (`RC2`). A user-initiated restore from a
backup is explicit (`RC3`); nothing auto-restores.

Recovery mode is a sync stop condition, not a sync state:

- The handle is read-only, and the sync stages require a writable
  `AppDatabase`, so no ingestion can be constructed from it.
- The shell must not start the scheduler while in recovery mode.
- Diagnostics/export remain available; no data is uploaded automatically.

## State → test map

Every row below is a documented state with the committed test that reproduces
it. Test names include the enclosing `group` where one exists. Paths are
relative to `app/`.

### Startup and local read path

| ID | State | Test file | Test |
|---|---|---|---|
| `P1` | Reopening an existing database keeps rows and the FTS index | `packages/data/test/reopen_test.dart` | `re-opening an existing database is idempotent and keeps rows` |
| `P2` | A mode with no applied dataset | `packages/data/test/dataset_state_repository_test.dart` | `an empty mode has no applied datasets` |
| `P3` | A mode that was never checked has no cached manifest | `packages/data/test/sync/manifest_repository_test.dart` | `an unchecked mode has no cached manifest` |
| `P4` | The background check is scheduled at the interval, not on the read path | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler scheduling › the scheduled check runs at the interval from the injected clock` |
| `P5` | First run offline leaves no manifest and no applied data | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › a first run with no connectivity leaves no manifest and no applied data` |

### Manifest fetch

| ID | State | Test file | Test |
|---|---|---|---|
| `MF1` | A first `200` inserts the raw body, validators, and both timestamps | `packages/data/test/sync/manifest_repository_test.dart` | `the first check inserts the raw body and both timestamps` |
| `MF2` | `304` sends conditional headers, moves only `lastCheckedAt`, and requests no dataset | `packages/data/test/sync/manifest_fetcher_test.dart` | `conditional manifest fetch › 200 then 304 sends If-None-Match, returns the cache and requests no dataset` |
| `MF3` | A changed `200` body replaces the cache and moves `lastChangedAt` | `packages/data/test/sync/manifest_fetcher_test.dart` | `conditional manifest fetch › a 200 with a changed body replaces the cache` |
| `MF4` | An identical body with a new `ETag` updates metadata without a change | `packages/data/test/sync/manifest_fetcher_test.dart` | `conditional manifest fetch › a 200 with the same body but a new ETag updates metadata without a change` |
| `MF5` | Modes have isolated URLs and cache rows | `packages/data/test/sync/manifest_fetcher_test.dart` | `per-mode URLs and caches are isolated` |
| `MF6` | `404` is `ManifestNotFound` and keeps the cache | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › 404 is ManifestNotFound and leaves an existing cache untouched` |
| `MF7` | Malformed JSON is `ManifestInvalid` and keeps the cache | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › malformed JSON is ManifestInvalid and leaves the cache untouched` |
| `MF8` | A manifest that fails the schema is `ManifestInvalid` | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › an invalid manifest schema is ManifestInvalid` |
| `MF9` | A document for another mode is refused | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › a document for another mode is ManifestModeMismatch` |
| `MF10` | `304` without a cache is refused | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › 304 without a cache is ManifestNotModifiedWithoutCache` |
| `MF11` | An offline transport failure propagates and keeps the cache | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › an offline transport failure propagates and leaves the cache untouched` |
| `MF12` | A `5xx` propagates `HttpStatusException` and keeps the cache | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › a 5xx propagates HttpStatusException and leaves the cache untouched` |
| `MF13` | A timeout propagates `HttpTimeoutException` and keeps the cache | `packages/data/test/sync/manifest_fetcher_test.dart` | `typed failures › a timeout propagates HttpTimeoutException and keeps the cache` |

### Compatibility

| ID | State | Test file | Test |
|---|---|---|---|
| `CP1` | The published bundle versions are compatible | `packages/data/test/bundle_manifest_test.dart` | `BundleManifest.checkCompatibility › accepts the published bundle versions` |
| `CP2` | A newer bundle schema is `bundleUnsupported` | `packages/data/test/bundle_manifest_test.dart` | `BundleManifest.checkCompatibility › refuses a newer bundle schema` |
| `CP3` | A newer `minAppSchemaVersion` is `appUpdateRequired` | `packages/data/test/bundle_manifest_test.dart` | `BundleManifest.checkCompatibility › requires an app update for a newer minAppSchemaVersion` |
| `CP4` | `bundleUnsupported` wins over `appUpdateRequired` | `packages/data/test/bundle_manifest_test.dart` | `BundleManifest.checkCompatibility › reports an unsupported bundle before an app update` |

### Dataset selection

| ID | State | Test file | Test |
|---|---|---|---|
| `DS1` | An applied dataset is current by checksum, schema, and record count | `packages/data/test/dataset_state_repository_test.dart` | `isCurrent tracks checksum, schema and record count` |
| `DS2` | A changed checksum is applied and moves `appliedAt` | `packages/data/test/dataset_state_repository_test.dart` | `a changed checksum is updated and moves appliedAt` |
| `DS3` | Re-ingesting the same dataset is a no-op | `packages/data/test/sync/dataset_ingestor_test.dart` | `re-ingesting the same dataset is idempotent` |

### Download

| ID | State | Test file | Test |
|---|---|---|---|
| `DL1` | A multi-chunk download writes exact bytes, verifies the digest, and reports monotonic progress | `packages/data/test/sync/dataset_downloader_test.dart` | `valid download › writes every chunk, verifies the digest and reports monotonic progress that ends at 1.0` |
| `DL2` | Missing parent directories are created | `packages/data/test/sync/dataset_downloader_test.dart` | `valid download › creates missing parent directories` |
| `DL3` | A flipped byte fails the checksum and removes the partial file | `packages/data/test/sync/dataset_downloader_test.dart` | `verification failures › a flipped byte fails the checksum and removes the partial file` |
| `DL4` | A wrong byte count fails the size check before hashing | `packages/data/test/sync/dataset_downloader_test.dart` | `verification failures › a wrong byte count fails the size check before hashing` |
| `DL5` | A dataset `404` writes nothing | `packages/data/test/sync/dataset_downloader_test.dart` | `verification failures › a 404 propagates HttpStatusException and writes nothing` |
| `DL6` | An asset URL outside the allowlist is rejected before any request | `packages/data/test/sync/dataset_downloader_test.dart` | `verification failures › an asset URL outside the allowlist is rejected before any request` |
| `DL7` | Cancelling after the first chunk aborts the transfer and deletes the partial file | `packages/data/test/sync/dataset_downloader_test.dart` | `cancellation › cancelling after the first chunk aborts the subscription and deletes the partial file` |
| `DL8` | A pre-cancelled token sends no request | `packages/data/test/sync/dataset_downloader_test.dart` | `cancellation › an already-cancelled token sends no request` |
| `DL9` | A failed update keeps the previous file; a verified update replaces it | `packages/data/test/sync/dataset_downloader_test.dart` | `replacing an existing dataset › a failed update keeps the previous file and a verified update replaces it` |
| `DL10` | A stalled body times out and removes the partial file | `packages/data/test/sync/dataset_downloader_test.dart` | `verification failures › a stalled body times out and removes the partial file` |

### Ingestion

| ID | State | Test file | Test |
|---|---|---|---|
| `IN1` | The fixture ingests rows, columns, payloads, FTS, auxiliary records, and `datasetState` | `packages/data/test/sync/dataset_ingestor_test.dart` | `ingests the item fixture: rows, columns, payload, FTS, gameRecords and datasetState match the manifest` |
| `IN2` | Re-ingesting the same dataset keeps rows and `appliedAt` | `packages/data/test/sync/dataset_ingestor_test.dart` | `re-ingesting the same dataset is idempotent` |
| `IN3` | An accented item name is searchable without diacritics | `packages/data/test/sync/dataset_ingestor_test.dart` | `an ingested accented name is searchable without diacritics` |
| `IN4` | A corrupt line rolls back the partial insert, deletes, and state | `packages/data/test/sync/dataset_ingestor_test.dart` | `a corrupt line rolls back the partial insert, the deletes and datasetState` |
| `IN5` | A record-count mismatch rolls back after inserting | `packages/data/test/sync/dataset_ingestor_test.dart` | `a record-count mismatch rolls back after inserting` |
| `IN6` | A decompression failure is typed and writes nothing | `packages/data/test/sync/dataset_ingestor_test.dart` | `a decompression failure is typed and writes nothing` |
| `IN7` | A missing dataset file is typed and writes nothing | `packages/data/test/sync/dataset_ingestor_test.dart` | `a missing dataset file is typed and writes nothing` |
| `IN8` | Task objectives are created and cascade on replacement | `packages/data/test/sync/dataset_ingestor_test.dart` | `tasks ingestion creates objectives and replacement cascades them` |
| `IN9` | Unknown kinds are stored and replaced cleanly | `packages/data/test/sync/dataset_ingestor_test.dart` | `unknown kinds are stored in gameRecords and replace cleanly` |
| `IN10` | A dataset larger than one decompression chunk streams correctly | `packages/data/test/sync/dataset_ingestor_test.dart` | `streams datasets larger than one decompression chunk` |
| `IN11` | A newer dataset schema is refused before any write | `packages/data/test/sync/dataset_ingestor_test.dart` | `a newer dataset schema is refused before any write` |
| `IN12` | A duplicate `kind`+`id` is rejected and rolled back | `packages/data/test/sync/dataset_ingestor_test.dart` | `a duplicate record is rejected and rolled back` |
| `IN13` | A line that is not UTF-8 is typed and writes nothing | `packages/data/test/sync/dataset_ingestor_test.dart` | `a line that is not UTF-8 is typed and writes nothing` |
| `IN14` | A record missing a required field is refused and rolled back | `packages/data/test/sync/dataset_ingestor_test.dart` | `a record missing a required field is refused and rolled back` |

### Scheduling, offline, and retry

| ID | State | Test file | Test |
|---|---|---|---|
| `SC1` | Automatic checks disabled | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler preference matrix (metered connection) › autoUpdate=false allowMetered=true foreground=true online=true` |
| `SC2` | App in the background | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler preference matrix (metered connection) › autoUpdate=true allowMetered=true foreground=false online=true` |
| `SC3` | Offline | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler preference matrix (metered connection) › autoUpdate=true allowMetered=true foreground=true online=false` |
| `SC4` | Metered connection with metered updates disallowed | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler preference matrix (metered connection) › autoUpdate=true allowMetered=false foreground=true online=true` |
| `SC5` | A check before the interval is skipped | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › a check before the interval is skipped and reports the due time` |
| `SC6` | A check exactly at the interval boundary runs | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › a check at the interval boundary runs` |
| `SC7` | A manual check bypasses preferences and the schedule | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › a manual check bypasses every preference and the schedule` |
| `SC8` | A manual check still requires connectivity | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › a manual check still requires a connection` |
| `SC9` | Failures back off 15, 30, and 60 minutes, then resume the interval | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › failures back off 15, 30 and 60 minutes, then resume the interval` |
| `SC10` | A check inside the backoff window is skipped | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › a check inside the backoff window is skipped` |
| `SC11` | A success resets the failure sequence | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › a success resets the failure sequence` |
| `SC12` | A concurrent check is not started twice | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › a concurrent check is reported instead of starting twice` |
| `SC13` | A network change triggers a due check | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler scheduling › a network change triggers a due check without a timer tick` |
| `SC14` | Returning to the foreground triggers a due check | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler scheduling › returning to the foreground triggers a due check` |
| `SC15` | Disposal cancels the pending check | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler scheduling › dispose cancels a pending check and ignores later events` |
| `SC16` | An unmetered connection runs despite a metered restriction | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › an unmetered connection runs despite a metered restriction` |
| `SC17` | A manual check bypasses an active failure backoff | `packages/data/test/sync/scheduler_test.dart` | `SyncScheduler policy › a manual check bypasses an active failure backoff` |

### Recovery mode

| ID | State | Test file | Test |
|---|---|---|---|
| `RC1` | A failing migration keeps the original at v1 and opens read-only recovery | `packages/data/test/migration_runner_test.dart` | `openAppDatabase › a failing migration keeps the original at v1 and opens recovery` |
| `RC2` | A corrupt file enters recovery and keeps its bytes | `packages/data/test/migration_runner_test.dart` | `openAppDatabase › a corrupt file enters recovery and keeps its bytes` |
| `RC3` | A user-initiated restore restores the backup and clears stale WAL sidecars | `packages/data/test/migration_runner_test.dart` | `restoreFromBackup › restores the backup row and clears stale WAL sidecars` |

### Price freshness

| ID | State | Test file | Test |
|---|---|---|---|
| `FR1` | An observation exactly at the threshold is fresh | `packages/data/test/catalog/price_freshness_test.dart` | `FreshnessPolicy › an age exactly at the threshold is fresh (strictly-greater rule)` |
| `FR2` | One second past the threshold is stale | `packages/data/test/catalog/price_freshness_test.dart` | `FreshnessPolicy › one second past the threshold is stale` |
| `FR3` | A null observation is unknown, not fresh | `packages/data/test/catalog/price_freshness_test.dart` | `FreshnessPolicy › a null observation is unknown, not fresh` |

## Running the verification

```bash
cd app

# The sync suite behind the state map.
dart test packages/data/test/sync

# The non-sync suites referenced above.
dart test packages/data/test/bundle_manifest_test.dart
dart test packages/data/test/dataset_state_repository_test.dart
dart test packages/data/test/reopen_test.dart
dart test packages/data/test/migration_runner_test.dart
dart test packages/data/test/catalog/price_freshness_test.dart
```

All sync tests are offline. `MockClient` is injected into
`AllowlistedHttpClient`, and the downloader is driven by a fake streaming
transport, so no socket is opened; the scheduler uses a fake clock and a
hand-advanced timer queue, so no real time passes.
