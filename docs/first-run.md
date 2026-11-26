# First run and local data layout

Tarkov Companion is local-first: every screen reads the SQLite database, and the
network is used only to obtain the versioned game-data bundle. On a device with
no applied dataset, the app shows a first-run gate instead of an empty catalog.
This page describes that gate, its size estimate, and the resume/cancel rules
that make the wait safe to interrupt.

Companion documents:

| Document | Covers |
|---|---|
| [`sync.md`](sync.md) | The sync protocol: manifest, compatibility, selection, download, ingestion. |
| [`client-sync.md`](client-sync.md) | Field-by-field implementation notes for the manifest cache, downloader, and ingestor. |
| [`data-bundles.md`](data-bundles.md) | Byte-level manifest and dataset contract. |
| [`network.md`](network.md) | Host allowlist and HTTPS policy. |

The implementation is `SyncCoordinator` in
`app/packages/data/lib/src/sync/sync_coordinator.dart`, the
`FirstRunScreen` in `app/packages/features/lib/src/first_run/`, and
`openAppSession` in `app/lib/src/app_session.dart`.

## Local data directory

The Linux desktop build resolves its data directory without `path_provider`:

```
XDG_DATA_HOME is set and non-empty:
  $XDG_DATA_HOME/tarkov_companion/

otherwise:
  $HOME/.local/share/tarkov_companion/
```

`AppPaths` then creates:

```
tarkov_companion/
  db/
    tarkov_companion.sqlite          # game data, player data, datasetState
    backups/                         # pre-migration copies (schema.md)
  logs/
    app.log, app.1.log, ...          # rotating JSON-lines diagnostics
  downloads/
    regular/
      items.jsonl.zst                # verified compressed dataset
      tasks.jsonl.zst
    pve/
    pvp-season/
```

`downloads/<mode>/` keeps the verified compressed files after ingestion for
diagnosis and for a future explicit re-apply; no UI reads them. Ingestion reads
them and writes only the database.

## What decides that this is a first run

`openAppSession` opens the database through the versioned migration lifecycle
(`openAppDatabase`). It then asks `DatasetStateRepository.appliedForMode(
GameMode.regular)` whether any dataset is applied:

- **none applied** → the first-run gate;
- **at least one applied** → the home screen opens immediately, and any later
  update is a background concern (task 8.2);
- **database recovery** → a read-only recovery screen; the file is never
  deleted or overwritten.

No manifest request happens during this decision. The first network call is
made by the gate itself, and only after the first frame.

## Gate states

`FirstRunScreen` is a small state machine:

| State | What the user sees | What happens |
|---|---|---|
| Preparing | “Checking for game data…” | `SyncService.prepare` fetches and validates the manifest. |
| Estimate | Download size, dataset count, and a Start button | Nothing is downloaded yet. The estimate is the sum of `compressedBytes` for datasets that are not current. |
| Downloading | Overall byte counter and bar, current dataset name, per-dataset bar, and Cancel | `SyncService.run` downloads and ingests datasets in manifest order. |
| Cancelling | “Cancelling…” | The cancellation token is set; the in-flight transfer stops. |
| Failed | Typed message and Retry | Nothing partial was applied; Retry calls `prepare` again. |
| Ready | “Game data is ready” | The shell replaces the gate with the home screen. |

Cancel is offered only while downloading. Start is offered only after the
estimate, so the network is never used to “find out how big it is” before the
user sees the size.

## Estimate

`prepare(mode)`:

1. fetches the manifest with the existing conditional-request cache;
2. refuses an incompatible `bundleSchemaVersion` or `minAppSchemaVersion`, and
   any dataset whose record `schemaVersion` is newer than this client;
3. compares each manifest dataset against `datasetState` with
   `DatasetStateRepository.isCurrent` (checksum, schema version, record count);
4. returns the current datasets as `applied` and the rest as `pending`, in
   manifest order.

The estimate is `sum(pending.compressedBytes)`; it is a download estimate, not
a total disk requirement. The UI formats it as B/KB/MB.

## Download, progress, and atomicity

`run(mode, {onProgress, cancellation, preparation})` iterates `pending` and,
for each dataset that is still not current:

1. emits a `downloading` event at `0` bytes;
2. streams the asset to `<destination>.part` through
   `DatasetDownloader`, verifying `compressedBytes` and SHA-256;
3. renames the verified file over the destination (atomic on POSIX);
4. emits an `ingesting` event and runs `DatasetIngestor`, which replaces the
   dataset in one SQLite transaction and writes `datasetState` in the same
   transaction;
5. adds the dataset to `applied` and continues.

`SyncProgress` carries the dataset, phase (`downloading`/`ingesting`),
one-based dataset position, dataset byte count, overall byte count, record
counts while ingesting, `datasetFraction`, and overall `fraction`. Overall
progress never moves backwards.

**No dataset is ever partially applied.** A checksum failure removes the
`.part` file and leaves the previous file and `datasetState` untouched. An
ingest failure rolls back deletes, inserts, and the state row together. The
next run sees the old state and retries that dataset.

## Cancel and resume

`DownloadCancellationToken.cancel()` is checked before the run, between
datasets, by the downloader between chunks, and again before ingestion:

- cancelling during a download deletes the `.part` file and throws
  `SyncCancelled`; no `datasetState` row moves;
- cancelling after a dataset was verified but before its ingest starts leaves
  the verified file but applies nothing;
- cancelling during an ingest lets that single transaction finish (SQLite has
  no safe mid-transaction abort here), then the run stops before the next
  dataset.

The UI shows “Download cancelled”, explains that browsing needs data, and
offers Retry. Retry calls `prepare` again. Datasets that already committed are
current and are skipped; the run resumes at the first unfinished dataset. A
crash has the same effect: `datasetState` is the record of what is usable.

## Typed failures

Every failure surfaced to the gate is a `SyncException`:

| Type | Meaning |
|---|---|
| `SyncOfflineException` | DNS/connect failure or request timeout. |
| `SyncCompatibilityException` | Bundle or dataset schema is newer than this app. |
| `SyncChecksumException` | Downloaded bytes failed size or SHA-256 verification. |
| `SyncIngestException` | A verified dataset failed to ingest; it was rolled back. |
| `SyncCancelled` | The user cancelled. |
| `SyncDownloadException` | Any other fetch, download, or local-storage failure. |

## Network policy during first run

Production construction is HTTPS-only and uses the documented allowlist. The
first-run integration test binds a real `HttpServer` on `127.0.0.1` and passes
`AllowlistedHttpClient(allowInsecureLocalhost: true)` together with an explicit
allowlist containing only that loopback host. The flag:

- defaults to `false`;
- permits plain HTTP only for `127.0.0.1`, `::1`, or `localhost`;
- still requires a host match in the allowlist.

Production code never sets it, so no default allowlist entry or TLS check is
weakened. The `ManifestFetcher.manifestUriFor` hook is likewise test-only.

## Privacy

The gate makes no analytics, telemetry, or crash-reporting call. It contacts
only the release manifest and the dataset assets on the allowlisted GitHub
hosts. Progress, estimates, and failures are local; diagnostics go to
`logs/app.log` and are never uploaded automatically.
