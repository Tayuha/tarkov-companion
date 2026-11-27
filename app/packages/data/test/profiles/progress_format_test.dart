import 'dart:convert';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';
import 'support/progress_test_support.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);

  late AppDatabase database;
  late ProfileRepository profiles;
  late ProgressExportWriter writer;

  setUp(() async {
    database = await openMemoryDatabase();
    profiles = ProfileRepository(database, clock: () => now);
    writer = ProgressExportWriter(database, clock: () => now);

    await insertProfileRow(
      database,
      id: 'profile-regular',
      gameMode: 'regular',
      now: now,
      playerLevel: 22,
    );
    await insertProfileRow(
      database,
      id: 'profile-pve',
      gameMode: 'pve',
      now: now,
      playerLevel: 5,
    );
    await profiles.activate('profile-regular');
    await insertQuestState(
      database,
      profileId: 'profile-regular',
      questId: 'quest-checking',
      state: 'in-progress',
      now: now,
    );
    await insertQuestState(
      database,
      profileId: 'profile-regular',
      questId: 'quest-debut',
      state: 'completed',
      now: now,
    );
    await insertObjectiveCount(
      database,
      profileId: 'profile-regular',
      questId: 'quest-checking',
      objectiveId: 'objective-checking-1',
      count: 3,
      now: now,
    );
  });

  tearDown(() => database.close());

  test('the active-profile export matches the checked-in golden', () async {
    final export = await writer.build(appVersion: '0.1.0');

    final golden = await dataTestFile('goldens/progress-export.json');
    if (updateGoldens) {
      await golden.writeAsString(export.json);
    }
    expect(
      export.json,
      await golden.readAsString(),
      reason:
          'regenerate with (cd app/packages/data && '
          'UPDATE_GOLDENS=1 dart test test/profiles/progress_format_test.dart)',
    );

    expect(export.document.questCount, 2);
    expect(export.document.objectiveCount, 1);
    expect(export.checksum, startsWith('sha256:'));
    expect(export.checksum, hasLength('sha256:'.length + 64));
    expect(export.json.endsWith('\n'), isTrue);
    expect(
      export.json,
      isNot(contains('profile-regular')),
      reason: 'profile ids are device-local and must not be exported',
    );
    final decoded = jsonDecode(export.json) as Map<String, Object?>;
    expect(
      (decoded['profiles'] as List<Object?>).map(
        (profile) => (profile! as Map<String, Object?>)['gameMode'],
      ),
      ['regular'],
      reason: 'the active profile is the regular one',
    );
  });

  test(
    'all-profiles export contains every profile, sorted and complete',
    () async {
      await profiles.createForMode(GameMode.pvpSeason);

      final export = await writer.build(appVersion: '0.1.0', allProfiles: true);

      expect(export.document.profiles, hasLength(3));
      expect(export.document.profiles.map((profile) => profile.gameMode), [
        GameMode.pve,
        GameMode.pvpSeason,
        GameMode.regular,
      ]);
      expect(export.document.questCount, 2);
      expect(export.document.objectiveCount, 1);
    },
  );

  test(
    'an export writes to a temporary directory and re-reads identically',
    () async {
      final directory = createTemporaryDirectory(addTearDown);
      final export = await writer.build(appVersion: '0.1.0', allProfiles: true);

      final file = await export.writeTo('${directory.path}/nested/export.json');

      expect(await file.exists(), isTrue);
      final reread = ProgressExportDocument.parse(await file.readAsString());
      expect(reread.checksum, export.checksum);
      expect(reread.canonicalJson, export.document.canonicalJson);
      expect(reread.profiles, hasLength(2));
    },
  );

  test('an empty progress set exports successfully', () async {
    await profiles.activate('profile-pve');

    final export = await writer.build(appVersion: '0.1.0');

    expect(export.document.profiles.single.gameMode, GameMode.pve);
    expect(export.document.profiles.single.quests, isEmpty);
    expect(export.document.profiles.single.objectives, isEmpty);
    expect(export.document.questCount, 0);
    expect(
      ProgressExportDocument.parse(export.json),
      isA<ProgressExportDocument>(),
    );
  });

  test(
    'checksum and parse are stable when object keys are reordered',
    () async {
      final export = await writer.build(appVersion: '0.1.0');
      final decoded = jsonDecode(export.json) as Map<String, Object?>;
      final reordered = Map<String, Object?>.of(
        reversedKeys(decoded)! as Map<String, Object?>,
      );

      final parsed = ProgressExportDocument.parse(jsonEncode(reordered));

      expect(parsed.checksum, export.checksum);
      expect(parsed.canonicalJson, export.document.canonicalJson);
      expect(parsed.canonicalJson, isNot(contains(': ')));
    },
  );

  test('exporting without an active profile fails typed', () async {
    await (database.delete(database.profiles)).go();
    await (database.delete(database.appSettings)).go();

    await expectLater(
      writer.build(appVersion: '0.1.0'),
      throwsA(isA<NoActiveProfileError>()),
    );
  });

  group('validation rejects without writes', () {
    late Map<String, Object?> valid;

    setUp(() async {
      final export = await writer.build(appVersion: '0.1.0');
      valid = jsonDecode(export.json) as Map<String, Object?>;
    });

    ProgressFormatException errorOf(String source) {
      Object? captured;
      try {
        ProgressExportDocument.parse(source);
      } on Object catch (error) {
        captured = error;
      }
      expect(captured, isA<ProgressFormatException>());
      return captured! as ProgressFormatException;
    }

    void reSign(Map<String, Object?> document) {
      document.remove('checksum');
      document['checksum'] = checksumOf(document);
    }

    test('truncated JSON', () {
      final error = errorOf('{"format": "tarkov-companion-progress",');
      expect(error.code, ProgressFormatErrorCode.malformedJson);
      expect(
        error.message,
        'The file is not a valid progress export: the JSON could not be '
        'parsed.',
      );
    });

    test('a non-object top level', () {
      expect(errorOf('[]').code, ProgressFormatErrorCode.malformedJson);
    });

    test('wrong format', () {
      final wrong = Map<String, Object?>.of(valid)
        ..['format'] = 'some-other-export';
      expect(
        errorOf(jsonEncode(wrong)).code,
        ProgressFormatErrorCode.wrongFormat,
      );
    });

    test('a newer format version names the update requirement', () {
      final newer = Map<String, Object?>.of(valid)..['formatVersion'] = 2;
      final error = errorOf(jsonEncode(newer));
      expect(error.code, ProgressFormatErrorCode.newerVersion);
      expect(error.message, contains('Update the app'));
    });

    test('a bad checksum', () {
      final tampered = Map<String, Object?>.of(valid)
        ..['checksum'] = 'sha256:${'0'.padRight(64, '0')}';
      final error = errorOf(jsonEncode(tampered));
      expect(error.code, ProgressFormatErrorCode.badChecksum);
      expect(
        error.message,
        'The file is not a valid progress export: the checksum does not match '
        'its contents.',
      );
    });

    test('a missing checksum', () {
      final missing = Map<String, Object?>.of(valid)..remove('checksum');
      expect(
        errorOf(jsonEncode(missing)).code,
        ProgressFormatErrorCode.badChecksum,
      );
    });

    test('player level outside the documented range', () {
      final invalid = Map<String, Object?>.of(valid);
      final first =
          (invalid['profiles'] as List<Object?>).first! as Map<String, Object?>;
      first['playerLevel'] = 100;
      reSign(invalid);

      final error = errorOf(jsonEncode(invalid));
      expect(error.code, ProgressFormatErrorCode.invalidValue);
      expect(error.path, 'profiles[0].playerLevel');
      expect(error.message, contains('between 1 and 99'));
    });

    test('an unknown quest state', () {
      final invalid = Map<String, Object?>.of(valid);
      final first =
          (invalid['profiles'] as List<Object?>).first! as Map<String, Object?>;
      ((first['quests'] as List<Object?>).first!
              as Map<String, Object?>)['state'] =
          'almost-done';
      reSign(invalid);

      expect(
        errorOf(jsonEncode(invalid)).code,
        ProgressFormatErrorCode.invalidValue,
      );
    });

    test('a negative objective count', () {
      final invalid = Map<String, Object?>.of(valid);
      final first =
          (invalid['profiles'] as List<Object?>).last! as Map<String, Object?>;
      ((first['objectives'] as List<Object?>).first!
              as Map<String, Object?>)['count'] =
          -1;
      reSign(invalid);

      final error = errorOf(jsonEncode(invalid));
      expect(error.code, ProgressFormatErrorCode.invalidValue);
      expect(error.path, contains('objectives[0].count'));
    });

    test('duplicate quest ids', () {
      final invalid = Map<String, Object?>.of(valid);
      final first =
          (invalid['profiles'] as List<Object?>).last! as Map<String, Object?>;
      final quests = first['quests']! as List<Object?>;
      quests.add(
        Map<String, Object?>.of(quests.first! as Map<String, Object?>),
      );
      reSign(invalid);

      expect(
        errorOf(jsonEncode(invalid)).code,
        ProgressFormatErrorCode.invalidValue,
      );
    });
  });
}
