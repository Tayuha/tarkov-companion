import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';

final class _FakeSource implements PriceHistorySource {
  _FakeSource(this.points);

  List<PriceHistoryPoint> points;
  Object? error;
  int calls = 0;

  @override
  Future<List<PriceHistoryPoint>> fetch(String itemId) async {
    calls++;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return points;
  }
}

List<PriceHistoryPoint> _points(DateTime newest) => [
  PriceHistoryPoint(
    observedAt: newest.subtract(const Duration(hours: 2)),
    price: 12000,
    priceMin: 11000,
  ),
  PriceHistoryPoint(
    observedAt: newest.subtract(const Duration(hours: 1)),
    price: 14000,
    priceMin: 13000,
  ),
  PriceHistoryPoint(observedAt: newest, price: 15000, priceMin: 14500),
];

void main() {
  late AppDatabase db;
  late DateTime now;

  setUp(() async {
    db = await openMemoryDatabase();
    now = DateTime.utc(2026, 11, 27, 12);
  });

  tearDown(() => db.close());

  PriceHistoryRepository repository(PriceHistorySource source) =>
      PriceHistoryRepository(
        db,
        source: source,
        ttl: const Duration(hours: 6),
        clock: () => now,
      );

  test('a cold load fetches and stores the observations', () async {
    final source = _FakeSource(_points(now));
    final history = repository(source);

    final snapshot = await history.load('item-1');

    expect(snapshot.status, PriceHistoryStatus.network);
    expect(snapshot.points, hasLength(3));
    expect(snapshot.observedAt, now);
    expect(source.calls, 1);

    final rows = await db.select(db.priceHistory).get();
    expect(rows, hasLength(3));
    expect(rows.map((row) => row.price), containsAll([12000, 14000, 15000]));
  });

  test('a fresh cache is served without a second fetch', () async {
    final source = _FakeSource(_points(now));
    final history = repository(source);
    await history.load('item-1');

    final snapshot = await history.load('item-1');

    expect(snapshot.status, PriceHistoryStatus.cached);
    expect(snapshot.points, hasLength(3));
    expect(source.calls, 1);
  });

  test('a cache older than the TTL is refetched', () async {
    final source = _FakeSource(_points(now));
    final history = repository(source);
    await history.load('item-1');

    now = now.add(const Duration(hours: 7));
    source.points = _points(now);
    final snapshot = await history.load('item-1');

    expect(snapshot.status, PriceHistoryStatus.network);
    expect(source.calls, 2);
    expect(snapshot.observedAt, now);
    final rows = await db.select(db.priceHistory).get();
    expect(rows, hasLength(3));
  });

  test('offline without a cache is unavailable and never fetches', () async {
    final source = _FakeSource(_points(now));
    final history = repository(source);

    final snapshot = await history.load('item-1', offline: true);

    expect(snapshot.status, PriceHistoryStatus.unavailable);
    expect(snapshot.hasData, isFalse);
    expect(source.calls, 0);
  });

  test('offline with a cache returns the stored points', () async {
    final online = _FakeSource(_points(now));
    await repository(online).load('item-1');

    final failing = _FakeSource(const [])..error = StateError('offline');
    final snapshot = await repository(failing).load('item-1', offline: true);

    expect(snapshot.status, PriceHistoryStatus.cached);
    expect(snapshot.points, hasLength(3));
    expect(failing.calls, 0);
  });

  test('a failed refresh falls back to a stale cache', () async {
    final source = _FakeSource(_points(now));
    final history = repository(source);
    await history.load('item-1');

    now = now.add(const Duration(hours: 7));
    source.error = StateError('network down');
    final snapshot = await history.load('item-1');

    expect(snapshot.status, PriceHistoryStatus.stale);
    expect(snapshot.points, hasLength(3));
  });

  test('a failed refresh without a cache is unavailable', () async {
    final source = _FakeSource(const [])..error = StateError('network down');

    final snapshot = await repository(source).load('item-1');

    expect(snapshot.status, PriceHistoryStatus.unavailable);
    expect(snapshot.hasData, isFalse);
  });

  test(
    'blank id and negative prices are rejected, duplicates collapse',
    () async {
      final source = _FakeSource([
        ..._points(now),
        PriceHistoryPoint(
          observedAt: now.subtract(const Duration(hours: 1)),
          price: 99999,
          priceMin: null,
        ),
        PriceHistoryPoint(observedAt: now, price: -1, priceMin: null),
      ]);

      final snapshot = await repository(source).load('item-1');

      expect(snapshot.points, hasLength(3));
      expect(snapshot.points[1].price, 99999);
      expect(snapshot.points.every((point) => point.price >= 0), isTrue);

      final blank = await repository(source).load('  ');
      expect(blank.status, PriceHistoryStatus.unavailable);
    },
  );
}
