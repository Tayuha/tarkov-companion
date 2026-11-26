import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'app_database.dart';

/// Builds an [AppDatabase] for a file path.
///
/// Production uses the default (a background isolate). Tests inject a factory
/// whose database declares a future schema version and its upgrade path.
typedef AppDatabaseFactory = AppDatabase Function(String path);

/// The outcome of [openAppDatabase].
///
/// The caller must [close] either variant. Recovery mode is deliberately not a
/// silent retry: writes are impossible until the user restores a backup or
/// exports progress.
sealed class DatabaseOpenResult {
  DatabaseOpenResult({
    required this.databasePath,
    required this.openFactory,
    required this.backupRetention,
  });

  /// The database file this result refers to.
  final String databasePath;

  /// How many pre-migration backups to keep. Used when restoring.
  final int backupRetention;

  /// How to reopen the database after a restore.
  final AppDatabaseFactory openFactory;

  /// Releases the handle owned by this result.
  Future<void> close();

  /// The factory used by [restoreFromBackup] when the caller does not pass one.
  ///
  /// Recovery returns `null`: restoring after a failed migration opens the
  /// backup at its own version instead of retrying the migration that just
  /// failed. The next normal [openAppDatabase] call decides whether to migrate.
  AppDatabaseFactory? get restoreFactory => null;

  /// Restores [backupPath] over the database, closing this handle first.
  ///
  /// This is an explicit user action. Nothing in the runner calls it
  /// automatically; in particular a failed migration never auto-restores.
  Future<DatabaseOpened> restoreFromBackup(
    File backupPath, {
    AppDatabaseFactory? open,
  }) async {
    await close();
    return restoreDatabaseFromBackup(
      databasePath: databasePath,
      backupPath: backupPath,
      open: open ?? restoreFactory,
      backupRetention: backupRetention,
    );
  }
}

/// The database opened normally.
final class DatabaseOpened extends DatabaseOpenResult {
  DatabaseOpened({
    required super.databasePath,
    required super.openFactory,
    required super.backupRetention,
    required this.database,
    required this.backup,
    required this.fromVersion,
    required this.toVersion,
  });

  final AppDatabase database;

  /// The pre-migration copy, or `null` when no migration was needed or the
  /// database is new.
  final File? backup;

  /// `user_version` found before opening the database (`0` for a fresh file).
  final int fromVersion;

  /// The schema version the database now has.
  final int toVersion;

  @override
  Future<void> close() => database.close();

  @override
  AppDatabaseFactory get restoreFactory => openFactory;
}

/// The database could not be opened, but was not deleted or overwritten.
///
/// [database] is a read-only SQLite handle. Reads (schema version, table names,
/// arbitrary `SELECT`) work; writes fail at the SQLite layer.
final class DatabaseRecovery extends DatabaseOpenResult {
  DatabaseRecovery({
    required super.databasePath,
    required super.openFactory,
    required super.backupRetention,
    required this.database,
    required this.backup,
    required this.failure,
    required this.detectedVersion,
    this.stackTrace,
  });

  final RecoveryDatabase database;

  /// The backup taken before the failed attempt, when one was possible.
  final File? backup;

  /// The exception that prevented the database from opening.
  final Object failure;

  final StackTrace? stackTrace;

  /// `user_version` read from the file after the failure (`-1` when the file is
  /// not a readable SQLite database).
  final int detectedVersion;

  @override
  Future<void> close() async => database.close();
}

/// A read-only view of a database file, used in recovery mode.
///
/// It is opened with SQLite's `OpenMode.readOnly`, so no API on this class can
/// modify the file. [execute] exists to run read statements and to let callers
/// observe the failure of a write attempt; the connection itself rejects it.
final class RecoveryDatabase {
  RecoveryDatabase._(this.path, this._db);

  /// Opens [path] read-only. Throws when the file does not exist.
  factory RecoveryDatabase.open(String path) {
    final db = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
    return RecoveryDatabase._(path, db);
  }

  final String path;
  final sqlite.Database _db;
  bool _closed = false;

  /// The file's `PRAGMA user_version`.
  int get schemaVersion {
    final rows = _db.select('PRAGMA user_version');
    return rows.first['user_version'] as int? ?? 0;
  }

  /// Every user table in the file, sorted by name.
  List<String> tableNames() => _db
      .select(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .map((row) => row['name'] as String)
      .toList();

  /// Runs a query and returns the rows as plain maps.
  List<Map<String, Object?>> select(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    return [
      for (final row in _db.select(sql, parameters))
        {for (final column in row.keys) column: row[column]},
    ];
  }

  /// Runs a statement on the read-only connection. Writes throw
  /// `SqliteException: attempt to write a readonly database`.
  void execute(String sql, [List<Object?> parameters = const []]) {
    _db.execute(sql, parameters);
  }

  /// Closes the handle. Safe to call twice.
  void close() {
    if (_closed) return;
    _closed = true;
    _db.close();
  }
}

/// Opens the database at [path], backing it up before any migration.
///
/// Lifecycle:
///
/// 1. read `user_version` with a raw connection, before drift touches the file;
/// 2. if the file is older than the target, checkpoint the WAL and copy it with
///    `VACUUM INTO` into `backups/`;
/// 3. let drift run its `onUpgrade` callbacks;
/// 4. on success return [DatabaseOpened], on any failure return
///    [DatabaseRecovery] with a read-only handle.
///
/// A failure never deletes, truncates or auto-restores the original file.
///
/// [open] is injectable for tests and for alternate executors. Production uses
/// [AppDatabase.inBackground]; tests use `AppDatabase.atPath`.
Future<DatabaseOpenResult> openAppDatabase(
  String path, {
  AppDatabaseFactory? open,
  int backupRetention = 3,
  DateTime Function()? clock,
}) async {
  RangeError.checkNotNegative(backupRetention, 'backupRetention');

  final openFactory = open ?? _openInBackground;
  final databaseFile = File(path)..parent.createSync(recursive: true);
  final db = openFactory(path);
  final targetVersion = db.schemaVersion;

  final exists = databaseFile.existsSync() && databaseFile.lengthSync() > 0;
  var fromVersion = 0;
  File? backup;

  if (exists) {
    sqlite.Database? inspection;
    try {
      inspection = sqlite.sqlite3.open(
        databaseFile.path,
        mode: sqlite.OpenMode.readWrite,
      );
      fromVersion = _readUserVersion(inspection);
    } catch (error, stackTrace) {
      inspection?.close();
      await _closeQuietly(db);
      return _recovery(
        path: path,
        open: openFactory,
        backupRetention: backupRetention,
        backup: null,
        failure: error,
        stackTrace: stackTrace,
        detectedVersion: -1,
      );
    }

    if (fromVersion > targetVersion) {
      inspection.close();
      await _closeQuietly(db);
      return _recovery(
        path: path,
        open: openFactory,
        backupRetention: backupRetention,
        backup: null,
        failure: StateError(
          'Database schema version $fromVersion is newer than the '
          'supported version $targetVersion. Refusing to downgrade.',
        ),
        stackTrace: StackTrace.current,
        detectedVersion: fromVersion,
      );
    }

    if (fromVersion < targetVersion) {
      try {
        backup = _createConsistentBackup(
          connection: inspection,
          databasePath: path,
          fromVersion: fromVersion,
          toVersion: targetVersion,
          timestamp: (clock ?? DateTime.now)(),
        );
        try {
          pruneBackups(path, keep: backupRetention);
        } catch (_) {
          // Retention is housekeeping; a locked old backup must not turn a
          // successful backup into a failed startup.
        }
      } catch (error, stackTrace) {
        inspection.close();
        await _closeQuietly(db);
        // No backup means no migration: keep the file exactly as it is.
        return _recovery(
          path: path,
          open: openFactory,
          backupRetention: backupRetention,
          backup: null,
          failure: error,
          stackTrace: stackTrace,
          detectedVersion: fromVersion,
        );
      }
    }

    inspection.close();
  }

  try {
    // `ensureOpen` reads `user_version` and runs drift's onCreate/onUpgrade.
    await db.executor.ensureOpen(db);
    return DatabaseOpened(
      databasePath: path,
      openFactory: openFactory,
      backupRetention: backupRetention,
      database: db,
      backup: backup,
      fromVersion: fromVersion,
      toVersion: targetVersion,
    );
  } catch (error, stackTrace) {
    await _closeQuietly(db);
    return _recovery(
      path: path,
      open: openFactory,
      backupRetention: backupRetention,
      backup: backup,
      failure: error,
      stackTrace: stackTrace,
      detectedVersion: fromVersion,
    );
  }
}

/// Restores [backupPath] over [databasePath] and reopens it.
///
/// The caller must close every handle on [databasePath] first (use
/// [DatabaseOpenResult.restoreFromBackup] to have the handle closed for you).
///
/// The backup is copied to a temporary file in the database directory, renamed
/// over the database, and the stale `-wal`/`-shm` sidecars are removed before
/// reopening. A backup that cannot be opened is reported by throwing; the
/// runner never swaps files back on its own.
Future<DatabaseOpened> restoreDatabaseFromBackup({
  required String databasePath,
  required File backupPath,
  AppDatabaseFactory? open,
  int backupRetention = 3,
}) async {
  RangeError.checkNotNegative(backupRetention, 'backupRetention');
  if (!backupPath.existsSync()) {
    throw ArgumentError.value(
      backupPath.path,
      'backupPath',
      'the backup file does not exist',
    );
  }

  final backupVersion = _databaseVersion(backupPath);

  final databaseFile = File(databasePath)..parent.createSync(recursive: true);
  final temporary = File(
    '$databasePath.restore-${DateTime.now().microsecondsSinceEpoch}.tmp',
  );

  try {
    backupPath.copySync(temporary.path);
    if (databaseFile.existsSync()) {
      try {
        temporary.renameSync(databasePath);
      } on FileSystemException {
        // Some Windows filesystems refuse to replace in a single rename.
        databaseFile.deleteSync();
        temporary.renameSync(databasePath);
      }
    } else {
      temporary.renameSync(databasePath);
    }
  } finally {
    if (temporary.existsSync()) temporary.deleteSync();
  }

  // A WAL from the replaced file must never be replayed into the restored one.
  for (final suffix in const ['-wal', '-shm']) {
    final sidecar = File('$databasePath$suffix');
    if (sidecar.existsSync()) sidecar.deleteSync();
  }

  // Without an explicit factory, open the restored file at its own version.
  // This returns a usable database and never silently retries a migration that
  // just failed.
  final restoreOpen =
      open ??
      (backupVersion > 0
          ? (String path) => AppDatabase.inBackground(
              path,
              targetSchemaVersion: backupVersion,
            )
          : null);

  final result = await openAppDatabase(
    databasePath,
    open: restoreOpen,
    backupRetention: backupRetention,
  );
  if (result is DatabaseOpened) return result;

  final recovery = result as DatabaseRecovery;
  await recovery.close();
  throw StateError(
    'The restored database still cannot be opened: ${recovery.failure}',
  );
}

/// The directory that holds pre-migration backups for [databasePath].
Directory backupDirectoryFor(String databasePath) {
  final parent = File(databasePath).parent.path;
  final separator = parent.endsWith(Platform.pathSeparator)
      ? ''
      : Platform.pathSeparator;
  return Directory('$parent${separator}backups');
}

/// The name of a pre-migration backup.
///
/// `tarkov_companion.v1-to-v2.20261126T120000.123456Z.sqlite`
String backupFileName({
  required String databasePath,
  required int fromVersion,
  required int toVersion,
  required DateTime timestamp,
}) {
  final base = _databaseBaseName(databasePath);
  return '$base.v$fromVersion-to-v$toVersion.'
      '${_formatTimestamp(timestamp)}.sqlite';
}

/// Existing backups for [databasePath], newest first.
///
/// Only files matching the backup pattern are returned. Anything else in the
/// `backups/` directory is left untouched by [pruneBackups].
List<File> listBackups(String databasePath) {
  final directory = backupDirectoryFor(databasePath);
  if (!directory.existsSync()) return const [];

  final pattern = _backupPattern(databasePath);
  final files =
      directory
          .listSync()
          .whereType<File>()
          .where((file) => pattern.hasMatch(_fileName(file.path)))
          .toList()
        ..sort((a, b) => _fileName(b.path).compareTo(_fileName(a.path)));
  return files;
}

/// Deletes all but the newest [keep] backups for [databasePath].
void pruneBackups(String databasePath, {int keep = 3}) {
  RangeError.checkNotNegative(keep, 'keep');
  for (final file in listBackups(databasePath).skip(keep)) {
    if (file.existsSync()) file.deleteSync();
  }
}

AppDatabase _openInBackground(String path) => AppDatabase.inBackground(path);

Future<void> _closeQuietly(AppDatabase db) async {
  try {
    await db.close();
  } catch (_) {
    // The original failure is the one worth reporting.
  }
}

int _readUserVersion(sqlite.Database db) {
  final rows = db.select('PRAGMA user_version');
  return rows.first['user_version'] as int? ?? 0;
}

int _databaseVersion(File file) {
  sqlite.Database? db;
  try {
    db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
    return _readUserVersion(db);
  } catch (error) {
    throw ArgumentError.value(
      file.path,
      'backupPath',
      'not a readable SQLite database: $error',
    );
  } finally {
    db?.close();
  }
}

File _createConsistentBackup({
  required sqlite.Database connection,
  required String databasePath,
  required int fromVersion,
  required int toVersion,
  required DateTime timestamp,
}) {
  // Committed WAL frames are not in the main file until a checkpoint. TRUNCATE
  // is safe here: no other connection in this process holds the file, and a
  // busy checkpoint still leaves `VACUUM INTO` reading a consistent snapshot.
  connection.execute('PRAGMA wal_checkpoint(TRUNCATE)');

  final directory = backupDirectoryFor(databasePath)
    ..createSync(recursive: true);
  var target = File(
    _join(
      directory.path,
      backupFileName(
        databasePath: databasePath,
        fromVersion: fromVersion,
        toVersion: toVersion,
        timestamp: timestamp,
      ),
    ),
  );
  var suffix = 1;
  while (target.existsSync()) {
    final name = backupFileName(
      databasePath: databasePath,
      fromVersion: fromVersion,
      toVersion: toVersion,
      timestamp: timestamp,
    );
    target = File(
      _join(directory.path, name.replaceAll('.sqlite', '-$suffix.sqlite')),
    );
    suffix++;
  }

  // VACUUM INTO produces a consistent, fully checkpointed copy (and never
  // copies the WAL blindly). Write to a partial name first so a crash cannot
  // leave a file that looks like a valid backup.
  final partial = File('${target.path}.partial');
  try {
    connection.execute('VACUUM INTO ?', [partial.path]);
    partial.renameSync(target.path);
  } catch (_) {
    if (partial.existsSync()) partial.deleteSync();
    rethrow;
  }

  return target;
}

DatabaseRecovery _recovery({
  required String path,
  required AppDatabaseFactory open,
  required int backupRetention,
  required File? backup,
  required Object failure,
  required StackTrace stackTrace,
  required int detectedVersion,
}) {
  final recovery = RecoveryDatabase.open(path);
  var version = detectedVersion;
  try {
    version = recovery.schemaVersion;
  } catch (_) {
    // The file is not a readable SQLite database; keep the pre-open value.
  }
  return DatabaseRecovery(
    databasePath: path,
    openFactory: open,
    backupRetention: backupRetention,
    database: recovery,
    backup: backup,
    failure: failure,
    stackTrace: stackTrace,
    detectedVersion: version,
  );
}

RegExp _backupPattern(String databasePath) {
  final base = RegExp.escape(_databaseBaseName(databasePath));
  return RegExp(
    '^$base'
    r'\.v\d+-to-v\d+\.\d{8}T\d{6}\.\d{6}Z(?:-\d+)?\.sqlite$',
  );
}

String _databaseBaseName(String databasePath) {
  final name = _fileName(databasePath);
  final dot = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

String _fileName(String path) => path.split(Platform.pathSeparator).last;

String _join(String directory, String name) {
  final separator = directory.endsWith(Platform.pathSeparator)
      ? ''
      : Platform.pathSeparator;
  return '$directory$separator$name';
}

String _formatTimestamp(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final micros = utc.millisecond * 1000 + utc.microsecond;
  return '${utc.year.toString().padLeft(4, '0')}'
      '${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}.'
      '${micros.toString().padLeft(6, '0')}Z';
}
