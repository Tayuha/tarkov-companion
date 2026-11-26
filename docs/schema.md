# Local schema

The app keeps everything it knows in one local SQLite database. There is no
server: game data arrives as bundles (`docs/data-bundles.md`), player progress is
created by the user and never leaves the device. The schema lives in
`app/packages/data/lib/src/database/` and is versioned by
`AppDatabase.schemaVersion` (currently **2**).

- Tables: `lib/src/database/tables.dart` (drift table classes)
- Search schema: `lib/src/database/fts.dart`
- Migration strategy and pragmas: `lib/src/database/app_database.dart`
- Generated code: `lib/src/database/app_database.g.dart` (committed)

## Game data and player data

Design D4 splits the file in two halves that are written by different owners.

| Half | Tables | Written by | Replacement |
|---|---|---|---|
| Game data | `datasetState`, `items`, `tasks`, `taskObjectives`, `traders`, `hideoutStations`, `crafts`, `barters`, `maps`, `priceHistory` | Bundle ingestion (task 4.x); `priceHistory` by the on-demand history cache | Whole-dataset `DELETE` + insert inside one transaction |
| Sync cache | `remoteManifest` | `ManifestRepository` (task 4.1) | One row per mode, replaced on a changed manifest |
| Player data | `profiles`, `questProgress`, `objectiveProgress`, `appSettings` | The user, through the app | Never touched by a dataset refresh |

Game-data tables are keyed by upstream identifiers, keep the complete JSONL
record in a `payload` column (canonical JSON), and expose the indexed columns the
UI queries. Player-data tables reference upstream identifiers as plain text.

Column names are `camelCase`, matching the bundle record fields, so ingestion
maps a record field to a column without a translation table. Timestamps are
drift `DateTimeColumn`s stored as **Unix epoch seconds** (drift's default);
values read back represent the same instant in the local time zone, so call
`.toUtc()` before serialising a timestamp.

### The no-cascade guarantee

> **Player data can never be deleted by a game-data refresh.**

This is a structural property, not a convention:

1. **No player table declares a foreign key onto a game-data table.**
   `questProgress.questId`, `objectiveProgress.questId`/`objectiveId` and
   `priceHistory.itemId` are plain text columns. `PRAGMA foreign_keys` is on, so
   a declared key would be enforced — there is none to enforce.
2. **`ON DELETE CASCADE` only exists inside the same half.** `taskObjectives.taskId`
   cascades to `tasks` (both replaced by the same `tasks` ingestion). The
   `profiles` key on `questProgress`/`objectiveProgress` cascades only when the
   player deletes that profile.
3. **`priceHistory` deliberately has no key to `items`.** A dataset refresh must
   neither fail because cached history references an item nor wipe the cache;
   history is invalidated by its TTL instead.
4. **Tests enforce it.** `test/player_data_test.dart` deletes every game-data
   row (and separately replaces the item dataset) and asserts progress is
   intact, inserts progress for a quest id that does not exist, proves the
   allowed `taskObjectives -> tasks` cascade is enforced, and reads
   `PRAGMA foreign_key_list` for every player table to assert the only allowed
   target is `profiles`.

A quest or item that an outdated profile references but the current dataset does
not contain is an ordinary missing join result: the row stays, and the UI reports
it as unavailable upstream (tasks 6.8 / 5.8).

## Pragmas

`MigrationStrategy.beforeOpen` runs on every open, before any query:

| Pragma | Value | Why |
|---|---|---|
| `journal_mode` | `WAL` | Readers keep working while ingestion writes a whole dataset; `-wal`/`-shm` sidecars sit next to the database file. |
| `foreign_keys` | `ON` | SQLite defaults to off per connection; the schema's (in-half) keys must be enforced. |
| `synchronous` | `NORMAL` | The WAL durability/throughput point the ingestion design (D5) assumes. |

`beforeOpen` runs outside a transaction, which `journal_mode` requires. In-memory
databases report `memory` instead of `wal`; a file-backed database is the only
place WAL can be observed, and `test/wal_test.dart` asserts both.

Setting `journal_mode` needs a writable database. The read-only recovery handle
(`RecoveryDatabase`) opens the file with a different SQLite connection and does
not run this `beforeOpen`, otherwise SQLite refuses the pragma on a read-only
file.

## Schema history

| Version | Change |
|---|---|
| 1 | Initial game-data, player-data and FTS5 schema. |
| 2 | Adds `remoteManifest` for conditional manifest fetching (task 4.1). Existing tables, indexes, triggers and rows are untouched; the upgrade runs inside one transaction after a pre-migration backup. |

## Migrations, backups and recovery

`openAppDatabase` in `lib/src/database/migration_runner.dart` is the only path
the app should use to open the file. It returns a sealed result:

| Result | Meaning | Handle |
|---|---|---|
| `DatabaseOpened` | Normal open; migrations succeeded or were not needed | Writable drift `AppDatabase` |
| `DatabaseRecovery` | Opening or migrating failed | `RecoveryDatabase`, opened with `OpenMode.readOnly` |

`DatabaseOpened` carries the `fromVersion`, the `toVersion`, and the backup
`File?` (null on a fresh database or when no migration was needed).
`DatabaseRecovery` carries the same backup path when one could be made, the
exception, and the detected `user_version` (`-1` when the file is not readable
SQLite).

### Pre-migration backup

Before drift opens the database, the runner reads `PRAGMA user_version` with a
raw `package:sqlite3` connection. When the file exists, is older than
`AppDatabase.schemaVersion`, and a migration is required:

1. `PRAGMA wal_checkpoint(TRUNCATE)` moves committed WAL frames into the main
   file.
2. `VACUUM INTO` writes a consistent snapshot to a temporary name in
   `backups/`, which is then renamed into place. Copying the three files blindly
   would race the WAL; `VACUUM INTO` cannot capture a partial WAL state.
3. Older backups are pruned to the configured count (default **3**), counting
   only files that match the backup pattern.

Backups live next to the database:

```
<database directory>/backups/
  tarkov_companion.v1-to-v2.20261126T120000.123456Z.sqlite
  tarkov_companion.v1-to-v2.20261126T090000.654321Z.sqlite
```

The name is `<base>.v<from>-to-v<to>.<UTC timestamp>.sqlite`
(`backupFileName`), and `listBackups`/`pruneBackups` only consider files that
match it. A fresh database creates no backup.

### Failure rule: never delete, never auto-restore

Drift's upgrade step runs inside one transaction (`AppDatabase.migration`). If
it throws, SQLite rolls back the DDL and data, `user_version` stays at
`fromVersion`, and the runner does **not** delete, truncate, or overwrite the
original file. It closes the partially opened drift handle and returns
`DatabaseRecovery` with the pre-migration backup path.

Recovery is read-only by construction: `RecoveryDatabase` exposes schema
version, table names, and `select`; any write throws
`SqliteException: attempt to write a readonly database`. The app must offer
export and a user-initiated restore, and keep writes disabled until the user
resolves it.

`restoreFromBackup` (on either result, or `restoreDatabaseFromBackup`) is only
called from an explicit user action. It closes the current handle, copies the
backup to a temporary file, renames it over the database, deletes stale `-wal`
and `-shm` sidecars, and reopens. Nothing in the startup path calls it
automatically.

A database whose `user_version` is higher than the app supports enters recovery
instead of being opened or downgraded.

## Timestamps, identifiers, payloads

- Ids are opaque non-empty upstream strings. Synthetic ids (`fleaMarket`,
  `playerLevel`, `goonReport`) follow the rules in `docs/data-bundles.md`.
- `datasetState` has a composite primary key `(mode, dataset)`; ingestion
  upserts it, so re-applying a dataset is idempotent and a new checksum replaces
  the row for that dataset only. Other datasets and other modes keep their rows.
- `payload` is the exact JSONL record, so a future ingestion task can add a
  query without a schema migration, and a removed column can be recovered from
  the payload.
- `priceHistory` is keyed `(itemId, observedAt)`; duplicate observations of the
  same timestamp replace each other.
- `profiles.gameMode` is `UNIQUE`, which is the "one profile per mode"
  invariant from `specs/local-profiles/spec.md` at the storage level.
- `appSettings` is a string key/value table; values stay strings so a preference
  keeps its meaning across app versions.

## Bundle manifest compatibility and dataset state

The data package exposes the client side of the bundle contract:
`BundleManifest.parse` for a decoded `manifest.json`, `BundleContract` for the
supported versions, and `DatasetStateRepository` for `datasetState`. The parser
is pure Dart and does no I/O; the sync layer owns the HTTP request.

`BundleContract` currently declares `manifestVersion` 1, bundle schema 1 and app
data schema 1. `BundleManifest.checkCompatibility` returns `bundleUnsupported`
when the manifest's bundle schema is newer, `appUpdateRequired` when its
`minAppSchemaVersion` is newer than the app data schema, and `compatible`
otherwise. The caller must not start a sync on a non-compatible result, so the
database stays at its last complete bundle.

`DatasetStateRepository.recordApplied` is the only writer of `datasetState`:

| Situation | Result | Write |
|---|---|---|
| No row for `(mode, dataset)` | `inserted` | Insert |
| Checksum, `schemaVersion` and `records` all equal | `unchanged` | **None** |
| Any of those three differs | `updated` | Update, replacing `appliedAt` |
| Dataset `schemaVersion` newer than `BundleContract.appDataSchemaVersion` | `rejected` | **None** |

Source metadata (`ETag`, `Last-Modified`, fetch time, sizes) is diagnostics
only: a change there alone is `unchanged`. On `unchanged` the whole row,
including `appliedAt`, is left exactly as it was, so a repeated sync is
idempotent. `clearMode` deletes rows for one mode only.

## Item search (FTS5)

`items_fts` is an FTS5 **external-content** table over `items`: it stores only the
index and reads text from `items` through `rowid`. Columns: `name`, `shortName`,
`normalizedName`. Tokenizer: `unicode61 remove_diacritics 2`, so `cafe` matches
`Café` and `m4a1` matches `M4A1`.

Three triggers keep it in sync, created in `onCreate`:

| Trigger | Fires on |
|---|---|
| `items_fts_ai` | `AFTER INSERT ON items` |
| `items_fts_au` | `AFTER UPDATE ON items` (deletes the old index row, inserts the new) |
| `items_fts_ad` | `AFTER DELETE ON items` (the FTS5 `'delete'` row form) |

Whole-dataset replacement (`DELETE FROM items` + bulk insert) is therefore
indexed without a separate rebuild step. Do not drop or recreate `items_fts`
outside a migration; the triggers reference it by name.

`FTS5` is compiled into the SQLite library the app ships (see below), so search
is available on every platform.

## SQLite runtime

`package:sqlite3` 3.x bundles SQLite through Dart build hooks on Windows, Linux,
macOS, Android and iOS. That is why `app/pubspec.yaml` does **not** depend on
`sqlite3_flutter_libs`: that package is end-of-life — its own description says
"not used anymore, update to version 3.x of package:sqlite3". Nothing (system
library, plugin, installer step) has to be added for the app to have SQLite at
runtime; `flutter build linux --debug` puts `libsqlite3.so` in the bundle.

## Changing the schema

1. Edit `tables.dart` / `fts.dart`.
2. Bump the schema version in `app_database.dart` and add the `DatabaseUpgrade`
   step for the previous version. The step may add tables, indexes and the FTS
   schema; `AppDatabase` already wraps it in a transaction.
3. Regenerate the drift code from the package directory:
   ```bash
   cd app/packages/data
   dart run build_runner build
   ```
   The generated `app_database.g.dart` is committed: CI never runs code
   generation.
4. Regenerate the golden and review the diff:
   ```bash
   cd app/packages/data
   UPDATE_GOLDENS=1 dart test
   ```
   The golden is `test/goldens/schema.sql`: every `sqlite_master` object with SQL,
   sorted by `(type, name)`, one entry per object. FTS5's internal shadow tables
   (`items_fts_data`, `_idx`, `_docsize`, `_config`) are omitted because they are
   implementation detail of SQLite; `items_fts` and the three triggers are part
   of the contract. The golden is resolved from the package URI, so
   `dart test packages/data` from `app/` and `dart test` from the package
   directory both work.
5. Run `flutter analyze`, `dart test packages/data`, and the architecture check.

Without `UPDATE_GOLDENS=1` the snapshot test fails with a diff, which is the
signal that a schema change reached the database without a deliberate golden
update.

## Where the file lives

The data package exposes the connection factory; the app decides the path
(task 8.x chooses the platform directory) and passes it to
`AppDatabase.atPath(path)` or `AppDatabase.inBackground(path)` for
non-blocking I/O. `atPath` creates parent directories. Uninstalling may or may
not remove the file per platform; `docs/progress-format.md` (task 7.10) covers
export as the durable path.
