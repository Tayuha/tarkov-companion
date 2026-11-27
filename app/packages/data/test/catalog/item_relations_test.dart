import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/catalog_fixture.dart';
import '../support/database_helpers.dart';

/// Real ids from the committed normalized fixtures.
const _salewa = '544fb45d4bdc2dee738b4568';
const _factoryKey = '5448ba0b4bdc2d02308b456c';
const _therapist = '54cb57776803fa99248b456e';
const buyOfferUnlockId = '596760e186f7741e11214d58';

void main() {
  late AppDatabase db;
  late Directory temporary;
  late CatalogRepository repository;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
    repository = CatalogRepository(db);
    for (final kind in [
      DatasetKind.items,
      DatasetKind.traders,
      DatasetKind.hideout,
      DatasetKind.barters,
      DatasetKind.crafts,
      DatasetKind.tasks,
    ]) {
      await ingestNormalizedDataset(db, temporary, kind);
    }
  });

  tearDown(() => db.close());

  test(
    'trader buy and sell rows resolve names from the traders dataset',
    () async {
      final relations = await repository.itemRelations(_salewa);

      expect(relations, isNotNull);
      expect(relations!.buyOffers, hasLength(1));
      final buy = relations.buyOffers.single;
      expect(buy.traderName, 'Therapist');
      expect(buy.price, 37126);
      expect(buy.currency, 'RUB');
      expect(buy.taskUnlockId, '596760e186f7741e11214d58');

      expect(relations.sellOffers, hasLength(4));
      expect(
        relations.sellOffers.map((offer) => offer.traderName),
        contains('Therapist'),
      );
      expect(
        relations.sellOffers.map((offer) => offer.traderId),
        contains(_therapist),
      );
    },
  );

  test('a craft producing the item resolves its station name', () async {
    final relations = await repository.itemRelations(_salewa);

    expect(relations, isNotNull);
    expect(relations!.crafts, hasLength(1));
    final craft = relations.crafts.single;
    expect(craft.product.itemId, _salewa);
    expect(craft.product.count, 1);
    expect(craft.stationName, isNotEmpty);
    expect(craft.stationName, isNot(craft.stationId));
    expect(craft.durationSeconds, greaterThan(0));
    expect(craft.requiredItems, isNotEmpty);
    expect(
      craft.requiredItems.every((required) => required.name.isNotEmpty),
      isTrue,
    );
  });

  test('quest objectives naming the item become requirement links', () async {
    final relations = await repository.itemRelations(_salewa);

    expect(relations, isNotNull);
    final quests = relations!.quests;
    expect(quests, isNotEmpty);
    expect(quests.map((quest) => quest.questName), contains('Shortage'));
    expect(
      quests
          .where((quest) => quest.kind == QuestRequirementKind.objective)
          .map((quest) => quest.detail),
      containsAll([
        'Find the item in raid: Salewa first aid kit',
        'Hand over the items',
      ]),
    );
    expect(
      quests.map((quest) => quest.questId),
      contains('5967733e86f774602332fc84'),
    );
    final unlock = quests.singleWhere(
      (quest) => quest.kind == QuestRequirementKind.purchaseUnlock,
    );
    expect(unlock.questId, buyOfferUnlockId);
    expect(unlock.detail, 'Unlocks a trader purchase');
    expect(unlock.questName, isNot(unlock.questId));
  });

  test('a barter appears as acquisition and as an input use', () async {
    final relations = await repository.itemRelations(_factoryKey);

    expect(relations, isNotNull);
    expect(relations!.barters, hasLength(1));
    expect(relations.bartersUsing, hasLength(1));
    final barter = relations.barters.single;
    expect(barter.offeredItem.itemId, _factoryKey);
    expect(
      barter.requiredItems.map((item) => item.itemId),
      contains(_factoryKey),
    );
    expect(barter.traderName, isNotEmpty);
    expect(barter.requiredItems.every((item) => item.name.isNotEmpty), isTrue);
    expect(relations.sellOffers, isNotEmpty);
  });

  test('an item without relation rows returns empty lists, not null', () async {
    await db.customStatement(
      'INSERT INTO items (id, name, shortName, normalizedName, payload) '
      "VALUES ('lonely', 'Lonely item', 'Lonely', 'lonely-item', "
      "'{\"id\":\"lonely\",\"kind\":\"item\"}')",
    );

    final relations = await repository.itemRelations('lonely');

    expect(relations, isNotNull);
    expect(relations!.isEmpty, isTrue);
    expect(relations.buyOffers, isEmpty);
    expect(relations.barters, isEmpty);
    expect(relations.crafts, isEmpty);
    expect(relations.quests, isEmpty);
  });

  test('an unknown or blank item returns null', () async {
    expect(await repository.itemRelations('does-not-exist'), isNull);
    expect(await repository.itemRelations('  '), isNull);
  });
}
