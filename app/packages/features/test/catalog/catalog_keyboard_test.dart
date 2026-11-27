import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/catalog_screen_fixture.dart';

/// Keyboard-only coverage for the item catalog.
///
/// Every traversal, activation and shortcut here starts with a synthetic key
/// event: no test taps or otherwise uses the pointer to move focus.
void main() {
  late AppDatabase database;
  late CatalogRepository repository;
  late List<String> selectedIds;

  setUp(() async {
    database = await openCatalogFixtureDatabase();
    repository = CatalogRepository(database);
    selectedIds = <String>[];
  });

  tearDown(() => database.close());

  Future<void> pumpCatalog(
    WidgetTester tester, {
    int pageSize = 50,
    Size size = const Size(1200, 1200),
    UpstreamCheck? upstreamCheck,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: CatalogScreen(
          repository: repository,
          pageSize: pageSize,
          categories: fixtureCategories,
          types: fixtureTypes,
          onItemSelected: selectedIds.add,
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
      find.byKey(const Key('catalog-search-field')),
    );
    return field.focusNode?.hasFocus ?? false;
  }

  group('focus traversal', () {
    testWidgets('Tab walks controls and rows in visual order', (tester) async {
      await pumpCatalog(tester, pageSize: 5);

      await pressTab(tester);
      expect(
        searchHasFocus(tester),
        isTrue,
        reason: 'search is the first stop',
      );

      await pressTab(tester);
      expect(holdsFocus(tester, const Key('catalog-sort-focus')), isTrue);

      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('catalog-category-filter-focus')),
        isTrue,
      );

      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('catalog-type-filter-focus')),
        isTrue,
      );

      await pressTab(tester);
      expect(
        holdsFocus(tester, const Key('catalog-flea-filter-focus')),
        isTrue,
      );

      final firstRow = tester.widget<CatalogTableRow>(
        find.byType(CatalogTableRow).first,
      );
      await pressTab(tester);
      expect(
        holdsFocus(tester, ValueKey('catalog-row-focus-${firstRow.item.id}')),
        isTrue,
      );

      final secondRow = tester.widget<CatalogTableRow>(
        find.byType(CatalogTableRow).at(1),
      );
      await pressTab(tester);
      expect(
        holdsFocus(tester, ValueKey('catalog-row-focus-${secondRow.item.id}')),
        isTrue,
      );

      for (var index = 2; index < 6; index++) {
        await pressTab(tester);
      }
      expect(holdsFocus(tester, const Key('catalog-load-more-focus')), isTrue);
    });

    testWidgets('Shift+Tab reverses the same order and wraps', (tester) async {
      await pumpCatalog(tester, pageSize: 5);

      await pressTab(tester);
      expect(searchHasFocus(tester), isTrue);

      await pressTab(tester, reverse: true);
      expect(holdsFocus(tester, const Key('catalog-load-more-focus')), isTrue);
    });

    testWidgets('a focused row is revealed inside the virtualised list', (
      tester,
    ) async {
      await pumpCatalog(tester, size: const Size(1200, 520));

      for (var index = 0; index < 5; index++) {
        await pressTab(tester);
      }
      // Five controls precede the rows; six more Tabs reach row index 5,
      // which starts below the visible window.
      for (var index = 0; index < 6; index++) {
        await pressTab(tester);
      }

      final rows = tester.widgetList<CatalogTableRow>(
        find.byType(CatalogTableRow),
      );
      final focusedRow = rows.lastWhere(
        (row) =>
            holdsFocus(tester, ValueKey('catalog-row-focus-${row.item.id}')),
        orElse: () => throw StateError('No row holds focus after Tab.'),
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const Key('catalog-list')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(focusedRow.item.id, isNotEmpty);
      expect(scrollable.position.pixels, greaterThan(0));
    });
  });

  group('activation', () {
    testWidgets('Enter opens the focused row and Space opens the next', (
      tester,
    ) async {
      await pumpCatalog(tester, pageSize: 5);
      for (var index = 0; index < 6; index++) {
        await pressTab(tester);
      }

      final firstRow = tester.widget<CatalogTableRow>(
        find.byType(CatalogTableRow).first,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selectedIds, <String>[firstRow.item.id]);

      await pressTab(tester);
      final secondRow = tester.widget<CatalogTableRow>(
        find.byType(CatalogTableRow).at(1),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(selectedIds, <String>[firstRow.item.id, secondRow.item.id]);
    });

    testWidgets('Enter activates a focused filter chip', (tester) async {
      await pumpCatalog(tester);

      // Search, sort, category and type precede the flea chip.
      for (var index = 0; index < 5; index++) {
        await pressTab(tester);
      }
      expect(
        holdsFocus(tester, const Key('catalog-flea-filter-focus')),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('Flea eligible'), findsWidgets);
      expect(find.text('Showing 11 of 11 items'), findsOneWidget);
    });

    testWidgets('the offline retry strip is reachable and activates', (
      tester,
    ) async {
      var checks = 0;
      Future<UpstreamStatus> failing() async {
        checks++;
        return const UpstreamStatus.offline();
      }

      await pumpCatalog(tester, upstreamCheck: failing);
      expect(checks, 1);

      for (var index = 0; index < 6; index++) {
        await pressTab(tester);
      }
      expect(
        holdsFocus(tester, const Key('catalog-upstream-retry-focus')),
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(checks, 2);
      expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);
    });
  });

  group('shortcuts', () {
    testWidgets('/ focuses search, Escape clears and returns focus', (
      tester,
    ) async {
      await pumpCatalog(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pumpAndSettle();
      expect(searchHasFocus(tester), isTrue);

      await tester.enterText(
        find.byKey(const Key('catalog-search-field')),
        'm4a1',
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('catalog-search-field')),
      );
      expect(field.controller?.text, isEmpty);
      expect(field.focusNode?.hasFocus, isFalse);
      expect(holdsFocus(tester, const Key('catalog-screen-focus')), isTrue);
    });
  });

  group('visible focus', () {
    testWidgets('the row ring uses the focus tokens', (tester) async {
      await pumpCatalog(tester, pageSize: 5);
      for (var index = 0; index < 6; index++) {
        await pressTab(tester);
      }

      final row = tester.widget<CatalogTableRow>(
        find.byType(CatalogTableRow).first,
      );
      final ring = tester.widget<DecoratedBox>(
        find.byKey(ValueKey('catalog-row-focus-ring-${row.item.id}')),
      );
      final decoration = ring.decoration as BoxDecoration;
      final border = decoration.border! as Border;
      const tokens = AppTokens.phosphor();

      expect(border.top.color, tokens.focusRing);
      expect(border.top.width, tokens.focusRingWidth);
    });
  });
}
