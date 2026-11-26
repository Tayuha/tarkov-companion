# Data bundles

> This is the public data contract. Tasks 2.6–2.8 implement the writer, the
> no-op comparison and publication to GitHub Releases; task 2.10 finalizes the
> document and adds `npm run validate:bundle`. Every statement below is
> enforced by code or by a test, so a change here is a contract change.

The pipeline turns each validated, localized upstream dataset into **JSONL**:
one JSON object per line, one record kind per line. The app ingests the records
into its own SQLite schema; it never interprets raw `json.tarkov.dev` payloads.

A reader can reproduce the layout with the
[hand-build tutorial](#build-one-by-hand), and check any bundle — local or
hand-built — with `npm run validate:bundle -- --dir <bundle-dir>`
([what it checks](#validating-a-bundle)).

## Bundle layout

```
dist/bundles/
  regular/
    manifest.json
    barters.jsonl.zst
    crafts.jsonl.zst
    hideout.jsonl.zst
    items.jsonl.zst
    maps.jsonl.zst
    tasks.jsonl.zst
    traders.jsonl.zst
  pve/
    manifest.json
    items.jsonl.zst
  pvp-season/
    manifest.json
    items.jsonl.zst
```

- One directory per game mode. A client fetches only the mode it needs.
- `manifest.json` `path` values are flat file names relative to the manifest's
  own directory (`items.jsonl.zst`). A flat name contains no `/` or `\` and is
  not `.` or `..`, so resolving it can never escape the bundle directory.
- Design decision D2 specifies one self-describing manifest **per mode**
  rather than a single root pointer: the mode is part of the bundle identity
  and a client downloads exactly one document for its active mode.
- Publication maps this layout to one flat GitHub release per mode (see
  [Publication](#publication-to-github-releases)). The stable URL is
  `https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json`;
  the released manifest keeps `path` relative, but rewrites it to the
  content-addressed asset name, so the same resolution rule works locally and
  remotely.
- `pvp-season/season` has a fixture and an upstream schema but no normalizer, so
  it is not part of a bundle yet. Only datasets in `pipeline/src/normalize/`
  can appear in a bundle.
- Files are written through a temporary file plus rename; the manifest is
  written last, so a reader never sees a manifest pointing at a half-written
  dataset. Stale `*.jsonl.zst` files from an earlier build in the same mode
  directory are removed.

## Compression

The writer uses **zstd** from Node's built-in `node:zlib` (`zstdCompressSync`),
so there is no native or WASM dependency and no build step. This requires
**Node 24 or newer**; `pipeline/package.json` declares `"engines": { "node":
">=24" }`.

| Setting | Value | Why |
|---|---|---|
| Compression level | `3` | Matches the measured budget (items + maps + tasks ≈ 1.98 MB) and keeps decompression cheap on low-end devices. |
| Worker threads | `0` (single-threaded) | Multi-threaded frames depend on job splitting; single-thread output is stable. |
| Frame checksum | off | The manifest carries a SHA-256 over the whole compressed frame. |
| Frame magic | `28 b5 2f fd` | Standard zstd frame; any zstd decoder can read it. |

Each dataset file is the zstd frame of the exact UTF-8 JSONL bytes documented
below (sorted records, canonical keys, one trailing newline). The manifest
`sha256` is computed over the **compressed** frame, exactly the bytes a client
downloads; `uncompressedBytes` describes the JSONL payload.

## File rules

- One dataset per file: `<mode>/<dataset>.jsonl.zst`, holding the JSONL below
  inside a zstd frame. Modes: `regular`, `pve`, `pvp-season`. Datasets:
  `items`, `tasks`, `traders`, `hideout`, `crafts`, `barters`, `maps`.
- Every line is a JSON object with a `kind` discriminator and a non-empty
  string `id`. `kind` + `id` is unique within a dataset.
- Records are sorted by `kind`, then `id`, using UTF-16 code-unit order.
- Object keys are sorted recursively (canonical key order). Array order is
  preserved because it is meaningful upstream.
- The file ends with a single trailing newline. With a fixed compressor version,
  the same validated input always produces byte-identical output.
- Text is English (`en`) only for now. Localization is resolved before
  normalization; see [Localization](#localization-contract). Any
  placeholder-shaped string that survives into a record field is a
  normalization failure.
- Unknown upstream fields are dropped rather than passed through. The
  normalizer counts them per dataset (`droppedFields`, `droppedFieldPaths`) so
  a contract change is visible in the build log.

## Localization contract

Upstream serves text as unresolved keys plus JSONPath pointers describing which
fields hold them:

```json
{
  "data": {
    "5447a9cd4bdc2dbd208b4567": { "id": "5447a9cd4bdc2dbd208b4567", "name": "5447a9cd4bdc2dbd208b4567 Name" }
  },
  "translations": ["$.data.items.*.name"]
}
```

The matching `/{mode}/{dataset}_en` document is a flat dictionary keyed by the
placeholder string itself:

```json
{ "data": { "5447a9cd4bdc2dbd208b4567 Name": "Colt M4A1 5.56x45 assault rifle" } }
```

Resolution has three stages, in this order:

1. **Declared pointers** (`localizeInPlace`). The supported JSONPath grammar is
   `$`, `.key`, `.*`, `[n]`, `[*]`, `..key`, `..*` and `['a','b']`. Every node a
   pointer selects that is a string with a dictionary entry is replaced in
   place. A pointer that matches nothing is recorded in
   `stats.unresolvedPaths`; one outside the grammar is recorded in
   `stats.failedPaths`. Neither is fatal, because upstream metadata is allowed
   to be stale.
2. **Opt-in dictionary fallback** (`resolveDictionaryFallback`). Only the
   scheduled sync enables it (`resolveUncoveredPlaceholders: true`); fixture
   localization and its goldens keep the pointer-only contract. It visits the
   whole localized payload and replaces a string only when it matches the
   placeholder pattern **and** the dictionary has an exact key for it. Upstream
   occasionally adds a translatable field before its pointer (observed on
   top-level task objective `effects`); without the fallback those keys survive
   and normalization rejects the dataset.
3. **Normalization gate** (`assertBundleRecords`). Every string in every record
   is tested against the placeholder pattern; a match fails the build. This is
   what makes a silently untranslated name impossible in a published bundle.

### Why the fallback is restricted to placeholder-shaped strings

The dictionary is not a general text map. It also contains bare entity ids
mapped to empty strings. A blind "if this string is a dictionary key, replace
it" pass over the payload would blank out identity fields such as `item.id`, and
the resulting record would still be valid JSON — a silent data loss, not a
caught error. The placeholder pattern is narrow enough to make the lookup safe:

```
^[0-9a-f]{24} \S      # 24 lowercase hex chars, one space, then non-space text
```

A string that does not match is never a candidate for the fallback. A string
that matches but is absent from the dictionary is left untouched, so the
normalization gate still fails rather than publishing a key. In short: the
fallback may only turn a key into text; it can never turn text or an id into
anything.

Text is English (`en`) only for now. A future locale changes the dictionary the
fetch step requests, not the bundle shape; the JSONL contains resolved text, not
keys.

## Manifest

One `manifest.json` per mode, written as canonical JSON (object keys sorted
recursively, no insignificant whitespace) with a single trailing newline. The
canonical form is a writer property, not a client requirement: clients parse
JSON and never compare manifest bytes, and the validator does not reject a
hand-built manifest with a different key order.

```json
{
  "bundleSchemaVersion": 1,
  "datasets": [
    {
      "compressedBytes": 41622,
      "dataset": "items",
      "path": "items.jsonl.zst",
      "records": 577,
      "schemaVersion": 1,
      "sha256": "bc330ec05ae34e3d1beb935c5913918ddca1890bb593fab5f1d758c01dbeaf8e",
      "source": {
        "etag": "W/\"3b74e92edb6baea8f6f4703e995ffaad\"",
        "fetchedAt": "2026-11-25T18:22:15.457Z",
        "lastModified": "Wed, 25 Nov 2026 18:20:24 GMT",
        "url": "https://json.tarkov.dev/regular/items"
      },
      "uncompressedBytes": 281549
    }
  ],
  "generatedAt": "2026-11-25T20:00:00.000Z",
  "manifestVersion": 1,
  "minAppSchemaVersion": 1,
  "mode": "regular",
  "skipped": [],
  "source": {
    "baseUrl": "https://json.tarkov.dev",
    "capturedAt": "2026-11-25T18:22:15.457Z"
  },
  "totals": {
    "compressedBytes": 133008,
    "datasets": 7,
    "records": 1064,
    "uncompressedBytes": 890950
  }
}
```

The `datasets` array is abridged to one entry; `totals` describe the full
regular fixture bundle (all seven datasets).

All fields are required. `manifestSchema` in `pipeline/src/bundle/manifest.ts`
is the executable definition (`manifestVersion` is the literal `1`). Unknown
extra fields in a future manifest are ignored by this schema, which is why a
shape change must also bump `manifestVersion` rather than rely on a client to
notice a new field.

| Field | Type | Meaning |
|---|---|---|
| `manifestVersion` | integer, literal `1` | Version of this manifest document. Bump when a field is added, removed, renamed or changes meaning. A client refuses a value it does not implement. |
| `bundleSchemaVersion` | positive integer | Version of the bundle contract as a whole (layout, compression, record envelope). A client refuses a value newer than it supports. See [Versioning policy](#versioning-policy). |
| `minAppSchemaVersion` | positive integer | Oldest app data-schema version that can ingest every dataset here. Currently `max(1, datasets[].schemaVersion)`. A client whose supported data schema is lower must update the app instead of applying the bundle. |
| `mode` | string enum | `regular`, `pve` or `pvp-season`. Must match the release tag (`data-<mode>-latest`) and the local mode directory. |
| `generatedAt` | ISO 8601 UTC string | Wall-clock timestamp of this build, always ending in `Z`. **Intentionally not reproducible**: it is the only field the writer takes from the clock, so two builds from the same captured fixtures differ only here. Live syncs may also change upstream `source` metadata without changing content; comparison ignores both. |
| `source` | object | Provenance of the whole build. Required; its members are nullable. |
| `source.baseUrl` | string \| null | Upstream API base URL (`https://json.tarkov.dev`), or `null` for a hand-built bundle. |
| `source.capturedAt` | ISO 8601 UTC string \| null | Earliest upstream `fetchedAt` in this build, or the fixture set's capture time. `null` when unknown. |
| `datasets` | array of objects | Datasets present in this bundle, sorted by `dataset`. This array is the complete present set. |
| `datasets[].dataset` | non-empty string | Dataset name: `items`, `tasks`, `traders`, `hideout`, `crafts`, `barters` or `maps`. Unique within the manifest. |
| `datasets[].path` | non-empty, flat string | File name relative to the manifest's directory. No `/` or `\`; not `.` or `..`; a client resolves it with `new URL(path, manifestUrl)`. Published bundles use `<dataset>-<sha12>.jsonl.zst`; local bundles use `<dataset>.jsonl.zst`. |
| `datasets[].schemaVersion` | positive integer | Record schema version for this dataset (`1` today). Each dataset is versioned independently. |
| `datasets[].sha256` | 64 lowercase hex chars | SHA-256 of the compressed `.jsonl.zst` file — the exact bytes a client downloads, not the JSONL text. |
| `datasets[].compressedBytes` | non-negative integer | Exact byte length of the compressed file. |
| `datasets[].uncompressedBytes` | non-negative integer | Byte length of the UTF-8 JSONL payload before compression. |
| `datasets[].records` | non-negative integer | Number of JSONL lines, one bundle record per line. Never `0` in a writer-produced bundle. |
| `datasets[].source` | object | Upstream provenance for this dataset. Required; members are nullable. Never used to decide whether to ingest. |
| `datasets[].source.url` | string \| null | Upstream URL the payload came from. |
| `datasets[].source.lastModified` | string \| null | Upstream HTTP `Last-Modified` value, verbatim (an HTTP date, not necessarily ISO 8601). |
| `datasets[].source.etag` | string \| null | Upstream HTTP `ETag`, verbatim (may be weak, e.g. `W/"…"`). |
| `datasets[].source.fetchedAt` | ISO 8601 UTC string \| null | When this dataset was fetched. |
| `totals` | object | Sums over `datasets[]`. The validator reports a mismatch as a warning; the writer always keeps them exact. |
| `totals.datasets` | non-negative integer | Length of `datasets[]`. |
| `totals.records` | non-negative integer | Sum of `datasets[].records`. |
| `totals.uncompressedBytes` | non-negative integer | Sum of `datasets[].uncompressedBytes`. |
| `totals.compressedBytes` | non-negative integer | Sum of `datasets[].compressedBytes`. |
| `skipped` | array of objects | Datasets deliberately not written in this build, in the fixed registry order `items`, `tasks`, `traders`, `hideout`, `crafts`, `barters`, `maps`. Clients must not depend on order. |
| `skipped[].dataset` | non-empty string | Dataset name. No file exists for it. |
| `skipped[].reason` | literal `"not-supplied"` | The caller had no records for the dataset. A client must keep its existing rows. |

## Missing and empty datasets

- **Missing** (the caller supplied no records for a dataset): the writer skips
  it, writes no file, and lists it under `skipped` with reason `not-supplied`.
  This is normal for the trimmed `pve` and `pvp-season` fixture sets, which only
  carry the three item markers.
- **Empty** (a dataset is explicitly supplied with zero records): the build
  **fails**. Publishing an empty JSONL file would make the client delete all
  rows for that dataset, and upstream emptiness is far more likely a bug than
  truth. Callers that really mean "empty" must omit the dataset instead.
- A mode with no datasets at all still yields a valid manifest with `totals`
  zeroed; the CLI refuses to build such a mode because it almost certainly
  means fixture discovery failed.

## Determinism guarantees

Given the same normalized records and the same zstd compressor version:

- Dataset files are byte-identical, so their SHA-256 checksums are identical.
- Record order in the caller's array does not matter: the writer sorts by
  `kind` then `id` before serializing, exactly as the normalizer does.
- Manifest `datasets` are sorted by `dataset`; `skipped` follows the fixed
  registry order; manifest keys are canonical; the newline ending is fixed.
- With the same `generatedAt`, the whole manifest is byte-identical. The CLI
  uses the wall clock, so two real builds differ only in `generatedAt`.
- Stale dataset files are removed from the mode directory, so a rebuild cannot
  leave an unreferenced artifact behind.

`npm test` proves this offline by building the regular fixture set twice,
decompressing every file back to the committed normalized goldens, and
comparing bytes and checksums.

## Comparison and no-op publishing

Publishing is gated on content, not on the clock. Before writing anything, the
pipeline can compare a freshly built manifest with the manifest of the bundle
that is already published and skip publication when nothing changed.

The comparison (`compareBundles` in `pipeline/src/bundle/compare.ts`) looks only
at dataset presence and each dataset's `sha256` (the checksum of the compressed
file the client downloads):

| Previous | Current | Classification |
|---|---|---|
| absent | present | `added` |
| present | absent | `removed` |
| present | present, same `sha256` | `unchanged` |
| present | present, different `sha256` | `changed` |

If `bundleSchemaVersion` or `minAppSchemaVersion` differs between the two
manifests, every dataset present on both sides is classified as `changed` even
when its checksum matches, and the reason names the version bump. A client has to
reconsider the whole bundle when the client contract moved, so a silent no-op
would strand it on an incompatible contract. `added` and `removed` keep their
classification, because a dataset that does not exist on one side cannot be
"changed".

Deliberately ignored: `generatedAt`, `source.capturedAt`, the per-dataset
`source.url`/`.etag`/`.lastModified`/`.fetchedAt`, `path`, byte sizes, record
counts and `totals`. None of them describes the bytes a client downloads:
timestamps come from the build clock or from the upstream transport, sizes are
derived from the checksummed file, and an upstream `ETag` can change while the
content does not. Comparing them would publish a "new" release on every run and
defeat the no-op.

Rules:

- Both manifests are validated against the manifest Zod schema before comparing;
  a malformed, incomplete, missing or wrong-mode previous manifest is an error.
  It is never treated as an empty baseline, because that would publish a whole
  bundle on a typo.
- A first run without a previous manifest writes the full bundle as before.
- A run with no changes writes **no files at all** — no dataset file, no
  manifest, no directory cleanup — prints `no changes` and exits 0.
- A run with changes writes the complete bundle, exactly as today, and reports
  which datasets were added, changed or removed and why.

`npm run compare` reports the same classification without building or writing
anything. It exits 0 whether or not there are changes (it is a report), and
non-zero only when an argument is missing or a manifest cannot be read or
validated. `--json` prints the machine-readable plan:

```json
{
  "mode": "regular",
  "hasChanges": true,
  "added": [],
  "changed": ["items"],
  "unchanged": ["tasks", "traders"],
  "removed": [],
  "reasons": {
    "items": "sha256 bc330ec05ae3 -> 0e11c1bce6b8",
    "tasks": "sha256 627bbfd58410 matches",
    "traders": "sha256 e5b5a695ca4d matches"
  },
  "previous": { "path": "/bundles/regular/manifest.json", "generatedAt": "2026-11-25T20:00:00.000Z" },
  "current": { "path": "/tmp/regular/manifest.json", "generatedAt": "2026-11-25T23:59:59.000Z" }
}
```

## Publication to GitHub Releases

Each game mode has **one rolling release**; the pipeline never creates a release
per build. A release is identified by its tag:

| Mode | Tag | Title |
|---|---|---|
| `regular` | `data-regular-latest` | `Tarkov Companion data — regular` |
| `pve` | `data-pve-latest` | `Tarkov Companion data — pve` |
| `pvp-season` | `data-pvp-season-latest` | `Tarkov Companion data — pvp-season` |

The stable manifest URL is therefore:

```
https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json
```

The repository is private today, so this URL requires an authenticated request
while it stays private. The client contract is the same once the repository is
public. Data releases are created with `--latest=false`, so they never become
the repository's "Latest" release (that slot is for app releases).

### Release assets

GitHub release assets are **flat**: an asset name cannot contain `/`, so the
mode directory from the local bundle layout cannot be uploaded as-is. Each
release holds exactly:

```
manifest.json
<dataset>-<sha12>.jsonl.zst
```

`<sha12>` is the first 12 lowercase hex characters of that dataset's `sha256`
(which is the checksum of the compressed `.jsonl.zst` bytes). For example:

```
items-bc330ec05ae3.jsonl.zst
tasks-627bbfd58410.jsonl.zst
```

A dataset asset is **immutable and content-addressed**: a changed dataset has a
different checksum, so it is uploaded under a new name and the previous asset is
left in place. That is what makes an interrupted publication recoverable.

Before upload, every `datasets[].path` in the manifest is rewritten from the
local file name (`items.jsonl.zst`) to the versioned asset name
(`items-bc330ec05ae3.jsonl.zst`). Every other manifest field is unchanged.

**Client resolution rule:** the client takes the stable manifest URL as its
base and resolves each dataset path relative to it:

```
new URL("items-bc330ec05ae3.jsonl.zst",
        "https://github.com/Tayuha/tarkov-companion/releases/download/data-regular-latest/manifest.json")
  -> https://github.com/Tayuha/tarkov-companion/releases/download/data-regular-latest/items-bc330ec05ae3.jsonl.zst
```

The resolved asset is a sibling in the same release; there is no `/<mode>/`
segment in the asset URL.

### Upload order and atomic swap

1. All changed or new dataset assets, sorted by dataset name.
2. `manifest.json` **last**.

Until the manifest is replaced, clients keep reading the previous manifest,
which still points at the old immutable assets. A client therefore never sees a
manifest that references an asset that has not finished uploading.

### Idempotency and the no-op rule

An asset that already exists with the same name and size is skipped. Because
asset names are content-addressed, "same name" already implies "same bytes" for
a healthy publication; the size check also repairs a partial or corrupted
upload.

`manifest.json` is replaced only when the task 2.7 comparison reports an added,
changed or removed dataset, a `bundleSchemaVersion`/`minAppSchemaVersion` change,
or when the published manifest does not use versioned asset paths. A rebuild
that only moves `generatedAt` (or upstream `ETag`/timestamps) is not a change.

Consequences:

- Re-running a publication with no upstream changes makes **zero create, upload
  or delete calls** and exits 0.
- A publication interrupted after some dataset uploads resumes on the next run:
  the already-uploaded assets are skipped by name + size and only the missing
  assets plus the manifest are sent.
- A missing release or a release without `manifest.json` means "publish
  everything"; existing matching dataset assets are still skipped.

### Pruning (opt-in)

`--prune` deletes dataset assets that the new manifest does not reference, after
the manifest swap. `manifest.json` is never a prune candidate.

Pruning is **off by default** because it removes rollback capability: a client
still holding the previous manifest may request an asset that has just been
deleted, and there is no way to roll the release back to the previous checksum.
Run it only when you accept losing the old datasets. Without pruning, old
immutable assets accumulate in the rolling release.

### Commands

```bash
cd pipeline

npm run bundle -- --all
npm run publish -- --mode regular --dry-run      # exact plan, zero mutations
npm run publish -- --mode regular                # create/update the rolling release
npm run publish -- --mode regular --prune        # also delete unreferenced assets
npm run publish -- --mode regular --json         # machine-readable report

# Custom tag (the manual test uses this one; it never touches data-regular-latest)
npm run publish -- --mode regular --tag data-test-regular-latest
```

Options:

| Option | Meaning |
|---|---|
| `--mode regular\|pve\|pvp-season` | Required. Selects the local mode directory and the default tag. |
| `--bundles <dir>` | Bundles root; default `dist/bundles`. |
| `--tag <tag>` | Release tag; default `data-<mode>-latest`. Custom tags are allowed, but a stable tag for another mode is refused. |
| `--dry-run` | Reads the release and prints the ordered plan; performs no create/upload/delete. |
| `--prune` | Deletes unreferenced dataset assets after the manifest swap. |
| `--json` | Prints the report as JSON instead of the human summary. |

Publication fails with a typed error and exit code 1 when `gh` is missing, gh is
not authenticated, the tag is invalid or belongs to another mode, the local
manifest is missing/invalid, a local dataset is missing, or a dataset file does
not match the manifest's size and SHA-256. Dry-run uses the same validation, so
a plan either reflects a publishable bundle or fails before any mutation.

## Client resolution

The client needs one configuration value per mode: the stable manifest URL. It
never builds a dataset URL by hand.

```
base = https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json
```

Algorithm:

1. **Fetch the manifest.** `GET base` with the stored `ETag`/`Last-Modified`
   (`If-None-Match` / `If-Modified-Since`). A `304` means the document is
   unchanged: stop, keep the database as it is. A `200` body is JSON; parse it.
2. **Check compatibility before touching data.**
   - `manifestVersion` must be one the client implements (currently `1`).
   - `mode` must equal the mode the client asked for.
   - `bundleSchemaVersion` must not be newer than the client supports.
   - `minAppSchemaVersion` must not be newer than the client's data schema.
     Also refuse a dataset whose `schemaVersion` is newer than the client
     supports, even if the aggregate looks acceptable.

   A failed check keeps the existing database and tells the user to update the
   app; it never partially applies a bundle.
3. **Compare checksums.** For each `datasets[]` entry, compare its `dataset`
   and `sha256` with the applied checksum stored in the client's
   `dataset_state`. Equal checksum → no download and no ingest (idempotent).
   Different or missing → download. Datasets listed under `skipped` are not in
   this bundle: keep their existing rows.
4. **Resolve each download relative to the manifest.** Use URL resolution, not
   string concatenation:

   ```
   url = new URL(entry.path, base)
   ```

   Locally `entry.path` is `items.jsonl.zst`; in a published bundle it is
   `items-bc330ec05ae3.jsonl.zst`. Both resolve to a sibling of the manifest
   (`manifest.json` is always the last path segment of `base`).
5. **Verify the bytes before parsing them.** The downloaded body must have
   exactly `compressedBytes` bytes and its SHA-256 must equal `sha256`
   (lowercase hex, computed over the compressed frame). On mismatch, discard
   the download, keep the old rows, and report a retriable sync error. Never
   decompress unverified bytes into the database.
6. **Decompress and read JSONL.** The payload is zstd, then UTF-8, then one
   JSON object per line. A line without non-empty string `kind` and `id` is a
   corrupt bundle: abort that dataset, keep the old rows. Ingestion may stream;
   it must not require the whole file in memory.
7. **Ingest one dataset atomically.** Inside one transaction: replace that
   dataset's rows (whole-dataset replacement, D3), write the applied `sha256`
   and `schemaVersion` to `dataset_state`, commit. Then refresh FTS and
   invalidate caches. A crash before commit leaves the previous rows and the
   previous `dataset_state` intact.
8. **Fail per dataset, not for the whole bundle.** A dataset that fails
   verification or ingestion keeps its old rows; the other datasets of the same
   manifest may still be applied. The next sync retries the failed one because
   its stored checksum still differs.

The manifest is authoritative for *which* datasets exist and *what bytes* they
are. `generatedAt`, `source.*`, sizes, record counts and `totals` are
diagnostics; a rebuild that only moves `generatedAt` must not trigger a
download.

## Versioning policy

Four independent numbers protect compatibility. A change in any of them is
published exactly like a data change: the release manifest is replaced, and the
comparison in [Comparison and no-op publishing](#comparison-and-no-op-publishing)
forces clients to reconsider the bundle even when dataset checksums match.

| Version | Bump when | Client behavior |
|---|---|---|
| `manifestVersion` | The manifest document shape changes: a field is added, removed, renamed, or its meaning changes. | Refuse a value it does not implement. Bumping requires a client release that understands the new document. |
| `bundleSchemaVersion` | The bundle-level contract changes for all datasets: path/asset scheme, compression format, JSONL envelope, or a rule in this document. | Refuse a newer value. A difference from the last applied value means re-check compatibility and re-ingest/revalidate every dataset; do not short-circuit on equal `sha256`. |
| `minAppSchemaVersion` | Any dataset's record schema becomes incompatible with an older app. The writer sets it to `max(1, datasets[].schemaVersion)`. | A client whose supported data schema is lower refuses the bundle and asks for an app update. Never guess at unknown fields. |
| `datasets[].schemaVersion` | That dataset's record shape changes incompatibly (field removed/retyped/renamed, new required semantics). | The client must implement it for that dataset. `minAppSchemaVersion` is the aggregate shortcut; a client that inspects per-dataset versions may apply the datasets it supports and skip the others. |

Rules:

- Versions only move forward in a published release. A client must accept a
  `bundleSchemaVersion` **lower** than its maximum (an older compatible
  bundle), but never a higher one.
- A `bundleSchemaVersion` or `minAppSchemaVersion` change reclassifies every
  dataset present on both sides as `changed` in the publisher's comparison, so
  a silent no-op cannot strand clients on a different contract.
- The same normalized record bytes always keep the same `sha256`; a version
  bump alone does not rename dataset assets. Clients that cached the bytes may
  reuse them, but must still re-run the compatibility checks.
- `NORMALIZED_CACHE_VERSION` (documented in
  [`data-sync.md`](data-sync.md#cache-behavior)) is a pipeline-internal cache
  key, not part of the bundle manifest. Bump it when the record shape changes
  so a stale normalized cache entry cannot be reused; it never reaches a
  client.

## Normalization conventions

Normalization (`pipeline/src/normalize/`) is the boundary between the validated,
localized upstream payload and the JSONL contract. It is pure: no I/O, no
clock, no randomness. Each line has this envelope:

```json
{"id":"5447a9cd4bdc2dbd208b4567","kind":"item","name":"Colt M4A1 5.56x45 assault rifle"}
```

`kind` selects the record shape and `id` identifies the record within its
dataset. Fields are projected through an explicit per-kind spec, so an upstream
addition is dropped and counted rather than silently entering the bundle.

| Concern | Convention |
|---|---|
| Field names | `camelCase`. |
| Identifiers | Non-empty strings. Upstream numeric ids are stringified. |
| References | End in `Id` / `Ids`: `traderId`, `traderIds`, `mapId`, `mapIds`, `itemId`, `itemIds`, `stationId`, `taskId`, `questItemId`, `keyItemId`, `achievementId`. |
| Related entities | Referenced by id only; the client joins locally. No entity objects are embedded. |
| Money | Integer number of roubles (`Math.round`). `currency` stays the upstream code (`RUB`, `USD`, ...). |
| Weight | Kilograms, as a number (upstream already serves kg). |
| Grid size | Integers (`width`, `height`). |
| Durations | Integer seconds (`raidDuration`, `constructionTime`, `craft.duration`). |
| Timestamps | ISO 8601 UTC strings ending in `Z`. Upstream epoch-millisecond strings are converted. |
| Objective types | `type` is always present. Only the fields admitted for that type are emitted; absent union fields are omitted, never `undefined`. |
| Opaque payloads | `map.btrStops` and `map.switches[].door` are copied as validated because upstream has no observable element shape. |

### Upstream drift tolerance

The live API is slightly richer than the trimmed fixtures. These allowances are
deliberate and do not change the bundle shape:

- `item.wikiLink` may be an empty string when there is no wiki page.
- Item price fields (`avg24hPrice`, `changeLast48h`, `changeLast48hPercent`,
  `lastLowPrice`, `lastOfferCount`, `lastScan`) may be absent on PvE items; the
  normalized `price` object writes `null` for them.
- `item.properties.propertiesType` and the nullable property numbers (`moa`,
  `defaultWidth`, `defaultHeight`, `defaultPreset`, `defaultAmmo`,
  `hpCostHeavyBleeding`, `hpCostLightBleeding`) may be absent or `null`.
- `task.experience` may be `null`; a null is kept as `null`.
- Map `hazards[]` may omit `top`/`bottom`, `bosses[]` may omit
  `spawnTimeRandom`, and `extracts[]` may omit `faction`.
- Map `switches[]` upstream `activates` entries are `{operation, switch}`; the
  bundle stores `{operation, switchId}`. `activatedBy` is a boolean or the id
  of the activating switch.
- Task objectives serve `notWearing` as `{id, name}` objects; the bundle keeps
  only `notWearingItemIds`.
- Craft `requiredQuestItems` entries are `{item}`; the bundle stores
  `{itemId}`.

### Dropped denormalized names

Upstream repeats display names next to references. Normalization drops those
duplicates and keeps the reference, so the client has exactly one source of
truth per entity and a rename in `items` is visible everywhere without
re-publishing every dataset:

- Task `wearing` / `notWearing` entries are `{id, name}` objects; the bundle
  keeps only the ids (`wearingItemIds`, `notWearingItemIds`).
- `possibleLocations[].map` and `zones[].map` become `mapId`; the map display
  name is not copied.
- Trader offers keep `traderId`, not the trader name; `currencyItemId`, not the
  currency item name.
- `goonReport` keeps `mapId`, not the map name.

The only intentional display-text exception is the customization fallback in
[Intentional embedded values](#intentional-embedded-values). Dropped fields are
counted per dataset in `stats.droppedFields`/`stats.droppedFieldPaths`; the
committed fixtures drop exactly the denormalized worn-item names plus one
unmodelled `craftUnlock.trader_name` (see
[Dropped fields in the fixtures](#dropped-fields-in-the-fixtures)).

### Price object

Items carry the live price snapshot in `price`:

```json
"price": {
  "lastLow": 40000,
  "avg24h": 111351,
  "low24h": 28888,
  "high24h": 900000,
  "change48h": 16102,
  "change48hPercent": 16.91,
  "lastOfferCount": 36,
  "observedAt": "2026-11-25T17:08:02.000Z"
}
```

All money fields are roubles. `change48hPercent` is a percentage, not money.
Missing values are `null`, never omitted, so "no data" is explicit.
`observedAt` is the upstream `lastScan`. The root `lastScan`, `avg24hPrice`,
`changeLast48h`, `changeLast48hPercent`, `high24hPrice`, `lastLowPrice`,
`low24hPrice` and `lastOfferCount` fields are folded into `price` and are not
emitted again.

### Trader offers

```json
"buyFromTrader": [
  { "traderId": "5a7c2eca...", "price": 22997, "currency": "RUB",
    "currencyItemId": "5449016a...", "loyaltyLevel": 3, "buyLimit": 5,
    "restockAmount": 100000, "taskUnlockId": null }
],
"sellToTrader": [
  { "traderId": "54cb50c7...", "price": 18000, "currency": "RUB",
    "currencyItemId": "5449016a..." }
]
```

`loyaltyLevel` is the upstream `minTraderLevel` and is only present when
upstream provides it. `buyLimit` is the upstream `buyLimit` and is **omitted
when upstream sends `null`** (no purchase limit). `currencyItemId` is the item
used to pay (for example the roubles item id). `restockAmount` is the stock per
trader reset. `taskUnlockId` references a task that unlocks the offer, or is
`null` when no task is required; it is always present on buy offers.

## Intentional embedded values

- `task.finishRewards.customization[].name` is `"Unnamed customization"` when
  upstream has no dictionary entry for the name. This is the only place where
  normalization writes display text; the design requires a labelled fallback
  instead of publishing an unresolved key. The counter
  `stats.fallbacks.customizationName` reports how many were substituted.
- `craft.productItem`, `barter.offeredItem` and the various `requiredItems`
  entries keep `{ itemId, count, attributes }` rather than a bare id, because
  the count/attributes are part of the recipe, not of the referenced item.

## Record kinds

Counts below are the committed fixture output (2026-11-25), used by the golden
tests.

| Dataset | Kinds (count) | Records |
|---|---|---|
| `items` | `item` 60, `itemCategory` 142, `handbookCategory` 117, `fleaMarket` 1, `armorMaterial` 8, `playerLevel` 79, `mastering` 82, `skill` 49, `specialItem` 38, `setting` 1 | 577 |
| `tasks` | `task` 80, `questItem` 138, `achievement` 131, `prestige` 6 | 355 |
| `traders` | `trader` 16 | 16 |
| `hideout` | `hideoutStation` 26 | 26 |
| `crafts` | `craft` 20 | 20 |
| `barters` | `barter` 20 | 20 |
| `maps` | `map` 2, `mob` 2, `lootContainer` 43, `stationaryWeapon` 2, `goonReport` 1 | 50 |

Synthetic ids: `fleaMarket` and `setting` use `id` equal to the collection name;
`playerLevel` uses the level as a string; `specialItem` uses the item id;
`goonReport` uses `<mapId>@<observedAt>` (there can be more than one report per
map over time).

## Objectives

Common fields: `id`, `type`, `description`, `optional`, `mapIds`.

Type-specific fields (renamed references in parentheses):

| Type | Fields |
|---|---|
| `buildWeapon` | `buildAttributes`, `containsAllItemIds`, `containsCategoryIds`, `count`, `itemId`, `zones` |
| `dialogue` | `count`, `traderIds`, `zones` |
| `experience` | `bodyParts`, `count`, `effects`, `healthEffect`, `zones` |
| `extract` | `bodyParts`, `count`, `effects`, `exitName`, `exitStatus`, `healthEffect` |
| `findItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability`, `zones` |
| `findQuestItem` | `count`, `possibleLocations`, `questItemId`, `requiredKeyItemIds` |
| `giveItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability` |
| `giveQuestItem` | `count`, `questItemId` |
| `globalVariable` | `count`, `globalVariable`, `zones` |
| `haveItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability` |
| `hideoutStation` | `count`, `stationId`, `stationLevel` |
| `mark` | `count`, `markerItemId`, `requiredKeyItemIds`, `zones` |
| `plantItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability`, `requiredKeyItemIds`, `zones` |
| `plantQuestItem` | `count`, `questItemId`, `requiredKeyItemIds`, `zones` |
| `playerLevel` | `count`, `playerLevel` |
| `sellItem` | `count`, `dogTagLevel`, `foundInRaid`, `itemIds`, `maxDurability`, `minDurability`, `zones` |
| `shoot` | `bodyParts`, `count`, `distance`, `effects`, `enemyHealthEffect`, `healthEffect`, `notWearingItemIds`, `playerHealthEffect`, `shotType`, `targetNames`, `timeFromHour`, `timeUntilHour`, `usingWeaponItemIds`, `usingWeaponModItemIds`, `wearingItemIds`, `zones` |
| `skill` | `level`, `skill`, `zones` |
| `taskStatus` | `count`, `status`, `taskId`, `zones` |
| `traderLevel` | `level`, `traderId` |
| `traderStanding` | `compareMethod`, `traderId`, `value` |
| `useItem` | `compareMethod`, `count`, `useAnyItemIds`, `zones` |
| `visit` | `requiredKeyItemIds`, `zones` |

`wearing` is reduced to `wearingItemIds` (arrays of item ids); upstream also
embeds each worn item's name, which is dropped because the item dataset is the
source of names. `zones[].map` becomes `zones[].mapId`; a zone keeps its own
`id`, geometry and optional `name`. `possibleLocations[].map` becomes `mapId`.

## Dropped fields in the fixtures

`items` drops no fields. Every trader-offer field the item schema validates is
preserved: `currencyItemId`, `restockAmount` and `taskUnlockId` now join the
price and loyalty fields.

`tasks` drops 17: 16 embedded worn-item `name` values (denormalized display
names) and one upstream `craftUnlock.trader_name` that the schema does not
model. Every other dataset drops zero fields.

## Build one by hand

This tutorial uses only Node built-ins (Node 24+). It produces the same shape as
the committed example in `test/fixtures/handbuilt-bundle/`, with one dataset
and two records.

### 1. Write the JSONL payload

```bash
mkdir -p /tmp/my-bundle && cd /tmp/my-bundle
cat > items.jsonl <<'EOF'
{"id":"example-ammo","kind":"item","name":"Example 5.56x45 cartridge","price":{"avg24h":120,"currency":"RUB","lastLow":110},"shortName":"Example ammo"}
{"id":"example-rifle","kind":"item","name":"Example 5.56x45 assault rifle","price":{"avg24h":45000,"currency":"RUB","lastLow":41000},"shortName":"Example rifle"}
EOF
```

Rules from [File rules](#file-rules): one JSON object per line, every object has
a non-empty string `kind` and `id`, `kind`+`id` is unique, keys are canonical
(sorted recursively), records sort by `kind` then `id`, and the file ends with
one newline. The `heredoc` above already satisfies them for this example.

### 2. Compress, hash and write the manifest

```bash
cat > build-bundle.mjs <<'EOF'
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { constants, zstdCompressSync } from "node:zlib";

const dataset = "items";
const payload = readFileSync(`${dataset}.jsonl`);
const frame = zstdCompressSync(payload, {
  params: {
    [constants.ZSTD_c_compressionLevel]: 3,
    [constants.ZSTD_c_nbWorkers]: 0,
    [constants.ZSTD_c_checksumFlag]: 0,
  },
});
writeFileSync(`${dataset}.jsonl.zst`, frame);

const sha256 = createHash("sha256").update(frame).digest("hex");
const records = payload.toString("utf8").trimEnd().split("\n").length;

const manifest = {
  manifestVersion: 1,
  bundleSchemaVersion: 1,
  minAppSchemaVersion: 1,
  mode: "regular",
  generatedAt: new Date().toISOString(),
  source: { baseUrl: null, capturedAt: null },
  totals: {
    datasets: 1,
    records,
    uncompressedBytes: payload.byteLength,
    compressedBytes: frame.byteLength,
  },
  datasets: [{
    dataset,
    path: `${dataset}.jsonl.zst`,
    schemaVersion: 1,
    sha256,
    compressedBytes: frame.byteLength,
    uncompressedBytes: payload.byteLength,
    records,
    source: { url: null, lastModified: null, etag: null, fetchedAt: null },
  }],
  skipped: [],
};

const sortKeys = (value) => {
  if (Array.isArray(value)) return value.map(sortKeys);
  if (typeof value !== "object" || value === null) return value;
  return Object.fromEntries(
    Object.keys(value).sort().map((key) => [key, sortKeys(value[key])]),
  );
};

writeFileSync("manifest.json", `${JSON.stringify(sortKeys(manifest))}\n`);
EOF
node build-bundle.mjs
rm items.jsonl          # optional: the plain JSONL is not part of the bundle
```

The key arithmetic is exactly what a client verifies:

- `sha256` covers the **compressed** frame (`frame`), not the JSONL text;
- `compressedBytes` is `frame.byteLength`;
- `uncompressedBytes` is the UTF-8 length of the JSONL payload;
- `records` is the number of JSONL lines (the trailing newline is not a record);
- `minAppSchemaVersion` is at least every dataset `schemaVersion`.

The manifest built above uses `null` source metadata, which is valid. The
result is:

```
/tmp/my-bundle/
  manifest.json
  items.jsonl.zst
```

### 3. Validate it

```bash
cd /path/to/tarkov-companion/pipeline
npm run validate:bundle -- --dir /tmp/my-bundle
```

```
bundle /tmp/my-bundle
  mode regular  generatedAt 2026-11-26T...
  ok   items         2 records       169 B  sha256 51a8d9ea1bae  items.jsonl.zst
PASS: 1 dataset(s), 0 error(s), 0 warning(s)
```

The compressed size and checksum will differ if you use a different Node/zlib
version — the script writes the manifest from the frame it actually produced,
so the validator still passes. Only the compressor version changes those bytes;
the JSONL is deterministic.

`test/fixtures/handbuilt-bundle/` is this bundle with a fixed `generatedAt`,
and `pipeline/src/bundle/validate.test.ts` rebuilds every failure mode from it.

## Validating a bundle

```bash
cd pipeline
npm run validate:bundle -- --dir <bundle-dir>          # human summary
npm run validate:bundle -- --dir <bundle-dir> --json   # machine-readable
```

`--dir` points at a mode directory (the directory that contains
`manifest.json`), locally or after unzipping downloaded release assets. The
command performs no network access. It exits `0` only when there are no errors;
any error exits `1`. Warnings never change the exit code.

| Check | Error code |
|---|---|
| `manifest.json` exists and is valid JSON | `invalid-json` (missing manifest is a CLI error) |
| Manifest matches `manifestSchema`, including required fields, version literals and `sha256` shape | `invalid-manifest` |
| A dataset name is listed once | `duplicate-dataset` |
| `minAppSchemaVersion` is at least every `datasets[].schemaVersion` | `min-app-schema-mismatch` |
| Every `path` is a flat, traversal-free file name (no `/` or `\`, not `.` or `..`) | `unsafe-path` |
| Every referenced file exists | `missing-file` |
| The file's byte length equals `compressedBytes` | `size-mismatch` |
| SHA-256 of the compressed file equals `sha256` | `sha256-mismatch` |
| The file decompresses as zstd | `zstd-error` |
| Decompressed length equals `uncompressedBytes` | `uncompressed-size-mismatch` |
| The payload is valid UTF-8 | `invalid-utf8` |
| Every line is a JSON object with non-empty `kind` and `id` | `invalid-jsonl`, `invalid-record` |
| `kind`+`id` is unique | `duplicate-record` |
| Line count equals `records` | `record-count-mismatch` |
| No string value matches the localization placeholder pattern | `placeholder` |
| The payload is not empty | `empty-dataset` |

Warnings (reported, exit 0): `extra-file` for a file the manifest does not
reference (directory entries are reported the same way, with a trailing `/`),
`missing-trailing-newline`, `totals-mismatch`, and `skipped-with-file` (a
dataset listed under `skipped` still has a file).

`--json` prints one object:

```json
{
  "dir": "/tmp/my-bundle",
  "manifest": "/tmp/my-bundle/manifest.json",
  "ok": true,
  "mode": "regular",
  "generatedAt": "2026-11-26T00:00:00.000Z",
  "datasets": [
    { "dataset": "items", "path": "items.jsonl.zst", "ok": true,
      "records": 2, "compressedBytes": 169,
      "sha256": "51a8d9ea1baebb73d840ea4229f331f41fbf6d1fa2bc4f3ad12792d94a334926" }
  ],
  "errors": [],
  "warnings": []
}
```

The validator is the executable form of this document. `npm test` runs it
against the hand-built fixture and against a mutated copy for each error code
above, so a documentation change that the code does not implement fails CI.

## Produce and verify

```bash
cd pipeline
npm run normalize -- --all                 # dist/normalized/<dataset>.jsonl
npm run normalize -- --dataset items --out /tmp/normalized

npm run bundle                             # regular -> dist/bundles/regular/
npm run bundle -- --mode pve               # one mode
npm run bundle -- --all                    # every mode with fixtures
npm run bundle -- --mode regular --out /tmp/bundles
npm run bundle -- --mode regular --previous /tmp/bundles          # skip when unchanged
npm run bundle -- --mode regular --previous /tmp/bundles/regular/manifest.json

npm run compare -- --previous /tmp/bundles/regular/manifest.json \
                   --current /tmp/fresh/regular/manifest.json      # human summary
npm run compare -- --previous old.json --current new.json --json   # machine output

npm run publish -- --mode regular --dry-run                  # plan only, no mutations
npm run publish -- --mode regular                            # rolling release
npm run publish -- --mode regular --prune                    # also drop old assets
npm run publish -- --mode regular --tag data-test-regular-latest

npm run validate:bundle -- --dir dist/bundles/regular        # contract check
npm run validate:bundle -- --dir dist/bundles/regular --json
npm run validate:bundle -- --dir ../test/fixtures/handbuilt-bundle

npm test                                   # golden, bundle, comparison, release and invariant suite
```

`--previous` accepts three forms:

- a manifest file: `/tmp/bundles/regular/manifest.json`;
- a bundles root: `/tmp/bundles`, resolved as `/tmp/bundles/<mode>/manifest.json`;
- a mode directory: `/tmp/bundles/regular`, resolved as `<dir>/manifest.json`.

With `--all`, use a directory form that contains a manifest for every selected
mode; a single manifest file is only unambiguous for one mode.

`npm run compare` only reads the two manifests: it never builds, never writes and
exits 0 even when datasets differ. See
["Comparison and no-op publishing"](#comparison-and-no-op-publishing) for the
classification rules and the JSON shape.

`npm run publish` is the only pipeline command that touches the network. It
needs `gh` installed and authenticated (`GH_TOKEN`/`GITHUB_TOKEN` are honored)
because it reads the current release manifest and asset list; `--dry-run` makes
no create/upload/delete call. The release test suite runs the publisher offline
against an in-memory release client.

`npm run normalize` localizes and validates each committed fixture offline,
normalizes it, and writes the plain JSONL with per-kind counts, output bytes,
dropped-field counts and fallbacks. `npm run bundle` runs the same load path and
then writes the zstd files and manifest, printing records, uncompressed and
compressed bytes, compression ratio, a checksum prefix, skipped datasets and
the manifest path. With `--previous` it first compares the in-memory build with
the published manifest and prints `no changes ... nothing written` instead of
touching the output directory.

To confirm determinism locally, build twice and compare the checksums:

```bash
cd pipeline
npm run bundle -- --mode regular --out /tmp/bundle-a
npm run bundle -- --mode regular --out /tmp/bundle-b
jq -S '.datasets' /tmp/bundle-a/regular/manifest.json > /tmp/a.json
jq -S '.datasets' /tmp/bundle-b/regular/manifest.json > /tmp/b.json
diff /tmp/a.json /tmp/b.json
```

The `datasets` arrays must be identical (including every `sha256`); only
`generatedAt` changes between runs.

Tests cover the writer offline: the regular fixture set is rebuilt twice and
must produce identical compressed bytes and checksums, every file is
decompressed back to the committed normalized golden, the manifest is validated
with Zod, records are counted, input order is reversed to prove order
independence, and the `pve`/`pvp-season` marker bundles and the
missing/empty-dataset rules are exercised.

Comparison tests run the real CLIs in temp directories: a second
`bundle --previous` run over the same fixtures emits no files and exits 0,
changed/added/removed datasets are classified individually, a
`bundleSchemaVersion` or `minAppSchemaVersion` bump marks every dataset changed,
timestamp-only differences compare as unchanged, and invalid or missing previous
manifests exit non-zero with an error naming the problem. `npm run compare`
covers both exit codes and the `--json` shape.

Validator tests run offline: the committed `test/fixtures/handbuilt-bundle/`
passes, and a copy mutated for each error code (missing file, wrong size, bad
SHA-256, corrupt zstd, invalid JSONL, missing `kind`/`id`, duplicate `kind`+`id`,
wrong record count, placeholder text, traversal path, an aggregate schema version
below a dataset's, schema-invalid manifest) fails with that code. The CLI cases cover the human summary, `--json`, exit `0`,
exit `1`, and a directory without `manifest.json`.
