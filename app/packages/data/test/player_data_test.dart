import 'package:drift/drift.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

/// Deletes every row of every game-data table, the way a full dataset refresh
/// does before re-inserting.
Future<void> deleteAllGameData(AppDatabase db) async {
  await db.delete(db.taskObjectives).go();
  await db.delete(db.tasks).go();
  await db.delete(db.items).go();
  await db.delete(db.priceHistory).go();
  await db.delete(db.datasetStates).go();
  await db.delete(db.crafts).go();
  await db.delete(db.barters).go();
  await db.delete(db.maps).go();
  await db.delete(db.traders).go();
  await db.delete(db.hideoutStations).go();
  await db.delete(db.gameRecords).go();
}

/// The tables that own game data (replaceable) and player data (durable).
const playerTables = <String>{
  'profiles',
  'questProgress',
  'objectiveProgress',
  'appSettings',
};

Future<List<({String table, String from, String to})>> foreignKeys(
  AppDatabase db,
  String table,
) async {
  final rows = await db.customSelect('PRAGMA foreign_key_list($table)').get();
  return rows
      .map(
        (row) => (
          table: row.read<String>('table'),
          from: row.read<String>('from'),
          to: row.read<String>('to'),
        ),
      )
      .toList();
}

void main() {
  late AppDatabase db;
  final now = DateTime.utc(2026, 11, 26, 12);

  setUp(() async {
    db = await openMemoryDatabase();
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
        .into(db.objectiveProgress)
        .insert(
          ObjectiveProgressCompanion.insert(
            profileId: 'profile-regular',
            questId: 'quest-debut',
            objectiveId: 'objective-1',
            count: const Value(3),
            updatedAt: now,
          ),
        );
    await insertItem(db, id: 'item-m4a1', name: 'Colt M4A1');
    await db
        .into(db.priceHistory)
        .insert(
          PriceHistoryCompanion.insert(
            itemId: 'item-m4a1',
            observedAt: now,
            price: 40000,
            priceMin: const Value(38000),
          ),
        );
  });

  tearDown(() => db.close());

  test('player progress survives deleting every game-data row', () async {
    await deleteAllGameData(db);

    expect(await db.select(db.items).get(), isEmpty);
    expect(await db.select(db.tasks).get(), isEmpty);

    final quests = await db.select(db.questProgress).get();
    final objectives = await db.select(db.objectiveProgress).get();

    expect(quests, hasLength(1));
    expect(quests.single.questId, 'quest-debut');
    expect(quests.single.state, 'completed');
    expect(objectives, hasLength(1));
    expect(objectives.single.count, 3);
  });

  test('progress survives a whole-dataset items replacement', () async {
    // The refresh pattern from design D3: delete the dataset, re-insert it.
    await db.delete(db.items).go();
    await insertItem(
      db,
      id: 'item-m4a1',
      name: 'Colt M4A1',
      payload: '{"v":2}',
    );
    await insertItem(db, id: 'item-new', name: 'New item');

    expect(await db.select(db.questProgress).get(), hasLength(1));
    expect(await db.select(db.objectiveProgress).get(), hasLength(1));
  });

  test('cached price history is not a foreign key onto items', () async {
    // No FK means deleting the item dataset neither fails nor wipes the cache.
    await db.delete(db.items).go();

    final history = await db.select(db.priceHistory).get();
    expect(history, hasLength(1));
    expect(history.single.itemId, 'item-m4a1');
  });

  test(
    'inserting progress for an unknown quest succeeds (no foreign key)',
    () async {
      await db
          .into(db.questProgress)
          .insert(
            QuestProgressCompanion.insert(
              profileId: 'profile-regular',
              questId: 'quest-removed-upstream',
              state: 'in-progress',
              updatedAt: now,
            ),
          );
      await db
          .into(db.objectiveProgress)
          .insert(
            ObjectiveProgressCompanion.insert(
              profileId: 'profile-regular',
              questId: 'quest-removed-upstream',
              objectiveId: 'objective-removed-upstream',
              updatedAt: now,
            ),
          );

      final removed =
          await (db.select(db.questProgress)
                ..where((row) => row.questId.equals('quest-removed-upstream')))
              .getSingle();

      expect(removed.state, 'in-progress');
      expect(await db.select(db.objectiveProgress).get(), hasLength(2));
    },
  );

  test('no player table declares a foreign key onto game data', () async {
    for (final table in playerTables) {
      final keys = await foreignKeys(db, table);
      final targets = keys.map((key) => key.table).toSet();

      expect(
        targets.difference({'profiles'}),
        isEmpty,
        reason: '$table may only reference player tables (profiles)',
      );
    }
  });

  test(
    'the allowed game-data foreign key cascades taskObjectives -> tasks',
    () async {
      final keys = await foreignKeys(db, 'taskObjectives');
      expect(
        keys.map((key) => (key.table, key.from, key.to)),
        contains(('tasks', 'taskId', 'id')),
      );

      // Prove enforcement is on: inserting an orphan objective fails.
      await expectLater(
        db
            .into(db.taskObjectives)
            .insert(
              TaskObjectivesCompanion.insert(
                id: 'orphan',
                taskId: 'missing-task',
                type: 'visit',
                payload: '{}',
              ),
            ),
        throwsA(anything),
      );
    },
  );

  test('deleting a profile cascades to its own progress only', () async {
    await insertProfile(db, id: 'profile-pve', gameMode: 'pve', now: now);

    await (db.delete(
      db.profiles,
    )..where((row) => row.id.equals('profile-regular'))).go();

    expect(await db.select(db.profiles).get(), hasLength(1));
    expect(await db.select(db.questProgress).get(), isEmpty);
    expect(await db.select(db.objectiveProgress).get(), isEmpty);
  });

  test('game modes are unique per profile', () async {
    await expectLater(
      insertProfile(db, id: 'profile-other-regular', now: now),
      throwsA(anything),
      reason: 'a second regular profile violates the UNIQUE constraint',
    );

    await insertProfile(db, id: 'profile-pve', gameMode: 'pve', now: now);
    expect(await db.select(db.profiles).get(), hasLength(2));
  });
}
