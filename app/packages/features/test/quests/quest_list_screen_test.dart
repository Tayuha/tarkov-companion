import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/quest_screen_fixture.dart';
import '../theme/support/load_fonts.dart';

void main() {
  late AppDatabase database;
  late QuestRepository repository;
  late List<String> selectedIds;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadDesignFonts();
  });

  setUp(() async {
    database = await openQuestFixtureDatabase();
    repository = QuestRepository(database);
    selectedIds = <String>[];
  });

  tearDown(() => database.close());

  Future<void> pumpQuests(
    WidgetTester tester, {
    String? profileId = fixtureProfileRegular,
    int pageSize = 50,
    Size size = const Size(1000, 1400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.view.reset();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: QuestListScreen(
          repository: repository,
          profileId: profileId,
          pageSize: pageSize,
          traderOptions: fixtureTraderOptions,
          mapOptions: fixtureMapOptions,
          onQuestSelected: selectedIds.add,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectDropdown(
    WidgetTester tester,
    String key,
    String label,
  ) async {
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> selectState(
    WidgetTester tester,
    QuestProgressState state,
  ) async {
    await tester.tap(find.byKey(Key('quest-state-filter-${state.name}')));
    await tester.pumpAndSettle();
  }

  Finder badgeIn(String questId, String label) => find.descendant(
    of: find.byKey(ValueKey('quest-row-$questId')),
    matching: find.text(label),
  );

  AppStatus statusIn(WidgetTester tester, String questId) => tester
      .widget<AppStatusBadge>(find.byKey(ValueKey('quest-state-$questId')))
      .status;

  testWidgets('initial load renders rows, metadata and state badges', (
    tester,
  ) async {
    await pumpQuests(tester);

    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);
    expect(find.text('Debut'), findsOneWidget);
    expect(find.text('Prapor · Level 1 · Customs'), findsOneWidget);
    expect(badgeIn('quest-debut', 'COMPLETED'), findsOneWidget);
    expect(badgeIn('quest-checking', 'IN PROGRESS'), findsOneWidget);
    expect(badgeIn('quest-shootout', 'FAILED'), findsOneWidget);
    expect(badgeIn('quest-collector', 'LOCKED'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('loads trader and map labels from the database', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: QuestListScreen(
          repository: repository,
          profileId: fixtureProfileRegular,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('quest-trader-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Prapor'), findsWidgets);

    await tester.tap(find.text('Prapor').last);
    await tester.pumpAndSettle();
    expect(find.text('Showing 7 of 7 quests'), findsOneWidget);
  });

  testWidgets('search is debounced and matches name tokens', (tester) async {
    await pumpQuests(tester);

    await tester.enterText(
      find.byKey(const Key('quest-search-field')),
      'punisher',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));

    // The debounce has not fired yet: the full catalog is still on screen.
    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 2 quests'), findsOneWidget);
    expect(find.text('The Punisher - Part 1'), findsOneWidget);
    expect(find.text('The Punisher - Part 2'), findsOneWidget);
    expect(find.text('Debut'), findsNothing);
    expect(find.byKey(const Key('quest-filter-chip-text')), findsOneWidget);
  });

  testWidgets('search folds diacritics', (tester) async {
    await pumpQuests(tester);

    await tester.enterText(find.byKey(const Key('quest-search-field')), 'cafe');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 1 quests'), findsOneWidget);
    expect(find.text('Café Crème'), findsOneWidget);
  });

  testWidgets('trader filter narrows to that trader and shows a chip', (
    tester,
  ) async {
    await pumpQuests(tester);

    await selectDropdown(tester, 'quest-trader-filter', 'Prapor');

    expect(find.text('Showing 7 of 7 quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-trader')), findsOneWidget);
    expect(find.text('Therapist · Level 5 · Customs'), findsNothing);
  });

  testWidgets('map filter narrows to that map', (tester) async {
    await pumpQuests(tester);

    await selectDropdown(tester, 'quest-map-filter', 'Customs');

    expect(find.text('Showing 6 of 6 quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-map')), findsOneWidget);
  });

  testWidgets('level filter keeps quests at or below the bound', (
    tester,
  ) async {
    await pumpQuests(tester);

    await selectDropdown(tester, 'quest-level-filter', 'Level ≤ 10');

    expect(find.text('Showing 6 of 6 quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-level')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('quest-filter-chip-level')),
        matching: find.text('LEVEL ≤ 10'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('state filter reads progress for the given profile', (
    tester,
  ) async {
    await pumpQuests(tester);

    await selectState(tester, QuestProgressState.completed);

    expect(find.text('Showing 2 of 2 quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-state')), findsOneWidget);
    expect(find.text('Debut'), findsOneWidget);
    expect(find.text('The Punisher - Part 1'), findsOneWidget);
    final selected = tester.widget<AppChip>(
      find.byKey(const Key('quest-state-filter-completed')),
    );
    expect(selected.selected, isTrue);
  });

  testWidgets('combined filters intersect and reset clears everything', (
    tester,
  ) async {
    await pumpQuests(tester);

    await selectDropdown(tester, 'quest-trader-filter', 'Prapor');
    await selectDropdown(tester, 'quest-map-filter', 'Customs');
    await selectDropdown(tester, 'quest-level-filter', 'Level ≤ 20');
    await selectState(tester, QuestProgressState.notStarted);

    expect(find.text('Showing 1 of 1 quests'), findsOneWidget);
    expect(find.text('The Punisher - Part 2'), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-trader')), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-map')), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-level')), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-state')), findsOneWidget);

    await tester.tap(find.byKey(const Key('quest-reset-filters')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-trader')), findsNothing);
    expect(find.byKey(const Key('quest-filter-chip-map')), findsNothing);
    expect(find.byKey(const Key('quest-filter-chip-level')), findsNothing);
    expect(find.byKey(const Key('quest-filter-chip-state')), findsNothing);
  });

  testWidgets('progress badges are isolated per profile', (tester) async {
    await pumpQuests(tester, profileId: fixtureProfileRegular);

    expect(badgeIn('quest-debut', 'COMPLETED'), findsOneWidget);
    expect(badgeIn('quest-checking', 'IN PROGRESS'), findsOneWidget);
    expect(badgeIn('quest-shootout', 'FAILED'), findsOneWidget);

    await pumpQuests(tester, profileId: fixtureProfilePve);

    expect(badgeIn('quest-debut', 'IN PROGRESS'), findsOneWidget);
    expect(badgeIn('quest-checking', 'COMPLETED'), findsOneWidget);
    expect(badgeIn('quest-shootout', 'AVAILABLE'), findsOneWidget);
  });

  testWidgets('status badges map availability and keep failed distinct', (
    tester,
  ) async {
    await pumpQuests(tester, size: const Size(1440, 1000));

    expect(statusIn(tester, 'quest-debut'), AppStatus.completed);
    expect(statusIn(tester, 'quest-checking'), AppStatus.inProgress);
    expect(statusIn(tester, 'quest-shootout'), AppStatus.failed);
    expect(statusIn(tester, 'quest-cafe'), AppStatus.available);
    expect(statusIn(tester, 'quest-collector'), AppStatus.locked);

    await pumpQuests(tester, profileId: null, size: const Size(1440, 1000));
    expect(statusIn(tester, 'quest-collector'), AppStatus.locked);
    expect(badgeIn('quest-collector', 'NOT STARTED'), findsOneWidget);
    expect(badgeIn('quest-debut', 'NOT STARTED'), findsOneWidget);
  });

  testWidgets('the catalog keeps only the active profile game mode', (
    tester,
  ) async {
    await pumpQuests(tester, profileId: fixtureProfileRegular);
    expect(find.text('PvE Only Raid'), findsNothing);
    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);

    await pumpQuests(tester, profileId: fixtureProfilePve);
    expect(find.text('PvE Only Raid'), findsOneWidget);
    expect(find.text('Showing 15 of 15 quests'), findsOneWidget);
  });

  testWidgets('available view lists startable quests and orders them', (
    tester,
  ) async {
    await pumpQuests(tester);

    await tester.tap(find.byKey(const Key('quest-view-available')));
    await tester.pumpAndSettle();

    expect(find.text('Available quests'), findsOneWidget);
    expect(find.text('6 available quests'), findsOneWidget);
    expect(badgeIn('quest-cafe', 'AVAILABLE'), findsOneWidget);
    expect(find.text('Café Crème'), findsOneWidget);
    expect(find.text('Shortage'), findsOneWidget);
    expect(find.text('The Punisher - Part 2'), findsOneWidget);
    expect(find.text('Debut'), findsNothing);
    expect(find.text('Collector'), findsNothing);
    expect(find.text('Prapor · Level 1 · Customs'), findsNothing);
    expect(find.text('Therapist · Level 10 · Interchange'), findsWidgets);

    double topOf(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(topOf('Shortage'), lessThan(topOf('Car Repair')));

    await tester.tap(find.byKey(const Key('quest-available-order-name')));
    await tester.pumpAndSettle();

    expect(topOf('Car Repair'), lessThan(topOf('Shortage')));
    final selected = tester.widget<AppChip>(
      find.byKey(const Key('quest-available-order-name')),
    );
    expect(selected.selected, isTrue);
  });

  testWidgets('available view explains an empty profile clearly', (
    tester,
  ) async {
    await database.customStatement('UPDATE tasks SET minPlayerLevel = 99');
    await pumpQuests(tester);

    await tester.tap(find.byKey(const Key('quest-view-available')));
    await tester.pumpAndSettle();

    expect(find.text('0 available quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-available-empty')), findsOneWidget);
    expect(find.text('Nothing is available to start.'), findsOneWidget);
    expect(
      find.textContaining('locked by a level, trader, or prerequisite'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('quest-available-open-catalog')));
    await tester.pumpAndSettle();
    expect(find.text('Quest catalog'), findsOneWidget);
  });

  testWidgets('progress for a removed quest is listed as unavailable', (
    tester,
  ) async {
    await database.customStatement(
      'INSERT INTO questProgress (profileId, questId, state, updatedAt) '
      'VALUES (?, ?, ?, ?)',
      [fixtureProfileRegular, 'quest-removed-upstream', 'in-progress', 0],
    );

    await pumpQuests(tester);

    expect(find.byKey(const Key('quest-unavailable-panel')), findsOneWidget);
    expect(find.text('UNAVAILABLE UPSTREAM'), findsOneWidget);
    expect(find.text('quest-removed-upstream'), findsOneWidget);
    expect(find.textContaining('In progress'), findsOneWidget);
    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);
  });

  testWidgets('empty results keep the query and reset restores the list', (
    tester,
  ) async {
    await pumpQuests(tester);

    await tester.enterText(find.byKey(const Key('quest-search-field')), 'zzzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Showing 0 of 0 quests'), findsOneWidget);
    expect(find.text('No quests match "zzzz".'), findsOneWidget);
    expect(find.byKey(const Key('quest-empty-reset')), findsOneWidget);

    await tester.tap(find.byKey(const Key('quest-empty-reset')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);
    expect(find.text('No quests match "zzzz".'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('quest-search-field')))
          .controller
          ?.text,
      isEmpty,
    );
  });

  testWidgets('pagination appends pages with the load-more control', (
    tester,
  ) async {
    await pumpQuests(tester, pageSize: 5);

    expect(find.text('Showing 5 of 14 quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-loaded-count')), findsOneWidget);

    await tester.tap(find.byKey(const Key('quest-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 10 of 14 quests'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quest-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-load-more')), findsNothing);
  });

  testWidgets('tapping a row reports the quest id', (tester) async {
    await pumpQuests(tester);

    await tester.tap(find.text('Debut'));
    await tester.pump();

    expect(selectedIds, ['quest-debut']);
  });

  group('layout helpers', () {
    test('breakpoints separate compact, standard and wide', () {
      expect(questLayoutForWidth(1099), QuestLayout.compact);
      expect(questLayoutForWidth(1100), QuestLayout.standard);
      expect(questLayoutForWidth(1599), QuestLayout.standard);
      expect(questLayoutForWidth(1600), QuestLayout.wide);
    });

    test('progress fraction ignores optional objectives and empty states', () {
      expect(formatQuestProgress(null), '—');
    });
  });

  group('responsive table', () {
    testWidgets('1440 shows the five-column header and table rows', (
      tester,
    ) async {
      await pumpQuests(tester, size: const Size(1440, 1000));

      final header = find.byKey(const Key('quest-table-header'));
      expect(header, findsOneWidget);
      for (final label in ['QUEST', 'TRADER', 'MAP', 'STATUS', 'PROGRESS']) {
        expect(
          find.descendant(of: header, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.text('LEVEL'), findsNothing);
      expect(find.byType(QuestTableRow), findsWidgets);
      expect(find.byType(QuestListRow), findsNothing);

      final row = tester.widget<QuestTableRow>(
        find.byType(QuestTableRow).first,
      );
      expect(row.layout, QuestLayout.standard);
    });

    testWidgets('1920 adds the level column and a wider quest cell', (
      tester,
    ) async {
      await pumpQuests(tester, size: const Size(1440, 1000));
      final standardCell = tester
          .getSize(find.byKey(const ValueKey('quest-row-quest-quest-debut')))
          .width;

      await pumpQuests(tester, size: const Size(1920, 1080));

      final header = find.byKey(const Key('quest-table-header'));
      expect(
        find.descendant(of: header, matching: find.text('LEVEL')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('quest-row-level-quest-debut')),
        findsOneWidget,
      );
      final row = tester.widget<QuestTableRow>(
        find.byType(QuestTableRow).first,
      );
      expect(row.layout, QuestLayout.wide);
      final wideCell = tester
          .getSize(find.byKey(const ValueKey('quest-row-quest-quest-debut')))
          .width;
      expect(wideCell, greaterThan(standardCell));
    });

    testWidgets('below 1100 drops the header for compact card rows', (
      tester,
    ) async {
      await pumpQuests(tester, size: const Size(900, 900));

      expect(find.byKey(const Key('quest-table-header')), findsNothing);
      expect(find.byType(QuestListRow), findsWidgets);
      expect(find.byType(QuestTableRow), findsNothing);

      await tester.tap(find.text('Debut'));
      await tester.pump();
      expect(selectedIds, ['quest-debut']);
    });

    testWidgets('content width is capped on an ultra-wide window', (
      tester,
    ) async {
      await pumpQuests(tester, size: const Size(2560, 1440));

      final content = find.byKey(const Key('quest-content'));
      expect(tester.getSize(content).width, QuestListScreen.maxContentWidth);
      expect(
        find.descendant(
          of: find.byKey(const Key('quest-table-header')),
          matching: find.text('LEVEL'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('table rows alternate their resting surface', (tester) async {
      await pumpQuests(tester, size: const Size(1440, 1000));
      final tokens = Theme.of(tester.element(find.byType(QuestListScreen)))
          .extension<AppTokens>()!;

      Color? surfaceFor(String id) {
        final container = tester.widget<Container>(
          find.byKey(ValueKey('quest-row-surface-$id')),
        );
        return (container.decoration! as BoxDecoration).color;
      }

      // Default repository order is name ascending: Café is row 0, Car row 1.
      expect(surfaceFor('quest-cafe'), tokens.surface);
      expect(surfaceFor('quest-car-repair'), tokens.background);
    });

    testWidgets('list fraction comes from required objective counts', (
      tester,
    ) async {
      await pumpQuests(tester, size: const Size(1440, 1000));

      final progress = tester.widget<Text>(
        find.byKey(const ValueKey('quest-row-progress-quest-cafe')),
      );
      expect(progress.data, '1 / 3');
    });
  });

  group('golden', () {
    testWidgets('quest list at 1440', (tester) async {
      await pumpQuests(tester, size: const Size(1440, 900));

      await expectLater(
        find.byType(QuestListScreen),
        matchesGoldenFile('goldens/quest_list_1440.png'),
      );
    });

    testWidgets('quest list at 1920', (tester) async {
      await pumpQuests(tester, size: const Size(1920, 1080));

      await expectLater(
        find.byType(QuestListScreen),
        matchesGoldenFile('goldens/quest_list_1920.png'),
      );
    });
  });
}
