import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion/src/app_root.dart';
import 'package:tarkov_companion/src/app_session.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 12);

  testWidgets('recovery offers exports and explains the read-only state', (
    tester,
  ) async {
    final environment = await _RecoveryEnvironment.create(now: now);
    addTearDown(environment.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppRoot(openSession: () async => environment.session),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(RecoveryKeys.screen), findsOneWidget);
    expect(find.text('Local database recovery'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Bad state: deliberate recovery failure'), findsOneWidget);
    expect(find.byKey(RecoveryKeys.exportProgress), findsOneWidget);
    expect(find.byKey(RecoveryKeys.exportDiagnostics), findsOneWidget);
    expect(
      find.text(
        'Writes are refused by SQLite, and the recovery handle stays open '
        'until the app closes.',
      ),
      findsOneWidget,
    );

    // Only the two export actions exist: no write, restore or import button.
    expect(find.byType(AppButton, skipOffstage: false), findsNWidgets(2));
  });

  testWidgets('Export progress writes into the export directory', (
    tester,
  ) async {
    final environment = await _RecoveryEnvironment.create(now: now);
    addTearDown(environment.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppRoot(openSession: () async => environment.session),
      ),
    );
    await tester.pumpAndSettle();

    await _tapAndSettleIo(tester, find.byKey(RecoveryKeys.exportProgress));

    final path = tester
        .widget<Text>(find.byKey(RecoveryKeys.progressPath))
        .data!;
    expect(path, contains(environment.exportDirectory.path));
    expect(path, matches(RegExp(r'progress-recovery-.*Z\.json$')));
    final file = File(path);
    expect(file.existsSync(), isTrue);

    final parsed = ProgressExportDocument.parse(file.readAsStringSync());
    expect(parsed.profiles.single.gameMode, GameMode.regular);
    expect(parsed.questCount, 2);
    expect(parsed.objectiveCount, 1);
    expect(parsed.checksum, startsWith('sha256:'));

    expect(
      tester.widget<Text>(find.byKey(RecoveryKeys.progressCounts)).data,
      '1 profile · 2 quest states · 1 objective count',
    );
    expect(
      tester.widget<Text>(find.byKey(RecoveryKeys.progressChecksum)).data,
      startsWith('Checksum sha256:'),
    );
    expect(
      find.text('Copy the path above to open the export folder.'),
      findsOneWidget,
    );
  });

  testWidgets('Export diagnostics copies the backup and log files', (
    tester,
  ) async {
    final environment = await _RecoveryEnvironment.create(now: now);
    addTearDown(environment.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppRoot(openSession: () async => environment.session),
      ),
    );
    await tester.pumpAndSettle();

    await _tapAndSettleIo(tester, find.byKey(RecoveryKeys.exportDiagnostics));

    expect(find.text('Copied 2 diagnostics files.'), findsOneWidget);
    final path = tester
        .widget<Text>(find.byKey(RecoveryKeys.diagnosticsPath))
        .data!;
    expect(path, environment.exportDirectory.path);
    expect(
      File('${environment.exportDirectory.path}/app.log').existsSync(),
      isTrue,
    );
    expect(
      File('${environment.exportDirectory.path}/backup.sqlite').existsSync(),
      isTrue,
    );
  });

  testWidgets('an empty database reports the export error inline', (
    tester,
  ) async {
    final environment = await _RecoveryEnvironment.create(
      now: now,
      seedProfiles: false,
    );
    addTearDown(environment.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AppRoot(openSession: () async => environment.session),
      ),
    );
    await tester.pumpAndSettle();

    await _tapAndSettleIo(tester, find.byKey(RecoveryKeys.exportProgress));

    expect(find.byKey(RecoveryKeys.error), findsOneWidget);
    expect(find.textContaining('No progress was exported'), findsOneWidget);
    expect(find.byKey(RecoveryKeys.progressPath), findsNothing);
  });
}

/// Runs the tap and the real filesystem I/O it starts, then rebuilds.
Future<void> _tapAndSettleIo(WidgetTester tester, Finder finder) async {
  await tester.runAsync(() async {
    await tester.tap(finder);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
  await tester.pumpAndSettle();
}

final class _RecoveryEnvironment {
  _RecoveryEnvironment._({
    required this.root,
    required this.recovery,
    required this.exportDirectory,
    required this.session,
  });

  final Directory root;
  final RecoveryDatabase recovery;
  final Directory exportDirectory;
  final AppSessionRecovery session;

  static Future<_RecoveryEnvironment> create({
    required DateTime now,
    bool seedProfiles = true,
  }) async {
    final root = Directory.systemTemp.createTempSync('tarkov_recovery_');
    final path = '${root.path}/tarkov_companion.sqlite';

    final database = AppDatabase.atPath(path);
    await database.customSelect('SELECT 1').get();
    if (seedProfiles) {
      final createdAt = now.millisecondsSinceEpoch ~/ 1000;
      await database.customStatement(
        'INSERT INTO profiles '
        '(id, gameMode, playerLevel, createdAt, updatedAt) '
        'VALUES (?, ?, ?, ?, ?)',
        ['profile-regular', 'regular', 22, createdAt, createdAt],
      );
      await database.customStatement(
        'INSERT INTO questProgress '
        '(profileId, questId, state, updatedAt) VALUES (?, ?, ?, ?)',
        ['profile-regular', 'quest-debut', 'completed', createdAt],
      );
      await database.customStatement(
        'INSERT INTO questProgress '
        '(profileId, questId, state, updatedAt) VALUES (?, ?, ?, ?)',
        ['profile-regular', 'quest-checking', 'in-progress', createdAt],
      );
      await database.customStatement(
        'INSERT INTO objectiveProgress '
        '(profileId, questId, objectiveId, count, updatedAt) '
        'VALUES (?, ?, ?, ?, ?)',
        ['profile-regular', 'quest-checking', 'objective-1', 3, createdAt],
      );
    }
    await database.close();

    final recovery = RecoveryDatabase.open(path);
    final logsDirectory = Directory('${root.path}/logs')..createSync();
    File('${logsDirectory.path}/app.log').writeAsStringSync('{"level":"info"}');
    final backup = File('${root.path}/backup.sqlite')
      ..writeAsStringSync('pre-migration backup');
    final exportDirectory = Directory('${root.path}/recovery');

    final session = AppSessionRecovery(
      message:
          'The local database could not be opened. It was left untouched and '
          'is available read-only. deliberate recovery failure',
      failure: StateError('deliberate recovery failure'),
      recoveryDatabase: recovery,
      detectedVersion: 5,
      backup: backup,
      logsDirectory: logsDirectory,
      exportDirectory: exportDirectory,
      close: () async {
        recovery.close();
      },
    );

    return _RecoveryEnvironment._(
      root: root,
      recovery: recovery,
      exportDirectory: exportDirectory,
      session: session,
    );
  }

  void dispose() {
    recovery.close();
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}
