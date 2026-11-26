import 'package:drift/drift.dart' show Value;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

Future<void> _seedItemAndProgress(AppDatabase db) async {
  await insertItem(
    db,
    id: 'item-m4a1',
    name: 'Colt M4A1',
    payload: '{"id":"item-m4a1","kind":"item"}',
  );
  final now = DateTime.utc(2026, 11, 26, 12);
  await insertProfile(db, now: now);
  await db
      .into(db.questProgress)
      .insert(
        QuestProgressCompanion.insert(
          profileId: 'profile-regular',
          questId: 'quest-debut',
          state: 'completed',
          updatedAt: now,
        ),
      );
  await db
      .into(db.datasetStates)
      .insert(
        DatasetStatesCompanion.insert(
          mode: 'regular',
          dataset: 'items',
          checksum: 'a' * 64,
          schemaVersion: 1,
          records: 1,
          appliedAt: now,
        ),
      );
}

/// Seeds a real schema-v3 file, before `items.priceObservedAt` existed.
///
/// `onCreate` always builds the shipped (latest) schema, so the later columns
/// and tables have to be dropped after creation to leave a genuine v3 file for
/// the migration.
Future<void> _seedV3(String path) async {
  final db = AppDatabase.atPath(path, targetSchemaVersion: 3);
  await _seedItemAndProgress(db);
  await _dropLaterSchema(db);
  await db.close();
}

/// Seeds a schema-v1 file: no `remoteManifest`, no `gameRecords`, and none of
/// the v4/v5 item columns or filter tables.
Future<void> _seedV1(String path) async {
  final db = AppDatabase.atPath(path, targetSchemaVersion: 1);
  await _seedItemAndProgress(db);
  await db.customStatement('DROP TABLE "remoteManifest"');
  await db.customStatement('DROP TABLE "gameRecords"');
  await _dropLaterSchema(db);
  await db.close();
}

Future<void> _dropLaterSchema(AppDatabase db) async {
  await db.customStatement('DROP TABLE "itemCategories"');
  await db.customStatement('DROP TABLE "itemTypes"');
  await db.customStatement('ALTER TABLE "items" DROP COLUMN "fleaEligible"');
  await db.customStatement('ALTER TABLE "items" DROP COLUMN "minLevelForFlea"');
  await db.customStatement('ALTER TABLE "items" DROP COLUMN "priceObservedAt"');
}

/// Opens at version 4 so this suite keeps exercising the v3 -> v4 step now that
/// the shipped schema is v5 (whose own suite covers v4 -> v5).
AppDatabase _openV4(String path) =>
    AppDatabase.atPath(path, targetSchemaVersion: 4);

Future<Set<String>> _itemColumns(AppDatabase db) async {
  final columns = await db.customSelect('PRAGMA table_info(items)').get();
  return columns.map((row) => row.read<String>('name')).toSet();
}

void main() {
  test('v3 -> v4 adds items.priceObservedAt, keeps every row, and backs up the '
      'v3 file', () async {
    final directory = createTemporaryDirectory(addTearDown);
    final path = '${directory.path}/tarkov_companion.sqlite';
    await _seedV3(path);

    final result = await openAppDatabase(path, open: _openV4);
    expect(result, isA<DatabaseOpened>());
    final opened = result as DatabaseOpened;
    addTearDown(opened.close);

    expect(opened.fromVersion, 3);
    expect(opened.toVersion, 4);
    expect(opened.backup, isNotNull);
    expect(opened.backup!.existsSync(), isTrue);
    expect(await readPragma(opened.database, 'PRAGMA user_version'), 4);

    expect(await _itemColumns(opened.database), contains('priceObservedAt'));
    expect(
      await opened.database.select(opened.database.gameRecords).get(),
      isEmpty,
    );

    // A v3 item row survives with an unknown observation: the migration must
    // not invent a price time it never had.
    final item = await opened.database
        .select(opened.database.items)
        .getSingle();
    expect(item.name, 'Colt M4A1');
    expect(item.priceObservedAt, isNull);
    expect(
      await opened.database.select(opened.database.questProgress).get(),
      hasLength(1),
    );
    expect(
      await opened.database.select(opened.database.datasetStates).get(),
      hasLength(1),
    );
    final fts = await opened.database
        .customSelect('SELECT count(*) AS n FROM items_fts')
        .getSingle();
    expect(fts.read<int>('n'), 1);

    // The new column is writable and reads back the same instant.
    final observedAt = DateTime.utc(2026, 11, 25, 17, 8, 2);
    await (opened.database.update(opened.database.items)
          ..where((row) => row.id.equals('item-m4a1')))
        .write(ItemsCompanion(priceObservedAt: Value(observedAt)));
    expect(
      (await opened.database.select(opened.database.items).getSingle())
          .priceObservedAt!
          .toUtc(),
      observedAt,
    );

    // The backup is the pre-migration state: v3, without the new column.
    final backup = sqlite.sqlite3.open(
      opened.backup!.path,
      mode: sqlite.OpenMode.readOnly,
    );
    addTearDown(backup.close);
    expect(backup.select('PRAGMA user_version').single['user_version'], 3);
    expect(
      backup
          .select('PRAGMA table_info(items)')
          .map((row) => row['name'])
          .toSet(),
      isNot(contains('priceObservedAt')),
    );
    expect(backup.select('SELECT name FROM items').single['name'], 'Colt M4A1');
  });

  test('v1 -> v4 runs every built-in step in one transaction', () async {
    final directory = createTemporaryDirectory(addTearDown);
    final path = '${directory.path}/tarkov_companion.sqlite';
    await _seedV1(path);

    final result = await openAppDatabase(path, open: _openV4) as DatabaseOpened;
    addTearDown(result.close);

    expect(result.fromVersion, 1);
    expect(result.toVersion, 4);
    expect(result.backup, isNotNull);
    expect(await readPragma(result.database, 'PRAGMA user_version'), 4);

    final tables = await result.database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN "
          "('remoteManifest', 'gameRecords')",
        )
        .get();
    expect(tables.map((row) => row.read<String>('name')).toSet(), {
      'remoteManifest',
      'gameRecords',
    });
    expect(await _itemColumns(result.database), contains('priceObservedAt'));
    expect(
      await result.database
          .select(result.database.items)
          .getSingle()
          .then((row) => row.name),
      'Colt M4A1',
    );
    expect(
      await result.database.select(result.database.questProgress).get(),
      hasLength(1),
    );
    final fts = await result.database
        .customSelect('SELECT count(*) AS n FROM items_fts')
        .getSingle();
    expect(fts.read<int>('n'), 1);
  });
}
