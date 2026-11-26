# Local schema

The app keeps everything it knows in one local SQLite database. There is no
server: game data arrives as bundles (`docs/data-bundles.md`), player progress is
created by the user and never leaves the device. The schema lives in
`app/packages/data/lib/src/database/` and is versioned by
`AppDatabase.schemaVersion` (currently **1**).

- Tables: `lib/src/database/tables.dart` (drift table classes)
- Search schema: `lib/src/database/fts.dart`
- Migration strategy and pragmas: `lib/src/database/app_database.dart`
- Generated code: `lib/src/database/app_database.g.dart` (committed)

## Game data and player data

Design D4 splits the file in two halves that are written by different owners.

| Half | Tables | Written by | Replacement |
|---|---|---|---|
| Game data | `datasetState`, `items`, `tasks`, `taskObjectives`, `traders`, `hideoutStations`, `crafts`, `barters`, `maps`, `priceHistory` | Bundle ingestion (task 4.x); `priceHistory` by the on-demand history cache | Whole-dataset `DELETE` + insert inside one transaction |
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

Setting `journal_mode` needs a writable database. The read-only recovery mode
from task 3.3 opens the file with a different connection and must not run this
`beforeOpen`, otherwise SQLite refuses the pragma on a read-only file.

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
2. Bump `schemaVersion` in `app_database.dart` and add the `onUpgrade` step (the
   versioned migration runner is task 3.3).
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
