# Client sync

The client keeps a complete local copy of the game data so every screen works
offline. Sync is split into three stages:

1. **Manifest fetch** — task 4.1, implemented in
   `app/packages/data/lib/src/sync/`. One small conditional request per game
   mode. This document covers it.
2. **Compatibility check** — `BundleManifest.checkCompatibility`, already part
   of the parsed manifest. A failed check stops the sync and leaves the current
   database untouched.
3. **Dataset download and ingestion** — task 4.2 and later: download only
   datasets whose `sha256` differs from `datasetState`, verify the bytes,
   decompress, ingest in one transaction, and refresh FTS.

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
          +-- compatible   -> task 4.2: compare each dataset sha256 with
                              datasetState and download only what changed
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
`AllowlistedHttpClient`, and no dataset body exists in the fixtures. Run them
with:

```bash
cd app
dart test packages/data/test/sync
dart test packages/data/test/schema_v2_migration_test.dart
```

The suite proves the 200-then-304 sequence sends `If-None-Match`, returns the
cached manifest, moves only `lastCheckedAt`, and makes exactly two transport
calls, both to the manifest URL — a `304` performs no dataset download. It also
covers changed/identical bodies, `404`, malformed JSON and schema, mode
mismatch, `304` without a cache, per-mode isolation and clock injection.
