import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/catalog_screen_fixture.dart';

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
    Size size = const Size(1440, 900),
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

  testWidgets('initial load renders rows and the total count', (tester) async {
    await pumpCatalog(tester);

    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);
    expect(find.text('0.75 kg'), findsOneWidget);
    expect(find.text('40,000 ₽'), findsOneWidget);
    expect(find.text('BASE 18,397 ₽'), findsOneWidget);
    expect(find.text('+22.0%'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('typing is debounced and then filters the list', (tester) async {
    await pumpCatalog(tester);

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'm4a1',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 299));

    // The query has not been sent yet: the full catalog is still on screen.
    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
    expect(
      find.text('Kalashnikov AK-74N 5.45x39 assault rifle'),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();

    expect(find.text('Showing 2 of 2 items'), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);
    expect(find.text('M4A1 5.56x45 upper receiver'), findsOneWidget);
    expect(find.text('Kalashnikov AK-74N 5.45x39 assault rifle'), findsNothing);
    expect(find.byKey(const Key('catalog-filter-chip-text')), findsOneWidget);
  });

  testWidgets('category, type and flea chips apply and clear individually', (
    tester,
  ) async {
    await pumpCatalog(tester);

    await selectDropdown(tester, 'catalog-category-filter', 'Meds');
    expect(find.text('Showing 3 of 3 items'), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-filter-chip-category')),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('catalog-filter-chip-category')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing 12 of 12 items'), findsOneWidget);

    await selectDropdown(tester, 'catalog-type-filter', 'Gun');
    expect(find.text('Showing 2 of 2 items'), findsOneWidget);
    expect(find.byKey(const Key('catalog-filter-chip-type')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('catalog-filter-chip-type')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing 12 of 12 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-flea-filter')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 11 of 11 items'), findsOneWidget);
    expect(find.byKey(const Key('catalog-filter-chip-flea')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('catalog-filter-chip-flea')),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
  });

  testWidgets('combined filters narrow, and reset restores the full list', (
    tester,
  ) async {
    await pumpCatalog(tester);

    await selectDropdown(tester, 'catalog-category-filter', 'Gear');
    await selectDropdown(tester, 'catalog-type-filter', 'Armor');
    await tester.tap(find.byKey(const Key('catalog-flea-filter')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 1 items'), findsOneWidget);
    expect(find.text('FORT Kiver-M bulletproof helmet'), findsOneWidget);
    expect(
      find.byKey(const Key('catalog-filter-chip-category')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('catalog-filter-chip-type')), findsOneWidget);
    expect(find.byKey(const Key('catalog-filter-chip-flea')), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-reset-filters')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
    expect(find.byKey(const Key('catalog-filter-chip-category')), findsNothing);
    expect(find.byKey(const Key('catalog-filter-chip-type')), findsNothing);
    expect(find.byKey(const Key('catalog-filter-chip-flea')), findsNothing);
  });

  testWidgets('no match shows the query in an explicit empty state', (
    tester,
  ) async {
    await pumpCatalog(tester);

    await tester.enterText(
      find.byKey(const Key('catalog-search-field')),
      'zzzz',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('Showing 0 of 0 items'), findsOneWidget);
    expect(find.text('No items match "zzzz".'), findsOneWidget);
    expect(find.byKey(const Key('catalog-empty-reset')), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-empty-reset')));
    await tester.pumpAndSettle();

    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('catalog-search-field')))
          .controller
          ?.text,
      isEmpty,
    );
    expect(find.text('No items match "zzzz".'), findsNothing);
  });

  testWidgets('sorting by flea price changes the row order and direction', (
    tester,
  ) async {
    await pumpCatalog(tester);

    await selectDropdown(tester, 'catalog-sort-field', 'Flea price');

    expect(find.text('500 ₽'), findsOneWidget);
    expect(find.text('6,000 ₽'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('500 ₽')).dy,
      lessThan(tester.getTopLeft(find.text('6,000 ₽')).dy),
    );

    await tester.tap(find.byKey(const Key('catalog-sort-direction')));
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('50,000 ₽')).dy,
      lessThan(tester.getTopLeft(find.text('40,000 ₽')).dy),
    );
  });

  testWidgets('pagination appends a page with the load-more control', (
    tester,
  ) async {
    await pumpCatalog(tester, pageSize: 5, size: const Size(1440, 1600));

    expect(find.text('Showing 5 of 12 items'), findsOneWidget);
    expect(find.byKey(const Key('catalog-loaded-count')), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 10 of 12 items'), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog-load-more')));
    await tester.pumpAndSettle();
    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
    expect(find.byKey(const Key('catalog-load-more')), findsNothing);
  });

  testWidgets('tapping a row reports the item id', (tester) async {
    await pumpCatalog(tester);

    await tester.tap(find.text('Colt M4A1 5.56x45 assault rifle'));
    await tester.pump();

    expect(selectedIds, ['item-colt']);
  });

  group('layout helpers', () {
    test('breakpoints separate compact, standard and wide', () {
      expect(catalogLayoutForWidth(1099), CatalogLayout.compact);
      expect(catalogLayoutForWidth(1100), CatalogLayout.standard);
      expect(catalogLayoutForWidth(1599), CatalogLayout.standard);
      expect(catalogLayoutForWidth(1600), CatalogLayout.wide);
    });

    test('observation age is coarse, signed and null-safe', () {
      final now = DateTime.utc(2026, 11, 27, 12);
      expect(formatObservationAge(null, now: now), '—');
      expect(
        formatObservationAge(
          now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        'now',
      );
      expect(
        formatObservationAge(
          now.subtract(const Duration(minutes: 12)),
          now: now,
        ),
        '12m',
      );
      expect(
        formatObservationAge(now.subtract(const Duration(hours: 4)), now: now),
        '4h',
      );
      expect(
        formatObservationAge(now.subtract(const Duration(days: 3)), now: now),
        '3d',
      );
    });
  });

  group('responsive table', () {
    testWidgets('1440 shows the five-column header and table rows', (
      tester,
    ) async {
      await pumpCatalog(tester);

      final header = find.byKey(const Key('catalog-table-header'));
      expect(header, findsOneWidget);
      for (final label in ['ITEM', 'FLEA', '24H', 'WEIGHT', 'SLOTS']) {
        expect(
          find.descendant(of: header, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.text('OBSERVED'), findsNothing);
      expect(find.byType(CatalogTableRow), findsWidgets);
      expect(find.byType(CatalogItemRow), findsNothing);

      final row = tester.widget<CatalogTableRow>(
        find.byType(CatalogTableRow).first,
      );
      expect(row.layout, CatalogLayout.standard);
    });

    testWidgets('1920 adds the observed column and a wider item cell', (
      tester,
    ) async {
      await pumpCatalog(tester, size: const Size(1440, 900));
      final standardCell = tester
          .getSize(find.byKey(const ValueKey('catalog-row-item-item-m855')))
          .width;

      await pumpCatalog(tester, size: const Size(1920, 1080));

      final header = find.byKey(const Key('catalog-table-header'));
      expect(
        find.descendant(of: header, matching: find.text('OBSERVED')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('catalog-row-observed-item-m855')),
        findsOneWidget,
      );
      final row = tester.widget<CatalogTableRow>(
        find.byType(CatalogTableRow).first,
      );
      expect(row.layout, CatalogLayout.wide);
      final wideCell = tester
          .getSize(find.byKey(const ValueKey('catalog-row-item-item-m855')))
          .width;
      expect(wideCell, greaterThan(standardCell));
    });

    testWidgets('below 1100 drops the header for compact card rows', (
      tester,
    ) async {
      await pumpCatalog(tester, size: const Size(900, 900));

      expect(find.byKey(const Key('catalog-table-header')), findsNothing);
      expect(find.byType(CatalogItemRow), findsWidgets);
      expect(find.byType(CatalogTableRow), findsNothing);

      await tester.tap(find.text('Colt M4A1 5.56x45 assault rifle'));
      await tester.pump();
      expect(selectedIds, ['item-colt']);
    });

    testWidgets('content width is capped on an ultra-wide window', (
      tester,
    ) async {
      await pumpCatalog(tester, size: const Size(2560, 1440));

      final content = find.byKey(const Key('catalog-content'));
      expect(tester.getSize(content).width, CatalogScreen.maxContentWidth);
      expect(
        find.descendant(
          of: find.byKey(const Key('catalog-table-header')),
          matching: find.text('OBSERVED'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('table rows alternate their resting surface', (tester) async {
      await pumpCatalog(tester);
      final tokens = Theme.of(tester.element(find.byType(CatalogScreen)))
          .extension<AppTokens>()!;

      Color? surfaceFor(String id) {
        final container = tester.widget<Container>(
          find.byKey(ValueKey('catalog-row-surface-$id')),
        );
        return (container.decoration! as BoxDecoration).color;
      }

      // Default repository order is name ascending: M855 is row 0, PMAG row 1.
      expect(surfaceFor('item-m855'), tokens.surface);
      expect(surfaceFor('item-pmag'), tokens.background);
    });
  });
}
