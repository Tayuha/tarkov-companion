import '../database/app_database.dart';
import 'price_freshness.dart';

/// Read-side queries over the `items` catalog table.
///
/// The catalog screens (task 5.x) and the detail view own presentation; this
/// repository only answers data questions so they stay unit-testable without a
/// widget tree.
final class ItemsRepository {
  const ItemsRepository(this._database);

  final AppDatabase _database;

  /// The freshness of [itemId]'s newest price observation at [now].
  ///
  /// Reads `items.priceObservedAt` — the bundle's `price.observedAt`, not the
  /// time the dataset was applied — and evaluates it with [policy]. A missing
  /// item and an item without a price observation both return
  /// [PriceFreshness.unknown]: the UI must not present either as current.
  ///
  /// [now] is supplied by the caller so the verdict is deterministic in tests
  /// and reproducible when several fields are evaluated against one clock read.
  Future<PriceFreshness> priceFreshness(
    String itemId,
    FreshnessPolicy policy,
    DateTime now,
  ) async {
    final row =
        await (_database.selectOnly(_database.items)
              ..addColumns([_database.items.priceObservedAt])
              ..where(_database.items.id.equals(itemId)))
            .getSingleOrNull();
    final observedAt = row?.read(_database.items.priceObservedAt);
    return policy.evaluate(observedAt, now);
  }
}
