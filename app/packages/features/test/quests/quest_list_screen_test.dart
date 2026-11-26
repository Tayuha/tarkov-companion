import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/quest_screen_fixture.dart';

void main() {
  late AppDatabase database;
  late QuestRepository repository;
  late List<String> selectedIds;

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
  }) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
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

  Finder badgeIn(String questId, String label) => find.descendant(
    of: find.byKey(ValueKey('quest-row-$questId')),
    matching: find.text(label),
  );

  testWidgets('initial load renders rows, metadata and state badges', (
    tester,
  ) async {
    await pumpQuests(tester);

    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);
    expect(find.text('Debut'), findsOneWidget);
    expect(find.text('Prapor · Level 1 · Customs'), findsOneWidget);
    expect(badgeIn('quest-debut', 'Completed'), findsOneWidget);
    expect(badgeIn('quest-checking', 'In progress'), findsOneWidget);
    expect(badgeIn('quest-shootout', 'Failed'), findsOneWidget);
    expect(badgeIn('quest-collector', 'Not started'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
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
        matching: find.text('Level ≤ 10'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('state filter reads progress for the given profile', (
    tester,
  ) async {
    await pumpQuests(tester);

    await selectDropdown(tester, 'quest-state-filter', 'Completed');

    expect(find.text('Showing 2 of 2 quests'), findsOneWidget);
    expect(find.byKey(const Key('quest-filter-chip-state')), findsOneWidget);
    expect(find.text('Debut'), findsOneWidget);
    expect(find.text('The Punisher - Part 1'), findsOneWidget);
  });

  testWidgets('combined filters intersect and reset clears everything', (
    tester,
  ) async {
    await pumpQuests(tester);

    await selectDropdown(tester, 'quest-trader-filter', 'Prapor');
    await selectDropdown(tester, 'quest-map-filter', 'Customs');
    await selectDropdown(tester, 'quest-level-filter', 'Level ≤ 20');
    await selectDropdown(tester, 'quest-state-filter', 'Not started');

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

    expect(badgeIn('quest-debut', 'Completed'), findsOneWidget);
    expect(badgeIn('quest-checking', 'In progress'), findsOneWidget);
    expect(badgeIn('quest-shootout', 'Failed'), findsOneWidget);

    await pumpQuests(tester, profileId: fixtureProfilePve);

    expect(badgeIn('quest-debut', 'In progress'), findsOneWidget);
    expect(badgeIn('quest-checking', 'Completed'), findsOneWidget);
    expect(badgeIn('quest-shootout', 'Not started'), findsOneWidget);
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
}
