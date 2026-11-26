import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'connection.dart';
import 'fts.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// A forward-only schema upgrade step.
///
/// [AppDatabase] runs this inside a single transaction. If the callback
/// throws, every statement it issued is rolled back and SQLite keeps the
/// previous `user_version`, so a failed migration cannot leave a half-applied
/// schema behind.
typedef DatabaseUpgrade = Future<void> Function(
  Migrator migrator,
  int fromVersion,
  int toVersion,
);

/// The local Tarkov Companion database.
///
/// Two data classes share one SQLite file (design D4):
///
/// * game data — [DatasetStates], [Items], [Tasks], [TaskObjectives],
///   [Traders], [HideoutStations], [Crafts], [Barters], [Maps],
///   [GameRecords] and [PriceHistory]; replaceable and written by ingestion;
/// * player data — [Profiles], [QuestProgress], [ObjectiveProgress] and
///   [AppSettings]; durable, and **never** reachable from game data by a
///   foreign key. A dataset refresh deletes and re-inserts game rows and cannot
///   cascade into progress.
///
/// Because the generated class name `Map` would shadow `dart:core`, the map row
/// class is [TarkovMap].
///
/// Open one of:
///
/// ```dart
/// final db = AppDatabase.atPath('/path/to/tarkov_companion.sqlite');
/// final testDb = AppDatabase.memory();
/// ```
@DriftDatabase(
  tables: [
    // Game data.
    DatasetStates,
    RemoteManifests,
    Items,
    Tasks,
    TaskObjectives,
    Traders,
    HideoutStations,
    Crafts,
    Barters,
    Maps,
    GameRecords,
    PriceHistory,
    // Player data.
    Profiles,
    QuestProgress,
    ObjectiveProgress,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [targetSchemaVersion] defaults to the shipped schema. Tests (and a future
  /// release before it is generated) pass a higher version together with the
  /// [upgrade] step from the previous version.
  ///
  /// When [upgrade] is `null`, the built-in forward migrations declared in
  /// [_builtInUpgrade] run. Version 2 adds `remoteManifest`; version 3 adds
  /// `gameRecords`.
  AppDatabase(super.e, {this.targetSchemaVersion = 3, this.upgrade});

  /// An in-memory database, for tests and short-lived tools.
  factory AppDatabase.memory({
    int targetSchemaVersion = 3,
    DatabaseUpgrade? upgrade,
  }) => AppDatabase(
    TarkovDatabaseConnection.inMemory(),
    targetSchemaVersion: targetSchemaVersion,
    upgrade: upgrade,
  );

  /// A file-backed database at [path]; parent directories are created.
  factory AppDatabase.atPath(
    String path, {
    int targetSchemaVersion = 3,
    DatabaseUpgrade? upgrade,
  }) => AppDatabase(
    TarkovDatabaseConnection.atPath(path),
    targetSchemaVersion: targetSchemaVersion,
    upgrade: upgrade,
  );

  /// A file-backed database whose I/O runs on a background isolate.
  factory AppDatabase.inBackground(
    String path, {
    int targetSchemaVersion = 3,
    DatabaseUpgrade? upgrade,
  }) => AppDatabase(
    TarkovDatabaseConnection.inBackground(path),
    targetSchemaVersion: targetSchemaVersion,
    upgrade: upgrade,
  );

  /// The SQLite library version bundled with the app.
  static String get sqliteLibraryVersion => sqlite3.version.libVersion;

  /// The schema version this database opens at.
  final int targetSchemaVersion;

  /// The upgrade from the previous version, run inside one transaction.
  final DatabaseUpgrade? upgrade;

  @override
  int get schemaVersion => targetSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Version 1 is the initial schema: every table and index from
    // `tables.dart`, plus the FTS5 index and its triggers.
    //
    // Version 2 adds `remoteManifest` and nothing else; v1 data is untouched.
    // Version 3 adds `gameRecords` and its kind index; v2 data is untouched.
    // Future versions add a `DatabaseUpgrade` callback from the constructor
    // (or a step in `_builtInUpgrade`) while bumping `schemaVersion`. The
    // runner in `migration_runner.dart` decides when an upgrade may run: it
    // only does so after a verified backup exists.
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createItemSearchSchema();
    },
    onUpgrade: (migrator, from, to) async {
      final upgradeStep = upgrade ?? _builtInUpgrade(from, to);
      if (upgradeStep == null) {
        throw StateError(
          'No upgrade path from schema version $from to $to. '
          'Provide an onUpgrade step for the new schemaVersion.',
        );
      }
      // One transaction for the whole upgrade. SQLite DDL is transactional,
      // so a throw here rolls back both schema changes and data changes, and
      // drift never bumps `user_version`.
      await migrator.database.transaction(
        () => upgradeStep(migrator, from, to),
      );
    },
    beforeOpen: (details) async {
      // WAL lets a reader run while ingestion writes, and is the mode the app
      // is designed around (design D2/D5). It must be set outside a
      // transaction, which `beforeOpen` is.
      await customStatement('PRAGMA journal_mode = WAL');
      // Enforce the foreign keys that are declared (game data -> game data and
      // player data -> profiles). None point from player data at game data.
      await customStatement('PRAGMA foreign_keys = ON');
      // WAL is durable enough with NORMAL, and much cheaper than FULL for
      // whole-dataset replacement during ingestion.
      await customStatement('PRAGMA synchronous = NORMAL');
    },
  );

  Future<void> _createItemSearchSchema() async {
    for (final statement in itemSearchSchema) {
      await customStatement(statement);
    }
  }

  /// The forward migration for `from -> to`, or `null` when there is none.
  ///
  /// One `onUpgrade` call can span several versions (a client can upgrade from
  /// v1 straight to the current schema), so the steps run in order inside the
  /// transaction drift already opened.
  DatabaseUpgrade? _builtInUpgrade(int from, int to) {
    if (to > 3 || from < 1 || from >= to) {
      return null;
    }
    return (migrator, fromVersion, toVersion) async {
      if (fromVersion < 2) {
        await _upgradeV1ToV2(migrator, fromVersion, 2);
      }
      if (fromVersion < 3) {
        await _upgradeV2ToV3(migrator, fromVersion, 3);
      }
    };
  }

  /// Version 2: add the sync layer's `remoteManifest` cache.
  ///
  /// `migrator.createTable` reads the current table definition, so it always
  /// produces exactly the v2 shape. No existing table, index or trigger is
  /// altered, and no row is rewritten.
  Future<void> _upgradeV1ToV2(Migrator migrator, int from, int to) async {
    await migrator.createTable(remoteManifests);
  }

  /// Version 3: add `gameRecords` for bundle kinds without a dedicated table.
  ///
  /// Only a new table and its kind index are created. Existing game rows,
  /// player rows, FTS5 objects and sync bookkeeping are untouched.
  Future<void> _upgradeV2ToV3(Migrator migrator, int from, int to) async {
    await migrator.createTable(gameRecords);
    await migrator.create(gameRecordsKind);
  }
}
