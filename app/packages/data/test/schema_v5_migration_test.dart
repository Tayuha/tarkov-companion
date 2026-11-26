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

/// Removes the v5 additions that `onCreate` built, leaving a genuine v4 file.
Future<void> _dropV5(AppDatabase db) async {
  await db.customStatement('DROP TABLE "itemCategories"');
  await db.customStatement('DROP TABLE "itemTypes"');
  await db.customStatement('ALTER TABLE "items" DROP COLUMN "fleaEligible"');
  await db.customStatement('ALTER TABLE "items" DROP COLUMN "minLevelForFlea"');
}

Future<void> _seedV4(String path) async {
  final db = AppDatabase.atPath(path, targetSchemaVersion: 4);
  await _seedItemAndProgress(db);
  await _dropV5(db);
  await db.close();
}

Future<void> _seedV1(String path) async {
  final db = AppDatabase.atPath(path, targetSchemaVersion: 1);
  await _seedItemAndProgress(db);
  await db.customStatement('DROP TABLE "remoteManifest"');
  await db.customStatement('DROP TABLE "gameRecords"');
  await db.customStatement('ALTER TABLE "items" DROP COLUMN "priceObservedAt"');
  await _dropV5(db);
  await db.close();
}

Future<Set<String>> _itemColumns(AppDatabase db) async {
  final columns = await db.customSelect('PRAGMA table_info(items)').get();
  return columns.map((row) => row.read<String>('name')).toSet();
}

Future<Set<String>> _tableNames(AppDatabase db) async {
  final rows = await db
      .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  test('v4 -> v5 adds the flea columns and filter tables, keeps every row, and '
      'backs up the v4 file', () async {
    final directory = createTemporaryDirectory(addTearDown);
    final path = '${directory.path}/tarkov_companion.sqlite';
    await _seedV4(path);

    final result = await openAppDatabase(path);
    expect(result, isA<DatabaseOpened>());
    final opened = result as DatabaseOpened;
    addTearDown(opened.close);

    expect(opened.fromVersion, 4);
    expect(opened.toVersion, 5);
    expect(opened.backup, isNotNull);
    expect(opened.backup!.existsSync(), isTrue);
    expect(await readPragma(opened.database, 'PRAGMA user_version'), 5);

    expect(
      await _itemColumns(opened.database),
      containsAll(<String>['minLevelForFlea', 'fleaEligible']),
    );
    expect(
      await _tableNames(opened.database),
      containsAll(<String>['itemTypes', 'itemCategories']),
    );

    // Existing rows survive, and the new columns are explicitly unknown
    // rather than guessed: the migration must not invent flea eligibility.
    final item = await opened.database
        .select(opened.database.items)
        .getSingle();
    expect(item.name, 'Colt M4A1');
    expect(item.minLevelForFlea, isNull);
    expect(item.fleaEligible, isNull);
    expect(item.priceObservedAt, isNull);
    expect(
      await opened.database.select(opened.database.itemTypes).get(),
      isEmpty,
    );
    expect(
      await opened.database.select(opened.database.itemCategories).get(),
      isEmpty,
    );
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

    // The new columns and tables are writable.
    await (opened.database.update(
      opened.database.items,
    )..where((row) => row.id.equals('item-m4a1'))).write(
      const ItemsCompanion(
        minLevelForFlea: Value(15),
        fleaEligible: Value(true),
      ),
    );
    await opened.database
        .into(opened.database.itemTypes)
        .insert(ItemTypesCompanion.insert(itemId: 'item-m4a1', type: 'gun'));
    await opened.database
        .into(opened.database.itemCategories)
        .insert(
          ItemCategoriesCompanion.insert(
            itemId: 'item-m4a1',
            categoryId: 'category-weapon',
            categoryKind: 'item',
          ),
        );
    final updated = await opened.database
        .select(opened.database.items)
        .getSingle();
    expect(updated.minLevelForFlea, 15);
    expect(updated.fleaEligible, isTrue);
    expect(
      await opened.database.select(opened.database.itemTypes).get(),
      hasLength(1),
    );

    // Deleting the item cascades its filter rows, both being game data.
    await (opened.database.delete(
      opened.database.items,
    )..where((row) => row.id.equals('item-m4a1'))).go();
    expect(
      await opened.database.select(opened.database.itemTypes).get(),
      isEmpty,
    );
    expect(
      await opened.database.select(opened.database.itemCategories).get(),
      isEmpty,
    );
    expect(
      await opened.database.select(opened.database.questProgress).get(),
      hasLength(1),
      reason: 'player data is never cascaded from game data',
    );

    // The backup is the pre-migration state: v4, without the v5 schema.
    final backup = sqlite.sqlite3.open(
      opened.backup!.path,
      mode: sqlite.OpenMode.readOnly,
    );
    addTearDown(backup.close);
    expect(backup.select('PRAGMA user_version').single['user_version'], 4);
    expect(
      backup
          .select('PRAGMA table_info(items)')
          .map((row) => row['name'])
          .toSet(),
      isNot(contains('fleaEligible')),
    );
    expect(
      backup.select(
        "SELECT name FROM sqlite_master WHERE name IN "
        "('itemTypes', 'itemCategories')",
      ),
      isEmpty,
    );
    expect(backup.select('SELECT name FROM items').single['name'], 'Colt M4A1');
  });

  test('v1 -> v5 runs every built-in step in one transaction', () async {
    final directory = createTemporaryDirectory(addTearDown);
    final path = '${directory.path}/tarkov_companion.sqlite';
    await _seedV1(path);

    final result = await openAppDatabase(path) as DatabaseOpened;
    addTearDown(result.close);

    expect(result.fromVersion, 1);
    expect(result.toVersion, 5);
    expect(result.backup, isNotNull);
    expect(await readPragma(result.database, 'PRAGMA user_version'), 5);

    expect(
      await _tableNames(result.database),
      containsAll(<String>[
        'remoteManifest',
        'gameRecords',
        'itemTypes',
        'itemCategories',
      ]),
    );
    expect(
      await _itemColumns(result.database),
      containsAll(<String>[
        'priceObservedAt',
        'minLevelForFlea',
        'fleaEligible',
      ]),
    );
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
  });
}
