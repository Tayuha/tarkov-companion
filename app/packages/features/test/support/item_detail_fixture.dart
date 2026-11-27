import 'dart:convert';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// Stable ids for the item detail screen tests.
const weaponItemId = 'detail-weapon';
const ammunitionItemId = 'detail-ammo';
const armorItemId = 'detail-armor';
const barterItemId = 'detail-barter';
const medicalItemId = 'detail-medkit';
const relationsItemId = 'detail-relations';
const completePriceItemId = 'detail-price-complete';
const missingPriceItemId = 'detail-price-missing';
const zeroPriceItemId = 'detail-price-zero';

const _praporId = 'trader-prapor';
const _therapistId = 'trader-therapist';
const _workbenchId = 'station-workbench';
const _questId = 'quest-relations';

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
  DetailFixtureItem(
    id: relationsItemId,
    name: 'Expeditionary fuel tank',
    shortName: 'Fuel tank',
    types: ['barter'],
    categoryIds: ['cat-barter'],
    weight: 2.5,
    width: 3,
    height: 2,
    record: {
      'description': 'A metal fuel tank used in barter trades.',
      'iconLink': 'https://assets.tarkov.dev/fuel-tank-icon.webp',
      'stackMaxSize': 1,
      'properties': null,
      'buyFromTrader': [
        {
          'traderId': _praporId,
          'price': 22000,
          'currency': 'RUB',
          'loyaltyLevel': 2,
          'buyLimit': 3,
          'taskUnlockId': _questId,
        },
      ],
      'sellToTrader': [
        {'traderId': _therapistId, 'price': 9000, 'currency': 'RUB'},
      ],
    },
  ),
  DetailFixtureItem(
    id: completePriceItemId,
    name: 'Price complete item',
    shortName: 'PRICE',
    types: ['barter'],
    categoryIds: ['cat-barter'],
    record: {
      'basePrice': 18397,
      'price': {
        'lastLow': 40000,
        'avg24h': 111351,
        'change48h': 16102,
        'change48hPercent': 16.91,
        'observedAt': '2026-11-25T17:08:02.000Z',
      },
    },
  ),
  DetailFixtureItem(
    id: missingPriceItemId,
    name: 'Price missing item',
    shortName: 'NOPRICE',
    types: ['barter'],
    categoryIds: ['cat-barter'],
    record: {
      'price': {
        'observedAt': '2026-11-25T17:08:02.000Z',
        'lastLow': null,
        'avg24h': null,
      },
    },
  ),
  DetailFixtureItem(
    id: zeroPriceItemId,
    name: 'Price zero item',
    shortName: 'ZERO',
    types: ['barter'],
    categoryIds: ['cat-barter'],
    record: {
      'price': {
        'lastLow': 0,
        'avg24h': 0,
        'change48h': 0,
        'change48hPercent': 0,
        'observedAt': '2026-11-25T17:08:02.000Z',
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

  await _seedRelations(database);
}

/// Inserts the traders, barters, crafts and quests the relation sections read.
Future<void> _seedRelations(AppDatabase database) async {
  for (final trader in [
    {'id': _praporId, 'name': 'Prapor'},
    {'id': _therapistId, 'name': 'Therapist'},
  ]) {
    await database.customStatement(
      'INSERT INTO traders (id, name, normalizedName, payload) '
      'VALUES (?, ?, ?, ?)',
      [
        trader['id'],
        trader['name'],
        trader['name']!.toLowerCase(),
        jsonEncode({
          'id': trader['id'],
          'kind': 'trader',
          'name': trader['name'],
        }),
      ],
    );
  }

  await database.customStatement(
    'INSERT INTO hideoutStations (id, name, payload) VALUES (?, ?, ?)',
    [
      _workbenchId,
      'Workbench',
      jsonEncode({
        'id': _workbenchId,
        'kind': 'hideoutStation',
        'name': 'Workbench',
      }),
    ],
  );

  final barters = [
    {
      'id': 'barter-offer',
      'traderId': _praporId,
      'minTraderLevel': 2,
      'buyLimit': 3,
      'offeredItem': {'itemId': relationsItemId, 'count': 1, 'attributes': {}},
      'requiredItems': [
        {'itemId': ammunitionItemId, 'count': 2, 'attributes': {}},
      ],
    },
    {
      'id': 'barter-consume',
      'traderId': _therapistId,
      'offeredItem': {'itemId': weaponItemId, 'count': 1, 'attributes': {}},
      'requiredItems': [
        {'itemId': relationsItemId, 'count': 1, 'attributes': {}},
      ],
    },
  ];
  for (final barter in barters) {
    await database.customStatement(
      'INSERT INTO barters (id, payload) VALUES (?, ?)',
      [
        barter['id'],
        jsonEncode({...barter, 'kind': 'barter'}),
      ],
    );
  }

  final crafts = [
    {
      'id': 'craft-make',
      'stationId': _workbenchId,
      'duration': 1200,
      'level': 2,
      'productItem': {'itemId': relationsItemId, 'count': 1, 'attributes': {}},
      'requiredItems': [
        {'itemId': medicalItemId, 'count': 1, 'attributes': {}},
      ],
    },
    {
      'id': 'craft-use',
      'stationId': _workbenchId,
      'duration': 600,
      'level': 1,
      'productItem': {'itemId': weaponItemId, 'count': 1, 'attributes': {}},
      'requiredItems': [
        {'itemId': relationsItemId, 'count': 1, 'attributes': {}},
      ],
    },
  ];
  for (final craft in crafts) {
    await database.customStatement(
      'INSERT INTO crafts (id, stationId, productItemId, payload) '
      'VALUES (?, ?, ?, ?)',
      [
        craft['id'],
        craft['stationId'],
        (craft['productItem']! as Map<String, Object?>)['itemId'],
        jsonEncode({...craft, 'kind': 'craft'}),
      ],
    );
  }

  final objective = {
    'id': 'obj-relations',
    'kind': 'taskObjective',
    'type': 'giveItem',
    'description': 'Hand over the fuel tank',
    'itemIds': [relationsItemId],
  };
  await database.customStatement(
    'INSERT INTO tasks (id, name, traderId, payload) VALUES (?, ?, ?, ?)',
    [
      _questId,
      'Supply Run',
      _praporId,
      jsonEncode({
        'id': _questId,
        'kind': 'task',
        'name': 'Supply Run',
        'traderId': _praporId,
        'objectives': [objective],
      }),
    ],
  );
  await database.customStatement(
    'INSERT INTO taskObjectives (id, taskId, type, description, payload) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      objective['id'],
      _questId,
      objective['type'],
      objective['description'],
      jsonEncode(objective),
    ],
  );
}

String _normalize(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
