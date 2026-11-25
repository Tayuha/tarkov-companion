# Data bundles

> OpenSpec task 2.6 implements the bundle writer (zstd data files + manifest),
> task 2.7 the comparison/no-op gate, and task 2.8 publication to GitHub
> Releases. Task 2.10 finalizes the public contract. This document already
> describes the exact bytes and manifest fields the writer produces and the
> release layout the publisher uses; treat changes here as a contract change.

The pipeline turns each validated, localized upstream dataset into **JSONL**:
one JSON object per line, one record kind per line. The app ingests the records
into its own SQLite schema; it never interprets raw `json.tarkov.dev` payloads.

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
- `manifest.json` `path` values are file names relative to the manifest's own
  directory (`items.jsonl.zst`), so the client concatenates its bundle base URL
  with the path.
- The design sketch in `design.md` (D2) showed one root `manifest.json` plus
  `bundles/<mode>/…`. The writer keeps a manifest **inside each mode directory**
  instead: the mode is part of the bundle identity, and a client downloads a
  single self-describing document for its active mode. Publication maps this
  layout to release assets under `bundles/<mode>/`.
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
- The file ends with a single trailing newline. The same validated input always
  produces byte-identical output.
- Text is English (`en`) only for now. Localization is resolved before
  normalization; a placeholder-shaped string is a normalization failure.
- Unknown upstream fields are dropped rather than passed through. The
  normalizer counts them per dataset (`droppedFields`, `droppedFieldPaths`) so
  a contract change is visible in the build log.

## Manifest

One `manifest.json` per mode, written as canonical JSON (object keys sorted
recursively, no insignificant whitespace) with a single trailing newline.

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

| Field | Meaning |
|---|---|
| `manifestVersion` | Version of this manifest document (`1`). Bump for a shape change to the manifest itself. |
| `bundleSchemaVersion` | Version of the bundle layout/contract as a whole (`1`). A client refuses a bundle whose value is newer than it supports. |
| `minAppSchemaVersion` | Oldest app data-schema version that can ingest every dataset here; currently the maximum of the per-dataset `schemaVersion` values. A client whose supported data schema is lower must update the app instead of applying the bundle. A newer-than-supported `bundleSchemaVersion` is refused the same way. |
| `mode` | `regular`, `pve`, or `pvp-season`. |
| `generatedAt` | Wall-clock timestamp of this build. **Intentionally not reproducible**; it is the only manifest field that may differ between two builds of identical data. |
| `source.baseUrl` | Upstream base URL the fixtures were captured from. |
| `source.capturedAt` | When the upstream fixture set was captured (`fetchedAt` of the fixture manifest). |
| `datasets[]` | Present datasets, sorted by `dataset`. |
| `datasets[].dataset` | Dataset name, e.g. `items`. |
| `datasets[].path` | File name relative to the manifest directory. |
| `datasets[].schemaVersion` | Record schema version of that dataset (`1` today). Each dataset can be versioned independently. |
| `datasets[].sha256` | Lowercase hex SHA-256 of the compressed `.jsonl.zst` file. |
| `datasets[].compressedBytes` | Exact size of the file on disk. |
| `datasets[].uncompressedBytes` | Size of the JSONL payload before compression. |
| `datasets[].records` | Number of JSONL lines (one bundle record per line). |
| `datasets[].source.url`, `.lastModified`, `.etag`, `.fetchedAt` | Upstream source timestamp(s) and validators recorded in the fixture manifest for this dataset; `null` when unavailable. |
| `totals` | Sums across `datasets[]`; `records` is the sum of per-dataset line counts. |
| `skipped[]` | Datasets not written in this build, sorted by `dataset`, each with `reason: "not-supplied"`. No file exists for them; a client must keep its existing rows. |

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
- Manifest datasets and `skipped` entries are sorted; manifest keys are
  canonical; the newline ending is fixed.
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

## Field conventions

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
upstream provides it. `currencyItemId` is the item used to pay (for example the
roubles item id). `restockAmount` is the stock per trader reset.
`taskUnlockId` references a task that unlocks the offer, or is `null` when no
task is required; it is always present on buy offers.

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
