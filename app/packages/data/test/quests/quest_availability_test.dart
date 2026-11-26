import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';
import '../support/quest_engine_fixture.dart';

void main() {
  final now = DateTime.utc(2026, 11, 26, 12);

  late AppDatabase db;
  late Directory temporary;
  late QuestRepository repository;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
    repository = QuestRepository(db, clock: () => now);
    await insertProfile(db, id: 'p1', gameMode: 'regular', now: now);
    await insertProfile(db, id: 'p2', gameMode: 'pve', now: now);
  });

  tearDown(() => db.close());

  Future<void> ingest(List<Map<String, Object?>> tasks) =>
      ingestTasks(db, temporary, tasks);

  Future<QuestStatus> status(String questId, {String profile = 'p1'}) async {
    final result = await repository.status(profile, questId);
    expect(result, isNotNull, reason: 'quest $questId is in the dataset');
    return result!;
  }

  group('prerequisite chain', () {
    setUp(() async {
      await ingest([
        questRecord(id: 'a', name: 'A'),
        questRecord(id: 'b', name: 'B', taskRequirements: [requiresQuest('a')]),
      ]);
    });

    test('completing a prerequisite makes the dependent available', () async {
      expect((await status('b')).availability, QuestAvailability.locked);
      final locked = await status('b');
      expect(locked.blockingReasons, hasLength(1));
      final reason = locked.blockingReasons.single as MissingPrerequisite;
      expect(reason.taskId, 'a');
      expect(reason.taskName, 'A');
      expect(reason.requiredStatuses, ['complete']);

      await repository.setQuestState('p1', 'a', QuestProgressState.completed);

      final available = await status('b');
      expect(available.availability, QuestAvailability.available);
      expect(available.blockingReasons, isEmpty);
    });

    test('reverting a prerequisite locks the dependent again', () async {
      await repository.setQuestState('p1', 'a', QuestProgressState.completed);
      expect((await status('b')).availability, QuestAvailability.available);

      await repository.setQuestState('p1', 'a', QuestProgressState.inProgress);

      final reverted = await status('b');
      expect(reverted.availability, QuestAvailability.locked);
      expect(
        reverted.blockingReasons.whereType<MissingPrerequisite>().single.taskId,
        'a',
      );
    });

    test(
      'a prerequisite requirement accepts only its listed statuses',
      () async {
        await ingest([
          questRecord(id: 'a', name: 'A'),
          questRecord(
            id: 'b',
            name: 'B',
            taskRequirements: [
              requiresQuest('a', statuses: ['active']),
            ],
          ),
        ]);

        expect((await status('b')).availability, QuestAvailability.locked);

        await repository.setQuestState(
          'p1',
          'a',
          QuestProgressState.inProgress,
        );
        expect((await status('b')).availability, QuestAvailability.available);

        await repository.setQuestState('p1', 'a', QuestProgressState.completed);
        expect(
          (await status('b')).availability,
          QuestAvailability.locked,
          reason: 'the requirement lists active, not complete',
        );
      },
    );

    test('multiple prerequisites all have to be satisfied', () async {
      await ingest([
        questRecord(id: 'a', name: 'A'),
        questRecord(id: 'b', name: 'B'),
        questRecord(
          id: 'c',
          name: 'C',
          taskRequirements: [requiresQuest('a'), requiresQuest('b')],
        ),
      ]);

      await repository.setQuestState('p1', 'a', QuestProgressState.completed);
      final oneOfTwo = await status('c');
      expect(oneOfTwo.availability, QuestAvailability.locked);
      expect(
        oneOfTwo.blockingReasons.whereType<MissingPrerequisite>().single.taskId,
        'b',
      );

      await repository.setQuestState('p1', 'b', QuestProgressState.completed);
      expect((await status('c')).availability, QuestAvailability.available);
    });
  });

  group('level gate', () {
    test('a level below the minimum locks with a level reason', () async {
      await ingest([
        questRecord(id: 'high', name: 'High', minPlayerLevel: 20),
        questRecord(id: 'low', name: 'Low', minPlayerLevel: 5),
      ]);
      await setPlayerLevel(db, 'p1', 5);

      final high = await status('high');
      expect(high.availability, QuestAvailability.locked);
      final reason = high.blockingReasons.whereType<PlayerLevelTooLow>().single;
      expect(reason.requiredLevel, 20);
      expect(reason.playerLevel, 5);

      expect((await status('low')).availability, QuestAvailability.available);

      await setPlayerLevel(db, 'p1', 20);
      expect((await status('high')).availability, QuestAvailability.available);
    });

    test(
      'profile isolation: level and progress never leak across modes',
      () async {
        await ingest([questRecord(id: 'a', name: 'A', minPlayerLevel: 10)]);
        await setPlayerLevel(db, 'p1', 1);
        await setPlayerLevel(db, 'p2', 10);

        expect((await status('a')).availability, QuestAvailability.locked);
        expect(
          (await status('a', profile: 'p2')).availability,
          QuestAvailability.available,
        );

        await repository.setQuestState('p1', 'a', QuestProgressState.completed);
        expect(
          (await status('a', profile: 'p2')).recordedState,
          QuestProgressState.notStarted,
        );
      },
    );

    test('an unknown profile is a typed error', () async {
      await ingest([questRecord(id: 'a', name: 'A')]);
      expect(
        () => repository.statuses('missing'),
        throwsA(isA<QuestProfileNotFoundError>()),
      );
      expect(
        () => repository.availableQuests('missing'),
        throwsA(isA<QuestProfileNotFoundError>()),
      );
    });
  });

  group('malformed data', () {
    test('a cycle terminates and is reported', () async {
      await ingest([
        questRecord(id: 'a', name: 'A', taskRequirements: [requiresQuest('b')]),
        questRecord(id: 'b', name: 'B', taskRequirements: [requiresQuest('a')]),
      ]);

      final all = await repository.statuses('p1');
      expect(all, hasLength(2));
      expect(
        all.every((quest) => quest.availability == QuestAvailability.locked),
        isTrue,
      );
      for (final quest in all) {
        expect(
          quest.reasons.whereType<PrerequisiteCycle>(),
          isNotEmpty,
          reason: '${quest.id} must report the cycle',
        );
      }
      final cycle = all.first.reasons.whereType<PrerequisiteCycle>().first;
      expect(cycle.cycle.first, cycle.cycle.last);
      expect(await repository.availableQuests('p1'), isEmpty);
    });

    test(
      'a manual completion breaks a cycle instead of locking it forever',
      () async {
        await ingest([
          questRecord(
            id: 'a',
            name: 'A',
            taskRequirements: [requiresQuest('b')],
          ),
          questRecord(
            id: 'b',
            name: 'B',
            taskRequirements: [requiresQuest('a')],
          ),
        ]);

        await repository.setQuestState('p1', 'a', QuestProgressState.completed);
        final b = await status('b');
        expect(b.availability, QuestAvailability.available);
        expect(b.reasons.whereType<PrerequisiteCycle>(), isEmpty);
      },
    );

    test('a missing prerequisite is reported and not satisfied by orphan progress', () async {
      await ingest([
        questRecord(
          id: 'b',
          name: 'B',
          taskRequirements: [requiresQuest('removed-quest')],
        ),
      ]);

      // A preserved completed row for the removed quest is player data: the
      // ingestion above does not touch it, but dependency math must ignore it.
      await db
          .into(db.questProgress)
          .insert(
            QuestProgressCompanion.insert(
              profileId: 'p1',
              questId: 'removed-quest',
              state: 'completed',
              updatedAt: now,
            ),
          );

      final b = await status('b');
      expect(b.availability, QuestAvailability.locked);
      final reason = b.blockingReasons.whereType<MissingPrerequisite>().single;
      expect(reason.taskId, 'removed-quest');
      expect(reason.prerequisiteInDataset, isFalse);
      expect(reason.actualState, QuestProgressState.completed);
    });

    test('an unrecognized prerequisite status is malformed', () async {
      await ingest([
        questRecord(id: 'a', name: 'A'),
        questRecord(
          id: 'b',
          name: 'B',
          taskRequirements: [
            requiresQuest('a', statuses: ['paused']),
          ],
        ),
      ]);

      final b = await status('b');
      expect(b.availability, QuestAvailability.locked);
      expect(b.reasons.whereType<MalformedPrerequisite>(), isNotEmpty);
    });
  });

  group('failed and advisory requirements', () {
    test('a non-restartable failed quest stays locked', () async {
      await ingest([questRecord(id: 'a', name: 'A', restartable: false)]);
      await repository.setQuestState('p1', 'a', QuestProgressState.failed);

      final a = await status('a');
      expect(a.availability, QuestAvailability.locked);
      expect(a.reasons.whereType<QuestFailed>(), isNotEmpty);
    });

    test('a restartable failed quest can become available again', () async {
      await ingest([questRecord(id: 'a', name: 'A', restartable: true)]);
      await repository.setQuestState('p1', 'a', QuestProgressState.failed);

      expect((await status('a')).availability, QuestAvailability.available);
    });

    test('trader loyalty is an advisory, never a gate', () async {
      await ingest([
        questRecord(
          id: 'a',
          name: 'A',
          traderRequirements: [
            traderRequirement(traderId: 'prapor', value: 4),
            traderRequirement(
              traderId: 'fence',
              type: 'reputation',
              compareMethod: '<=',
              value: -1,
            ),
          ],
        ),
      ]);

      final a = await status('a');
      expect(a.availability, QuestAvailability.available);
      expect(a.blockingReasons, isEmpty);
      expect(a.advisories, hasLength(2));
      expect(a.advisories.every((r) => r is TraderRequirementAdvisory), isTrue);

      final available = await repository.availableQuests('p1');
      expect(available.map((quest) => quest.id), contains('a'));
      expect(available.single.advisories, hasLength(2));
    });
  });

  group('available quests', () {
    test('returns only available quests in deterministic order', () async {
      await ingest([
        questRecord(id: 'z', name: 'Zulu', minPlayerLevel: 5),
        questRecord(id: 'b', name: 'Bravo', minPlayerLevel: 1),
        questRecord(id: 'a', name: 'Alpha', minPlayerLevel: 1),
        questRecord(id: 'c', name: 'Charlie', minPlayerLevel: 1),
        questRecord(
          id: 'locked',
          name: 'Locked',
          taskRequirements: [requiresQuest('missing')],
        ),
        questRecord(id: 'started', name: 'Started'),
      ]);
      await repository.setQuestState(
        'p1',
        'started',
        QuestProgressState.inProgress,
      );
      await setPlayerLevel(db, 'p1', 5);

      final available = await repository.availableQuests('p1');
      expect([for (final quest in available) quest.id], ['a', 'b', 'c', 'z']);
    });
  });
}
