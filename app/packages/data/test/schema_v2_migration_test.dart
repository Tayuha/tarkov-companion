import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

/// Seeds a real schema-v1 file, before `remoteManifest` and `gameRecords`
/// existed.
Future<void> _seedV1(String path) async {
  final db = AppDatabase.atPath(path, targetSchemaVersion: 1);
  await insertProfile(
    db,
    id: 'profile-regular',
    now: DateTime.utc(2026, 11, 26, 12),
  );
  await (db.update(db.profiles)
        ..where((row) => row.id.equals('profile-regular')))
      .write(const ProfilesCompanion(playerLevel: Value(34)));
  await db
      .into(db.appSettings)
      .insert(
        const AppSettingsCompanion(
          key: Value('settings.activeProfileId'),
          value: Value('"profile-regular"'),
        ),
      );
  // `onCreate` always builds the shipped (latest) schema, so remove the later
  // additions to leave a genuine v1 file for the migration to upgrade.
  await db.customStatement('DROP TABLE "remoteManifest"');
  await db.customStatement('DROP TABLE "gameRecords"');
  await db.close();
}

AppDatabase _openV2(String path) =>
    AppDatabase.atPath(path, targetSchemaVersion: 2);

void main() {
  test(
    'v1 -> v2 adds remoteManifest, keeps settings and profile rows, and backs '
    'up the v1 file',
    () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';
      await _seedV1(path);

      final result = await openAppDatabase(path, open: _openV2);
      expect(result, isA<DatabaseOpened>());
      final opened = result as DatabaseOpened;
      addTearDown(opened.close);

      expect(opened.fromVersion, 1);
      expect(opened.toVersion, 2);
      expect(opened.backup, isNotNull);
      expect(opened.backup!.existsSync(), isTrue);
      expect(await readPragma(opened.database, 'PRAGMA user_version'), 2);

      // The new table exists, has the documented shape and starts empty.
      final columns = await opened.database
          .customSelect('PRAGMA table_info(remoteManifest)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')).toList(),
        containsAllInOrder(<String>[
          'mode',
          'etag',
          'lastModified',
          'manifestJson',
          'manifestGeneratedAt',
          'lastCheckedAt',
          'lastChangedAt',
          'contentHash',
        ]),
      );
      expect(
        await opened.database.select(opened.database.remoteManifests).get(),
        isEmpty,
      );

      // Existing v1 data survived the migration unchanged.
      final profile = await opened.database
          .select(opened.database.profiles)
          .getSingle();
      expect(profile.id, 'profile-regular');
      expect(profile.playerLevel, 34);
      expect(
        await opened.database
            .select(opened.database.appSettings)
            .getSingle()
            .then((row) => row.value),
        '"profile-regular"',
      );

      // The backup is the pre-migration state: v1 and no new table.
      final backup = sqlite.sqlite3.open(
        opened.backup!.path,
        mode: sqlite.OpenMode.readOnly,
      );
      addTearDown(backup.close);
      expect(backup.select('PRAGMA user_version').single['user_version'], 1);
      expect(
        backup.select(
          "SELECT name FROM sqlite_master WHERE name = 'remoteManifest'",
        ),
        isEmpty,
      );
      expect(
        backup.select('SELECT playerLevel FROM profiles').single['playerLevel'],
        34,
      );

      // A second open is a no-op and still reads the migrated rows.
      await opened.close();
      final reopened = AppDatabase.atPath(path, targetSchemaVersion: 2);
      addTearDown(reopened.close);
      expect(await readPragma(reopened, 'PRAGMA user_version'), 2);
      expect(
        await reopened
            .select(reopened.profiles)
            .getSingle()
            .then((row) => row.playerLevel),
        34,
      );
    },
  );

  test(
    'a fresh v2 database records the version and creates the table',
    () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';

      final opened =
          await openAppDatabase(path, open: _openV2) as DatabaseOpened;
      addTearDown(opened.close);

      expect(opened.fromVersion, 0);
      expect(opened.toVersion, 2);
      expect(opened.backup, isNull);
      expect(await readPragma(opened.database, 'PRAGMA user_version'), 2);
      final tables = await opened.database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
            variables: [Variable<String>('remoteManifest')],
          )
          .get();
      expect(tables, hasLength(1));
      expect(File(path).existsSync(), isTrue);
    },
  );
}
