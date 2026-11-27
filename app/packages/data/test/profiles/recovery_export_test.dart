import 'dart:io';

import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';
import 'support/progress_test_support.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);

  group('RecoveryProgressExporter', () {
    late Directory directory;
    late String path;
    late RecoveryDatabase recovery;

    setUp(() async {
      directory = createTemporaryDirectory(addTearDown);
      path = '${directory.path}/tarkov_companion.sqlite';

      final database = AppDatabase.atPath(path);
      await database.customSelect('SELECT 1').get();

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
      await insertProfileRow(
        database,
        id: 'profile-season',
        gameMode: 'pvp-season',
        now: now,
        playerLevel: 9,
      );

      // Inserted out of order on purpose; the export sorts by id.
      await insertQuestState(
        database,
        profileId: 'profile-regular',
        questId: 'quest-zulu',
        state: 'in-progress',
        now: now,
      );
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
      await insertQuestState(
        database,
        profileId: 'profile-regular',
        questId: 'quest-corrupt',
        state: 'mystery-state',
        now: now,
      );
      await insertQuestState(
        database,
        profileId: 'profile-pve',
        questId: 'quest-debut',
        state: 'failed',
        now: now,
      );

      await insertObjectiveCount(
        database,
        profileId: 'profile-regular',
        questId: 'quest-checking',
        objectiveId: 'objective-checking-2',
        count: 3,
        now: now,
      );
      await insertObjectiveCount(
        database,
        profileId: 'profile-regular',
        questId: 'quest-checking',
        objectiveId: 'objective-checking-1',
        count: -5,
        now: now,
      );
      await insertObjectiveCount(
        database,
        profileId: 'profile-regular',
        questId: 'quest-debut',
        objectiveId: 'objective-debut-1',
        count: progressMaxObjectiveCount + 10,
        now: now,
      );

      await database.close();
      recovery = RecoveryDatabase.open(path);
      addTearDown(recovery.close);
    });

    test('exports the same format, checksum and stable order', () async {
      final exporter = RecoveryProgressExporter(recovery);
      final result = await exporter.writeTo(
        appVersion: '0.1.0',
        directory: Directory('${directory.path}/recovery'),
        exportedAt: DateTime.utc(2026, 11, 27, 13, 30),
      );

      expect(
        result.file.path,
        endsWith('/recovery/progress-recovery-20261127T133000.000000Z.json'),
      );
      final written = await result.file.readAsString();
      final parsed = ProgressExportDocument.parse(written);
      expect(parsed.checksum, result.export.checksum);
      expect(parsed.canonicalJson, result.export.document.canonicalJson);
      expect(written.endsWith('\n'), isTrue);

      // Modes sort by their wire value, exactly like the normal writer.
      expect(parsed.profiles.map((profile) => profile.gameMode), [
        GameMode.pve,
        GameMode.pvpSeason,
        GameMode.regular,
      ]);
      final regular = parsed.profiles.last;
      expect(regular.playerLevel, 22);
      expect(regular.quests.map((quest) => quest.questId), [
        'quest-checking',
        'quest-debut',
        'quest-zulu',
      ]);
      expect(regular.objectives.map((objective) => objective.objectiveId), [
        'objective-checking-1',
        'objective-checking-2',
        'objective-debut-1',
      ]);
      expect(parsed.questCount, 4);
      expect(parsed.objectiveCount, 3);

      // The malformed state is skipped, the out-of-range counts are clamped.
      expect(
        regular.quests.where((quest) => quest.questId == 'quest-corrupt'),
        isEmpty,
      );
      expect(result.diagnostics.skippedRows, 1);
      expect(result.diagnostics.normalizedRows, 2);
      expect(regular.objectives.first.count, 0);
      expect(regular.objectives.last.count, progressMaxObjectiveCount);

      // A second build with the same clock is byte-identical.
      final again = exporter.build(
        appVersion: '0.1.0',
        exportedAt: DateTime.utc(2026, 11, 27, 13, 30),
      );
      expect(again.export.json, result.export.json);
    });

    test('never writes to the recovered database', () {
      expect(
        () => recovery.execute('DELETE FROM profiles'),
        throwsA(
          isA<sqlite.SqliteException>().having(
            (error) => error.toString(),
            'message',
            contains('readonly'),
          ),
        ),
      );
      expect(
        recovery.select('SELECT count(*) AS n FROM profiles').single['n'],
        3,
      );
    });

    test('a database with no profile row is a typed outcome', () async {
      final emptyPath = '${directory.path}/empty.sqlite';
      final database = AppDatabase.atPath(emptyPath);
      await database.customSelect('SELECT 1').get();
      await database.close();

      final empty = RecoveryDatabase.open(emptyPath);
      addTearDown(empty.close);
      expect(
        () => RecoveryProgressExporter(empty).build(appVersion: '0.1.0'),
        throwsA(isA<NoRecoveryProfilesError>()),
      );
    });

    test('unreadable quest and objective tables degrade to warnings', () async {
      // A minimal file with only the profile table: the other reads fail.
      final partialPath = '${directory.path}/partial.sqlite';
      final raw = sqlite.sqlite3.open(partialPath);
      raw
        ..execute(
          'CREATE TABLE profiles (id TEXT, gameMode TEXT, playerLevel INTEGER)',
        )
        ..execute(
          "INSERT INTO profiles VALUES ('profile-regular', 'regular', 12)",
        )
        ..close();

      final partial = RecoveryDatabase.open(partialPath);
      addTearDown(partial.close);
      final result = RecoveryProgressExporter(partial)
          .build(appVersion: '0.1.0');

      expect(result.export.document.profiles.single.playerLevel, 12);
      expect(result.export.document.questCount, 0);
      expect(result.diagnostics.warnings, hasLength(2));
      expect(result.diagnostics.isExact, isTrue);
    });
  });

  group('recovery rows without database constraints', () {
    test('duplicates, blank ids and unknown modes are skipped safely', () {
      final directory = createTemporaryDirectory(addTearDown);
      final path = '${directory.path}/raw.sqlite';
      final raw = sqlite.sqlite3.open(path);
      raw
        ..execute(
          'CREATE TABLE profiles (id TEXT, gameMode TEXT, playerLevel INTEGER)',
        )
        ..execute(
          'CREATE TABLE questProgress ('
          'profileId TEXT, questId TEXT, state TEXT)',
        )
        ..execute(
          'CREATE TABLE objectiveProgress ('
          'profileId TEXT, questId TEXT, objectiveId TEXT, count INTEGER)',
        )
        ..execute(
          "INSERT INTO profiles VALUES "
          "('p1', 'regular', 50), ('p2', 'regular', 60), "
          "('p3', 'pve', 3), ('p4', 'weird', 1), ('', 'pve', 1)",
        )
        ..execute(
          "INSERT INTO questProgress VALUES "
          "('p1', 'q2', 'completed'), ('p1', 'q1', 'completed'), "
          "('p1', 'q1', 'failed'), ('p1', 'q3', 'bogus'), "
          "('p3', 'q1', 'failed'), ('ghost', 'q1', 'failed')",
        )
        ..execute(
          "INSERT INTO objectiveProgress VALUES "
          "('p1', 'q1', 'o2', 5), ('p1', 'q1', 'o1', 2), "
          "('p1', 'q1', 'o2', 9), ('p1', 'q2', 'o1', -3)",
        )
        ..close();

      final recovery = RecoveryDatabase.open(path);
      addTearDown(recovery.close);
      final result = RecoveryProgressExporter(recovery)
          .build(appVersion: '0.1.0');

      expect(result.export.document.profiles.map((p) => p.gameMode), [
        GameMode.pve,
        GameMode.regular,
      ]);
      final regular = result.export.document.profiles.last;
      expect(regular.quests.map((quest) => quest.questId), ['q1', 'q2']);
      expect(regular.objectives.map((objective) => objective.objectiveId), [
        'o1',
        'o2',
        'o1',
      ]);
      expect(regular.objectives.last.count, 0);
      // Duplicate profile, duplicate quest, duplicate objective, unknown state,
      // unknown mode, blank id and the orphan row are all skipped. The negative
      // count is kept after clamping to zero.
      expect(result.diagnostics.skippedRows, 7);
      expect(result.diagnostics.normalizedRows, 1);
    });
  });

  group('exportRecoveryDiagnostics', () {
    test('copies the backup and log files deterministically', () async {
      final root = createTemporaryDirectory(addTearDown);
      final logs = Directory('${root.path}/logs')..createSync();
      File('${logs.path}/app.log').writeAsStringSync('current');
      File('${logs.path}/app.1.log').writeAsStringSync('older');
      File('${logs.path}/notes.txt').writeAsStringSync('not a log');
      final backup = File('${root.path}/backup.sqlite')
        ..writeAsStringSync('backup bytes');

      final result = await exportRecoveryDiagnostics(
        directory: Directory('${root.path}/recovery'),
        logsDirectory: logs,
        backup: backup,
      );

      expect(result.isEmpty, isFalse);
      expect(result.copiedFileCount, 3);
      expect(result.backup?.readAsStringSync(), 'backup bytes');
      expect(result.logFiles.map((file) => file.path.split('/').last), [
        'app.log',
        'app.1.log',
      ]);
      expect(result.logFiles.first.readAsStringSync(), 'current');
    });

    test('reports an empty result when nothing is available', () async {
      final root = createTemporaryDirectory(addTearDown);
      final result = await exportRecoveryDiagnostics(
        directory: Directory('${root.path}/recovery'),
        logsDirectory: Directory('${root.path}/missing-logs'),
        backup: File('${root.path}/missing.sqlite'),
      );

      expect(result.isEmpty, isTrue);
      expect(result.copiedFileCount, 0);
    });
  });

  test('recoveryProgressFileName is a compact UTC timestamp', () {
    expect(
      recoveryProgressFileName(DateTime.utc(2026, 1, 2, 3, 4, 5, 6, 7)),
      'progress-recovery-20260102T030405.006007Z.json',
    );
    expect(
      recoveryProgressFileName(DateTime.utc(2026, 1, 2, 15, 4, 5)),
      'progress-recovery-20260102T150405.000000Z.json',
    );
  });
}
