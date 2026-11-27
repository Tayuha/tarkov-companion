import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion/src/app_root.dart';
import 'package:tarkov_companion/src/home_shell.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/e2e_environment.dart';

/// The item and quest carried by the committed bundle fixture.
const _coltItemId = '5447a9cd4bdc2dbd208b4567';
const _coltName = 'Colt M4A1 5.56x45 assault rifle';
const _debutQuestId = '5936d90786f7742b1420ba5b';
const _debutObjectiveId = '5967379186f77463860dadd6';

void main() {
  testWidgets(
    'first run, browse, complete a quest, then export and re-import',
    (tester) async {
      final environment = await E2eEnvironment.create();
      final progressFile = File('${environment.root.path}/progress.json');
      final picker = DirectoryProgressFilePicker(
        environment.root,
        savePath: progressFile.path,
        importPath: progressFile.path,
      );
      addTearDown(environment.dispose);

      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: AppRoot(
            openSession: () async => environment.session,
            progressFilePicker: picker,
          ),
        ),
      );

      // ---------------------------------------------------------------------
      // First run: the gate prepares the fixture manifest, Start applies it.
      // ---------------------------------------------------------------------
      await _settle(tester);
      expect(find.byKey(FirstRunKeys.estimate), findsOneWidget);
      expect(find.text('Download game data to get started'), findsOneWidget);

      await tester.tap(find.byKey(FirstRunKeys.startButton));
      await _settle(tester);

      expect(find.byKey(FirstRunKeys.estimate), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.byType(CatalogScreen), findsOneWidget);

      // ---------------------------------------------------------------------
      // Catalog browse: search narrows the two fixture items to the Colt.
      // ---------------------------------------------------------------------
      await tester.enterText(
        find.byKey(const Key('catalog-search-field')),
        'colt',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await _settle(tester);

      expect(find.text(_coltName), findsOneWidget);
      expect(find.text('5.56x45mm M855 ammo pack (50 pcs)'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('catalog-item-$_coltItemId')));
      await _settle(tester);

      expect(find.byKey(const Key('item-detail-screen')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('item-detail-name'))).data,
        _coltName,
      );

      await tester.pageBack();
      await _settle(tester);

      // ---------------------------------------------------------------------
      // Quest completion: record the full objective count, then complete.
      // ---------------------------------------------------------------------
      await tester.tap(find.byKey(const Key('home-rail-quests-label')));
      await _settle(tester);
      expect(
        find.byKey(const ValueKey('quest-row-$_debutQuestId')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('quest-row-$_debutQuestId')));
      await _settle(tester);
      expect(find.byKey(const Key('quest-detail-screen')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('quest-detail-name'))).data,
        'Debut',
      );

      final increment = find.byKey(
        ValueKey('quest-objective-increment-$_debutObjectiveId'),
      );
      for (var count = 1; count <= 5; count++) {
        await tester.tap(increment);
        await _settle(tester);
      }
      expect(
        tester
            .widget<TextField>(
              find.byKey(ValueKey('quest-objective-count-$_debutObjectiveId')),
            )
            .controller
            ?.text,
        '5',
      );

      await tester.tap(find.byKey(const Key('quest-status-mark-completed')));
      await _settle(tester);
      expect(find.byKey(const Key('quest-override-dialog')), findsNothing);
      expect(find.text('COMPLETED'), findsWidgets);

      await tester.pageBack();
      await _settle(tester);

      // ---------------------------------------------------------------------
      // Profile facts and export: raise the level, then export the active
      // profile through the directory-backed picker.
      // ---------------------------------------------------------------------
      await tester.tap(find.byKey(const Key('home-rail-profiles-label')));
      await _settle(tester);

      await tester.tap(find.byKey(const Key('profile-edit-regular')));
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('profile-level-field')),
        '37',
      );
      await tester.tap(find.byKey(const Key('profile-level-save')));
      await _settle(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('profile-level-regular')))
            .data,
        '37',
      );

      await tester.tap(find.byKey(const Key('profiles-export-active')));
      await _settle(tester);
      await _waitForFile(tester, progressFile);
      await _waitFor(tester, find.textContaining('Exported'));

      expect(progressFile.existsSync(), isTrue);
      final exported = ProgressExportDocument.parse(
        progressFile.readAsStringSync(),
      );
      expect(exported.profiles.single.playerLevel, 37);
      expect(exported.profiles.single.quests.single.questId, _debutQuestId);
      expect(
        exported.profiles.single.quests.single.state,
        QuestProgressState.completed,
      );
      expect(exported.profiles.single.objectives.single.count, 5);

      // ---------------------------------------------------------------------
      // Delete the profile, then re-import the exported file. This proves
      // both facts and progress come back from the file alone.
      // ---------------------------------------------------------------------
      await tester.tap(find.byKey(const Key('profile-delete-regular')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('profile-confirm-delete')));
      await _settle(tester);
      expect(find.byKey(const Key('profiles-empty')), findsOneWidget);

      await tester.tap(find.byKey(const Key('profiles-import')));
      await _settle(tester);
      await _waitFor(tester, find.byKey(const Key('import-preview')));
      expect(
        tester.widget<Text>(find.byKey(const Key('import-counts'))).data,
        '1 profile(s) · 1 quest state(s) · 1 objective count(s)',
      );

      await tester.tap(find.byKey(const Key('import-apply')));
      await _waitFor(tester, find.byKey(const Key('profile-active-regular')));

      expect(find.byKey(const Key('profiles-empty')), findsNothing);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('profile-level-regular')))
            .data,
        '37',
      );
      expect(find.byKey(const Key('profile-active-regular')), findsOneWidget);

      // ---------------------------------------------------------------------
      // The restored progress is visible through the quest screens again.
      // ---------------------------------------------------------------------
      await tester.tap(find.byKey(const Key('home-rail-quests-label')));
      await _settle(tester);
      expect(
        find.descendant(
          of: find.byKey(ValueKey('quest-state-$_debutQuestId')),
          matching: find.text('COMPLETED'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('quest-row-$_debutQuestId')));
      await _settle(tester);
      expect(
        tester
            .widget<TextField>(
              find.byKey(ValueKey('quest-objective-count-$_debutObjectiveId')),
            )
            .controller
            ?.text,
        '5',
      );

      // Let the tree close its session before the temp directory goes away.
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
    },
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out waiting for $finder');
    }
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _waitForFile(
  WidgetTester tester,
  File file, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    if (file.existsSync() && file.lengthSync() > 0) {
      try {
        ProgressExportDocument.parse(file.readAsStringSync());
        return;
      } on ProgressFormatException {
        // The writer is still completing the file.
      }
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TestFailure('Timed out waiting for ${file.path}');
    }
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  // Widget-test time is fake, so file and SQLite work started by a button
  // callback needs one real event-loop turn before the fake clock advances.
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 10)),
  );
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 15),
  );
}
