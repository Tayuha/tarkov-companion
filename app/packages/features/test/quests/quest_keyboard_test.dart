import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/quest_screen_fixture.dart';
import '../theme/support/load_fonts.dart';

/// Keyboard-only coverage for the quest list.
///
/// Every traversal and activation starts with a synthetic key event: no test
/// taps or otherwise uses the pointer to move focus.
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
    int pageSize = 5,
    Size size = const Size(1200, 1400),
    UpstreamCheck? upstreamCheck,
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
          upstreamCheck: upstreamCheck,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressTab(WidgetTester tester, {bool reverse = false}) async {
    if (reverse) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    if (reverse) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await tester.pumpAndSettle();
  }

  bool holdsFocus(WidgetTester tester, Key key) {
    final focus = tester.widget<Focus>(find.byKey(key));
    return focus.focusNode?.hasFocus ?? false;
  }

  bool searchHasFocus(WidgetTester tester) {
    final field = tester.widget<TextField>(
      find.byKey(const Key('quest-search-field')),
    );
    return field.focusNode?.hasFocus ?? false;
  }

  /// Moves past the two segment chips, search, three dropdowns and five state
  /// chips: the eleven controls that precede the first row in the catalog view.
  Future<void> tabToFirstRow(WidgetTester tester) async {
    for (var index = 0; index < 12; index++) {
      await pressTab(tester);
    }
  }

  group('focus traversal', () {
    testWidgets('Tab walks the segment, filters and rows in visual order', (
      tester,
    ) async {
      await pumpQuests(tester);

      await pressTab(tester);
      expect(holdsFocus(tester, const Key('quest-view-catalog-focus')), isTrue);
      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('quest-view-available-focus')),
        isTrue,
      );

      await pressTab(tester);
      expect(searchHasFocus(tester), isTrue);

      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('quest-trader-filter-focus')),
        isTrue,
      );
      await pressTab(tester);
      expect(holdsFocus(tester, const Key('quest-map-filter-focus')), isTrue);
      await pressTab(tester);
      expect(holdsFocus(tester, const Key('quest-level-filter-focus')), isTrue);

      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('quest-state-filter-any-focus')),
        isTrue,
      );
      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('quest-state-filter-notStarted-focus')),
        isTrue,
      );

      final firstRow = tester.widget<QuestTableRow>(
        find.byType(QuestTableRow).first,
      );
      for (var index = 0; index < 4; index++) {
        await pressTab(tester);
      }
      expect(
        holdsFocus(tester, ValueKey('quest-row-focus-${firstRow.quest.id}')),
        isTrue,
      );

      final secondRow = tester.widget<QuestTableRow>(
        find.byType(QuestTableRow).at(1),
      );
      await pressTab(tester);
      expect(
        holdsFocus(tester, ValueKey('quest-row-focus-${secondRow.quest.id}')),
        isTrue,
      );

      for (var index = 1; index < 5; index++) {
        await pressTab(tester);
      }
      expect(holdsFocus(tester, const Key('quest-load-more-focus')), isTrue);
    });

    testWidgets('Shift+Tab reverses the same order and wraps', (tester) async {
      await pumpQuests(tester);

      await pressTab(tester);
      expect(holdsFocus(tester, const Key('quest-view-catalog-focus')), isTrue);

      await pressTab(tester, reverse: true);
      expect(holdsFocus(tester, const Key('quest-load-more-focus')), isTrue);
    });
  });

  group('activation', () {
    testWidgets('Enter opens the focused quest', (tester) async {
      await pumpQuests(tester);
      await tabToFirstRow(tester);
      final firstRow = tester.widget<QuestTableRow>(
        find.byType(QuestTableRow).first,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selectedIds, <String>[firstRow.quest.id]);
    });

    testWidgets('the offline retry strip is reachable and activates', (
      tester,
    ) async {
      var checks = 0;
      Future<UpstreamStatus> failing() async {
        checks++;
        return const UpstreamStatus.offline();
      }

      await pumpQuests(tester, upstreamCheck: failing);
      expect(checks, 1);

      for (var index = 0; index < 12; index++) {
        await pressTab(tester);
      }
      expect(
        holdsFocus(tester, const Key('quest-upstream-retry-focus')),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(checks, 2);
    });
  });

  group('available view', () {
    testWidgets('the segment switches and ordering chips take focus next', (
      tester,
    ) async {
      await pumpQuests(tester);

      await pressTab(tester);
      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('quest-view-available-focus')),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Available quests'), findsOneWidget);

      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('quest-available-order-level-focus')),
        isTrue,
      );
      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('quest-available-order-trader-focus')),
        isTrue,
      );
    });
  });

  group('shortcuts', () {
    testWidgets('/ focuses search, Escape clears and returns focus', (
      tester,
    ) async {
      await pumpQuests(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pumpAndSettle();
      expect(searchHasFocus(tester), isTrue);

      await tester.enterText(
        find.byKey(const Key('quest-search-field')),
        'punisher',
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('quest-search-field')),
      );
      expect(field.controller?.text, isEmpty);
      expect(field.focusNode?.hasFocus, isFalse);
      expect(holdsFocus(tester, const Key('quest-screen-focus')), isTrue);
    });
  });

  group('visible focus', () {
    testWidgets('the row ring uses the focus tokens', (tester) async {
      await pumpQuests(tester);
      await tabToFirstRow(tester);

      final row = tester.widget<QuestTableRow>(
        find.byType(QuestTableRow).first,
      );
      final ring = tester.widget<DecoratedBox>(
        find.byKey(ValueKey('quest-row-focus-ring-${row.quest.id}')),
      );
      final decoration = ring.decoration as BoxDecoration;
      final border = decoration.border! as Border;
      const tokens = AppTokens.phosphor();

      expect(border.top.color, tokens.focusRing);
      expect(border.top.width, tokens.focusRingWidth);
    });
  });
}
