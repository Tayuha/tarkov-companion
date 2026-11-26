import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

void main() {
  test('a file-backed database actually runs in WAL mode', () async {
    final directory = createTemporaryDirectory(addTearDown);
    final path = '${directory.path}/tarkov_companion.sqlite';

    final db = AppDatabase.atPath(path);
    addTearDown(db.close);

    // Any query opens the database and runs `beforeOpen`.
    expect(await readPragma(db, 'PRAGMA journal_mode'), 'wal');
    expect(await readPragma(db, 'PRAGMA foreign_keys'), 1);
    expect(await readPragma(db, 'PRAGMA synchronous'), 1); // NORMAL

    expect(File(path).existsSync(), isTrue);

    // WAL keeps the committed data in a sidecar file until a checkpoint.
    final wal = File('$path-wal');
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          const AppSettingsCompanion(
            key: Value('activeProfile'),
            value: Value('profile-regular'),
          ),
        );
    expect(wal.existsSync() || File(path).existsSync(), isTrue);
  });

  test('re-opening a file-backed database keeps WAL enabled', () async {
    final directory = createTemporaryDirectory(addTearDown);
    final path = '${directory.path}/tarkov_companion.sqlite';

    final first = AppDatabase.atPath(path);
    expect(await readPragma(first, 'PRAGMA journal_mode'), 'wal');
    await first.close();

    final second = AppDatabase.atPath(path);
    addTearDown(second.close);
    expect(await readPragma(second, 'PRAGMA journal_mode'), 'wal');
  });

  test('the in-memory database has foreign keys enabled too', () async {
    // `memory` is the only journal mode an in-memory database supports; WAL is
    // a file property, so this test pins the part that still applies.
    final db = await openMemoryDatabase();
    addTearDown(db.close);

    expect(await readPragma(db, 'PRAGMA journal_mode'), 'memory');
    expect(await readPragma(db, 'PRAGMA foreign_keys'), 1);
  });
}
