# Client sync

The client keeps a complete local copy of the game data so every screen works
offline. Sync is split into three stages:

1. **Manifest fetch** — task 4.1, implemented in
   `app/packages/data/lib/src/sync/`. One small conditional request per game
   mode. This document covers it.
2. **Compatibility check** — `BundleManifest.checkCompatibility`, already part
   of the parsed manifest. A failed check stops the sync and leaves the current
   database untouched.
3. **Dataset download** — task 4.2, implemented by `DatasetDownloader`: download
   only the datasets whose `sha256` differs from `datasetState`, stream them to
   disk, verify the byte count and SHA-256, and atomically replace the previous
   file.
4. **Decompression and ingestion** — task 4.3, implemented by
   `JsonlLineReader` and `DatasetIngestor`: stream the zstd frame, parse JSONL
   line by line, replace the dataset's rows in one transaction, and record the
   applied checksum and version.

The public bundle contract lives in [`data-bundles.md`](data-bundles.md); the
network policy lives in [`network.md`](network.md).

## Flow

```
app start (renders from the last applied dataset)
  |
  v
ManifestFetcher.fetch(mode)
  |
  +-- GET data-<mode>-latest/manifest.json
  |     If-None-Match / If-Modified-Since from remoteManifest
  |
  +-- 304 Not Modified
  |     markChecked(mode, now)       -> only lastCheckedAt moves
  |     parse the cached body        -> ManifestNotModified
  |     \
  |      no dataset request, no download
  |
  +-- 200 OK
        strict UTF-8 -> JSON -> BundleManifest.parse
        mode must equal the requested mode
        contentHash = SHA-256(raw bytes)
        recordCheck(...)             -> remoteManifest row
        BundleManifest.checkCompatibility()
          |
          +-- incompatible -> keep the current data, ask for an app update
          |
          +-- compatible   -> for each dataset whose sha256 differs from
                              datasetState: DatasetDownloader.download()
                                GET <manifest>/<dataset.path>
                                stream to <destination>.part (+ SHA-256)
                                verify size + digest
                                rename over <destination>
```

## Manifest URL

```
https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json
```

The URL is built only by `ManifestFetcher.uriFor(mode)`. The fetcher never
builds a dataset URL; a dataset path is resolved relative to the manifest by the
download stage (task 4.2), exactly as documented in
[`data-bundles.md`](data-bundles.md#client-resolution).

`regular`, `pve` and `pvp-season` have independent URLs, rows and validators.
One mode's `304`, `404` or invalid document never touches another mode.

## Cache: `remoteManifest`

Schema version 2 adds one row per mode (migration `1 -> 2` in
`AppDatabase`). The table is client-owned sync bookkeeping, not ingested game
data, and no ingestion step writes or clears it.

| Column | Type | Meaning |
|---|---|---|
| `mode` | TEXT PK | `regular`, `pve` or `pvp-season`. |
| `etag` | TEXT NULL | Last response `ETag`, verbatim (may be weak). |
| `lastModified` | TEXT NULL | Last response `Last-Modified`, verbatim. |
| `manifestJson` | TEXT NOT NULL | Raw manifest body exactly as received. |
| `manifestGeneratedAt` | TEXT NULL | The document's `generatedAt`, verbatim, for diagnostics. |
| `lastCheckedAt` | DATETIME NOT NULL | When this client last asked the server. |
| `lastChangedAt` | DATETIME NULL | When the body last changed; `null` before the first change. |
| `contentHash` | TEXT NOT NULL | Lowercase SHA-256 of the raw body bytes. |

`ManifestRepository` is the only writer:

- `read(mode)` returns the cached document or `null`.
- `recordCheck(mode, ...)` writes a validated `200` and reports `inserted`,
  `unchanged` or `changed`.
- `markChecked(mode, checkedAt)` moves only `lastCheckedAt`, for a `304`.

Change detection is `contentHash`, not `ETag`. A `200` with an identical body
but a new validator (GitHub's asset CDN can answer with its own `ETag`) updates
`etag`, `lastModified` and `lastCheckedAt` while `lastChangedAt` stays put.
`lastChangedAt` moves only when the hash changes. The repository and the
fetcher accept an injectable clock, so tests and logs use deterministic
timestamps. Cache timestamps are returned in UTC.

## Result states

`ManifestFetcher.fetch` returns one of two results:

| Result | When | Cache write |
|---|---|---|
| `ManifestFetched` | A valid, compatible-mode `200` | Raw body, validators, `generatedAt`, hash, check and change times |
| `ManifestNotModified` | `304` with a cached manifest | `lastCheckedAt` only |

Both carry `mode`, `checkedAt`, the parsed `BundleManifest` and the resulting
`CachedManifest`. `ManifestNotModified.manifest` is parsed from the stored raw
body, so a caller can run the compatibility check without another request.
`checkedAt` is the exposed last-check time; `ManifestFetcher.lastCheckedAt(mode)`
reads the persisted value without a request.

The fetcher performs no dataset request in either state. Task 4.2 receives the
manifest and decides what to download.

## Dataset download

Task 4.2, implemented by `DatasetDownloader` in
`app/packages/data/lib/src/sync/dataset_downloader.dart`. Given the manifest
URL, one `ManifestDataset` and the final `File`, it owns steps 4 and 5 of the
client resolution algorithm in
[`data-bundles.md`](data-bundles.md#client-resolution).

The asset URL is `manifestUri.resolve(dataset.path)`, never string
concatenation. It goes through the same `AllowlistedHttpClient.send` checks as
the manifest, so a dataset served from an unlisted host is rejected before any
bytes are requested.

```dart
final token = DownloadCancellationToken();
await DatasetDownloader(client).download(
  manifestUri: ManifestFetcher.uriFor(mode),
  dataset: entry,               // ManifestDataset from the parsed manifest
  destination: File('.../regular/items.jsonl.zst'),
  cancellation: token,
  onProgress: (progress) => show(progress.fraction),
);
```

Rules:

1. **Stream, do not buffer.** `AllowlistedHttpClient.send` returns the status,
   lowercased headers, the final URI after redirects and a single-subscription
   body. Each chunk is written to `<destination>.part` and flushed, so memory is
   bounded by the chunk size rather than by the dataset.
2. **Hash while writing.** SHA-256 is computed over exactly the bytes written to
   disk. Nothing is decompressed or parsed before verification passes.
3. **Progress is per chunk and monotonic.** `downloadedBytes` never decreases,
   `totalBytes` is the manifest's `compressedBytes`, and `fraction` reaches
   `1.0` when the last byte arrives.
4. **Cancellation is cooperative.** `DownloadCancellationToken.cancel()` is
   checked before the request and between chunks, and is safe to call from an
   `onProgress` handler. A cancelled download cancels the body subscription
   (releasing the connection), deletes the `.part` file and throws
   `DownloadCancelled`.
5. **Verify both numbers.** When the body ends, the received byte count must
   equal `compressedBytes` (`DownloadSizeMismatchException`) and the digest must
   equal `sha256` (`DownloadChecksumMismatchException`). A mismatch deletes the
   `.part` file.
6. **Replace atomically.** Parent directories are created, then the verified
   temp file is renamed onto `destination`. POSIX `rename` replaces the file
   atomically; on Windows, where `rename` cannot overwrite, the previous file is
   deleted immediately before the rename. That delete is the only window in
   which the destination is absent, and it opens only after verification.

### Failure and replacement semantics

| Outcome | Destination | `.part` |
|---|---|---|
| First download succeeds | Created | Gone after the rename |
| First download fails (transport, cancel, size, checksum) | Absent | Deleted |
| Update succeeds | Replaced by the verified bytes | Gone after the rename |
| Update fails | Previous verified file untouched | Deleted |

**The old dataset file remains until verification succeeds.** A corrupted,
cancelled or timed-out update therefore never removes working data: the app
keeps serving the previous dataset until a verified replacement is ready. A
leftover `.part` from a crash or power loss is truncated by the next
`openWrite`; the rename is the only step that makes a dataset visible.

### Typed download errors

| Error | Cause |
|---|---|
| `DownloadCancelled` | The token was cancelled before or during the transfer |
| `DownloadSizeMismatchException` | Byte count differs from `compressedBytes` |
| `DownloadChecksumMismatchException` | SHA-256 differs from the manifest |
| `DownloadReplaceException` | The verified file could not be moved into place |
| `HttpStatusException` | Final status outside `2xx`, e.g. `404` for a missing asset |
| `HttpTimeoutException` | Headers, or an idle body read, exceeded the timeout |
| `DisallowedHostException` (and the other policy errors) | Asset URL outside the network policy |

## Decompression and ingestion

Task 4.3, implemented by `JsonlLineReader` and `DatasetIngestor` in
`app/packages/data/lib/src/sync/`. It runs only on a file that the downloader
has already verified; ingestion never sees an unverified byte.

```dart
final result = await DatasetIngestor(db).ingest(
  mode: GameMode.regular,
  dataset: entry,                               // ManifestDataset from the manifest
  compressedFile: File('.../regular/items.jsonl.zst'),
  onProgress: (progress) => show(progress.fraction),
);
// result.records == entry.records, result.stateOutcome == inserted | updated | unchanged
```

### zstd decoder and memory bound

The client uses **`archive` 4.7.1's pure-Dart `ZstdDecoder`** through
`decodeLazy`. It is a direct dependency of `tarkov_companion_data`:

- no native library, FFI, build hook or DLL — the same code runs on Linux and
  Windows CI, and on Android;
- `decodeLazy(InputFileStream(path))` decodes a block at a time, so the
  compressed frame and the decoded payload are never held whole;
- `JsonlLineReader` pulls 64 KiB chunks from that stream and splits on `0x0A`
  before UTF-8 decoding each line. Memory is bounded by the chunk size plus the
  longest single line, independent of the dataset size.

The largest shipped dataset (items, roughly 8 MB decompressed; the design table
measured 17 MB before trimming) is well inside that bound. A one-shot decode
would also work for today's sizes but would allocate the full payload and break
design D7's bounded-memory rule, so streaming is the contract, not an
optimization. Frames are standard zstd (`28 b5 2f fd`, level 3, no frame
checksum); no decoder settings differ from the pipeline's writer.

### Record routing

Every line must be a JSON object with a non-empty string `kind` and `id`.
`kind`+`id` must be unique within the dataset. The ingestor maps kinds to the
dedicated tables and stores every other kind in `gameRecords` (schema v3), so a
collection the UI does not query yet is still replaced atomically instead of
being dropped:

| Kinds | Destination |
|---|---|
| `item` | `items` (the FTS triggers index `name`, `shortName`, `normalizedName`) |
| `task` | `tasks`, plus one `taskObjectives` row per entry in `objectives` |
| `trader` | `traders` |
| `hideoutStation` | `hideoutStations` |
| `craft` | `crafts` |
| `barter` | `barters` |
| `map` | `maps` |
| `itemCategory`, `handbookCategory`, `fleaMarket`, `armorMaterial`, `playerLevel`, `mastering`, `skill`, `specialItem`, `setting`, `questItem`, `achievement`, `prestige`, `mob`, `lootContainer`, `stationaryWeapon`, `goonReport`, and any future/unknown kind | `gameRecords(kind, id, payload)` |

Each row keeps the complete record as canonical JSON in `payload` (object keys
sorted recursively). Dedicated columns are mapped from the documented fields;
`price.avg24h`, `price.lastLow` and `price.change48hPercent` feed the item price
columns. A missing required field, a wrong type, invalid UTF-8, malformed JSON
or a duplicate record is a typed `IngestError`; it never falls back to a null
column silently.

### One transaction, batched, whole-dataset replacement

`DatasetIngestor.ingest` opens exactly **one** SQLite transaction per dataset:

1. Delete the previous rows this dataset owns — the dedicated table(s) plus
   its auxiliary kinds in `gameRecords`. Deleting `tasks` cascades the old
   `taskObjectives` rows (the only game-data foreign key); auxiliary kinds are
   removed even when the new payload no longer contains them, so a collection
   that disappears upstream does not linger.
2. Stream the JSONL and buffer rows. A buffer is flushed with
   `batch.insertAll` when 500 rows are pending and once more at the end; tasks
   are flushed before their objectives so the immediate foreign key holds.
3. Compare the processed line count with `datasets[].records`. A mismatch
   aborts the transaction.
4. Write `datasetState` (`checksum`, `schemaVersion`, `records`,
   `sourceUpdatedAt`, `appliedAt`) through `DatasetStateRepository` in the same
   transaction.
5. Commit.

Nothing is published to readers until the commit succeeds. Any throw at any
step — including a corrupt line after a partial batch, a decompression failure,
a missing file or a count mismatch — rolls back the deletes, every inserted row
and the `datasetState` write together. The previous dataset and its applied
version remain exactly as they were, which is the rollback scenario in the
[data-sync spec](../openspec/changes/bootstrap-tarkov-companion/specs/data-sync/spec.md).

Player data, `priceHistory` and the FTS index are never written by ingestion.
Player tables have no foreign key onto game data (see
[`schema.md`](schema.md#the-no-cascade-guarantee)), price history is invalidated
by its own TTL, and `items_fts` is maintained by the existing insert/delete/update
triggers while the item rows are replaced.

### Progress and typed errors

`onProgress` reports `IngestProgress(recordsProcessed, totalRecords)` once per
processed line, so a caller can show a fraction without knowing the dataset
ahead of time.

| `IngestError.failure` | Cause |
|---|---|
| `missingFile` | The verified file is gone before ingestion starts |
| `decompression` | The bytes are not a valid zstd frame, or the frame is truncated |
| `invalidUtf8` | A decoded line is not valid UTF-8 |
| `malformedJson` | A line is empty or is not a JSON object |
| `invalidRecord` | Missing `kind`/`id`, or a dedicated kind lacks a required field |
| `duplicateRecord` | The same `kind`+`id` appears twice |
| `recordCountMismatch` | The file's line count differs from the manifest |
| `unsupportedSchema` | `datasets[].schemaVersion` is newer than the client supports |
| `datasetStateRejected` | `DatasetStateRepository` refused the dataset |

Every one of them is non-destructive. A failed dataset is retried on the next
sync because its stored checksum still differs from the manifest.

## Typed failures

| Error | Cause | Cache |
|---|---|---|
| `ManifestNotFound` | HTTP `404`: no manifest published for the mode | Unchanged |
| `ManifestNotModifiedWithoutCache` | HTTP `304` on a first sync | None exists |
| `ManifestInvalid` | Body is not UTF-8/JSON, or fails `BundleManifest.parse`; `cause` carries the parser error | Unchanged |
| `ManifestModeMismatch` | The document's `mode` differs from the requested mode | Unchanged |

Failures that are not about the document propagate from
`AllowlistedHttpClient`: `HttpStatusException` for `5xx`, `HttpTimeoutException`
for a timeout, and the underlying `dart:io` exception for DNS or TLS. They are
retriable and never modify the cache. A `404` and an invalid document are also
non-destructive: the last known manifest stays available for the next attempt,
but neither is reported as "unchanged".

## Redirects and validators

GitHub answers the stable URL with a redirect to
`objects.githubusercontent.com` or `release-assets.githubusercontent.com`.
`AllowlistedHttpClient` follows the hop itself, re-checks the allowlist, and
keeps the `If-None-Match` / `If-Modified-Since` headers on the redirected
request (see [`network.md`](network.md#redirects)). The validators stored in
`remoteManifest` are the ones from the final response the client actually read.

## Tests

All sync tests are offline: `MockClient` is injected into
`AllowlistedHttpClient`, and no dataset body exists in the fixtures. The
downloader is driven by a fake streaming transport that returns a
`Stream<List<int>>`, so cancellation and a corrupted payload are deterministic
and no socket is opened. Run them with:

```bash
cd app
dart test packages/data/test/sync
dart test packages/data/test/net
dart test packages/data/test/schema_v2_migration_test.dart
dart test packages/data/test/schema_v3_migration_test.dart
```

The manifest suite proves the 200-then-304 sequence sends `If-None-Match`,
returns the cached manifest, moves only `lastCheckedAt`, and makes exactly two
transport calls, both to the manifest URL — a `304` performs no dataset
download. It also covers changed/identical bodies, `404`, malformed JSON and
schema, mode mismatch, `304` without a cache, per-mode isolation and clock
injection.

The download suite covers a valid multi-chunk download (bytes on disk, digest,
monotonic progress ending at `1.0`, temp file gone), a single flipped byte, a
wrong byte count, `404`, an asset URL outside the allowlist (no request sent),
cancellation after the first chunk (subscription cancelled, no files left),
cancellation before the request, parent-directory creation, and re-downloading
over an existing file where a failed update leaves the previous dataset intact.
The HTTP suite adds the streaming API: unbuffered body, pre-flight allowlist,
redirect-body drain before the next hop, and a non-2xx status error.

The ingestion suite (`test/sync/dataset_ingestor_test.dart`) uses the committed
`test/fixtures/bundle/` slice (provenance in its README) plus synthetic frames
built with `archive`'s encoder. It asserts:

- the item fixture produces 2 `items` rows and 5 `gameRecords` rows, the
  documented item columns and canonical `payload`, an FTS match by name, and a
  `datasetState` row with the manifest's checksum, schema version, record count
  and injected `appliedAt`;
- re-ingesting the same dataset leaves the row counts and `appliedAt`
  unchanged;
- a corrupt line after a partial insert, a record-count mismatch, a
  decompression failure and a missing file all roll back to empty (or to the
  previous dataset) with a typed `IngestError`;
- a tasks dataset creates task + objective rows and a newer version removes the
  dropped objective through the cascade;
- unknown kinds land in `gameRecords` and re-ingest without duplicates.
