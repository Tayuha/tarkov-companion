import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';
import 'support/progress_test_support.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 9);

  late AppDatabase database;
  late ProfileRepository profiles;
  late QuestRepository quests;

  setUp(() async {
    database = await openMemoryDatabase();
    profiles = ProfileRepository(database, clock: () => now);
    quests = QuestRepository(database, clock: () => now);
    await insertProfileRow(
      database,
      id: 'profile-regular',
      gameMode: 'regular',
      now: now,
      playerLevel: 15,
    );
    await insertProfileRow(
      database,
      id: 'profile-pve',
      gameMode: 'pve',
      now: now.add(const Duration(minutes: 1)),
      playerLevel: 8,
    );
    await profiles.activate('profile-regular');
  });

  tearDown(() => database.close());

  group('editable profile facts', () {
    test('raising the level from 15 to 20 unlocks a level-20 quest without '
        'restarting anything', () async {
      await insertTask(
        database,
        id: 'quest-gated',
        name: 'Gated quest',
        minPlayerLevel: 20,
      );

      final before = await quests.status('profile-regular', 'quest-gated');
      expect(before?.availability, QuestAvailability.locked);
      expect(
        before?.reasons.whereType<PlayerLevelTooLow>().single.requiredLevel,
        20,
      );
      expect(
        (await quests.availableQuests('profile-regular')),
        isEmpty,
        reason: 'nothing else is in the fixture dataset',
      );

      final updated = await profiles.updatePlayerLevel('profile-regular', 20);

      expect(updated.playerLevel, 20);
      expect(updated.updatedAt.isAtSameMomentAs(now), isTrue);
      final after = await quests.status('profile-regular', 'quest-gated');
      expect(
        after?.availability,
        QuestAvailability.available,
        reason: 'the next derived read reflects the new level',
      );
      expect(
        (await quests.availableQuests('profile-regular')).single.id,
        'quest-gated',
      );

      // A separately scoped profile keeps its own facts.
      expect((await profiles.byId('profile-pve'))?.playerLevel, 8);
    });

    test('a level outside 1..99 is rejected without a write', () async {
      for (final invalid in [0, -1, 100]) {
        expect(
          () => profiles.updatePlayerLevel('profile-regular', invalid),
          throwsA(isA<ProfileFactValidationError>()),
        );
      }
      expect((await profiles.byId('profile-regular'))?.playerLevel, 15);
    });

    test('updating a missing profile throws ProfileNotFoundError', () async {
      await expectLater(
        profiles.updatePlayerLevel('profile-missing', 10),
        throwsA(
          isA<ProfileNotFoundError>().having(
            (error) => error.profileId,
            'profileId',
            'profile-missing',
          ),
        ),
      );
    });
  });

  group('reset and deletion', () {
    setUp(() async {
      await insertQuestState(
        database,
        profileId: 'profile-regular',
        questId: 'quest-a',
        state: 'completed',
        now: now,
      );
      await insertObjectiveCount(
        database,
        profileId: 'profile-regular',
        questId: 'quest-a',
        objectiveId: 'objective-a',
        count: 2,
        now: now,
      );
      await insertQuestState(
        database,
        profileId: 'profile-pve',
        questId: 'quest-b',
        state: 'in-progress',
        now: now,
      );
    });

    test('reset clears only the target profile progress and keeps the profile '
        'and level', () async {
      final result = await profiles.resetProgress('profile-regular');

      expect(result.questStatesCleared, 1);
      expect(result.objectiveCountsCleared, 1);
      expect(result.wasEmpty, isFalse);
      final profile = await profiles.byId('profile-regular');
      expect(profile, isNotNull);
      expect(profile?.playerLevel, 15);
      expect(
        await (database.select(
          database.questProgress,
        )..where((row) => row.profileId.equals('profile-regular'))).get(),
        isEmpty,
      );
      expect(
        await (database.select(
          database.objectiveProgress,
        )..where((row) => row.profileId.equals('profile-regular'))).get(),
        isEmpty,
      );
      expect(
        await (database.select(
          database.questProgress,
        )..where((row) => row.profileId.equals('profile-pve'))).get(),
        hasLength(1),
        reason: 'other profiles are unaffected',
      );
    });

    test('resetting an empty profile reports zero rows', () async {
      await profiles.resetProgress('profile-regular');
      final second = await profiles.resetProgress('profile-regular');
      expect(second.wasEmpty, isTrue);
      expect(second.questStatesCleared, 0);
      expect(second.objectiveCountsCleared, 0);
    });

    test('deleting the active profile activates the regular profile', () async {
      await profiles.activate('profile-pve');

      final result = await profiles.delete('profile-pve');

      expect(result.deleted.id, 'profile-pve');
      expect(result.active?.id, 'profile-regular');
      expect(await profiles.byId('profile-pve'), isNull);
      expect((await profiles.active())?.id, 'profile-regular');
      expect(
        await (database.select(
          database.questProgress,
        )..where((row) => row.profileId.equals('profile-pve'))).get(),
        isEmpty,
        reason: 'the profile progress was deleted with it',
      );
    });

    test(
      'deleting a non-active profile leaves the active profile alone',
      () async {
        final result = await profiles.delete('profile-pve');

        expect(result.active?.id, 'profile-regular');
        expect((await profiles.active())?.id, 'profile-regular');
      },
    );

    test('deleting the last profile leaves no active profile and first launch '
        'recreates a regular profile', () async {
      final pve = await profiles.delete('profile-pve');
      expect(pve.active?.id, 'profile-regular');

      final last = await profiles.delete('profile-regular');

      expect(last.active, isNull);
      expect(await profiles.list(), isEmpty);
      expect(await profiles.active(), isNull);
      expect(
        await (database.select(database.appSettings)
              ..where((row) => row.key.equals(AppSettingKeys.activeProfileId)))
            .get(),
        isEmpty,
        reason: 'the dangling setting must not survive',
      );

      final recreated = await profiles.ensureFirstLaunch();
      expect(recreated.gameMode, GameMode.regular.wireValue);
      expect(recreated.playerLevel, 1);
      expect((await profiles.active())?.id, recreated.id);
    });

    test(
      'deleting a missing profile throws before touching anything',
      () async {
        await expectLater(
          profiles.delete('profile-missing'),
          throwsA(isA<ProfileNotFoundError>()),
        );
        expect(await profiles.list(), hasLength(2));
        expect((await profiles.active())?.id, 'profile-regular');
      },
    );
  });
}
