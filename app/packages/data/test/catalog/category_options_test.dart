import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/catalog_fixture.dart';
import '../support/database_helpers.dart';

void main() {
  late AppDatabase db;
  late Directory temporary;
  late CatalogRepository repository;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
    repository = CatalogRepository(db);
    await ingestNormalizedItemsFixture(db, temporary);
  });

  tearDown(() => db.close());

  test(
    'category options return real id/name pairs from bundle records',
    () async {
      final categories = await repository.categoryOptions();

      expect(categories, isNotEmpty);
      final weapons = categories.where(
        (category) => category.id == '5422acb9af1c889c16000029',
      );
      expect(weapons, hasLength(1));
      expect(weapons.single.name, 'Weapon');
      expect(weapons.single.kind, CatalogCategoryKind.item);

      expect(
        categories.map((category) => category.name),
        containsAll(['Weapon', 'Meds', 'Barter item']),
      );
      expect(
        categories.every((category) => category.name != category.id),
        isTrue,
        reason: 'every used category has a bundle record in the fixture',
      );
    },
  );

  test('options are unique, sorted and only include used categories', () async {
    final categories = await repository.categoryOptions();
    final ids = [for (final category in categories) category.id];

    expect(ids.toSet(), hasLength(ids.length));

    final names = [
      for (final category in categories) category.name.toLowerCase(),
    ];
    for (var index = 1; index < names.length; index++) {
      expect(names[index].compareTo(names[index - 1]), greaterThanOrEqualTo(0));
    }

    final used = await db
        .customSelect(
          'SELECT DISTINCT categoryId FROM itemCategories '
          "WHERE categoryKind = 'item'",
        )
        .get();
    expect(
      ids.toSet(),
      used.map((row) => row.read<String>('categoryId')).toSet(),
    );
  });

  test('handbook options use the handbook tree and its names', () async {
    final categories = await repository.categoryOptions(
      kind: CatalogCategoryKind.handbook,
    );

    expect(categories, isNotEmpty);
    expect(
      categories.every(
        (category) => category.kind == CatalogCategoryKind.handbook,
      ),
      isTrue,
    );
    expect(categories.map((category) => category.name), contains('Medkits'));
  });
}
