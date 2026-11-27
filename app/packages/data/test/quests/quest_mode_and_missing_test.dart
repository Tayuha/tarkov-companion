import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';
import '../support/quest_engine_fixture.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);

  late AppDatabase db;
  late Directory temporary;
  late QuestRepository repository;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
    repository = QuestRepository(db, clock: () => now);
    await insertProfile(db, id: 'regular', gameMode: 'regular', now: now);
    await insertProfile(db, id: 'pve', gameMode: 'pve', now: now);
  });

  tearDown(() => db.close());

  Future<void> ingest(List<Map<String, Object?>> tasks) =>
      ingestTasks(db, temporary, tasks);

  group('game-mode scoping', () {
    setUp(() async {
      await ingest([
        questRecord(id: 'shared', name: 'Shared'),
        questRecord(
          id: 'regular-only',
          name: 'Regular Only',
          gameMode: ['regular'],
        ),
        questRecord(id: 'pve-only', name: 'PvE Only', gameMode: ['pve']),
        questRecord(id: 'unscoped', name: 'Unscoped', gameMode: []),
      ]);
    });

    test('the catalog query keeps only the profile mode\'s tasks', () async {
      Future<Set<String>> ids(String? profileId) async {
        final page = await repository.query(
          QuestQuery(profileId: profileId, limit: QuestQuery.maxLimit),
        );
        return {for (final quest in page.quests) quest.id};
      }

      expect(await ids('regular'), {'shared', 'regular-only', 'unscoped'});
      expect(await ids('pve'), {'shared', 'pve-only', 'unscoped'});
      expect(await ids(null), {
        'shared',
        'regular-only',
        'pve-only',
        'unscoped',
      });
    });

    test('count uses the same mode filter as the page', () async {
      expect(await repository.count(const QuestQuery(profileId: 'regular')), 3);
      expect(await repository.count(const QuestQuery(profileId: 'pve')), 3);
      expect(await repository.count(const QuestQuery()), 4);
    });

    test('a PvE-only quest is absent under the regular profile', () async {
      expect(
        (await repository.query(const QuestQuery(profileId: 'regular'))).quests
            .map((quest) => quest.id),
        isNot(contains('pve-only')),
      );
      expect(
        (await repository.query(const QuestQuery(profileId: 'pve'))).quests
            .map((quest) => quest.id),
        contains('pve-only'),
      );

      expect(await repository.status('regular', 'pve-only'), isNull);
      expect(await repository.detail('pve-only', profileId: 'regular'), isNull);
      expect(await repository.detail('pve-only', profileId: 'pve'), isNotNull);
      expect(
        (await repository.availableQuests('regular')).map((quest) => quest.id),
        isNot(contains('pve-only')),
      );
    });

    test('a write for a quest outside the profile mode is rejected', () async {
      await expectLater(
        repository.setQuestState(
          'regular',
          'pve-only',
          QuestProgressState.completed,
        ),
        throwsA(isA<QuestNotFoundError>()),
      );
      expect(await db.select(db.questProgress).get(), isEmpty);
    });

    test('a malformed gameMode list stays readable', () async {
      await ingest([
        questRecord(id: 'bad', name: 'Bad Mode')..['gameMode'] = 'pve',
      ]);

      expect(
        (await repository.query(const QuestQuery(profileId: 'regular'))).quests
            .map((quest) => quest.id),
        contains('bad'),
      );
    });
  });

  group('missing quests from the active dataset', () {
    setUp(() async {
      await ingest([
        questRecord(
          id: 'dependent',
          name: 'Dependent',
          taskRequirements: [requiresQuest('removed')],
        ),
        questRecord(id: 'free', name: 'Free'),
      ]);

      await db
          .into(db.questProgress)
          .insert(
            QuestProgressCompanion.insert(
              profileId: 'regular',
              questId: 'removed',
              state: 'completed',
              updatedAt: now,
            ),
          );
      await db
          .into(db.objectiveProgress)
          .insert(
            ObjectiveProgressCompanion.insert(
              profileId: 'regular',
              questId: 'removed',
              objectiveId: 'removed-objective',
              count: const Value(3),
              updatedAt: now,
            ),
          );
    });

    test(
      'preserved progress is listed as unavailable, never dropped',
      () async {
        final orphans = await repository.orphanedProgress('regular');
        expect(orphans, hasLength(1));
        final orphan = orphans.single;
        expect(orphan.questId, 'removed');
        expect(orphan.state, QuestProgressState.completed);
        expect(orphan.objectiveCounts, {'removed-objective': 3});
        expect(orphan.updatedAt, isNotNull);
      },
    );

    test(
      'the orphan is absent from the catalog but the catalog still reads',
      () async {
        final page = await repository.query(
          const QuestQuery(profileId: 'regular', limit: QuestQuery.maxLimit),
        );
        expect(
          {for (final quest in page.quests) quest.id},
          {'dependent', 'free'},
        );
        expect(page.total, 2);
      },
    );

    test('orphaned progress is excluded from dependency math', () async {
      final dependent = await repository.status('regular', 'dependent');
      expect(dependent, isNotNull);
      expect(dependent!.availability, QuestAvailability.locked);
      final reason = dependent.blockingReasons
          .whereType<MissingPrerequisite>()
          .single;
      expect(reason.taskId, 'removed');
      expect(reason.prerequisiteInDataset, isFalse);
      expect(reason.actualState, QuestProgressState.completed);

      final available = await repository.availableQuests('regular');
      expect(available.map((quest) => quest.id), ['free']);
    });

    test('a profile that references nothing removed has no orphans', () async {
      expect(await repository.orphanedProgress('pve'), isEmpty);
    });
  });

  group('available ordering', () {
    setUp(() async {
      await ingest([
        questRecord(
          id: 'zulu',
          name: 'Zulu',
          minPlayerLevel: 20,
          traderId: 'trader-b',
          mapId: 'map-b',
        ),
        questRecord(
          id: 'alpha',
          name: 'Alpha',
          minPlayerLevel: 20,
          traderId: 'trader-b',
          mapId: 'map-a',
        ),
        questRecord(
          id: 'bravo',
          name: 'Bravo',
          minPlayerLevel: 10,
          traderId: 'trader-a',
          mapId: 'map-b',
        ),
        questRecord(
          id: 'no-level',
          name: 'No Level',
          minPlayerLevel: null,
          traderId: null,
          mapId: null,
        ),
      ]);
      await setPlayerLevel(db, 'regular', 20);
    });

    Future<List<String>> ids({QuestSort? sort}) async => [
      for (final status in await repository.availableQuests(
        'regular',
        sort: sort,
      ))
        status.id,
    ];

    test('default order is level, trader, then name', () async {
      expect(await ids(), ['bravo', 'alpha', 'zulu', 'no-level']);
    });

    test('name order', () async {
      expect(await ids(sort: const QuestSort(QuestSortField.name)), [
        'alpha',
        'bravo',
        'no-level',
        'zulu',
      ]);
    });

    test('trader order keeps missing traders last', () async {
      expect(await ids(sort: const QuestSort(QuestSortField.traderId)), [
        'bravo',
        'alpha',
        'zulu',
        'no-level',
      ]);
      expect(
        await ids(
          sort: const QuestSort(QuestSortField.traderId, descending: true),
        ),
        ['alpha', 'zulu', 'bravo', 'no-level'],
      );
    });

    test('map order keeps missing maps last', () async {
      expect(await ids(sort: const QuestSort(QuestSortField.mapId)), [
        'alpha',
        'bravo',
        'zulu',
        'no-level',
      ]);
    });

    test('level order puts quests without a level last', () async {
      expect(await ids(sort: const QuestSort(QuestSortField.minPlayerLevel)), [
        'bravo',
        'alpha',
        'zulu',
        'no-level',
      ]);
      expect(
        await ids(
          sort: const QuestSort(
            QuestSortField.minPlayerLevel,
            descending: true,
          ),
        ),
        ['alpha', 'zulu', 'bravo', 'no-level'],
      );
    });
  });
}
