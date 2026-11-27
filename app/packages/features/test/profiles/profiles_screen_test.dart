import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../theme/support/load_fonts.dart';

void main() {
  final now = DateTime.utc(2026, 11, 27, 10);

  late AppDatabase database;
  late ProfileServices services;
  late List<String> ids;
  late Directory directory;
  late List<Profile?> changes;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadDesignFonts();
  });

  setUp(() async {
    database = AppDatabase.memory();
    await database.customSelect('SELECT 1').get();
    ids = ['profile-regular', 'profile-pve', 'profile-imported'];
    services = ProfileServices(
      database,
      clock: () => now,
      idGenerator: () => ids.removeAt(0),
    );
    directory = Directory.systemTemp.createTempSync('tarkov_profiles_ui_');
    changes = [];

    await services.profiles.ensureFirstLaunch();
    await services.profiles.updatePlayerLevel('profile-regular', 15);
    await services.profiles.createForMode(GameMode.pve);
    await services.profiles.updatePlayerLevel('profile-pve', 8);
    await services.profiles.activate('profile-regular');
    await database.customStatement(
      'INSERT INTO tasks (id, name, payload) VALUES (?, ?, ?)',
      ['quest-debut', 'Debut', '{}'],
    );
    await QuestRepository(database, clock: () => now).setQuestState(
      'profile-regular',
      'quest-debut',
      QuestProgressState.completed,
    );
  });

  tearDown(() async {
    await database.close();
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  Future<void> pump(
    WidgetTester tester, {
    String? importPath,
    String? savePath,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ProfilesScreen(
          services: services,
          appVersion: '0.1.0',
          picker: DirectoryProgressFilePicker(
            directory,
            importPath: importPath,
            savePath: savePath,
          ),
          onProfileChanged: changes.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Taps a button whose handler performs real file I/O.
  ///
  /// `pumpAndSettle` only drains fake-async work, so the tap and the file
  /// operation run inside `runAsync` and the UI is rendered afterwards.
  Future<void> tapFileAction(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  String importJson({List<Map<String, Object?>> profiles = const []}) {
    final document = <String, Object?>{
      'format': progressFormat,
      'formatVersion': progressFormatVersion,
      'appVersion': '0.1.0',
      'exportedAt': now.toIso8601String(),
      'profiles': profiles.isEmpty
          ? [
              {
                'gameMode': 'regular',
                'playerLevel': 25,
                'quests': [
                  {'questId': 'quest-debut', 'state': 'in-progress'},
                  {'questId': 'quest-shootout', 'state': 'completed'},
                ],
                'objectives': [
                  {
                    'questId': 'quest-debut',
                    'objectiveId': 'objective-debut-1',
                    'count': 4,
                  },
                ],
              },
            ]
          : profiles,
    };
    document['checksum'] = checksumOf(document);
    return jsonEncode(document);
  }

  File writeImport(String contents) {
    final file = File('${directory.path}/import.json')
      ..writeAsStringSync(contents);
    return file;
  }

  Future<String?> storedState(String profileId, String questId) async {
    final rows = await database
        .customSelect(
          "SELECT state FROM questProgress WHERE profileId = '$profileId' "
          "AND questId = '$questId'",
        )
        .get();
    return rows.isEmpty ? null : rows.single.read<String>('state');
  }

  Future<int> storedQuestRows(String profileId) async {
    final row = await database
        .customSelect(
          "SELECT count(*) AS n FROM questProgress WHERE profileId = '$profileId'",
        )
        .getSingle();
    return row.read<int>('n');
  }

  testWidgets('renders every profile with its level and active badge', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byKey(const Key('profiles-screen')), findsOneWidget);
    expect(find.byKey(const Key('profile-card-regular')), findsOneWidget);
    expect(find.byKey(const Key('profile-card-pve')), findsOneWidget);
    expect(find.byKey(const Key('profile-active-regular')), findsOneWidget);
    expect(find.byKey(const Key('profile-active-pve')), findsNothing);
    expect(find.text('15'), findsOneWidget);
    expect(find.text('8'), findsOneWidget);
    expect(find.byKey(const Key('profiles-create-pvp-season')), findsOneWidget);
  });

  testWidgets('editing the level persists immediately and reports the active '
      'profile', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('profile-edit-regular')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('profile-level-field')), '20');
    await tester.tap(find.byKey(const Key('profile-level-save')));
    await tester.pumpAndSettle();

    expect((await services.profiles.byId('profile-regular'))?.playerLevel, 20);
    expect(
      tester.widget<Text>(find.byKey(const Key('profile-level-regular'))).data,
      '20',
    );
    expect(changes.last?.id, 'profile-regular');
    expect(changes.last?.playerLevel, 20);
  });

  testWidgets('a new mode can be created and becomes active', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('profiles-create-pvp-season')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-card-pvp-season')), findsOneWidget);
    expect(find.byKey(const Key('profile-active-pvp-season')), findsOneWidget);
    expect(changes.last?.gameMode, 'pvp-season');
  });

  testWidgets('reset asks for confirmation and clears only progress', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('profile-reset-regular')));
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot be undone'), findsOneWidget);

    await tester.tap(find.byKey(const Key('profile-confirm-reset')));
    await tester.pumpAndSettle();

    expect(await storedQuestRows('profile-regular'), 0);
    expect((await services.profiles.byId('profile-regular'))?.playerLevel, 15);
    expect(find.byKey(const Key('profiles-notice')), findsOneWidget);
  });

  testWidgets('delete removes a profile and activates another; deleting the '
      'last profile shows the empty state', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('profile-delete-regular')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-confirm-delete')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-card-regular')), findsNothing);
    expect(find.byKey(const Key('profile-active-pve')), findsOneWidget);
    expect(changes.last?.gameMode, 'pve');

    await tester.tap(find.byKey(const Key('profile-delete-pve')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('profile-confirm-delete')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profiles-empty')), findsOneWidget);
    expect(await services.profiles.active(), isNull);
    expect(changes.last, isNull);
  });

  testWidgets('import preview shows counts, defaults to merge and cancelling '
      'changes nothing', (tester) async {
    final file = writeImport(importJson());
    await pump(tester, importPath: file.path);

    await tapFileAction(tester, 'profiles-import');

    expect(find.byKey(const Key('import-preview')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('import-counts'))).data,
      '1 profile(s) · 2 quest state(s) · 1 objective count(s)',
    );
    expect(
      tester
          .widget<AppChip>(find.byKey(const Key('import-mode-merge')))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<AppChip>(find.byKey(const Key('import-mode-replace')))
          .selected,
      isFalse,
    );
    expect(
      find.byKey(const Key('import-conflict-quest-debut-keep')),
      findsOneWidget,
    );

    await tapKey(tester, 'import-cancel');

    expect(find.byKey(const Key('import-preview')), findsNothing);
    expect(await storedState('profile-regular', 'quest-debut'), 'completed');
    expect(await storedState('profile-regular', 'quest-shootout'), isNull);
  });

  testWidgets('replace asks for confirmation and overwrites the profile', (
    tester,
  ) async {
    final file = writeImport(importJson());
    await pump(tester, importPath: file.path);

    await tapFileAction(tester, 'profiles-import');
    await tapKey(tester, 'import-mode-replace');
    await tapKey(tester, 'import-apply');

    expect(find.byKey(const Key('import-confirm-replace')), findsOneWidget);
    await tester.tap(find.byKey(const Key('import-confirm-replace')));
    await tester.pumpAndSettle();

    expect(await storedState('profile-regular', 'quest-debut'), 'in-progress');
    expect(await storedState('profile-regular', 'quest-shootout'), 'completed');
    expect(find.byKey(const Key('import-preview')), findsNothing);
  });

  testWidgets('merge keeps local conflicts by default and applies the chosen '
      'resolution', (tester) async {
    final file = writeImport(importJson());
    await pump(tester, importPath: file.path);

    await tapFileAction(tester, 'profiles-import');
    await tapKey(tester, 'import-conflict-quest-debut-use');
    await tapKey(tester, 'import-apply');

    expect(await storedState('profile-regular', 'quest-debut'), 'in-progress');
    expect(await storedState('profile-regular', 'quest-shootout'), 'completed');
    expect(find.byKey(const Key('import-preview')), findsNothing);
  });

  testWidgets('export writes a file that re-reads with the same checksum', (
    tester,
  ) async {
    final target = '${directory.path}/export.json';
    await pump(tester, savePath: target);

    await tapFileAction(tester, 'profiles-export-active');

    final file = File(target);
    expect(file.existsSync(), isTrue);
    final reread = ProgressExportDocument.parse(file.readAsStringSync());
    expect(reread.profiles.single.gameMode, GameMode.regular);
    expect(reread.questCount, 1);
    expect(find.byKey(const Key('profiles-notice')), findsOneWidget);
  });

  testWidgets('export all writes every profile', (tester) async {
    final target = '${directory.path}/export-all.json';
    await pump(tester, savePath: target);

    await tapFileAction(tester, 'profiles-export-all');

    final reread = ProgressExportDocument.parse(
      File(target).readAsStringSync(),
    );
    expect(reread.profiles, hasLength(2));
  });

  testWidgets('an invalid import is rejected with the documented message and '
      'writes nothing', (tester) async {
    final file = writeImport(
      importJson().replaceFirst(
        RegExp(r'"checksum"\s*:\s*"[^"]+"'),
        '"checksum": "sha256:${'0'.padRight(64, '0')}"',
      ),
    );
    await pump(tester, importPath: file.path);

    await tapFileAction(tester, 'profiles-import');

    expect(find.byKey(const Key('import-preview')), findsNothing);
    expect(
      find.textContaining('the checksum does not match its contents'),
      findsOneWidget,
    );
    expect(await storedState('profile-regular', 'quest-debut'), 'completed');
    expect(await storedQuestRows('profile-regular'), 1);
  });
}
