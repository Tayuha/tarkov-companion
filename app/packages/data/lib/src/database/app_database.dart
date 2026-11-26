import 'package:drift/drift.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;

import 'connection.dart';
import 'fts.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The local Tarkov Companion database.
///
/// Two data classes share one SQLite file (design D4):
///
/// * game data — [DatasetStates], [Items], [Tasks], [TaskObjectives],
///   [Traders], [HideoutStations], [Crafts], [Barters], [Maps] and
///   [PriceHistory]; replaceable and written by ingestion;
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
    Items,
    Tasks,
    TaskObjectives,
    Traders,
    HideoutStations,
    Crafts,
    Barters,
    Maps,
    PriceHistory,
    // Player data.
    Profiles,
    QuestProgress,
    ObjectiveProgress,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// An in-memory database, for tests and short-lived tools.
  factory AppDatabase.memory() =>
      AppDatabase(TarkovDatabaseConnection.inMemory());

  /// A file-backed database at [path]; parent directories are created.
  factory AppDatabase.atPath(String path) =>
      AppDatabase(TarkovDatabaseConnection.atPath(path));

  /// A file-backed database whose I/O runs on a background isolate.
  factory AppDatabase.inBackground(String path) =>
      AppDatabase(TarkovDatabaseConnection.inBackground(path));

  /// The SQLite library version bundled with the app.
  static String get sqliteLibraryVersion => sqlite3.version.libVersion;

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    // Version 1 is the initial schema: every table and index from
    // `tables.dart`, plus the FTS5 index and its triggers. There is no
    // `onUpgrade` yet; the versioned migration runner is task 3.3.
    onCreate: (migrator) async {
      await migrator.createAll();
      await _createItemSearchSchema();
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
}
