import 'dart:convert';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// Stable ids for the item detail screen tests.
const weaponItemId = 'detail-weapon';
const ammunitionItemId = 'detail-ammo';
const armorItemId = 'detail-armor';
const barterItemId = 'detail-barter';
const medicalItemId = 'detail-medkit';

/// One hand-written bundle item.
///
/// The map is stored verbatim as the canonical payload, so the repository
/// parses exactly the shape a published bundle has instead of a test-only
/// flattening.
final class DetailFixtureItem {
  const DetailFixtureItem({
    required this.id,
    required this.name,
    required this.shortName,
    required this.types,
    required this.categoryIds,
    this.handbookCategoryIds = const [],
    this.weight,
    this.width,
    this.height,
    this.record = const {},
  });

  final String id;
  final String name;
  final String shortName;
  final List<String> types;
  final List<String> categoryIds;
  final List<String> handbookCategoryIds;
  final double? weight;
  final int? width;
  final int? height;

  /// Extra bundle fields (`properties`, links, description, ...).
  final Map<String, Object?> record;
}

const _categories = <String, String>{
  'cat-weapons': 'Weapon',
  'cat-rifles': 'Assault rifle',
  'cat-ammo': 'Ammo',
  'cat-armor': 'Armor',
  'cat-barter': 'Barter items',
  'cat-meds': 'Meds',
};

const fixtureDetailItems = <DetailFixtureItem>[
  DetailFixtureItem(
    id: weaponItemId,
    name: 'Colt M4A1 5.56x45 assault rifle',
    shortName: 'M4A1',
    types: ['gun', 'wearable'],
    categoryIds: ['cat-weapons', 'cat-rifles'],
    weight: 3.4,
    width: 5,
    height: 2,
    record: {
      'description':
          'The Colt M4A1 carbine is a fully automatic variant of the basic '
          'M4 Carbine.',
      'wikiLink': 'https://escapefromtarkov.fandom.com/wiki/Colt_M4A1_5.56x45_assault_rifle',
      'link': 'https://tarkov.dev/item/colt-m4a1-556x45-assault-rifle',
      'stackMaxSize': 1,
      'conflictingItemIds': [],
      'conflictingSlotIds': [],
      'properties': {
        'propertiesType': 'ItemPropertiesWeapon',
        'caliber': 'Caliber556x45NATO',
        'fireRate': 800,
        'ergonomics': 48,
        'recoilVertical': 119,
        'recoilHorizontal': 342,
        'effectiveDistance': 500,
        'fireModes': ['Single fire', 'Full auto'],
        'slots': [
          {'id': 'slot-grip', 'name': 'Pistol Grip', 'required': true},
          {'id': 'slot-mag', 'name': 'Magazine', 'required': false},
        ],
      },
    },
  ),
  DetailFixtureItem(
    id: ammunitionItemId,
    name: '5.56x45mm M855',
    shortName: 'M855',
    types: ['ammo'],
    categoryIds: ['cat-ammo'],
    weight: 0.012,
    width: 1,
    height: 1,
    record: {
      'description':
          'A 5.56x45mm NATO M855 cartridge with a steel penetrator tip.',
      'wikiLink': 'https://escapefromtarkov.fandom.com/wiki/5.56x45mm_M855',
      'link': 'https://tarkov.dev/item/556x45mm-m855',
      'stackMaxSize': 80,
      'properties': {
        'propertiesType': 'ItemPropertiesAmmo',
        'caliber': 'Caliber556x45NATO',
        'damage': 54,
        'penetrationPower': 31,
        'armorDamage': 37,
      },
    },
  ),
  DetailFixtureItem(
    id: armorItemId,
    name: '6B43 Zabralo-Sh body armor (EMR)',
    shortName: '6B43',
    types: ['armor', 'wearable'],
    categoryIds: ['cat-armor'],
    weight: 10.8,
    width: 4,
    height: 4,
    record: {
      'description':
          'The 6B43 bulletproof vest is designed for protection from light '
          'weapon bullets.',
      'wikiLink': 'https://escapefromtarkov.fandom.com/wiki/6B43_Zabralo-Sh_body_armor_(EMR)',
      'link': 'https://tarkov.dev/item/6b43-zabralo-sh-body-armor-emr',
      'stackMaxSize': 1,
      'properties': {
        'propertiesType': 'ItemPropertiesArmor',
        'class': 6,
        'durability': 510,
        'material': 'Aramid',
        'armorType': 'Heavy',
        'zones': ['Front plate', 'Back plate', 'Stomach', 'Thorax'],
      },
    },
  ),
  DetailFixtureItem(
    id: barterItemId,
    name: 'Leatherman Multitool',
    shortName: 'MultiTool',
    types: ['barter', 'specialSlot'],
    categoryIds: ['cat-barter'],
    weight: 0.142,
    width: 1,
    height: 1,
    record: {
      'description':
          'With this compact and versatile multitool there is no need to be '
          'worried about having no tools on you at the right time.',
      'wikiLink':
          'https://escapefromtarkov.fandom.com/wiki/Leatherman_Multitool',
      'link': 'https://tarkov.dev/item/leatherman-multitool',
      'stackMaxSize': 1,
      'properties': null,
    },
  ),
  DetailFixtureItem(
    id: medicalItemId,
    name: 'Salewa first aid kit',
    shortName: 'SALEWA',
    types: ['meds'],
    categoryIds: ['cat-meds'],
    weight: 0.6,
    width: 1,
    height: 2,
    record: {
      'description': 'A first aid kit containing a bivibag and bandages.',
      'wikiLink':
          'https://escapefromtarkov.fandom.com/wiki/Salewa_first_aid_kit',
      'link': 'https://tarkov.dev/item/salewa-first-aid-kit',
      'stackMaxSize': 1,
      'properties': {
        'propertiesType': 'ItemPropertiesMedKit',
        'hitpoints': 400,
        'maxHealPerUse': 85,
        'cures': ['LightBleeding', 'HeavyBleeding'],
        'useTime': 3,
      },
    },
  ),
];

/// Opens an in-memory database seeded with [fixtureDetailItems].
Future<AppDatabase> openItemDetailFixtureDatabase() async {
  final database = AppDatabase.memory();
  await database.customSelect('SELECT 1').get(); // Force `beforeOpen`.
  await seedItemDetailFixture(database);
  return database;
}

/// Inserts the detail fixture with the same raw SQL shape ingestion writes.
Future<void> seedItemDetailFixture(AppDatabase database) async {
  for (final item in fixtureDetailItems) {
    final payload = <String, Object?>{
      'id': item.id,
      'kind': 'item',
      'name': item.name,
      'shortName': item.shortName,
      'types': item.types,
      'categoryIds': item.categoryIds,
      'handbookCategoryIds': item.handbookCategoryIds,
      'weight': item.weight,
      'width': item.width,
      'height': item.height,
      ...item.record,
    };
    await database.customStatement(
      'INSERT INTO items ('
      'id, name, shortName, normalizedName, weight, width, height, payload'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        item.id,
        item.name,
        item.shortName,
        _normalize(item.name),
        item.weight,
        item.width,
        item.height,
        jsonEncode(payload),
      ],
    );
    for (final type in item.types) {
      await database.customStatement(
        'INSERT INTO itemTypes (itemId, type) VALUES (?, ?)',
        [item.id, type],
      );
    }
    for (final categoryId in item.categoryIds) {
      await database.customStatement(
        'INSERT INTO itemCategories (itemId, categoryId, categoryKind) '
        'VALUES (?, ?, ?)',
        [item.id, categoryId, 'item'],
      );
    }
    for (final categoryId in item.handbookCategoryIds) {
      await database.customStatement(
        'INSERT INTO itemCategories (itemId, categoryId, categoryKind) '
        'VALUES (?, ?, ?)',
        [item.id, categoryId, 'handbook'],
      );
    }
  }

  for (final entry in _categories.entries) {
    await database.customStatement(
      'INSERT INTO gameRecords (kind, id, payload) VALUES (?, ?, ?)',
      [
        'itemCategory',
        entry.key,
        jsonEncode({
          'id': entry.key,
          'kind': 'itemCategory',
          'name': entry.value,
        }),
      ],
    );
  }
}

String _normalize(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
