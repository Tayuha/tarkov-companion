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
    expect(result, isNotNull);
    return result!;
  }

  Map<String, Object?> countedQuest({
    String id = 'q',
    String name = 'Quest',
    int count = 5,
    List<Map<String, Object?>> extraObjectives = const [],
  }) => questRecord(
    id: id,
    name: name,
    objectives: [
      objectiveRecord(
        id: '$id-main',
        type: 'shoot',
        description: 'Eliminate targets',
        count: count,
      ),
      ...extraObjectives,
    ],
  );

  group('state transitions', () {
    setUp(() async {
      await ingest([
        questRecord(id: 'a', name: 'A'),
        questRecord(id: 'b', name: 'B', taskRequirements: [requiresQuest('a')]),
      ]);
    });

    test(
      'complete and revert persist and recompute dependents immediately',
      () async {
        expect((await status('b')).availability, QuestAvailability.locked);

        await repository.setQuestState('p1', 'a', QuestProgressState.completed);
        expect((await status('a')).recordedState, QuestProgressState.completed);
        expect((await status('b')).availability, QuestAvailability.available);

        await repository.setQuestState(
          'p1',
          'a',
          QuestProgressState.notStarted,
        );
        expect(
          (await status('a')).recordedState,
          QuestProgressState.notStarted,
        );
        expect((await status('b')).availability, QuestAvailability.locked);
      },
    );

    test(
      'failed and in-progress are recorded, not derived from count',
      () async {
        await repository.setQuestState('p1', 'a', QuestProgressState.failed);
        expect((await status('a')).recordedState, QuestProgressState.failed);

        await repository.setQuestState(
          'p1',
          'a',
          QuestProgressState.inProgress,
        );
        expect((await status('a')).availability, QuestAvailability.inProgress);
      },
    );

    test('state is profile-scoped', () async {
      await repository.setQuestState('p1', 'a', QuestProgressState.completed);

      expect(
        (await status('a', profile: 'p2')).recordedState,
        QuestProgressState.notStarted,
      );
      expect(
        (await status('b', profile: 'p2')).availability,
        QuestAvailability.locked,
      );
    });

    test('unknown profile or quest is rejected without writing', () async {
      expect(
        () => repository.setQuestState(
          'missing',
          'a',
          QuestProgressState.completed,
        ),
        throwsA(isA<QuestProfileNotFoundError>()),
      );
      expect(
        () => repository.setQuestState(
          'p1',
          'missing',
          QuestProgressState.completed,
        ),
        throwsA(isA<QuestNotFoundError>()),
      );
      expect(await db.select(db.questProgress).get(), isEmpty);
    });
  });

  group('objective progress', () {
    setUp(() async {
      await ingest([
        countedQuest(
          extraObjectives: [
            objectiveRecord(
              id: 'q-optional',
              type: 'visit',
              description: 'Optional visit',
              count: 1,
              optional: true,
            ),
          ],
        ),
      ]);
    });

    test(
      'partial progress keeps the quest in progress and shows x of y',
      () async {
        final initial = await status('q');
        expect(initial.availability, QuestAvailability.available);
        expect(initial.objectives, hasLength(2));
        expect(initial.objectives.first.count, 0);

        await repository.setObjectiveCount('p1', 'q', 'q-main', 3);

        final partial = await status('q');
        expect(partial.availability, QuestAvailability.inProgress);
        expect(partial.recordedState, QuestProgressState.inProgress);
        expect(partial.objectivesSatisfied, isFalse);
        expect(partial.derivedCompletionReady, isFalse);
        expect(partial.canMarkComplete, isFalse);
        final main = partial.objectives.singleWhere(
          (entry) => entry.objective.id == 'q-main',
        );
        expect(main.count, 3);
        expect(main.requiredCount, 5);
        expect(main.satisfied, isFalse);
      },
    );

    test(
      'required objectives drive derived completion; optional do not',
      () async {
        await repository.setObjectiveCount('p1', 'q', 'q-main', 5);

        final satisfied = await status('q');
        expect(satisfied.availability, QuestAvailability.inProgress);
        expect(satisfied.objectivesSatisfied, isTrue);
        expect(satisfied.derivedCompletionReady, isTrue);
        expect(satisfied.canMarkComplete, isTrue);
        expect(
          satisfied.objectives.singleWhere((entry) => entry.optional).satisfied,
          isFalse,
          reason: 'the optional objective was never recorded',
        );
      },
    );

    test('marking complete keeps every objective count', () async {
      await repository.setObjectiveCount('p1', 'q', 'q-main', 5);
      await repository.setObjectiveCount('p1', 'q', 'q-optional', 1);

      await repository.setQuestState('p1', 'q', QuestProgressState.completed);

      final completed = await status('q');
      expect(completed.availability, QuestAvailability.completed);
      expect(completed.manuallyCompleted, isFalse);
      expect(
        completed.objectives
            .singleWhere((entry) => entry.objective.id == 'q-main')
            .count,
        5,
      );
      expect(
        completed.objectives
            .singleWhere((entry) => entry.objective.id == 'q-optional')
            .count,
        1,
      );
    });

    test('manual completion override never alters counts', () async {
      await repository.setObjectiveCount('p1', 'q', 'q-main', 1);

      await repository.setQuestState('p1', 'q', QuestProgressState.completed);

      final overridden = await status('q');
      expect(overridden.availability, QuestAvailability.completed);
      expect(overridden.manuallyCompleted, isTrue);
      expect(overridden.objectivesSatisfied, isFalse);
      expect(
        overridden.objectives
            .singleWhere((entry) => entry.objective.id == 'q-main')
            .count,
        1,
      );
    });

    test(
      'changing a count after completion does not change the state',
      () async {
        await repository.setQuestState('p1', 'q', QuestProgressState.completed);
        await repository.setObjectiveCount('p1', 'q', 'q-main', 2);

        final state = await status('q');
        expect(state.availability, QuestAvailability.completed);
        expect(state.manuallyCompleted, isTrue);
      },
    );

    test('validation rejects out-of-range and unknown targets', () async {
      await repository.setObjectiveCount('p1', 'q', 'q-main', 3);

      const invalidCounts = [-1, 6];
      for (final count in invalidCounts) {
        await expectLater(
          repository.setObjectiveCount('p1', 'q', 'q-main', count),
          throwsA(isA<QuestProgressValidationError>()),
          reason: 'count $count',
        );
      }

      await expectLater(
        repository.setObjectiveCount('p1', 'q', 'missing', 1),
        throwsA(isA<QuestObjectiveNotFoundError>()),
      );
      await expectLater(
        repository.setObjectiveCount('p1', 'missing', 'q-main', 1),
        throwsA(isA<QuestNotFoundError>()),
      );
      await expectLater(
        repository.setObjectiveCount('missing', 'q', 'q-main', 1),
        throwsA(isA<QuestProfileNotFoundError>()),
      );

      final unchanged = await status('q');
      expect(
        unchanged.objectives
            .singleWhere((entry) => entry.objective.id == 'q-main')
            .count,
        3,
      );
      expect(unchanged.availability, QuestAvailability.inProgress);
    });

    test('a rejected first write leaves no partial auto-start row', () async {
      await expectLater(
        repository.setObjectiveCount('p1', 'q', 'q-main', 99),
        throwsA(isA<QuestProgressValidationError>()),
      );

      expect(await db.select(db.questProgress).get(), isEmpty);
      expect(await db.select(db.objectiveProgress).get(), isEmpty);
      expect((await status('q')).availability, QuestAvailability.available);
    });

    test('profile isolation covers objective counts', () async {
      await repository.setObjectiveCount('p1', 'q', 'q-main', 5);

      final other = await status('q', profile: 'p2');
      expect(other.recordedState, QuestProgressState.notStarted);
      expect(other.objectives.first.count, 0);
    });

    test('a binary objective requires one recorded step', () async {
      await ingest([
        questRecord(
          id: 'binary',
          name: 'Binary',
          objectives: [
            objectiveRecord(
              id: 'visit',
              type: 'visit',
              description: 'Visit the marker',
            ),
          ],
        ),
      ]);

      final initial = (await status('binary')).objectives.single;
      expect(initial.requiredCount, 1);
      expect(initial.satisfied, isFalse);

      await expectLater(
        repository.setObjectiveCount('p1', 'binary', 'visit', 2),
        throwsA(isA<QuestProgressValidationError>()),
      );
      await repository.setObjectiveCount('p1', 'binary', 'visit', 1);

      final complete = await status('binary');
      expect(complete.objectivesSatisfied, isTrue);
      expect(complete.availability, QuestAvailability.inProgress);
    });

    test(
      'a level-based objective uses its level as the required count',
      () async {
        await ingest([
          questRecord(
            id: 'skill',
            name: 'Skill',
            objectives: [
              objectiveRecord(
                id: 'level-obj',
                type: 'skill',
                description: 'Reach a skill level',
                level: 3,
                skill: 'Endurance',
              ),
            ],
          ),
        ]);

        final initial = (await status('skill')).objectives.single;
        expect(initial.requiredCount, 3);

        await expectLater(
          repository.setObjectiveCount('p1', 'skill', 'level-obj', 4),
          throwsA(isA<QuestProgressValidationError>()),
        );
        await repository.setObjectiveCount('p1', 'skill', 'level-obj', 3);
        expect((await status('skill')).objectivesSatisfied, isTrue);
      },
    );

    test('a quest without objectives completes without an override', () async {
      await ingest([questRecord(id: 'empty', name: 'Empty')]);
      await repository.setQuestState(
        'p1',
        'empty',
        QuestProgressState.completed,
      );

      final completed = await status('empty');
      expect(completed.availability, QuestAvailability.completed);
      expect(completed.objectivesSatisfied, isTrue);
      expect(completed.manuallyCompleted, isFalse);
    });
  });

  group('orphaned progress', () {
    test(
      'preserved rows are listed and excluded from dependency math',
      () async {
        await ingest([
          questRecord(
            id: 'a',
            name: 'A',
            objectives: [objectiveRecord(id: 'a-obj', type: 'shoot', count: 5)],
          ),
          questRecord(
            id: 'b',
            name: 'B',
            taskRequirements: [requiresQuest('a')],
          ),
        ]);

        await repository.setObjectiveCount('p1', 'a', 'a-obj', 5);
        await repository.setQuestState('p1', 'a', QuestProgressState.completed);
        expect((await status('b')).availability, QuestAvailability.available);
        expect(await repository.orphanedProgress('p1'), isEmpty);

        // A dataset refresh removes A but must not touch player data.
        await ingest([
          questRecord(
            id: 'b',
            name: 'B',
            taskRequirements: [requiresQuest('a')],
          ),
        ]);

        final orphans = await repository.orphanedProgress('p1');
        expect(orphans, hasLength(1));
        final orphan = orphans.single;
        expect(orphan.questId, 'a');
        expect(orphan.state, QuestProgressState.completed);
        expect(orphan.objectiveCounts, {'a-obj': 5});
        expect(orphan.updatedAt, isNotNull);

        // The orphan is excluded: B cannot be unlocked by a quest the current
        // dataset no longer contains.
        final b = await status('b');
        expect(b.availability, QuestAvailability.locked);
        final reason = b.blockingReasons
            .whereType<MissingPrerequisite>()
            .single;
        expect(reason.taskId, 'a');
        expect(reason.prerequisiteInDataset, isFalse);

        expect((await repository.statuses('p1')).map((quest) => quest.id), [
          'b',
        ]);
        expect(await repository.availableQuests('p1'), isEmpty);
      },
    );

    test('orphan listing is profile-scoped', () async {
      await ingest([questRecord(id: 'a', name: 'A')]);
      await repository.setQuestState('p1', 'a', QuestProgressState.completed);

      await ingest([questRecord(id: 'b', name: 'B')]);

      expect(await repository.orphanedProgress('p1'), hasLength(1));
      expect(await repository.orphanedProgress('p2'), isEmpty);
    });

    test('writing progress for a removed quest is refused', () async {
      await ingest([questRecord(id: 'a', name: 'A')]);
      await ingest([questRecord(id: 'b', name: 'B')]);

      await expectLater(
        repository.setQuestState('p1', 'a', QuestProgressState.completed),
        throwsA(isA<QuestNotFoundError>()),
      );
    });
  });
}
