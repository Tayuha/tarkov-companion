import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

/// One hand-written item used by the catalog screen tests.
///
/// The screen tests do not need the full pipeline corpus: a small corpus makes
/// sorting and pagination assertions readable while still exercising the real
/// [CatalogRepository], the real FTS triggers and the real filter SQL.
final class CatalogFixtureItem {
  const CatalogFixtureItem({
    required this.id,
    required this.name,
    required this.shortName,
    required this.types,
    required this.categoryIds,
    this.weight,
    this.width,
    this.height,
    this.basePrice,
    this.fleaPrice,
    this.change48hPercent,
    this.fleaEligible = true,
  });

  final String id;
  final String name;
  final String shortName;
  final List<String> types;
  final List<String> categoryIds;
  final double? weight;
  final int? width;
  final int? height;
  final int? basePrice;
  final int? fleaPrice;
  final double? change48hPercent;
  final bool? fleaEligible;
}

const fixtureWeapons = 'cat-weapons';
const fixtureMods = 'cat-mods';
const fixtureAmmo = 'cat-ammo';
const fixtureMeds = 'cat-meds';
const fixtureProvisions = 'cat-provisions';
const fixtureGear = 'cat-gear';

const fixtureCategories = <CatalogCategoryOption>[
  CatalogCategoryOption(id: fixtureWeapons, label: 'Weapons'),
  CatalogCategoryOption(id: fixtureMods, label: 'Weapon mods'),
  CatalogCategoryOption(id: fixtureAmmo, label: 'Ammo'),
  CatalogCategoryOption(id: fixtureMeds, label: 'Meds'),
  CatalogCategoryOption(id: fixtureProvisions, label: 'Provisions'),
  CatalogCategoryOption(id: fixtureGear, label: 'Gear'),
];

const fixtureTypes = <String>[
  'gun',
  'ammo',
  'mods',
  'meds',
  'provisions',
  'armor',
  'rig',
];

/// Twelve items: enough for three pages of five, with distinct prices so a
/// sorting assertion has one obvious first row in each direction.
const fixtureItems = <CatalogFixtureItem>[
  CatalogFixtureItem(
    id: 'item-colt',
    name: 'Colt M4A1 5.56x45 assault rifle',
    shortName: 'M4A1',
    weight: 0.75,
    width: 5,
    height: 2,
    basePrice: 18397,
    change48hPercent: 22.0,
    fleaPrice: 40000,
    types: ['gun', 'wearable'],
    categoryIds: [fixtureWeapons],
  ),
  CatalogFixtureItem(
    id: 'item-m4a1-upper',
    name: 'M4A1 5.56x45 upper receiver',
    shortName: 'M4A1',
    weight: 0.3,
    width: 4,
    height: 1,
    basePrice: 20000,
    change48hPercent: 3.1,
    fleaPrice: 25000,
    types: ['mods'],
    categoryIds: [fixtureMods],
  ),
  CatalogFixtureItem(
    id: 'item-ak74n',
    name: 'Kalashnikov AK-74N 5.45x39 assault rifle',
    shortName: 'AK-74N',
    weight: 3.3,
    width: 5,
    height: 2,
    basePrice: 21000,
    change48hPercent: 4.8,
    fleaPrice: 30000,
    types: ['gun', 'wearable'],
    categoryIds: [fixtureWeapons],
  ),
  CatalogFixtureItem(
    id: 'item-m855',
    name: '5.56x45mm M855',
    shortName: 'M855',
    weight: 0.012,
    width: 1,
    height: 1,
    basePrice: 150,
    change48hPercent: 4.8,
    fleaPrice: 500,
    types: ['ammo'],
    categoryIds: [fixtureAmmo],
  ),
  CatalogFixtureItem(
    id: 'item-salewa',
    name: 'Salewa first aid kit',
    shortName: 'SALEWA',
    weight: 0.6,
    width: 2,
    height: 2,
    basePrice: 15000,
    change48hPercent: -7.4,
    fleaPrice: 20000,
    types: ['meds'],
    categoryIds: [fixtureMeds],
  ),
  CatalogFixtureItem(
    id: 'item-cms',
    name: 'CMS surgical kit',
    shortName: 'CMS',
    weight: 0.5,
    width: 2,
    height: 2,
    basePrice: 30000,
    change48hPercent: -1.1,
    fleaEligible: false,
    types: ['meds'],
    categoryIds: [fixtureMeds],
  ),
  CatalogFixtureItem(
    id: 'item-water',
    name: 'Bottle of water (0.6L)',
    shortName: 'Water',
    weight: 0.6,
    width: 1,
    height: 2,
    basePrice: 10000,
    change48hPercent: 0.4,
    fleaPrice: 12000,
    types: ['provisions'],
    categoryIds: [fixtureProvisions],
  ),
  CatalogFixtureItem(
    id: 'item-crackers',
    name: 'Army crackers',
    shortName: 'Crackers',
    weight: 0.2,
    width: 1,
    height: 1,
    basePrice: 5000,
    change48hPercent: 1.2,
    fleaPrice: 6000,
    types: ['provisions'],
    categoryIds: [fixtureProvisions],
  ),
  CatalogFixtureItem(
    id: 'item-bandage',
    name: 'Aseptic bandage',
    shortName: 'Bandage',
    weight: 0.1,
    width: 1,
    height: 1,
    basePrice: 3000,
    change48hPercent: -2.1,
    fleaPrice: 4000,
    types: ['meds'],
    categoryIds: [fixtureMeds],
  ),
  CatalogFixtureItem(
    id: 'item-pmag',
    name: 'AR-15 5.56x45 Magpul PMAG 20 GEN M3 STANAG 20-round magazine',
    shortName: 'PMAG 20',
    weight: 0.2,
    width: 1,
    height: 2,
    basePrice: 8000,
    change48hPercent: 12.6,
    fleaPrice: 9000,
    types: ['mods'],
    categoryIds: [fixtureMods],
  ),
  CatalogFixtureItem(
    id: 'item-kiver',
    name: 'FORT Kiver-M bulletproof helmet',
    shortName: 'Kiver-M',
    weight: 1.5,
    width: 2,
    height: 2,
    basePrice: 25000,
    change48hPercent: -1.1,
    fleaPrice: 35000,
    types: ['armor'],
    categoryIds: [fixtureGear],
  ),
  CatalogFixtureItem(
    id: 'item-blackrock',
    name: 'BlackRock chest rig (Gray)',
    shortName: 'BlackRock',
    weight: 0.8,
    width: 3,
    height: 2,
    basePrice: 40000,
    change48hPercent: 8.1,
    fleaPrice: 50000,
    types: ['rig'],
    categoryIds: [fixtureGear],
  ),
];

/// Opens an in-memory database with the schema and FTS triggers created.
Future<AppDatabase> openCatalogFixtureDatabase() async {
  final database = AppDatabase.memory();
  await database.customSelect('SELECT 1').get(); // Force `beforeOpen`.
  await seedCatalogFixture(database);
  return database;
}

/// Inserts [fixtureItems] with their type and category tags.
///
/// Raw SQL is used on purpose: it keeps drift out of the test's imports and the
/// `items_fts` insert trigger indexes the rows exactly as ingestion would.
Future<void> seedCatalogFixture(AppDatabase database) async {
  for (final item in fixtureItems) {
    await database.customStatement(
      'INSERT INTO items ('
      'id, name, shortName, normalizedName, weight, width, height, basePrice, '
      'avg24hPrice, lastLowPrice, changeLast48hPercent, fleaEligible, payload'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        item.id,
        item.name,
        item.shortName,
        _normalize(item.name),
        item.weight,
        item.width,
        item.height,
        item.basePrice,
        item.fleaPrice,
        item.fleaPrice,
        item.change48hPercent,
        item.fleaEligible == null ? null : (item.fleaEligible! ? 1 : 0),
        '{}',
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
  }
}

String _normalize(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
