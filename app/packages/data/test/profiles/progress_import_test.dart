import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';
import 'support/progress_test_support.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 15);

  late AppDatabase database;
  late ProfileRepository profiles;
  late ProgressImporter importer;

  setUp(() async {
    database = await openMemoryDatabase();
    profiles = ProfileRepository(database, clock: () => now);
    importer = ProgressImporter(database, clock: () => now);
    await insertProfileRow(
      database,
      id: 'profile-regular',
      gameMode: 'regular',
      now: now,
      playerLevel: 10,
    );
    await profiles.activate('profile-regular');
    await insertQuestState(
      database,
      profileId: 'profile-regular',
      questId: 'quest-debut',
      state: 'completed',
      now: now,
    );
    await insertQuestState(
      database,
      profileId: 'profile-regular',
      questId: 'quest-checking',
      state: 'in-progress',
      now: now,
    );
    await insertObjectiveCount(
      database,
      profileId: 'profile-regular',
      questId: 'quest-checking',
      objectiveId: 'objective-checking-1',
      count: 2,
      now: now,
    );
  });

  tearDown(() => database.close());

  ProgressExportDocument signed(List<Map<String, Object?>> profiles) {
    final document = <String, Object?>{
      'format': progressFormat,
      'formatVersion': progressFormatVersion,
      'appVersion': '0.1.0',
      'exportedAt': now.toIso8601String(),
      'profiles': profiles,
    };
    document['checksum'] = checksumOf(document);
    return ProgressExportDocument.parse(jsonEncode(document));
  }

  ProgressExportDocument regularImport({
    int playerLevel = 25,
    List<Map<String, Object?>> quests = const [
      {'questId': 'quest-debut', 'state': 'in-progress'},
      {'questId': 'quest-shootout', 'state': 'completed'},
    ],
    List<Map<String, Object?>> objectives = const [
      {
        'questId': 'quest-checking',
        'objectiveId': 'objective-checking-1',
        'count': 5,
      },
    ],
  }) => signed([
    {
      'gameMode': 'regular',
      'playerLevel': playerLevel,
      'quests': quests,
      'objectives': objectives,
    },
  ]);

  Future<QuestProgressState?> localState(String questId) async {
    final row =
        await (database.select(database.questProgress)..where(
              (row) =>
                  row.profileId.equals('profile-regular') &
                  row.questId.equals(questId),
            ))
            .getSingleOrNull();
    return row == null ? null : QuestProgressState.fromStoredValue(row.state);
  }

  Future<int?> localCount(String questId, String objectiveId) async {
    final row =
        await (database.select(database.objectiveProgress)..where(
              (row) =>
                  row.profileId.equals('profile-regular') &
                  row.questId.equals(questId) &
                  row.objectiveId.equals(objectiveId),
            ))
            .getSingleOrNull();
    return row?.count;
  }

  group('preview', () {
    test(
      'reports new, matching and conflicting rows without writing',
      () async {
        final preview = await importer.preview(regularImport());

        expect(preview.profileCount, 1);
        expect(preview.questStateCount, 2);
        expect(preview.objectiveCount, 1);
        expect(preview.newQuestStates, 1, reason: 'quest-shootout is new');
        expect(
          preview.conflictingQuestStates,
          1,
          reason: 'quest-debut differs',
        );
        expect(preview.newObjectiveCounts, 0);
        expect(preview.conflictingObjectiveCounts, 1);
        expect(preview.createdProfiles, 0);
        expect(preview.hasConflicts, isTrue);
        expect(preview.questConflicts.single.questId, 'quest-debut');
        expect(
          preview.questConflicts.single.localState,
          QuestProgressState.completed,
        );
        expect(
          preview.questConflicts.single.importedState,
          QuestProgressState.inProgress,
        );

        // Nothing was written.
        expect(await localState('quest-shootout'), isNull);
        expect(await localState('quest-debut'), QuestProgressState.completed);
        expect(await localCount('quest-checking', 'objective-checking-1'), 2);
        expect((await profiles.byId('profile-regular'))?.playerLevel, 10);
      },
    );

    test(
      'reports a profile creation for a mode with no stored profile',
      () async {
        final document = ProgressExportDocument.parse(
          await (await dataTestFile('fixtures/profiles/hand-edited-valid.json'))
              .readAsString(),
        );

        final preview = await importer.preview(document);

        expect(preview.createdProfiles, 1);
        expect(preview.profiles.single.gameMode, GameMode.pve);
        expect(preview.profiles.single.existingPlayerLevel, isNull);
        expect(preview.newQuestStates, 2);
        expect(preview.newObjectiveCounts, 1);
        expect(await profiles.byId('profile-pve'), isNull);
      },
    );
  });

  group('merge', () {
    test('adds missing rows, keeps local conflicts and raises counts by '
        'default', () async {
      final result = await importer.apply(regularImport());

      expect(result.profilesCreated, 0);
      expect(result.profilesUpdated, 1);
      expect(result.conflictsKept, 1);
      expect(result.questStatesWritten, 1);
      expect(result.objectiveCountsWritten, 1);

      expect(await localState('quest-debut'), QuestProgressState.completed);
      expect(await localState('quest-shootout'), QuestProgressState.completed);
      expect(await localCount('quest-checking', 'objective-checking-1'), 5);
      expect(
        (await profiles.byId('profile-regular'))?.playerLevel,
        25,
        reason: 'merge records the higher level',
      );
      expect(result.activeProfileId, 'profile-regular');
    });

    test('an explicit resolution overwrites one conflicting quest', () async {
      final result = await importer.apply(
        regularImport(),
        resolutions: {
          progressConflictKey(GameMode.regular, 'quest-debut'):
              ProgressConflictResolution.useImported,
        },
      );

      expect(result.conflictsKept, 0);
      expect(await localState('quest-debut'), QuestProgressState.inProgress);
      expect(await localState('quest-shootout'), QuestProgressState.completed);
    });

    test('a lower imported count never lowers a local count', () async {
      final result = await importer.apply(
        regularImport(
          objectives: const [
            {
              'questId': 'quest-checking',
              'objectiveId': 'objective-checking-1',
              'count': 1,
            },
          ],
        ),
      );

      expect(result.objectiveCountsWritten, 0);
      expect(await localCount('quest-checking', 'objective-checking-1'), 2);
    });

    test('creates and activates a profile for a missing mode', () async {
      final document = ProgressExportDocument.parse(
        await (await dataTestFile('fixtures/profiles/hand-edited-valid.json'))
            .readAsString(),
      );

      final result = await importer.apply(document);

      expect(result.profilesCreated, 1);
      expect(result.activeProfileId, 'profile-regular');
      final created = await profiles.byId(
        (await profiles.list()).singleWhere((p) => p.gameMode == 'pve').id,
      );
      expect(created?.playerLevel, 22);
      expect(
        await stateFor(database, created!.id, 'quest-debut'),
        QuestProgressState.completed,
      );
    });
  });

  group('replace', () {
    test('replaces only the target profile progress and discards local-only '
        'rows after the write succeeds', () async {
      await insertQuestState(
        database,
        profileId: 'profile-regular',
        questId: 'quest-local-only',
        state: 'completed',
        now: now,
      );

      final result = await importer.apply(
        regularImport(),
        strategy: ProgressImportStrategy.replace,
      );

      expect(result.questStatesWritten, 2);
      expect(await localState('quest-local-only'), isNull);
      expect(await localState('quest-debut'), QuestProgressState.inProgress);
      expect(await localState('quest-shootout'), QuestProgressState.completed);
      expect(await localCount('quest-checking', 'objective-checking-1'), 5);
    });
  });

  group('transactional application', () {
    test('a write failure before commit rolls every change back', () async {
      var fail = false;
      final failing = ProgressImporter(
        database,
        clock: () => now,
        beforeCommit: () {
          if (fail) {
            throw StateError('injected write failure');
          }
        },
      );
      final document = regularImport();
      fail = true;

      await expectLater(
        failing.apply(document, strategy: ProgressImportStrategy.replace),
        throwsA(isA<StateError>()),
      );

      expect(await localState('quest-debut'), QuestProgressState.completed);
      expect(await localState('quest-checking'), QuestProgressState.inProgress);
      expect(await localState('quest-shootout'), isNull);
      expect(await localCount('quest-checking', 'objective-checking-1'), 2);
      expect((await profiles.byId('profile-regular'))?.playerLevel, 10);
      expect((await profiles.list()), hasLength(1));
    });

    test(
      'a failed import does not leave a newly created profile behind',
      () async {
        final failing = ProgressImporter(
          database,
          clock: () => now,
          idGenerator: () => 'profile-imported',
          beforeCommit: () => throw StateError('injected write failure'),
        );
        final document = ProgressExportDocument.parse(
          await (await dataTestFile('fixtures/profiles/hand-edited-valid.json'))
              .readAsString(),
        );

        await expectLater(failing.apply(document), throwsA(isA<StateError>()));

        expect(await profiles.byId('profile-imported'), isNull);
        expect(await profiles.list(), hasLength(1));
      },
    );
  });

  group('cross-format portability', () {
    test('a Windows-produced fixture imports on this platform and restores '
        'every row', () async {
      final file = await dataTestFile(
        'fixtures/profiles/export-from-windows.json',
      );
      final text = await file.readAsString();
      final document = ProgressExportDocument.parse(text);

      expect(document.appVersion, '0.1.0');
      expect(document.profiles.single.gameMode, GameMode.regular);

      final preview = await importer.preview(document);
      expect(preview.createdProfiles, 0);
      expect(preview.newQuestStates, 2, reason: 'collector and shootout');
      expect(
        preview.conflictingQuestStates,
        0,
        reason: 'debut is completed on both sides',
      );

      await importer.apply(document);

      expect(await localState('quest-collector'), QuestProgressState.failed);
      expect(await localState('quest-shootout'), QuestProgressState.inProgress);
      expect(await localState('quest-debut'), QuestProgressState.completed);
      expect(await localCount('quest-checking', 'objective-checking-1'), 5);
      expect(await localCount('quest-shootout', 'objective-shootout-1'), 0);
      expect((await profiles.byId('profile-regular'))?.playerLevel, 31);
    });

    test(
      'the hand-editable documentation fixture imports successfully',
      () async {
        final document = ProgressExportDocument.parse(
          await (await dataTestFile('fixtures/profiles/hand-edited-valid.json'))
              .readAsString(),
        );

        final result = await importer.apply(document);

        expect(result.profilesCreated, 1);
        expect(result.questStatesWritten, 2);
        expect(result.objectiveCountsWritten, 1);
        final pve = (await profiles.list()).singleWhere(
          (profile) => profile.gameMode == 'pve',
        );
        expect(
          await stateFor(database, pve.id, 'quest-debut'),
          QuestProgressState.completed,
        );
        expect(
          await stateFor(database, pve.id, 'quest-checking'),
          QuestProgressState.inProgress,
        );
        expect(
          await countFor(
            database,
            pve.id,
            'quest-checking',
            'objective-checking-1',
          ),
          3,
        );
      },
    );

    test('the invalid documentation fixture fails with the documented '
        'message', () async {
      final text = await (await dataTestFile(
        'fixtures/profiles/invalid-bad-checksum.json',
      )).readAsString();

      await expectLater(
        Future<void>.sync(() => ProgressExportDocument.parse(text)),
        throwsA(
          isA<ProgressFormatException>()
              .having(
                (error) => error.code,
                'code',
                ProgressFormatErrorCode.badChecksum,
              )
              .having(
                (error) => error.message,
                'message',
                'The file is not a valid progress export: the checksum does '
                    'not match its contents.',
              ),
        ),
      );
    });

    test('the wrong-format fixture is refused as not a progress export', () async {
      final text = await (await dataTestFile(
        'fixtures/profiles/invalid-wrong-format.json',
      )).readAsString();

      await expectLater(
        Future<void>.sync(() => ProgressExportDocument.parse(text)),
        throwsA(
          isA<ProgressFormatException>()
              .having(
                (error) => error.code,
                'code',
                ProgressFormatErrorCode.wrongFormat,
              )
              .having(
                (error) => error.message,
                'message',
                'The file is not a valid progress export: the format marker is '
                    'missing or unknown.',
              ),
        ),
      );
    });
  });
}

Future<QuestProgressState?> stateFor(
  AppDatabase database,
  String profileId,
  String questId,
) async {
  final row =
      await (database.select(database.questProgress)..where(
            (row) =>
                row.profileId.equals(profileId) & row.questId.equals(questId),
          ))
          .getSingleOrNull();
  return row == null ? null : QuestProgressState.fromStoredValue(row.state);
}

Future<int?> countFor(
  AppDatabase database,
  String profileId,
  String questId,
  String objectiveId,
) async {
  final row =
      await (database.select(database.objectiveProgress)..where(
            (row) =>
                row.profileId.equals(profileId) &
                row.questId.equals(questId) &
                row.objectiveId.equals(objectiveId),
          ))
          .getSingleOrNull();
  return row?.count;
}
