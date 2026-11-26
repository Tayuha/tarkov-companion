import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Creates the SQLite executors used by [AppDatabase].
///
/// The app passes a real filesystem path (`TarkovDatabaseConnection.atPath`);
/// tests pass either the in-memory executor or a temporary file. Drift takes a
/// [QueryExecutor], so a test can also inject its own executor.
///
/// `package:sqlite3` 3.x bundles SQLite through Dart build hooks on every
/// supported platform (Windows, Linux, macOS, Android, iOS), so no plugin or
/// system library is required.
abstract final class TarkovDatabaseConnection {
  /// An in-memory database. Fast, disposable, and not WAL-capable — use a file
  /// when the journal mode matters.
  static QueryExecutor inMemory({bool logStatements = false}) =>
      NativeDatabase.memory(logStatements: logStatements);

  /// A file-backed database at [path], creating parent directories as needed.
  ///
  /// This runs on the calling isolate. Use [inBackground] for the app so I/O
  /// does not block the UI isolate.
  static QueryExecutor atPath(String path, {bool logStatements = false}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return NativeDatabase(file, logStatements: logStatements);
  }

  /// A file-backed database whose I/O runs on a background isolate.
  ///
  /// This is what the app should use; it is not used by the unit tests because
  /// they need to observe pragmas directly.
  static QueryExecutor inBackground(String path, {bool logStatements = false}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    return NativeDatabase.createInBackground(
      file,
      logStatements: logStatements,
    );
  }
}
