# Design

## Context

See `proposal.md` for motivation and `specs/*` for behavioral requirements. The constraints that shape
this design were measured against the live API on 2026-11-25:

| Endpoint | Size | Content |
|---|---|---|
| `/regular/items` | 17.0 MB | 5,498 items, prices, properties, barter refs, settings, levels |
| `/regular/maps` | 9.0 MB | maps, loot, bosses, extracts |
| `/regular/tasks` | 2.1 MB | quests, objectives, rewards, prestige |
| `/regular/barters` | 289 KB | trader barters |
| `/regular/crafts` | 97 KB | hideout crafts |
| `/regular/hideout` | 80 KB | stations and levels |
| `/regular/traders` | 59 KB | traders |
| `/pve/*`, `/pvp-season/*` | ~17 MB each | same shape, different mode |
| `/regular/prices/{itemId}` | 134 KB | full price history for one item |

Additional observed facts:

- Responses are plain JSON under `{"data": ...}` and include `ETag`, `Last-Modified`, and `Content-Length`.
- Item and task text fields arrive as unresolved localization keys, with a root-level `translations`
  array of JSONPath pointers and a matching dictionary at `/{mode}/{dataset}_{lang}` (see
  "Localization contract" below).
- `pve/items_en` is byte-identical to `regular/items_en` (same md5), so mode-level dictionary caching must
  key on content, not just mode.
- The translation metadata is itself stale in places: 13 task pointers reference a removed `story`
  collection or a rewards shape that no longer matches, and reward customization names have no dictionary
  entry at all.
- Item records already carry `lastLowPrice`, `avg24hPrice`, `changeLast48h`, `buyFromTrader`,
  `sellToTrader`, so live prices arrive with the catalog; history is a separate per-item call.

### Localization contract

Each translatable dataset ships as a pair:

```
GET /{mode}/{dataset}          -> { "data": {...}, "translations": ["$.data.items.*.name", ...] }
GET /{mode}/{dataset}_{lang}   -> { "data": { "5447a9cd... Name": "Colt M4A1 ..." } }
```

The dictionary is keyed by the placeholder string, not by path. Resolution is therefore: walk every node
selected by each pointer, and if the node is a string with a dictionary entry, replace it in place.

Measured coverage (2026-11-25, `regular`, `en`):

| Dataset | Pointers | Strings resolved | Stale pointers | Unparsable |
|---|---|---|---|---|
| items | 17 | 25,016 / 25,016 | 2 | 0 |
| tasks | 32 | 3,642 / 3,642 | 13 | 0 |
| traders | 2 | 32 / 32 | 0 | 0 |

Pointers use more than dotted keys: `..bodyParts[*]` (recursive descent) and
`['startRewards','finishRewards']` (key unions) both appear in the tasks payload. The resolver supports
that subset and reports, rather than throws, on anything outside it.

Stale pointers are not fatal: affected values stay as placeholders and are reported. Missing dictionary
keys are reported individually so the pipeline can fail a build when coverage regresses.

## Goals / Non-Goals

**Goals:**
- One Dart codebase that builds for Windows now and Android/iOS later, with all shared logic in pure Dart
  packages that can be unit-tested without a UI.
- A deterministic, reproducible data pipeline where the app never interprets raw upstream JSON.
- Local SQLite as the only read path, so every screen works offline and search is sub-100 ms.
- Progress data that is impossible to lose silently: transactional writes, versioned migrations, verified
  export/import.
- Zero operating cost beyond GitHub: no servers, no accounts, no databases to run.

**Non-Goals:**
- Live game-client integration, log parsing, or screenshot OCR.
- Real-time price streaming; polling cadence is bundle-level.
- Cross-device sync.
- A design system or final visual layout (later change).
- Map rendering and interactive map UI.

## Decisions

### D1. Flutter for the client

**Chosen:** Flutter (Dart) with `drift` over SQLite.

- Windows, Linux, macOS, Android, and iOS from one codebase; Windows is the launch target and Android is the
  likely second.
- `drift` gives typed queries, migrations, and the same SQLite engine on every platform.
- Custom-painted dense tables and slivers handle a 5,500-row catalog and ammo-style grids well.
- Export/import is ordinary file I/O with the platform file picker.

**Alternatives:** React Native + Tauri (two shells, two build systems, two update paths); PWA (weak
filesystem access for exports, no true background sync, less native feel); Kotlin Multiplatform (desktop
Linux/Windows tooling less mature; no benefit here).

**Consequence:** No code sharing with a future web build, and a smaller hiring pool. Accepted.

### D2. Prebuilt data bundles published as GitHub Releases

**Chosen:** A Node/TypeScript pipeline in `pipeline/`, scheduled by GitHub Actions, fetches upstream,
resolves localization dictionaries, validates and normalizes the result, and publishes:

```
manifest.json
bundles/<mode>/<dataset>.jsonl.zst     # games: regular | pve | pvp-season
                                       # datasets: items, tasks, traders, hideout, crafts, barters, maps
```

The app downloads the manifest, compares dataset checksums, downloads only changed datasets, verifies
SHA-256, and ingests them into its own SQLite database inside a transaction.

**Why JSONL + zstd instead of shipping a prebuilt SQLite file:**
- The client owns its schema and migrations; a prebuilt `.db` would couple the app's schema version to the
  pipeline's build and make migrations across app versions painful.
- JSONL streams, so ingestion is memory-bounded and can be cancelled.
- zstd keeps the full item dataset in the low single-digit megabytes, which is an acceptable full-dataset
  re-download when it changes.
- Text bundles are diffable and debuggable by contributors, which matters for an OSS project.

**Why not the client calling upstream directly:** first-run cost, no control over upstream shape changes,
no ability to fix bad data, and it makes offline behavior depend on whatever the client happened to cache.

**Why not a hosted sync server:** adds cost, uptime, auth, and a privacy surface for zero user-facing gain
at this stage.

### D3. Per-dataset versioning, whole-dataset replacement

Each dataset has its own checksum and version. Ingestion replaces a dataset's rows in one transaction
(`DELETE` + bulk insert, or `INSERT OR REPLACE` for small tables) and records the applied version in
`dataset_state`. No field-level merging: upstream is authoritative for game data, the app is authoritative
for player data.

This avoids diff formats, tombstone logic, and partial-update corruption. The worst case is re-downloading
one dataset, which is seconds on a normal connection.

### D4. Local schema separates game data from player data

```
+---------------------------+        +---------------------------+
| game data (replaceable)   |        | player data (durable)     |
+---------------------------+        +---------------------------+
| items, item_properties    |        | profiles                  |
| item_sources, barters     |        | quest_progress            |
| tasks, task_objectives    |        | objective_progress        |
| task_requirements         |        | app_settings              |
| traders, maps, crafts     |        | schema_meta               |
| price_history (cache)     |        |                           |
+---------------------------+        +---------------------------+
        ^                                      ^
        | ingested from bundles                | never touched by sync
        +--------------------------------------+
```

Game-data tables are keyed by upstream identifiers. Player-data tables reference those identifiers but
never declare a cascading foreign key onto game data, so a dataset refresh cannot delete progress. Missing
references are surfaced as "unavailable upstream" instead of being silently dropped.

`items_fts` is an FTS5 virtual table over `name`, `shortName`, and `normalizedName` with
`unicode61 remove_diacritics 2`, kept in sync by triggers during ingestion.

### D5. Idempotent, validated ingestion

The pipeline validates upstream payloads against a Zod schema per dataset and fails the build on drift.
Each dataset has a `bundle_schema_version`; the app declares supported versions in `dataset_state` and
refuses a newer bundle instead of guessing. Ingestion is idempotent: applying the same dataset version
twice is a no-op.

Sync flow:

```
app start
   |
   v
open SQLite (last applied bundle) --> UI ready
   |
   +--> background: GET manifest (ETag)
            |
            +-- unchanged --> done
            |
            +-- changed --> for each dataset with new checksum:
                             download .jsonl.zst
                                   |
                             sha256 verify --fail--> keep old, report
                                   |
                             BEGIN; ingest; update dataset_state; COMMIT
                                   |
                             refresh FTS + invalidate caches
```

### D6. Price history is on-demand and separately cached

History is per-item, ~130 KB each, and not needed to render the catalog. It is fetched when a detail view
opens the history tab, cached in `price_history` with a TTL (default 24 h), and served from cache offline.
Prefetching is not done at scale; the pipeline may later publish a compact daily aggregate if demand
justifies it.

### D7. Search and listing performance budgets

- Catalog query with filters: p95 under 50 ms on the reference machine.
- First interactive frame with an existing dataset: under 1.5 s cold start.
- Initial bundle download target: under 10 MB compressed for one game mode, including maps. Measured
  2026-11-25: raw items + maps + tasks total 27.7 MB, compressing to **1.98 MB at zstd -3** (items 1.17,
  maps 0.60, tasks 0.21), so the budget has roughly 5x headroom. Ingest time remains unmeasured until the
  client database exists.
- Memory ceiling during ingestion: bounded streaming, no full-dataset JSON parse in memory.

Row rendering is virtualized; images load lazily through a disk-backed cache with a fixed size budget.

### D8. Progress file format

A single JSON document, versioned, with an integrity checksum over the canonicalized payload:

```json
{
  "format": "tarkov-companion.progress",
  "formatVersion": 1,
  "appVersion": "0.1.0",
  "exportedAt": "2026-11-25T15:00:00Z",
  "profiles": [
    {
      "gameMode": "regular",
      "playerLevel": 34,
      "quests": [
        { "questId": "657315ddab5a49b71f098853", "state": "completed",
          "objectives": [{ "objectiveId": "65732ac3...", "count": 5 }] }
      ]
    }
  ],
  "checksum": "sha256:..."
}
```

Checksum is computed over the document with `checksum` removed, canonical JSON (sorted keys, no
whitespace). Import is validated fully before any write, then applied in one transaction. Merge conflicts
are resolved per quest by the user with explicit choices; replace mode is opt-in and never the default.

### D9. Platform-appropriate packaging

- Windows: per-user installer built in CI (Inno Setup or MSIX; decided during implementation by signing
  feasibility), checksums published, signing optional and disclosed.
- Android (later): signed APK/AAB with the same release workflow.
- Data updates and app updates are separate concerns: data is a bundle fetch, app updates are a version
  check that opens the release page (no silent self-updater in v1).

### D10. OSS operations

- MIT license, `NOTICE` with upstream attribution, trademark disclaimer, and a code of conduct.
- Workflows: `ci.yml` (format, analyze, test, build), `data-sync.yml` (scheduled pipeline + release of
  bundles), `release-app.yml` (tag-triggered Windows installer).
- Contributions: issue templates, `good first issue` labeling, generated data fixtures for tests, and a
  documented local pipeline run that does not require secrets.
- The app never depends on contributor credentials; the pipeline uses the default `GITHUB_TOKEN`.

## Risks / Trade-offs

- **Upstream translation metadata drifts** → the resolver reports stale pointers and missing keys; the
  pipeline fails when missing coverage exceeds the configured threshold instead of publishing a bundle
  with placeholder names; normalization falls back to `normalizedName` where a display name is missing.
- **Reward customization names have no dictionary entries** → these are cosmetic clothing rewards; render
  them as "Unnamed customization" with the image when no name resolves, and track the gap upstream.
- **Upstream schema drift breaks the pipeline** → strict validation, last-good bundle stays published,
  failure notification, and a pipeline version pinned in CI.
- **GitHub Releases as a CDN** → acceptable for this scale; mitigate with ETag/If-None-Match, compressed
  assets, and a manifest small enough to poll. If traffic grows, bundles can move to any static host
  without changing the client contract.
- **Whole-dataset reloads** waste bandwidth when one item changes → mitigated by per-dataset granularity;
  if needed later, add a content-addressed chunk layer without changing the manifest shape.
- **SQLite write cost during ingestion on low-end devices** → batched inserts in one transaction, WAL mode,
  ingestion off the UI isolate.
- **Trademark and branding** → use a neutral project name in public listings, avoid official logos, include
  a clear "not affiliated with Battlestate Games" disclaimer, and never monetize.
- **Unsigned Windows installer triggers SmartScreen** → publish checksums, document the warning, and add
  signing when a certificate is available.
- **Flutter desktop maturity on Windows** → target the stable channel, test on a clean VM per release, and
  keep platform-specific code behind narrow interfaces.
- **`pvp-season` semantics are undocumented** → treat it as an independent mode with its own dataset;
  confirm behavior before enabling its profile in a release.

## Migration Plan

This is the initial release, so there is no data to migrate. The forward plan:

1. Land pipeline + client data layer behind a feature flag with a fixture dataset checked into `test/`.
2. Ship an internal build that reads only the fixture, verify offline behavior and ingestion rollback.
3. Enable live bundles for `regular` only; `pve` and `pvp-season` follow after validation.
4. Every release keeps the previous database copy; a failed migration enters read-only recovery mode and
   offers export instead of deleting data.

## Open Questions

- Final public project name and branding, given trademark constraints.
- Whether `pvp-season` progress should be scoped per season (new profile per season) or reuse one profile.
- Whether a compact daily price aggregate is needed in bundles, or on-demand history is sufficient.
- Why `pve/items_en` is byte-identical to `regular/items_en`; if PvE ever diverges, dictionary caching must
  follow content and not assume mode identity.
