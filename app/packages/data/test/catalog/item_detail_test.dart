import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/catalog_fixture.dart';
import '../support/database_helpers.dart';

/// Item ids from the committed normalized fixture.
const _m4a1 = '5447a9cd4bdc2dbd208b4567';
const _m855 = '54527a984bdc2d4e668b4567';
const _zabralo = '545cdb794bdc2d3a198b456a';
const _multitool = '544fb5454bdc2df8738b456a';

void main() {
  late AppDatabase db;
  late Directory temporary;
  late CatalogRepository repository;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
    repository = CatalogRepository(db);
  });

  tearDown(() => db.close());

  Future<void> ingestFixture() => ingestNormalizedItemsFixture(db, temporary);

  test('weapon detail exposes weapon properties and slots', () async {
    await ingestFixture();

    final detail = await repository.itemDetail(_m4a1);

    expect(detail, isNotNull);
    expect(detail!.name, 'Colt M4A1 5.56x45 assault rifle');
    expect(detail.shortName, 'M4A1');
    expect(detail.gridSize, '1 × 1');
    expect(detail.weight, closeTo(0.75, 0.001));
    expect(detail.types, containsAll(['gun', 'wearable']));
    expect(
      detail.categories.map((category) => category.name),
      contains('Weapon'),
    );
    expect(detail.wikiLink, startsWith('https://escapefromtarkov.fandom.com/'));
    expect(detail.description, isNotNull);

    final properties = detail.properties;
    expect(properties, isA<WeaponProperties>());
    properties as WeaponProperties;
    expect(properties.caliber, 'Caliber556x45NATO');
    expect(properties.fireRate, 800);
    expect(properties.ergonomics, 48);
    expect(properties.recoilVertical, 119);
    expect(properties.recoilHorizontal, 342);
    expect(properties.effectiveDistance, 500);
    expect(properties.fireModes, containsAll(['Single fire', 'Full auto']));
    expect(properties.slots, isNotEmpty);
    expect(
      properties.slots.map((slot) => slot.name),
      containsAll(['Pistol Grip', 'Magazine']),
    );
  });

  test('ammunition detail exposes ballistic properties', () async {
    await ingestFixture();

    final detail = await repository.itemDetail(_m855);

    expect(detail, isNotNull);
    final properties = detail!.properties;
    expect(properties, isA<AmmunitionProperties>());
    properties as AmmunitionProperties;
    expect(properties.caliber, 'Caliber556x45NATO');
    expect(properties.damage, 54);
    expect(properties.penetrationPower, 31);
    expect(properties.armorDamage, 37);
  });

  test('armor detail exposes class, durability, zones and material', () async {
    await ingestFixture();

    final detail = await repository.itemDetail(_zabralo);

    expect(detail, isNotNull);
    final properties = detail!.properties;
    expect(properties, isA<ArmorProperties>());
    properties as ArmorProperties;
    expect(properties.armorClass, 6);
    expect(properties.durability, 510);
    expect(properties.zones, containsAll(['Thorax', 'Stomach']));
    expect(properties.material, 'Aramid');
  });

  test('barter-only item falls back to the generic property set', () async {
    await ingestFixture();

    final detail = await repository.itemDetail(_multitool);

    expect(detail, isNotNull);
    expect(detail!.types, containsAll(['barter', 'specialSlot']));
    expect(detail.properties, isA<GenericProperties>());
    expect(
      detail.categories.map((category) => category.name),
      contains('Multitools'),
    );
    expect(detail.wikiLink, isNotNull);
  });

  test('an unknown or blank id returns null', () async {
    await ingestFixture();

    expect(await repository.itemDetail('does-not-exist'), isNull);
    expect(await repository.itemDetail('   '), isNull);
  });

  test(
    'a corrupt payload throws instead of returning partial detail',
    () async {
      await insertItem(db, id: 'broken', payload: 'not json');

      expect(
        () => repository.itemDetail('broken'),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
