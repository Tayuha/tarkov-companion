import 'dart:io';
import 'dart:isolate';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// One row of `sqlite_master`, reduced to what the schema snapshot needs.
final class SchemaObject {
  const SchemaObject({
    required this.type,
    required this.name,
    required this.sql,
  });

  /// `table`, `index`, `trigger` or `view`.
  final String type;

  /// Object name as SQLite stores it.
  final String name;

  /// The original `CREATE` statement.
  final String sql;

  @override
  String toString() => '$type $name';
}

/// FTS5 shadow tables created by SQLite itself. Their `CREATE` statements are
/// implementation details of the FTS5 module and are not part of our schema
/// contract, so the snapshot excludes them. `items_fts` and its triggers stay.
const ftsShadowTables = <String>{
  'items_fts_data',
  'items_fts_idx',
  'items_fts_docsize',
  'items_fts_config',
};

/// Reads every schema object with SQL, sorted so the snapshot is stable.
///
/// Auto-indexes (`sqlite_autoindex_*`) have a `NULL` SQL text and are skipped by
/// the query; they are an implementation detail of the declared primary keys.
Future<List<SchemaObject>> readSchemaObjects(AppDatabase db) async {
  final rows = await db.customSelect('''
        SELECT type, name, sql
        FROM sqlite_master
        WHERE sql IS NOT NULL
        ORDER BY type, name
        ''', readsFrom: {}).get();

  return rows
      .where((row) => !ftsShadowTables.contains(row.read<String>('name')))
      .map(
        (row) => SchemaObject(
          type: row.read<String>('type'),
          name: row.read<String>('name'),
          sql: row.read<String>('sql'),
        ),
      )
      .toList();
}

/// Renders a deterministic, human-diffable snapshot of [objects].
///
/// Object order is `(type, name)`; one blank line separates entries. The golden
/// is checked in and regenerated with `UPDATE_GOLDENS=1 dart test`.
String renderSchemaSnapshot(List<SchemaObject> objects) {
  final buffer = StringBuffer()
    ..writeln('-- AppDatabase schema snapshot (schemaVersion 5).')
    ..writeln(
      '-- Regenerate: (cd app/packages/data && UPDATE_GOLDENS=1 dart test)',
    )
    ..writeln('-- FTS5 shadow tables (items_fts_data, _idx, _docsize,')
    ..writeln('-- _config) are omitted; items_fts and its triggers are part')
    ..writeln('-- of the contract.')
    ..writeln();

  for (final object in objects) {
    buffer
      ..writeln('${object.type} ${object.name}')
      ..writeln('${object.sql};')
      ..writeln();
  }

  return buffer.toString();
}

/// The checked-in golden file, resolved from this package rather than from the
/// working directory: CI runs `dart test packages/data` from `app/`, so
/// `File('test/goldens/schema.sql')` would land in the wrong place.
Future<File> schemaGoldenFile() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:tarkov_companion_data/tarkov_companion_data.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Could not resolve the data package URI.');
  }
  return File.fromUri(libraryUri.resolve('../test/goldens/schema.sql'));
}

/// Writes [snapshot] to the golden when `UPDATE_GOLDENS=1`.
bool get regeneratingGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

/// Opens an in-memory database and closes it after the test.
///
/// Memory databases keep the file-backed guarantees (constraints, triggers,
/// foreign keys) but cannot use WAL; tests that assert the journal mode use a
/// temporary file instead.
Future<AppDatabase> openMemoryDatabase() async {
  final db = AppDatabase.memory();
  await db.customSelect('SELECT 1').get(); // Force `beforeOpen` to run.
  return db;
}

/// Creates a temporary directory that is removed after the test.
Directory createTemporaryDirectory(void Function(void Function()) addTearDown) {
  final directory = Directory.systemTemp.createTempSync('tarkov_companion_db_');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

/// Reads a single scalar pragma, e.g. `PRAGMA journal_mode`.
Future<Object?> readPragma(AppDatabase db, String pragma) async {
  final row = await db.customSelect(pragma).getSingle();
  return row.data.values.first;
}

/// Inserts a minimal item row. Memory-safe defaults for every other column.
Future<void> insertItem(
  AppDatabase db, {
  required String id,
  String name = 'Test item',
  String shortName = 'Test',
  String normalizedName = 'test-item',
  String payload = '{}',
}) async {
  await db
      .into(db.items)
      .insert(
        ItemsCompanion.insert(
          id: id,
          name: name,
          shortName: shortName,
          normalizedName: normalizedName,
          payload: payload,
        ),
      );
}

/// Inserts a minimal profile.
Future<void> insertProfile(
  AppDatabase db, {
  String id = 'profile-regular',
  String gameMode = 'regular',
  required DateTime now,
}) async {
  await db
      .into(db.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: id,
          gameMode: gameMode,
          createdAt: now,
          updatedAt: now,
        ),
      );
}
