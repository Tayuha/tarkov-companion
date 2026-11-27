/// Acquisition and disposition relationships of one item.
///
/// These records are derived from the applied bundle datasets, not from a
/// fixture-only model:
///
/// * trader offers come from the item's own `buyFromTrader` / `sellToTrader`
///   records (the pipeline's projection of the trader assortment);
/// * barters come from the `barters` dataset;
/// * crafts come from the `crafts` dataset;
/// * quest requirements come from the `tasks`/`taskObjectives` records that
///   name the item in an objective, plus a trader offer's `taskUnlockId`.
///
/// A relationship that is absent from the applied bundle is absent here: the
/// screen omits the row instead of rendering a placeholder. See
/// `docs/item-detail.md` for the current dataset coverage.
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';

/// Everything the detail screen needs for the acquisition and disposition
/// sections.
final class ItemRelations {
  const ItemRelations({
    required this.buyOffers,
    required this.sellOffers,
    required this.barters,
    required this.bartersUsing,
    required this.crafts,
    required this.craftsUsing,
    required this.quests,
  });

  /// No relations at all; every section is omitted.
  static const empty = ItemRelations(
    buyOffers: [],
    sellOffers: [],
    barters: [],
    bartersUsing: [],
    crafts: [],
    craftsUsing: [],
    quests: [],
  );

  /// Trader offers that sell this item to the player.
  final List<TraderOffer> buyOffers;

  /// Trader offers that buy this item from the player.
  final List<TraderOffer> sellOffers;

  /// Barters whose offered item is this item.
  final List<BarterRelation> barters;

  /// Barters that consume this item as a required input.
  final List<BarterRelation> bartersUsing;

  /// Crafts whose product is this item.
  final List<CraftRelation> crafts;

  /// Crafts that consume this item as a required input.
  final List<CraftRelation> craftsUsing;

  /// Quests that require the item or unlock a trader offer for it.
  final List<QuestRequirement> quests;

  bool get isEmpty =>
      buyOffers.isEmpty &&
      sellOffers.isEmpty &&
      barters.isEmpty &&
      bartersUsing.isEmpty &&
      crafts.isEmpty &&
      craftsUsing.isEmpty &&
      quests.isEmpty;
}

/// A trader price row.
final class TraderOffer {
  const TraderOffer({
    required this.traderId,
    required this.traderName,
    required this.price,
    required this.currency,
    required this.loyaltyLevel,
    required this.buyLimit,
    required this.taskUnlockId,
    required this.taskUnlockName,
  });

  final String traderId;

  /// Display name from the `traders` table, falling back to [traderId].
  final String traderName;

  /// Price in [currency].
  final int price;

  /// Bundle currency code (`RUB`, `USD`, `EUR`).
  final String currency;

  /// Trader loyalty level required for the offer, when the bundle has one.
  final int? loyaltyLevel;

  /// Purchase limit per restock, when the bundle has one.
  final int? buyLimit;

  /// Quest that unlocks the offer, when the bundle names one.
  final String? taskUnlockId;

  /// Display name of [taskUnlockId] when the task is in the dataset.
  final String? taskUnlockName;
}

/// One barter trade.
final class BarterRelation {
  const BarterRelation({
    required this.id,
    required this.traderId,
    required this.traderName,
    required this.minTraderLevel,
    required this.buyLimit,
    required this.offeredItem,
    required this.requiredItems,
  });

  final String id;
  final String traderId;

  /// Display name from the `traders` table, falling back to [traderId].
  final String traderName;
  final int? minTraderLevel;
  final int? buyLimit;
  final ItemQuantity offeredItem;
  final List<ItemQuantity> requiredItems;
}

/// One hideout craft.
final class CraftRelation {
  const CraftRelation({
    required this.id,
    required this.stationId,
    required this.stationName,
    required this.durationSeconds,
    required this.level,
    required this.product,
    required this.requiredItems,
  });

  final String id;
  final String stationId;

  /// Display name from `hideoutStations`, falling back to [stationId].
  final String stationName;

  /// Craft duration in seconds.
  final int durationSeconds;

  /// Station level required by the craft.
  final int? level;
  final ItemQuantity product;
  final List<ItemQuantity> requiredItems;
}

/// An item and a count, with a display name resolved from the `items` table.
final class ItemQuantity {
  const ItemQuantity({
    required this.itemId,
    required this.name,
    required this.count,
  });

  final String itemId;

  /// Display name, falling back to [itemId] when the item is not in the
  /// current dataset.
  final String name;
  final int count;
}

/// Why a quest appears in the requirement list.
enum QuestRequirementKind {
  /// A task objective names the item.
  objective,

  /// A trader offer names the task that unlocks it.
  purchaseUnlock,
}

/// A quest that requires the item or gates a trader offer for it.
final class QuestRequirement {
  const QuestRequirement({
    required this.questId,
    required this.questName,
    required this.kind,
    required this.detail,
  });

  final String questId;

  /// Display name, falling back to [questId] when the task is absent.
  final String questName;
  final QuestRequirementKind kind;

  /// The objective description, or a short explanation for an unlock.
  final String? detail;
}

/// Reads acquisition and disposition relationships for one item.
///
/// The queries use the dedicated `barters`/`crafts`/`tasks` tables where they
/// exist and SQLite's JSON1 functions over the canonical `payload` only for the
/// nested arrays the schema does not flatten. A missing collection simply
/// yields no rows, so a partial bundle omits a section instead of inventing a
/// relationship.
final class ItemRelationsRepository {
  const ItemRelationsRepository(this._database);

  final AppDatabase _database;

  /// All relations for [itemId], or `null` when the item is not in the current
  /// dataset.
  Future<ItemRelations?> relations(String itemId) async {
    final id = itemId.trim();
    if (id.isEmpty) {
      return null;
    }

    final itemRow = await (_database.select(
      _database.items,
    )..where((item) => item.id.equals(id))).getSingleOrNull();
    if (itemRow == null) {
      return null;
    }

    final payload = _decode(itemRow.payload);
    final buyRaw = _maps(payload['buyFromTrader']);
    final sellRaw = _maps(payload['sellToTrader']);

    final barterRows = await _database
        .customSelect(
          'SELECT id, payload FROM barters '
          "WHERE json_extract(payload, '\$.offeredItem.itemId') = ? "
          'OR EXISTS (SELECT 1 FROM json_each(barters.payload, '
          "'\$.requiredItems') required "
          "WHERE json_extract(required.value, '\$.itemId') = ?)",
          variables: [Variable<String>(id), Variable<String>(id)],
        )
        .get();
    final craftRows = await _database
        .customSelect(
          'SELECT id, payload FROM crafts '
          'WHERE productItemId = ? '
          'OR EXISTS (SELECT 1 FROM json_each(crafts.payload, '
          "'\$.requiredItems') required "
          "WHERE json_extract(required.value, '\$.itemId') = ?)",
          variables: [Variable<String>(id), Variable<String>(id)],
        )
        .get();
    final questRows = await _database
        .customSelect(
          'SELECT o.taskId AS taskId, o.description AS description, '
          't.name AS taskName '
          'FROM taskObjectives o JOIN tasks t ON t.id = o.taskId '
          'WHERE EXISTS (SELECT 1 FROM json_each(o.payload, '
          "'\$.itemIds') objective WHERE objective.value = ?)",
          variables: [Variable<String>(id)],
        )
        .get();

    final unlockIds = <String>{
      for (final offer in [...buyRaw, ...sellRaw])
        ?_text(offer['taskUnlockId']),
    };

    final traderIds = <String>{
      for (final offer in [...buyRaw, ...sellRaw]) ?_text(offer['traderId']),
      for (final row in barterRows)
        ?_text(_decode(row.read<String>('payload'))['traderId']),
    };

    final itemIds = <String>{};
    final barterPayloads = <Map<String, Object?>>[];
    for (final row in barterRows) {
      final record = _decode(row.read<String>('payload'));
      barterPayloads.add({'id': row.read<String>('id'), ...record});
      if (_map(record['offeredItem']) case final offered) {
        if (_text(offered['itemId']) case final itemId?) itemIds.add(itemId);
      }
      for (final required in _maps(record['requiredItems'])) {
        if (_text(required['itemId']) case final itemId?) itemIds.add(itemId);
      }
    }

    final craftPayloads = <Map<String, Object?>>[];
    for (final row in craftRows) {
      final record = _decode(row.read<String>('payload'));
      craftPayloads.add({'id': row.read<String>('id'), ...record});
      if (_map(record['productItem']) case final product) {
        if (_text(product['itemId']) case final itemId?) itemIds.add(itemId);
      }
      for (final required in _maps(record['requiredItems'])) {
        if (_text(required['itemId']) case final itemId?) itemIds.add(itemId);
      }
    }

    final stationIds = <String>{
      for (final record in craftPayloads) ?_text(record['stationId']),
    };
    final taskIds = <String>{
      for (final row in questRows) row.read<String>('taskId'),
      ...unlockIds,
    };

    final traders = await _names('traders', traderIds);
    final items = await _names('items', itemIds);
    final stations = await _names('hideoutStations', stationIds);
    final tasks = await _names('tasks', taskIds);

    TraderOffer offer(Map<String, Object?> raw) {
      final traderId = _text(raw['traderId']) ?? '';
      final unlockId = _text(raw['taskUnlockId']);
      return TraderOffer(
        traderId: traderId,
        traderName: traders[traderId] ?? traderId,
        price: _int(raw['price']) ?? 0,
        currency: _text(raw['currency']) ?? 'RUB',
        loyaltyLevel: _int(raw['loyaltyLevel']),
        buyLimit: _int(raw['buyLimit']),
        taskUnlockId: unlockId,
        taskUnlockName: unlockId == null ? null : tasks[unlockId],
      );
    }

    final barters = <BarterRelation>[];
    final bartersUsing = <BarterRelation>[];
    for (final record in barterPayloads) {
      final barter = BarterRelation(
        id: _text(record['id']) ?? '',
        traderId: _text(record['traderId']) ?? '',
        traderName:
            traders[_text(record['traderId']) ?? ''] ??
            _text(record['traderId']) ??
            '',
        minTraderLevel: _int(record['minTraderLevel']),
        buyLimit: _int(record['buyLimit']),
        offeredItem: _quantity(_map(record['offeredItem']), items),
        requiredItems: [
          for (final required in _maps(record['requiredItems']))
            _quantity(required, items),
        ],
      );
      if (barter.offeredItem.itemId == id) {
        barters.add(barter);
      }
      if (barter.requiredItems.any((required) => required.itemId == id)) {
        bartersUsing.add(barter);
      }
    }

    final crafts = <CraftRelation>[];
    final craftsUsing = <CraftRelation>[];
    for (final record in craftPayloads) {
      final stationId = _text(record['stationId']) ?? '';
      final craft = CraftRelation(
        id: _text(record['id']) ?? '',
        stationId: stationId,
        stationName: stations[stationId] ?? stationId,
        durationSeconds: _int(record['duration']) ?? 0,
        level: _int(record['level']),
        product: _quantity(_map(record['productItem']), items),
        requiredItems: [
          for (final required in _maps(record['requiredItems']))
            _quantity(required, items),
        ],
      );
      if (craft.product.itemId == id) {
        crafts.add(craft);
      }
      if (craft.requiredItems.any((required) => required.itemId == id)) {
        craftsUsing.add(craft);
      }
    }

    final quests = <QuestRequirement>[];
    final seenQuests = <String>{};
    for (final row in questRows) {
      final questId = row.read<String>('taskId');
      final detail = _text(row.read<String>('description'));
      if (!seenQuests.add('objective:$questId:${detail ?? ''}')) {
        continue;
      }
      quests.add(
        QuestRequirement(
          questId: questId,
          questName: row.read<String>('taskName'),
          kind: QuestRequirementKind.objective,
          detail: detail,
        ),
      );
    }
    for (final unlockId in unlockIds) {
      if (!seenQuests.add('unlock:$unlockId')) {
        continue;
      }
      final name = tasks[unlockId];
      quests.add(
        QuestRequirement(
          questId: unlockId,
          questName: name ?? unlockId,
          kind: QuestRequirementKind.purchaseUnlock,
          detail: 'Unlocks a trader purchase',
        ),
      );
    }

    quests.sort((a, b) {
      final byName = a.questName.toLowerCase().compareTo(
        b.questName.toLowerCase(),
      );
      return byName != 0 ? byName : a.questId.compareTo(b.questId);
    });
    barters.sort((a, b) => a.offeredItem.name.compareTo(b.offeredItem.name));
    bartersUsing.sort(
      (a, b) => a.offeredItem.name.compareTo(b.offeredItem.name),
    );
    crafts.sort((a, b) => a.stationName.compareTo(b.stationName));
    craftsUsing.sort((a, b) => a.product.name.compareTo(b.product.name));

    return ItemRelations(
      buyOffers: [for (final raw in buyRaw) offer(raw)],
      sellOffers: [for (final raw in sellRaw) offer(raw)],
      barters: List.unmodifiable(barters),
      bartersUsing: List.unmodifiable(bartersUsing),
      crafts: List.unmodifiable(crafts),
      craftsUsing: List.unmodifiable(craftsUsing),
      quests: List.unmodifiable(quests),
    );
  }

  /// Fetches `id -> name` for [ids] from one of the name-bearing tables, in
  /// one query.
  ///
  /// [table] is a compile-time constant chosen by this file, never caller
  /// input, so it is safe to interpolate into the statement.
  Future<Map<String, String>> _names(String table, Set<String> ids) async {
    if (ids.isEmpty) {
      return const {};
    }
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _database
        .customSelect(
          'SELECT id, name FROM $table WHERE id IN ($placeholders)',
          variables: [for (final id in ids) Variable<String>(id)],
        )
        .get();
    return {
      for (final row in rows) row.read<String>('id'): row.read<String>('name'),
    };
  }
}

ItemQuantity _quantity(Map<String, Object?> raw, Map<String, String> names) {
  final itemId = _text(raw['itemId']) ?? '';
  return ItemQuantity(
    itemId: itemId,
    name: names[itemId] ?? itemId,
    count: _int(raw['count']) ?? 1,
  );
}

Map<String, Object?> _decode(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
  } on FormatException {
    // A corrupt record contributes no relationship; the detail payload parse
    // is what surfaces a corrupt item to the user.
  }
  return const {};
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return const {};
}

List<Map<String, Object?>> _maps(Object? value) => [
  for (final entry in value is List ? value : const [])
    if (entry is Map<String, Object?>) entry,
];

String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return null;
}
