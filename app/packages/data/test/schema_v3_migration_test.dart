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
}

/// Seeds a real schema-v2 file, before `gameRecords` existed.
Future<void> _seedV2(String path) async {
  final db = AppDatabase.atPath(path, targetSchemaVersion: 2);
  await _seedItemAndProgress(db);
  await db
      .into(db.datasetStates)
      .insert(
        DatasetStatesCompanion.insert(
          mode: 'regular',
          dataset: 'items',
          checksum: 'a' * 64,
          schemaVersion: 1,
          records: 1,
          appliedAt: DateTime.utc(2026, 11, 26, 12),
        ),
      );
  await db
      .into(db.remoteManifests)
      .insert(
        RemoteManifestsCompanion.insert(
          mode: 'regular',
          etag: const Value('"v1"'),
          lastModified: const Value('Wed, 25 Nov 2026 18:20:24 GMT'),
          manifestJson: '{"mode":"regular"}',
          manifestGeneratedAt: const Value('2026-11-25T20:00:00.000Z'),
          lastCheckedAt: DateTime.utc(2026, 11, 26, 12),
          contentHash: 'b' * 64,
        ),
      );
  // `onCreate` always builds the shipped (latest) schema, so remove the v3
  // addition to leave a genuine v2 file for the migration to upgrade.
  await db.customStatement('DROP TABLE "gameRecords"');
  await db.close();
}

/// Seeds a schema-v1 file: no `remoteManifest` and no `gameRecords`.
Future<void> _seedV1(String path) async {
  final db = AppDatabase.atPath(path, targetSchemaVersion: 1);
  await _seedItemAndProgress(db);
  await db.customStatement('DROP TABLE "remoteManifest"');
  await db.customStatement('DROP TABLE "gameRecords"');
  await db.close();
}

void main() {
  test(
    'v2 -> v3 adds gameRecords and its kind index, keeps every row, and backs '
    'up the v2 file',
    () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';
      await _seedV2(path);

      final result = await openAppDatabase(path);
      expect(result, isA<DatabaseOpened>());
      final opened = result as DatabaseOpened;
      addTearDown(opened.close);

      expect(opened.fromVersion, 2);
      expect(opened.toVersion, 3);
      expect(opened.backup, isNotNull);
      expect(opened.backup!.existsSync(), isTrue);
      expect(await readPragma(opened.database, 'PRAGMA user_version'), 3);

      final columns = await opened.database
          .customSelect('PRAGMA table_info(gameRecords)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        containsAllInOrder(<String>['kind', 'id', 'payload']),
      );
      expect(
        await opened.database.select(opened.database.gameRecords).get(),
        isEmpty,
      );
      expect(
        await opened.database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'gameRecordsKind'",
            )
            .get(),
        hasLength(1),
      );

      // v2 game, player and sync rows survived unchanged.
      final item = await opened.database
          .select(opened.database.items)
          .getSingle();
      expect(item.name, 'Colt M4A1');
      expect(
        await opened.database.select(opened.database.questProgress).getSingle(),
        isNotNull,
      );
      expect(
        await opened.database.select(opened.database.datasetStates).getSingle(),
        isNotNull,
      );
      expect(
        await opened.database
            .select(opened.database.remoteManifests)
            .getSingle(),
        isNotNull,
      );
      final fts = await opened.database
          .customSelect('SELECT count(*) AS n FROM items_fts')
          .getSingle();
      expect(fts.read<int>('n'), 1);

      // The new table is writable and keyed by kind + id.
      await opened.database
          .into(opened.database.gameRecords)
          .insert(
            GameRecordsCompanion.insert(
              kind: 'armorMaterial',
              id: 'Aluminium',
              payload: '{"id":"Aluminium","kind":"armorMaterial"}',
            ),
          );
      expect(
        await opened.database.select(opened.database.gameRecords).get(),
        hasLength(1),
      );

      // The backup is the pre-migration state: v2, no gameRecords.
      final backup = sqlite.sqlite3.open(
        opened.backup!.path,
        mode: sqlite.OpenMode.readOnly,
      );
      addTearDown(backup.close);
      expect(backup.select('PRAGMA user_version').single['user_version'], 2);
      expect(
        backup.select(
          "SELECT name FROM sqlite_master WHERE name = 'gameRecords'",
        ),
        isEmpty,
      );
      expect(
        backup.select('SELECT name FROM items').single['name'],
        'Colt M4A1',
      );
    },
  );

  test('v1 -> v3 runs both built-in steps in one transaction', () async {
    final directory = createTemporaryDirectory(addTearDown);
    final path = '${directory.path}/tarkov_companion.sqlite';
    await _seedV1(path);

    final result = await openAppDatabase(path) as DatabaseOpened;
    addTearDown(result.close);

    expect(result.fromVersion, 1);
    expect(result.toVersion, 3);
    expect(result.backup, isNotNull);
    expect(await readPragma(result.database, 'PRAGMA user_version'), 3);

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
