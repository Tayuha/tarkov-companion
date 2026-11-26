import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Migrator, Value;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

Future<void> _upgradeToV2(Migrator migrator, int from, int to) async {
  await migrator.database.customStatement(
    'CREATE TABLE migrationProbe (id INTEGER PRIMARY KEY, note TEXT)',
  );
  await migrator.database.customStatement(
    "INSERT INTO migrationProbe (note) VALUES ('v2')",
  );
}

/// Adds real schema state before throwing, so the test proves the whole
/// upgrade rolled back rather than only that the exception was caught.
Future<void> _failingUpgrade(Migrator migrator, int from, int to) async {
  await migrator.database.customStatement(
    'CREATE TABLE migrationProbe (id INTEGER PRIMARY KEY, note TEXT)',
  );
  await migrator.database.customStatement(
    "INSERT INTO appSettings (key, value) VALUES ('migration', 'half')",
  );
  throw StateError('deliberate migration failure');
}

AppDatabase _openV2(String path) =>
    AppDatabase.atPath(path, targetSchemaVersion: 2, upgrade: _upgradeToV2);

AppDatabase _openFailingV2(String path) =>
    AppDatabase.atPath(path, targetSchemaVersion: 2, upgrade: _failingUpgrade);

Future<void> _seedV1(String path, {String itemName = 'Colt M4A1'}) async {
  // The runner tests need a real v1 file, while the shipped factory now opens
  // at v2; pin the version explicitly so these tests keep exercising v1 -> v2.
  final db = AppDatabase.atPath(path, targetSchemaVersion: 1);
  await insertItem(db, id: 'item-m4a1', name: itemName);
  await insertProfile(db, now: DateTime.utc(2026, 11, 26, 12));
  await db
      .into(db.appSettings)
      .insert(
        const AppSettingsCompanion(
          key: Value('activeProfile'),
          value: Value('profile-regular'),
        ),
      );
  await db.close();
}

Object? _userVersion(sqlite.Database db) =>
    db.select('PRAGMA user_version').first['user_version'];

void main() {
  group('openAppDatabase', () {
    test(
      'migrates v1 to v2 with a backup that still contains the v1 row',
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
        expect(opened.backup!.parent.path, backupDirectoryFor(path).path);
        expect(listBackups(path), hasLength(1));

        expect(await readPragma(opened.database, 'PRAGMA user_version'), 2);
        expect(
          await opened.database.select(opened.database.items).get(),
          hasLength(1),
        );
        expect(
          await opened.database.select(opened.database.profiles).get(),
          hasLength(1),
        );
        final probe = await opened.database
            .customSelect('SELECT note FROM migrationProbe')
            .getSingle();
        expect(probe.read<String>('note'), 'v2');

        final backup = sqlite.sqlite3.open(
          opened.backup!.path,
          mode: sqlite.OpenMode.readOnly,
        );
        addTearDown(backup.close);

        expect(_userVersion(backup), 1);
        expect(
          backup.select('SELECT name FROM items').single['name'],
          'Colt M4A1',
        );
        expect(
          backup.select(
            "SELECT name FROM sqlite_master WHERE name = 'migrationProbe'",
          ),
          isEmpty,
          reason: 'the backup must be the pre-migration state',
        );
      },
    );

    test('a failing migration keeps the original at v1 and opens recovery', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';
      await _seedV1(path);

      final result = await openAppDatabase(path, open: _openFailingV2);
      expect(result, isA<DatabaseRecovery>());
      final recovery = result as DatabaseRecovery;
      addTearDown(recovery.close);

      expect(recovery.detectedVersion, 1);
      expect(recovery.backup, isNotNull);
      expect(recovery.backup!.existsSync(), isTrue);
      expect(recovery.database.schemaVersion, 1);
      expect(
        recovery.database.tableNames(),
        containsAll(<String>[
          'appSettings',
          'items',
          'profiles',
          'questProgress',
        ]),
      );
      expect(
        recovery.database.tableNames(),
        isNot(contains('migrationProbe')),
        reason: 'the transaction must have rolled the DDL back',
      );
      expect(
        recovery.database.select('SELECT name FROM items').single['name'],
        'Colt M4A1',
      );
      expect(
        recovery.database
            .select(
              "SELECT count(*) AS n FROM appSettings WHERE key = 'migration'",
            )
            .single['n'],
        0,
        reason: 'the partially applied data change must be gone',
      );

      expect(
        () => recovery.database.execute(
          "INSERT INTO appSettings (key, value) VALUES ('x', 'y')",
        ),
        throwsA(isA<sqlite.SqliteException>()),
        reason: 'recovery mode is read-only',
      );

      // Nothing was deleted, replaced or auto-restored: the file on disk still
      // has version 1 and the original progress row.
      final raw = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
      addTearDown(raw.close);
      expect(_userVersion(raw), 1);
      expect(raw.select('SELECT name FROM items').single['name'], 'Colt M4A1');
    });

    test('a row in an uncheckpointed WAL reaches the backup', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';
      await _seedV1(path);

      // Keep this connection open so the committed row stays in `-wal` and is
      // never checkpointed by a clean close.
      final writer = sqlite.sqlite3.open(path);
      addTearDown(writer.close);
      writer.execute('PRAGMA journal_mode = WAL');
      writer.execute(
        "INSERT INTO appSettings (key, value) VALUES ('walOnly', 'visible')",
      );
      final wal = File('$path-wal');
      expect(wal.existsSync(), isTrue);
      expect(wal.lengthSync(), greaterThan(0));

      final result = await openAppDatabase(path, open: _openV2);
      expect(result, isA<DatabaseOpened>());
      final opened = result as DatabaseOpened;
      addTearDown(opened.close);
      expect(opened.backup, isNotNull);

      final backup = sqlite.sqlite3.open(
        opened.backup!.path,
        mode: sqlite.OpenMode.readOnly,
      );
      addTearDown(backup.close);
      final rows = backup.select(
        "SELECT value FROM appSettings WHERE key = 'walOnly'",
      );
      expect(rows, hasLength(1), reason: 'VACUUM INTO must read the WAL');
      expect(rows.single['value'], 'visible');

      // The migrated live database has the row as well.
      expect(
        await opened.database
            .customSelect("SELECT value FROM appSettings WHERE key = 'walOnly'")
            .getSingle()
            .then((row) => row.read<String>('value')),
        'visible',
      );
    });

    test('prunes old backups and leaves unrelated files alone', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';
      final backups = backupDirectoryFor(path)..createSync(recursive: true);

      for (var second = 0; second < 5; second++) {
        final file = File(
          '${backups.path}/${backupFileName(databasePath: path, fromVersion: 1, toVersion: 2, timestamp: DateTime.utc(2026, 11, 26, 12, 0, second))}',
        )..writeAsStringSync('backup $second');
        expect(file.existsSync(), isTrue);
      }
      final foreign = File('${backups.path}/notes.txt')
        ..writeAsStringSync('keep me');

      pruneBackups(path, keep: 3);

      final remaining = listBackups(path);
      expect(remaining, hasLength(3));
      expect(remaining.map((file) => file.readAsStringSync()).toSet(), {
        'backup 2',
        'backup 3',
        'backup 4',
      });
      expect(foreign.existsSync(), isTrue);
    });

    test('retention applies when a migration creates a backup', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';
      await _seedV1(path);

      final backups = backupDirectoryFor(path)..createSync(recursive: true);
      for (var minute = 0; minute < 4; minute++) {
        File(
          '${backups.path}/${backupFileName(databasePath: path, fromVersion: 1, toVersion: 2, timestamp: DateTime.utc(2026, 11, 26, 11, minute))}',
        ).writeAsStringSync('old $minute');
      }

      final result = await openAppDatabase(
        path,
        open: _openV2,
        backupRetention: 3,
      ) as DatabaseOpened;
      addTearDown(result.close);
      expect(listBackups(path), hasLength(3));
    });

    test('a fresh database creates no backup', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';

      final result = await openAppDatabase(path) as DatabaseOpened;
      addTearDown(result.close);

      expect(result.fromVersion, 0);
      expect(result.toVersion, 4);
      expect(result.backup, isNull);
      expect(backupDirectoryFor(path).existsSync(), isFalse);
      expect(await readPragma(result.database, 'PRAGMA user_version'), 4);
    });

    test(
      'a newer schema version enters recovery instead of downgrading',
      () async {
        final directory = createTemporaryDirectory(addTearDown);
        final path = '${directory.path}/tarkov_companion.sqlite';
        await _seedV1(path);

        final raw = sqlite.sqlite3.open(path);
        raw.execute('PRAGMA user_version = 99');
        raw.close();

        final result = await openAppDatabase(path) as DatabaseRecovery;
        addTearDown(result.close);

        expect(result.detectedVersion, 99);
        expect(result.backup, isNull);
        expect(result.database.schemaVersion, 99);
        expect(result.database.tableNames(), contains('items'));

        final check = sqlite.sqlite3.open(path, mode: sqlite.OpenMode.readOnly);
        addTearDown(check.close);
        expect(_userVersion(check), 99);
      },
    );

    test('a corrupt file enters recovery and keeps its bytes', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/broken.sqlite';
      File(path).writeAsStringSync('this is not a sqlite database');

      final result = await openAppDatabase(path) as DatabaseRecovery;
      addTearDown(result.close);

      expect(result.detectedVersion, -1);
      expect(result.backup, isNull);
      expect(File(path).readAsStringSync(), 'this is not a sqlite database');
    });
  });

  group('restoreFromBackup', () {
    test('restores the backup row and clears stale WAL sidecars', () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';
      await _seedV1(path, itemName: 'original');

      final opened =
          await openAppDatabase(path, open: _openV2) as DatabaseOpened;
      final backup = opened.backup!;
      expect(backup.existsSync(), isTrue);

      await opened.database.customStatement(
        "UPDATE items SET name = 'changed' WHERE id = 'item-m4a1'",
      );
      await opened.close();

      // Simulate sidecars left behind by an interrupted process. If restore
      // fails to remove them, SQLite would refuse or misread the new file.
      File('$path-wal').writeAsStringSync('stale wal');
      File('$path-shm').writeAsStringSync('stale shm');

      final restored = await restoreDatabaseFromBackup(
        databasePath: path,
        backupPath: backup,
        open: _openV2,
      );
      addTearDown(restored.close);

      final rows = await restored.database
          .select(restored.database.items)
          .get();
      expect(rows.single.name, 'original');

      final wal = File('$path-wal');
      if (wal.existsSync()) {
        expect(wal.readAsBytesSync(), isNot(utf8.encode('stale wal')));
      }
      final shm = File('$path-shm');
      if (shm.existsSync()) {
        expect(shm.readAsBytesSync(), isNot(utf8.encode('stale shm')));
      }
    });

    test(
      'the recovery handle can trigger the restore and closes first',
      () async {
        final directory = createTemporaryDirectory(addTearDown);
        final path = '${directory.path}/tarkov_companion.sqlite';
        await _seedV1(path, itemName: 'original');

        final recovery = await openAppDatabase(
          path,
          open: _openFailingV2,
        ) as DatabaseRecovery;
        final backup = recovery.backup!;

        // No factory: the backup is restored at its own version and the
        // failed v2 migration is not retried immediately.
        final restored = await recovery.restoreFromBackup(backup);
        addTearDown(restored.close);

        final rows = await restored.database
            .select(restored.database.items)
            .get();
        expect(rows.single.name, 'original');
        expect(restored.fromVersion, 1);
        expect(restored.toVersion, 1);
        expect(
          () => recovery.database.select('SELECT 1'),
          throwsA(anything),
          reason: 'the recovery handle was closed before restoring',
        );
      },
    );
  });
}
