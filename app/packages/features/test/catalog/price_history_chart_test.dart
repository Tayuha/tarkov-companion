import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../theme/support/load_fonts.dart';

PriceHistoryPoint _point(int hoursAgo, int price) => PriceHistoryPoint(
  observedAt: DateTime.utc(
    2026,
    11,
    27,
    12,
  ).subtract(Duration(hours: hoursAgo)),
  price: price,
  priceMin: price,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadDesignFonts();
  });

  Future<void> pumpChart(
    WidgetTester tester,
    PriceHistorySnapshot snapshot,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              child: PriceHistoryChart(snapshot: snapshot),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unavailable state names offline and the missing cache', (
    tester,
  ) async {
    await pumpChart(tester, const PriceHistorySnapshot.unavailable('item-1'));

    expect(find.byKey(const Key('price-history-unavailable')), findsOneWidget);
    expect(
      find.textContaining('Price history unavailable offline'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('price-history-chart')), findsNothing);
  });

  testWidgets('a populated snapshot draws the plot and its figures', (
    tester,
  ) async {
    final points = [_point(2, 12000), _point(1, 14000), _point(0, 15000)];
    await pumpChart(
      tester,
      PriceHistorySnapshot(
        itemId: 'item-1',
        points: points,
        status: PriceHistoryStatus.network,
        observedAt: points.last.observedAt,
      ),
    );

    expect(find.byKey(const Key('price-history-chart')), findsOneWidget);
    expect(find.byKey(const Key('price-history-plot')), findsOneWidget);
    expect(find.text('15,000 ₽'), findsNWidgets(2));
    expect(find.text('12,000 ₽'), findsOneWidget);
    expect(find.byKey(const Key('price-history-delta')), findsOneWidget);
    expect(find.text('+3,000 ₽ over 3 observations'), findsOneWidget);
    expect(
      find.text('2026-11-27 10:00 UTC → 2026-11-27 12:00 UTC'),
      findsOneWidget,
    );
  });

  testWidgets('a stale snapshot keeps the chart and labels the fallback', (
    tester,
  ) async {
    final points = [_point(1, 14000), _point(0, 15000)];
    await pumpChart(
      tester,
      PriceHistorySnapshot(
        itemId: 'item-1',
        points: points,
        status: PriceHistoryStatus.stale,
        observedAt: points.last.observedAt,
      ),
    );

    expect(find.byKey(const Key('price-history-plot')), findsOneWidget);
    expect(find.byKey(const Key('price-history-stale')), findsOneWidget);
  });

  testWidgets('a single observation explains why there is no line', (
    tester,
  ) async {
    await pumpChart(
      tester,
      PriceHistorySnapshot(
        itemId: 'item-1',
        points: [_point(0, 15000)],
        status: PriceHistoryStatus.cached,
        observedAt: DateTime.utc(2026, 11, 27, 12),
      ),
    );

    expect(find.byKey(const Key('price-history-single-point')), findsOneWidget);
    expect(find.byKey(const Key('price-history-plot')), findsNothing);
  });
}
