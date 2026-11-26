import 'dart:io';

import 'package:drift/drift.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

void main() {
  test(
    're-opening an existing database is idempotent and keeps rows',
    () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/tarkov_companion.sqlite';
      final now = DateTime.utc(2026, 11, 26, 12);

      final first = AppDatabase.atPath(path);
      await insertProfile(first, now: now);
      await first
          .into(first.questProgress)
          .insert(
            QuestProgressCompanion.insert(
              profileId: 'profile-regular',
              questId: 'quest-debut',
              state: 'completed',
              updatedAt: now,
            ),
          );
      await insertItem(first, id: 'item-m4a1', name: 'Colt M4A1');
      await first.close();

      // The schema is created once; a second open must not recreate, drop or
      // duplicate anything.
      final second = AppDatabase.atPath(path);
      addTearDown(second.close);

      expect(await readPragma(second, 'PRAGMA user_version'), 4);
      expect(await readPragma(second, 'PRAGMA journal_mode'), 'wal');
      expect(await second.select(second.items).get(), hasLength(1));
      expect(await second.select(second.profiles).get(), hasLength(1));
      expect(await second.select(second.questProgress).get(), hasLength(1));

      final ftsCount = await second
          .customSelect('SELECT count(*) AS n FROM items_fts')
          .getSingle();
      expect(ftsCount.read<int>('n'), 1, reason: 'FTS rows were duplicated');

      // Writes after a reopen land in the same file.
      await second
          .into(second.appSettings)
          .insertOnConflictUpdate(
            const AppSettingsCompanion(
              key: Value('activeProfile'),
              value: Value('profile-regular'),
            ),
          );

      await second.close();

      final third = AppDatabase.atPath(path);
      addTearDown(third.close);
      expect(
        await third
            .select(third.appSettings)
            .getSingle()
            .then((row) => row.value),
        'profile-regular',
      );
      expect(File('$path-wal').existsSync(), isTrue);
    },
  );

  test(
    'a burned database file is detected instead of silently opened',
    () async {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/broken.sqlite';
      File(path).writeAsStringSync('this is not a sqlite database');

      final db = AppDatabase.atPath(path);
      addTearDown(db.close);

      await expectLater(db.select(db.items).get(), throwsA(anything));
    },
  );
}
