/// On-demand flea price history and its local cache.
///
/// The published bundle has **no** price-history dataset: it carries only the
/// current `price` snapshot per item. The chart therefore fetches history from
/// an injectable [PriceHistorySource] and caches the result in the
/// `priceHistory` table. Until a documented history endpoint exists on the
/// network allowlist, the production app supplies no source and the chart
/// shows its unavailable state; tests use a fake source. See
/// `docs/item-detail.md` and `docs/freshness.md`.
library;

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// One observation on the flea-market price chart.
final class PriceHistoryPoint {
  const PriceHistoryPoint({
    required this.observedAt,
    required this.price,
    required this.priceMin,
  });

  /// When the observation was taken, in UTC.
  final DateTime observedAt;

  /// Lowest flea offer at that time, in roubles.
  final int price;

  /// Lowest offer across the window, when the source provides it.
  final int? priceMin;

  @override
  String toString() => 'PriceHistoryPoint($observedAt, $price)';
}

/// The network side of price history.
///
/// Implementations must not be called from tests over a real network: the data
/// package has no history endpoint in the bundle contract, and every test uses
/// a fake. The production app may only implement this over
/// `AllowlistedHttpClient` once a history host is added to the allowlist.
abstract interface class PriceHistorySource {
  /// Fetches observations for [itemId], in any order. An empty list is a valid
  /// answer (no known history).
  Future<List<PriceHistoryPoint>> fetch(String itemId);
}

/// Where a [PriceHistorySnapshot] came from.
enum PriceHistoryStatus {
  /// Fetched from the source during this call.
  network,

  /// Served from the cache and still inside its TTL.
  cached,

  /// Served from the cache after a failed refresh or while offline.
  stale,

  /// Neither the network nor the cache produced observations.
  unavailable,
}

/// The data the chart renders, plus why it is showing it.
final class PriceHistorySnapshot {
  const PriceHistorySnapshot({
    required this.itemId,
    required this.points,
    required this.status,
    required this.observedAt,
  });

  const PriceHistorySnapshot.unavailable(this.itemId)
    : points = const [],
      status = PriceHistoryStatus.unavailable,
      observedAt = null;

  final String itemId;

  /// Observations ordered oldest first.
  final List<PriceHistoryPoint> points;
  final PriceHistoryStatus status;

  /// Newest observation in [points], the cache's freshness marker.
  final DateTime? observedAt;

  bool get hasData => points.isNotEmpty;

  /// Whether the chart can draw a line.
  bool get isUnavailable => status == PriceHistoryStatus.unavailable;
}

/// Fetches price history on demand and caches it in `priceHistory`.
///
/// ## TTL
///
/// The cache TTL is measured from the newest stored observation — the
/// snapshot's own timestamp — because the bundle contract has no separate
/// fetch timestamp and this repository must not alter the schema for a cache.
/// A fetched snapshot whose newest point is older than [ttl] is therefore
/// immediately considered stale and will be refreshed on the next online
/// request; that is deliberate and documented in `docs/freshness.md`.
final class PriceHistoryRepository {
  PriceHistoryRepository(
    this._database, {
    required this.source,
    this.ttl = const Duration(hours: 6),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase _database;

  /// The network side of the fetch, injected so tests never touch a network.
  final PriceHistorySource source;

  /// How long a cached snapshot stays fresh.
  final Duration ttl;

  final DateTime Function() _clock;

  /// Loads history for [itemId].
  ///
  /// * a fresh cache is returned without touching the source;
  /// * [offline] never calls the source: a cache is returned as
  ///   [PriceHistoryStatus.stale] (or `cached` when still fresh), and no cache
  ///   yields [PriceHistoryStatus.unavailable];
  /// * an online refresh failure falls back to a stale cache when one exists,
  ///   and is otherwise unavailable — it never fabricates points.
  ///
  /// [forceRefresh] bypasses a fresh cache; the UI uses it for an explicit
  /// refresh action rather than on every rebuild.
  Future<PriceHistorySnapshot> load(
    String itemId, {
    bool offline = false,
    bool forceRefresh = false,
  }) async {
    final id = itemId.trim();
    if (id.isEmpty) {
      return const PriceHistorySnapshot.unavailable('');
    }

    final cached = await _read(id);
    final now = _clock().toUtc();
    final fresh = _isFresh(cached, now);

    if (offline) {
      if (cached.isEmpty) {
        return PriceHistorySnapshot.unavailable(id);
      }
      return PriceHistorySnapshot(
        itemId: id,
        points: cached,
        status: fresh ? PriceHistoryStatus.cached : PriceHistoryStatus.stale,
        observedAt: cached.last.observedAt,
      );
    }

    if (fresh && !forceRefresh) {
      return PriceHistorySnapshot(
        itemId: id,
        points: cached,
        status: PriceHistoryStatus.cached,
        observedAt: cached.last.observedAt,
      );
    }

    try {
      final fetched = await source.fetch(id);
      final points = _normalize(fetched);
      if (points.isEmpty) {
        if (cached.isNotEmpty) {
          return PriceHistorySnapshot(
            itemId: id,
            points: cached,
            status: PriceHistoryStatus.stale,
            observedAt: cached.last.observedAt,
          );
        }
        return PriceHistorySnapshot.unavailable(id);
      }
      await _store(id, points);
      return PriceHistorySnapshot(
        itemId: id,
        points: points,
        status: PriceHistoryStatus.network,
        observedAt: points.last.observedAt,
      );
    } on Object {
      if (cached.isEmpty) {
        return PriceHistorySnapshot.unavailable(id);
      }
      return PriceHistorySnapshot(
        itemId: id,
        points: cached,
        status: PriceHistoryStatus.stale,
        observedAt: cached.last.observedAt,
      );
    }
  }

  bool _isFresh(List<PriceHistoryPoint> points, DateTime now) {
    if (points.isEmpty) {
      return false;
    }
    final age = now.difference(points.last.observedAt.toUtc());
    return !age.isNegative && age <= ttl;
  }

  Future<List<PriceHistoryPoint>> _read(String itemId) async {
    final rows =
        await (_database.select(_database.priceHistory)
              ..where((row) => row.itemId.equals(itemId))
              ..orderBy([(row) => OrderingTerm.asc(row.observedAt)]))
            .get();
    return [
      for (final row in rows)
        PriceHistoryPoint(
          observedAt: row.observedAt.toUtc(),
          price: row.price,
          priceMin: row.priceMin,
        ),
    ];
  }

  Future<void> _store(String itemId, List<PriceHistoryPoint> points) async {
    await _database.transaction(() async {
      await (_database.delete(
        _database.priceHistory,
      )..where((row) => row.itemId.equals(itemId))).go();
      await _database.batch((batch) {
        batch.insertAll(_database.priceHistory, [
          for (final point in points)
            PriceHistoryCompanion.insert(
              itemId: itemId,
              observedAt: point.observedAt,
              price: point.price,
              priceMin: Value(point.priceMin),
            ),
        ]);
      });
    });
  }

  /// Deduplicates by observation instant, drops negative prices, and orders
  /// oldest first so the chart and the TTL agree.
  static List<PriceHistoryPoint> _normalize(List<PriceHistoryPoint> points) {
    final byInstant = <DateTime, PriceHistoryPoint>{};
    for (final point in points) {
      if (point.price < 0) {
        continue;
      }
      byInstant[point.observedAt.toUtc()] = point;
    }
    final ordered = byInstant.values.toList()
      ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
    return List.unmodifiable(ordered);
  }
}
