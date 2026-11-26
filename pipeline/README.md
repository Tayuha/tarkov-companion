# Pipeline

Normalizes `json.tarkov.dev` data into versioned bundles for the app. See
[`../openspec/changes/bootstrap-tarkov-companion/design.md`](../openspec/changes/bootstrap-tarkov-companion/design.md)
for the architecture and [`../NOTICE`](../NOTICE) for attribution.

## Status

Implemented so far:

- Minimal JSONPath resolver for the upstream `translations` pointers (`$`, `.key`, `.*`, `[n]`, `[*]`,
  `..key`, `..*`, `['a','b']`).
- Locale dictionary lookup and in-place resolution with diagnostics.
- Fetch helper with timeouts, retries, user agent, and strict dictionary handling.
- Conditional requests (`If-None-Match` / `If-Modified-Since`) plus a per-dataset checksum cache, so an
  unchanged dataset is skipped instead of re-downloaded and re-published.
- CLI to inspect any dataset.
- Deterministic, committed upstream fixtures for the pipeline tests (`test/fixtures/upstream/`).
- Zod schemas for every captured dataset, with a registry keyed by `{mode, dataset}` and an offline
  fixture-validation CLI.
- Deterministic normalization from the localized upstream shape to bundle JSONL records, with a dataset
  registry, per-kind counts, dropped-field stats, and golden-file tests.
- Deterministic bundle writing: per-dataset `.jsonl.zst` files plus a canonical `manifest.json` with
  SHA-256 checksums, sizes, schema versions and upstream source timestamps, offline from the committed
  fixtures.
- Content-based bundle comparison and no-op gating: `bundle --previous` writes nothing when no dataset
  checksum changed, and `npm run compare` reports the per-dataset plan.
- Idempotent publication to GitHub Releases: one rolling release per mode, content-addressed dataset
  assets, a stable `manifest.json` pointer swapped last, and a dry-run plan with zero mutations.
- Production sync orchestration (`npm run sync`) and the scheduled `.github/workflows/data-sync.yml`:
  live fetch with the conditional cache, schema validation, normalization, normalized-JSONL cache,
  bundling, publication, per-mode failure isolation, and a single `Data sync failing` issue lifecycle.
  Operational guide: [`../docs/data-sync.md`](../docs/data-sync.md).
- Bundle contract validation (`npm run validate:bundle`): manifest schema, file presence, compressed
  size and SHA-256, zstd decompression, JSONL records and ids, record counts, placeholder strings and
  path traversal. It also passes the hand-built example in `test/fixtures/handbuilt-bundle/`.

Bundle writing uses zstd from `node:zlib`, so the pipeline requires **Node 24 or newer** (declared in
`engines`); no native module or WASM dependency is involved.

## Usage

```bash
npm ci
npm test
npm run lint
npm run build
npm run validate:fixtures   # offline: parse every committed fixture through its schema
npm run normalize -- --all  # offline: write dist/normalized/<dataset>.jsonl
npm run normalize -- --dataset items --out /tmp/normalized
npm run bundle               # offline: write dist/bundles/regular/
npm run bundle -- --mode pve
npm run bundle -- --all      # every mode with fixtures
npm run bundle -- --mode regular --out /tmp/bundles

# Check a bundle directory against the published contract (offline)
npm run validate:bundle -- --dir dist/bundles/regular
npm run validate:bundle -- --dir dist/bundles/regular --json
npm run validate:bundle -- --dir ../test/fixtures/handbuilt-bundle

# Compare with a published bundle and skip writing when nothing changed
npm run bundle -- --mode regular --previous /tmp/bundles
npm run bundle -- --mode regular --previous /tmp/bundles/regular/manifest.json

# Report a comparison without building or writing anything
npm run compare -- --previous /tmp/old/regular/manifest.json --current /tmp/new/regular/manifest.json
npm run compare -- --previous old.json --current new.json --json

# Publish the built bundle to its rolling GitHub release (network)
npm run publish -- --mode regular --dry-run      # exact plan, zero mutations
npm run publish -- --mode regular                # create/update data-regular-latest
npm run publish -- --mode regular --prune        # also delete unreferenced assets
npm run publish -- --mode regular --json
npm run publish -- --mode regular --tag data-test-regular-latest

# Production sync: fetch -> validate -> normalize -> bundle -> publish (network)
npm run sync -- --all                            # every mode, rolling releases
npm run sync -- --mode regular --dry-run         # read the release, mutate nothing
npm run sync -- --all --force                    # bypass conditional-request validators
npm run sync -- --all --fixtures ../test/fixtures/upstream --dry-run   # offline plan

# CI failure-issue reporter (used by .github/workflows/data-sync.yml)
npm run report:status -- --status success --run-url https://github.com/Tayuha/tarkov-companion/actions/runs/0

# Inspect a dataset with real data
npm run fetch -- --dataset traders --sample 3
npm run fetch -- --dataset items --sample 3 --out /tmp/items.localized.json

# Refresh the committed upstream fixtures (network; rewrites test/fixtures/upstream/)
npm run fixtures
npm run fixtures -- --refresh   # ignore cached validators and re-download everything
```

Options: `--mode regular|pve|pvp-season`, `--dataset <name>`, `--lang <code>` (default `en`),
`--base-url <url>`, `--out <file>`, `--sample <n>`, `--cache-dir <dir>`, `--refresh`.

Fixtures keep unresolved placeholders plus a filtered `_en` dictionary so tests exercise the
resolver. See [`../test/fixtures/README.md`](../test/fixtures/README.md) for the trimming policy,
layout, budget, and stale-pointer notes.

## Schema validation

Upstream payloads are validated with Zod before normalization. One module per dataset, plus shared
primitives:

```
pipeline/src/schemas/
  primitives.ts   ids, timestamps, URLs, prices, vectors, item filters
  envelope.ts     { data, translations? } and { data: Record<string, string> }
  items.ts        /{mode}/items (named collections, property unions)
  tasks.ts        /regular/tasks (+ questItems, achievements, prestige)
  traders.ts      /regular/traders (id-keyed)
  hideout.ts      /regular/hideout (id-keyed)
  crafts.ts       /regular/crafts (array)
  barters.ts      /regular/barters (array)
  maps.ts         /regular/maps (maps, mobs, loot containers, …)
  prices.ts       /regular/prices/{itemId} (array)
  status.ts       /common/status
  season.ts       /pvp-season/season
  registry.ts     {mode, dataset} -> schema, envelope, counts
  fixtures.ts     offline fixture discovery helpers
```

`registry.ts` is the only place that maps a fixture to a schema. The test suite fails if a fixture
directory/dataset has no schema, or if a registered schema has no fixture, so a newly captured dataset
cannot slip through unvalidated.

Strictness policy:

- Objects are **loose**: unknown upstream fields are preserved and ignored, so a new field never breaks
  a build. Known fields are strictly typed; a missing required field or a retyped one fails with a Zod
  path naming it.
- Fields selected by a discriminator (`ItemProperties*.propertiesType`, task objective `type`) are
  typed but optional unless the fixture shows them on every record. The committed fixtures are trimmed
  snapshots, so requiring every per-type field would reject valid upstream records.
- Nulls and `nullish` are only used where a fixture justifies them: nullable price fields, task `map`,
  barter `taskUnlock`, trader multipliers, season `points`, prestige customization `imageLink`, and
  the few objective fields that are both absent and `null`.
- Entity references (item, task, trader ids) are validated as non-empty strings, never checked for
  existence: a fixture may reference a record trimmed out of another dataset.
- Empty arrays are always valid.

```bash
npm run validate:fixtures
```

The CLI parses every committed base fixture and every dictionary, prints per-dataset record counts, and
exits non-zero on the first schema regression. It performs no network I/O.

## Normalization

`src/normalize/` converts a validated, localized payload into the bundle record shape. It is pure: no
I/O, no clock, no randomness.

```
pipeline/src/normalize/
  contract.ts   BundleRecord, field projection, ids/money/timestamps, contract checks
  items.ts      item + itemCategory, handbookCategory, fleaMarket, armorMaterial,
                playerLevel, mastering, skill, specialItem, setting
  tasks.ts      task + questItem, achievement, prestige
  traders.ts    trader
  hideout.ts    hideoutStation
  crafts.ts     craft
  barters.ts    barter
  maps.ts       map, mob, lootContainer, stationaryWeapon, goonReport
  registry.ts   dataset -> normalizer, deterministic ordering
  index.ts      normalizeDataset() and serializeJsonl()
```

- Every line has `kind` and `id`; `kind` + `id` is unique per dataset.
- Records sort by `kind` then `id`, keys are canonical, and the file has a trailing newline, so the same
  input is byte-identical output.
- References are ids ending in `Id`; related entities are never embedded. Money is integer roubles,
  weights are kilograms, grid sizes are integers, and timestamps are ISO 8601 UTC strings.
- Items fold the price snapshot into a `price` object; task objectives are discriminated by `type` and
  only carry the fields their type admits.
- Unknown upstream fields are dropped and counted in `stats.droppedFields`; a placeholder-shaped string,
  duplicate `kind`+`id`, missing id or non-finite number fails normalization.

The full contract is in [`../docs/data-bundles.md`](../docs/data-bundles.md). Goldens for every dataset
live in `test/fixtures/normalized/` and are compared byte for byte by `npm test`.

## Bundling

```
pipeline/src/bundle/
  manifest.ts   version constants, Zod manifest schema, canonical serializer
  zstd.ts       deterministic zstd wrapper (built-in node:zlib)
  writer.ts     buildBundle() (no I/O) and writeBundle() (atomic files)
  compare.ts    compareBundles(), manifest loading, no-op classification
  validate.ts   pure contract validator (manifest, bytes, JSONL, paths)
  index.ts      public exports
pipeline/src/fixtures/bundle-set.ts   fixtures -> normalized bundle input
pipeline/src/cli/bundle.ts            npm run bundle (with --previous)
pipeline/src/cli/compare.ts           npm run compare
pipeline/src/cli/validate-bundle.ts   npm run validate:bundle
```

Output layout (relative to `--out`, default `dist/bundles`):

```
<out>/<mode>/manifest.json
<out>/<mode>/<dataset>.jsonl.zst
```

**Compression.** zstd comes from Node's built-in `node:zlib` (`zstdCompressSync`): no native module, no
WASM, no build step. The writer pins **level 3**, a single worker thread and no frame checksum, so the
frame depends only on the input and the compressor version. Node 24+ is required (see `engines`).

**Manifest.** Canonical JSON with sorted keys and a trailing newline. It carries `manifestVersion`,
`bundleSchemaVersion`, `minAppSchemaVersion`, `mode`, `generatedAt`, per-mode source info and, per
dataset: `dataset`, relative `path`, `schemaVersion`, `sha256` of the compressed file,
`compressedBytes`, `uncompressedBytes`, `records`, and the upstream `source` (`url`, `lastModified`,
`etag`, `fetchedAt`). Datasets the caller did not supply appear under `skipped` with reason
`not-supplied`. `minAppSchemaVersion` is the oldest app data schema that can ingest every dataset; a
client below it must update. Field-by-field detail: [`../docs/data-bundles.md`](../docs/data-bundles.md#manifest).

**Determinism.** Records are sorted by `kind` then `id`, keys are canonical, and files are compressed
with fixed parameters. The same input therefore yields byte-identical `.jsonl.zst` files and identical
SHA-256 checksums, independent of the order of the caller's record arrays. `generatedAt` is the only
non-deterministic manifest field; `npm test` rebuilds the regular fixture set twice and compares dataset
bytes and checksums, not the timestamp.

**Missing vs empty.** A dataset absent from the input is skipped and recorded under `skipped` (normal
for the trimmed `pve`/`pvp-season` fixture sets, which only carry item markers). A dataset explicitly
supplied with zero records **fails the build**, because an empty file would erase the client's rows.
The writer removes stale `*.jsonl.zst` files from the mode directory and writes the manifest last, each
through a temporary file plus rename.

**Contract validation.** `npm run validate:bundle -- --dir <bundle-dir>` reads `manifest.json` and
every file next to it, then checks the manifest schema, file presence, compressed size, SHA-256,
zstd decompression, UTF-8 JSONL, `kind`/`id`, duplicate ids, record counts, placeholder strings and
flat traversal-free paths. Unknown extra files are warnings; any error exits 1. `--json` prints the
machine-readable report. The implementation is `src/bundle/validate.ts` (pure) plus
`src/cli/validate-bundle.ts`, and the documented hand-built example lives in
`test/fixtures/handbuilt-bundle/`.

**Comparison and no-op builds.** `src/bundle/compare.ts` compares two manifests by dataset presence and
`sha256`: only in current is `added`, only in previous is `removed`, a different checksum is `changed`,
an equal checksum is `unchanged`. `generatedAt`, `source.capturedAt`, per-dataset `source.*`
(`url`/`etag`/`lastModified`/`fetchedAt`), paths, sizes, counts and totals are ignored because they do
not describe the downloaded bytes. A `bundleSchemaVersion` or `minAppSchemaVersion` difference instead
marks every dataset present on both sides as changed, with the version bump named in its reason.

`npm run bundle -- --previous <path>` builds in memory, loads the previous manifest and, when nothing
changed, writes no files at all, prints `no changes` and exits 0. With changes it writes the full bundle
and reports each dataset's status and reason. `--previous` accepts a manifest file, a bundles root
(`<root>/<mode>/manifest.json`) or a mode directory (`<dir>/manifest.json`); with `--all` a directory
must hold a manifest for every selected mode. A missing or invalid previous manifest is a typed error
and exits non-zero — it is never treated as an empty baseline.

`npm run compare -- --previous <manifest> --current <manifest>` applies the same rules without building
or writing. It exits 0 whether or not datasets differ (non-zero only on invalid input) and prints a human
summary, or the plan as JSON with `--json`.

`npm run bundle -- --all` prints per-dataset records, uncompressed and compressed bytes, compression
ratio and a checksum prefix, plus the manifest path.

## Publication

```
pipeline/src/release/
  assets.ts         tag/asset naming, stable URL, manifest path rewriting
  client.ts         ReleaseClient interface
  gh-client.ts      gh CLI implementation (execFile, never a shell)
  memory-client.ts  offline test double
  plan.ts           pure ordered plan: uploads, skips, prune candidates, noop
  publish.ts        validate, read remote manifest, plan, apply
  report.ts         human summary and --json report
pipeline/src/cli/publish.ts   npm run publish
```

Each mode publishes to **one rolling release**, tagged `data-<mode>-latest`
(`regular`, `pve`, `pvp-season`) and titled `Tarkov Companion data — <mode>`.
The stable client pointer is:

```
https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json
```

Release assets are flat because GitHub forbids `/` in asset names:

```
manifest.json
<dataset>-<sha12>.jsonl.zst     # sha12 = first 12 hex chars of the dataset sha256
```

Before upload every manifest `datasets[].path` is rewritten to the versioned
asset name. The client resolves each path relative to the manifest URL, so it
lands on a sibling asset in the same release.

**Order and atomicity.** Changed/new dataset assets are uploaded first, sorted
by dataset name; `manifest.json` is replaced last. Until that swap, clients read
the previous manifest and its still-present immutable assets, so no reader ever
sees a manifest pointing at an asset that is not fully uploaded.

**Idempotency.** An existing asset with the same name and size is skipped. The
manifest is replaced only when `compareBundles` reports added/changed/removed
datasets, a contract-version change, or a published manifest whose paths are not
versioned; `generatedAt` alone does not count. A re-run with no changes makes
zero create/upload/delete calls and exits 0, and an interrupted run resumes by
skipping the assets it already uploaded.

**Pruning.** Off by default. `--prune` deletes dataset assets the new manifest
does not reference, after the manifest swap; `manifest.json` is never deleted.
It removes rollback capability (a client on the previous manifest may ask for a
deleted asset), so use it deliberately.

`--dry-run` reads the release and prints the exact ordered plan but performs no
mutation. `--json` emits the machine-readable report. Missing `gh`, an
unauthenticated gh, an invalid tag (or another mode's stable tag), a missing
local manifest, and a local dataset that does not match its checksum are typed
errors with exit code 1. `GH_TOKEN` and `GITHUB_TOKEN` are honored through gh;
otherwise the existing gh login is used. Full contract, examples and the client
resolution rule: [`../docs/data-bundles.md`](../docs/data-bundles.md#publication-to-github-releases).

## Scheduled sync

`npm run sync` is the production entry point the workflow calls. It composes the
stages above instead of reimplementing them:

```
pipeline/src/sync/
  types.ts            provider, report and cache interfaces
  provider.ts         UpstreamDatasetProvider (fetchDataset adapter)
  fixture-provider.ts FixtureDatasetProvider (offline `--fixtures`)
  normalized-cache.ts content-addressed normalized JSONL cache
  run.ts              per-mode fetch -> validate -> normalize -> bundle -> publish
  report.ts           human summary (`fetched` / `304` / `reused`, bytes, uploads)
pipeline/src/cli/sync.ts     npm run sync
pipeline/src/ci/report-status.ts  failure/success issue lifecycle
```

- Every dataset is fetched with the conditional cache. On `200` it is validated
  with the schema registry, normalized and its JSONL is stored under the upstream
  content checksum. On `304` the stored normalized JSONL is reused; when that
  entry is missing the dataset is re-fetched unconditionally and the decision is
  logged.
- A validation or normalization failure blocks that dataset's whole mode:
  publishing the rest would mark the dataset `removed` and make clients delete
  their rows. Other modes still run.
- All modes are processed before exiting. `exitCode` is 1 when any mode failed,
  and a JSON report is written for the CI issue reporter.
- A mode with no changes still builds locally, but `publishBundle` makes zero
  API mutations. A dry run writes any temporary bundle outside the repository and
  never mutates a release.
- `--fixtures <dir>` reads committed (or synthesized) fixtures and requires
  `--dry-run`; fixture bundles are never published.

Schedule, cache key, release tags, issue lifecycle, forced refresh and rollback
are documented in [`../docs/data-sync.md`](../docs/data-sync.md).

## Localization contract

The upstream payload carries unresolved keys plus a list of JSONPath pointers:

```json
{
  "data": { "5447a9cd...": { "name": "5447a9cd... Name" } },
  "translations": ["$.data.items.*.name"]
}
```

The dictionary is a flat map keyed by the placeholder string:

```json
{ "data": { "5447a9cd... Name": "Colt M4A1 5.56x45 assault rifle" } }
```

`localizeInPlace` walks each pointer and swaps matching strings. It never throws on a stale or unparsable
pointer; it records them in `stats` so the pipeline can decide whether to publish.

### Diagnostics

| Field | Meaning |
|---|---|
| `translated` | Strings replaced from the dictionary |
| `missingKeys` | Placeholder-shaped strings with no dictionary entry |
| `unresolvedPaths` | Pointers that matched nothing (stale metadata) |
| `failedPaths` | Pointers outside the supported grammar |
| `unmatched` | Selected strings that were already final text |

Measured on 2026-11-25 for `regular/en`: items 25,016 strings, tasks 3,642, traders 32, all with zero
missing keys. Known gaps: 13 stale task pointers and reward customization names absent from the
dictionary.

## Conditional fetching and dataset checksums

`fetchDataset` accepts an optional `cache: DatasetCacheStore`. When one is supplied, every request is
conditional and the result is a discriminated union, so callers cannot forget the `304` case:

```ts
import { fetchDataset } from "./src/upstream/fetch.js";
import { FileDatasetCacheStore } from "./src/upstream/cache.js";

const cache = new FileDatasetCacheStore(); // default: .cache/pipeline/
const result = await fetchDataset({ mode: "regular", dataset: "items", cache });

if (result.status === "not-modified") {
  // Nothing was downloaded; result.cache is the previously stored entry.
  return;
}

// result.status === "modified"
result.data;      // localized dataset, ready for normalization
result.stats;     // localization diagnostics
result.changed;   // false when the localized content checksum is unchanged
result.cache;     // { checksum, etag, lastModified, dictionaryEtag, …, fetchedAt, byteSize }
```

- `If-None-Match` and `If-Modified-Since` are stored and sent per `{mode, dataset, lang}` for both the
  base dataset and its `_{lang}` dictionary. ETag values (weak `W/"…"` or strong `"…"`) are forwarded
  verbatim.
- A `304` on the base dataset short-circuits the call: no body is read and the dictionary is **not**
  requested. The cached entry's validators were written atomically with the content they describe, so
  the dataset and dictionary checksums still apply. `meta.fetchedAt` stays at the time the cached
  content was downloaded.
- The dictionary is only requested when the base dataset came back `200`. If the dictionary itself
  answers `304` (base changed, dictionary did not), bodies are not cached, so the fetcher performs one
  unconditional dictionary GET and stores its new validators.
- `changed` is computed from a SHA-256 over the canonical JSON of the localized `data` (sorted object
  keys, no insignificant whitespace), so reordered keys or a re-serialized payload do not trigger a
  publish. It is `true` when there is no cached entry or the checksum differs.
- `allowMissingDictionary: true` still tolerates a `404` on the dictionary; a `404` on the base dataset
  always throws `UpstreamError`.
- `429` and `5xx` responses are retried with exponential backoff before a typed `UpstreamError` is
  raised. `forceRefresh: true` skips conditional headers for both resources.

### Cache file

One JSON file per dataset in `.cache/pipeline/` (gitignored), named
`<mode>__<dataset>__<lang>.json`; override the directory with `--cache-dir` or
`new FileDatasetCacheStore({ dir })`. The entry is exactly:

```json
{
  "mode": "regular",
  "dataset": "items",
  "lang": "en",
  "etag": "W/\"abc123\"",
  "lastModified": "Wed, 25 Nov 2026 10:00:00 GMT",
  "dictionaryEtag": "\"def456\"",
  "dictionaryLastModified": "Wed, 25 Nov 2026 10:00:00 GMT",
  "checksum": "<sha256 hex over canonical localized JSON>",
  "fetchedAt": "2026-11-25T12:00:00.000Z",
  "byteSize": 17229444
}
```

Writes are atomic (temporary file + rename). A missing, unreadable, or malformed entry is treated as a
cache miss, never a failure. `npm run fixtures` accepts `--refresh`; without it a cached `304` is
detected and the capture retries with a forced refresh so fixtures always contain full payloads.

`fetchDataset` returns `data` ready for normalization. Pass `allowMissingDictionary: true` only for
diagnostics; the default fails closed so untranslated placeholders never reach a bundle silently.
