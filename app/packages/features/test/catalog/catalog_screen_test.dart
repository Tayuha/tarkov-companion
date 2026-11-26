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

  Future<void> pumpCatalog(WidgetTester tester, {int pageSize = 50}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
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
    expect(find.textContaining('0.75 kg'), findsOneWidget);
    expect(find.text('40,000 ₽'), findsOneWidget);
    expect(find.text('base 18,397 ₽'), findsOneWidget);
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
    await pumpCatalog(tester, pageSize: 5);

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
}
