import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';
import '../support/catalog_fixture.dart';
import '../support/database_helpers.dart';

/// The committed fixture ids used by the assertions below.
const _coltM4a1 = '5447a9cd4bdc2dbd208b4567';
const _m4a1Upper = '55d355e64bdc2d962f8b4569';
const _m855Ammo = '54527a984bdc2d4e668b4567';
const _weaponCategory = '5422acb9af1c889c16000029';
const _medsCategory = '543be5664bdc2dd4348b4569';
const _medsHandbookCategory = '5b47574386f77428ca22b344';

List<String> _strings(Map<String, Object?> record, String field) =>
    (record[field] as List<Object?>? ?? const []).cast<String>();

Map<String, Object?> _price(Map<String, Object?> record) =>
    (record['price'] as Map<String, Object?>?) ?? const {};

int? _fleaPrice(Map<String, Object?> record) =>
    _price(record)['lastLow'] as int?;

bool _isFleaEligible(Map<String, Object?> record) =>
    !_strings(record, 'types').contains('noFlea');

List<String> _textTokens(String text) => RegExp(
  r'[\p{L}\p{N}]+',
  unicode: true,
).allMatches(text.toLowerCase()).map((match) => match[0]!).toList();

/// Approximates the FTS contract for a fixture record: every query token must
/// prefix a word in one of the indexed text columns.
bool _matchesText(Map<String, Object?> record, String text) {
  final haystack =
      '${record['name']} ${record['shortName']} ${record['normalizedName']}'
          .toLowerCase();
  return _textTokens(text).every(
    (token) => RegExp(
      '(^|[^\\p{L}\\p{N}])${RegExp.escape(token)}',
      unicode: true,
    ).hasMatch(haystack),
  );
}

Set<String> _ids(Iterable<ItemSummary> items) => {
  for (final item in items) item.id,
};

void _expectMonotonic(List<num> values, {required bool descending}) {
  for (var index = 1; index < values.length; index++) {
    final previous = values[index - 1];
    final current = values[index];
    if (descending) {
      expect(
        previous,
        greaterThanOrEqualTo(current),
        reason: 'value $index breaks descending order: $values',
      );
    } else {
      expect(
        previous,
        lessThanOrEqualTo(current),
        reason: 'value $index breaks ascending order: $values',
      );
    }
  }
}

/// Asserts nulls are last and the non-null prefix is sorted.
void _expectNullsLastSorted(List<int?> values, {required bool descending}) {
  final firstNull = values.indexOf(null);
  if (firstNull != -1) {
    expect(
      values.skip(firstNull).every((value) => value == null),
      isTrue,
      reason: 'a non-null appeared after a null: $values',
    );
  }
  final present = [for (final value in values) ?value];
  _expectMonotonic(present, descending: descending);
}

void main() {
  late AppDatabase db;
  late CatalogRepository catalog;
  late Directory temporary;
  late List<Map<String, Object?>> fixture;

  setUpAll(() async {
    db = await openMemoryDatabase();
    temporary = Directory.systemTemp.createTempSync('tarkov_catalog_');
    await ingestNormalizedItemsFixture(db, temporary);
    catalog = CatalogRepository(db);
    fixture = await readNormalizedItemsFixture();
  });

  tearDownAll(() async {
    await db.close();
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  Future<CatalogPage> query(CatalogFilters filters, {CatalogSort? sort}) =>
      catalog.query(
        CatalogQuery(
          filters: filters,
          sort: sort,
          limit: CatalogQuery.maxLimit,
        ),
      );

  Set<String> expected(bool Function(Map<String, Object?>) matches) => {
    for (final record in fixture)
      if (matches(record)) record['id']! as String,
  };

  group('published fixture', () {
    test('the pipeline corpus is what the catalog queries read', () async {
      expect(fixture, hasLength(60));

      final page = await query(const CatalogFilters());
      expect(page.total, 60);
      expect(page.items, hasLength(60));
      expect(_ids(page.items), expected((_) => true));

      final colt = page.items.singleWhere((item) => item.id == _coltM4a1);
      expect(colt.name, 'Colt M4A1 5.56x45 assault rifle');
      expect(colt.shortName, 'M4A1');
      expect(colt.weight, 0.75);
      expect(colt.width, 1);
      expect(colt.height, 1);
      expect(colt.basePrice, 18397);
      expect(colt.avg24hPrice, 111351);
      expect(colt.fleaPrice, 40000);
      expect(colt.change48hPercent, 16.91);
      expect(
        colt.priceObservedAt!.toUtc(),
        DateTime.utc(2026, 11, 25, 17, 8, 2),
      );
      expect(colt.fleaEligible, isTrue);
      expect(colt.minLevelForFlea, 25);
      expect(colt.types, ['gun', 'wearable']);
      expect(colt.categoryIds, contains(_weaponCategory));
      expect(colt.handbookCategoryIds, isNotEmpty);

      // Every summary carries typed tags, not raw rows or JSON.
      for (final item in page.items) {
        expect(item.types, isNotEmpty, reason: item.id);
        expect(item.categoryIds, isNotEmpty, reason: item.id);
      }
    });

    test('the total count ignores pagination', () async {
      expect(await catalog.count(const CatalogQuery()), 60);
      expect(
        await catalog.count(
          const CatalogQuery(filters: CatalogFilters(type: 'gun')),
        ),
        3,
      );
    });
  });

  group('each filter alone', () {
    test('category (in-game tree)', () async {
      final page = await query(const CatalogFilters(categoryId: _medsCategory));
      final expectedIds = expected(
        (record) => _strings(record, 'categoryIds').contains(_medsCategory),
      );

      expect(page.total, expectedIds.length);
      expect(_ids(page.items), expectedIds);
      expect(expectedIds, hasLength(6));
      expect(
        page.items.every((item) => item.categoryIds.contains(_medsCategory)),
        isTrue,
      );
    });

    test('category (handbook tree)', () async {
      final page = await query(
        const CatalogFilters(
          categoryId: _medsHandbookCategory,
          categoryKind: CatalogCategoryKind.handbook,
        ),
      );
      final expectedIds = expected(
        (record) => _strings(
          record,
          'handbookCategoryIds',
        ).contains(_medsHandbookCategory),
      );

      expect(page.total, expectedIds.length);
      expect(_ids(page.items), expectedIds);
      expect(page.items, isNotEmpty);
      expect(
        page.items.every(
          (item) => item.handbookCategoryIds.contains(_medsHandbookCategory),
        ),
        isTrue,
      );
    });

    test('type', () async {
      final page = await query(const CatalogFilters(type: 'gun'));
      final expectedIds = expected(
        (record) => _strings(record, 'types').contains('gun'),
      );

      expect(page.total, expectedIds.length);
      expect(_ids(page.items), expectedIds);
      expect(expectedIds, hasLength(3));
      expect(page.items.every((item) => item.types.contains('gun')), isTrue);
    });

    test('flea eligibility (true and false are complements)', () async {
      final eligible = await query(const CatalogFilters(fleaEligible: true));
      final banned = await query(const CatalogFilters(fleaEligible: false));

      expect(_ids(eligible.items), expected(_isFleaEligible));
      expect(
        _ids(banned.items),
        expected((record) => !_isFleaEligible(record)),
      );
      expect(eligible.total, 53);
      expect(banned.total, 7);
      expect(eligible.total + banned.total, 60);
      expect(eligible.items.every((item) => item.fleaEligible == true), isTrue);
      expect(banned.items.every((item) => item.fleaEligible == false), isTrue);
    });

    test('text search', () async {
      final page = await query(const CatalogFilters(text: 'm4a1'));
      final expectedIds = expected((record) => _matchesText(record, 'm4a1'));

      expect(_ids(page.items), expectedIds);
      expect(expectedIds, {_coltM4a1, _m4a1Upper});
      expect(page.total, 2);
    });

    test('price range', () async {
      final page = await query(
        const CatalogFilters(minPrice: 10000, maxPrice: 30000),
      );
      final expectedIds = expected((record) {
        final price = _fleaPrice(record);
        return price != null && price >= 10000 && price <= 30000;
      });

      expect(_ids(page.items), expectedIds);
      expect(page.total, expectedIds.length);
      expect(
        page.items.every(
          (item) => item.fleaPrice! >= 10000 && item.fleaPrice! <= 30000,
        ),
        isTrue,
      );
    });

    test('a blank filter is no filter', () async {
      final page = await query(
        const CatalogFilters(text: '   ', categoryId: ' ', type: ''),
      );
      expect(page.total, 60);
    });
  });

  group('combined filters', () {
    test('category + type', () async {
      final page = await query(
        const CatalogFilters(categoryId: _medsCategory, type: 'specialSlot'),
      );
      final expectedIds = expected(
        (record) =>
            _strings(record, 'categoryIds').contains(_medsCategory) &&
            _strings(record, 'types').contains('specialSlot'),
      );

      expect(_ids(page.items), expectedIds);
      expect(expectedIds, {'5d02778e86f774203e7dedbe'}); // CMS surgical kit
    });

    test('search + category', () async {
      final page = await query(
        const CatalogFilters(text: 'colt', categoryId: _weaponCategory),
      );
      final expectedIds = expected(
        (record) =>
            _matchesText(record, 'colt') &&
            _strings(record, 'categoryIds').contains(_weaponCategory),
      );

      expect(_ids(page.items), expectedIds);
      expect(expectedIds, {_coltM4a1});
    });

    test('search + type', () async {
      final page = await query(
        const CatalogFilters(text: 'm4a1', type: 'mods'),
      );
      expect(_ids(page.items), {_m4a1Upper});
    });

    test('flea eligibility + price range', () async {
      final page = await query(
        const CatalogFilters(fleaEligible: true, minPrice: 40000),
      );
      final expectedIds = expected((record) {
        final price = _fleaPrice(record);
        return _isFleaEligible(record) && price != null && price >= 40000;
      });

      expect(_ids(page.items), expectedIds);
      expect(page.total, expectedIds.length);
      expect(page.items, isNotEmpty);
      expect(page.items.every((item) => item.fleaEligible == true), isTrue);
      expect(page.items.every((item) => item.fleaPrice! >= 40000), isTrue);
    });

    test('category + type + flea eligibility + search', () async {
      final page = await query(
        const CatalogFilters(
          categoryId: _medsCategory,
          type: 'provisions',
          fleaEligible: true,
          text: 'salewa',
        ),
      );
      expect(_ids(page.items), {'544fb45d4bdc2dee738b4568'});
    });

    test('clearing one filter keeps the others', () async {
      final filters = const CatalogFilters(text: 'ak', type: 'mods');
      final narrowed = await query(filters);
      expect(_ids(narrowed.items), {
        '564caa3d4bdc2d17108b458e',
        '5649af094bdc2df8348b4586',
        '6a16dc8b12144b7727017dad',
      });

      final cleared = await query(filters.withType(null));
      expect(
        _ids(cleared.items),
        containsAll(<String>[
          '564caa3d4bdc2d17108b458e',
          '5649af094bdc2df8348b4586',
          '6a16dc8b12144b7727017dad',
          '5841474424597759ba49be91',
        ]),
      );
      expect(cleared.total, greaterThan(narrowed.total));
      expect(
        cleared.items.every(
          (item) => _matchesText({
            'name': item.name,
            'shortName': item.shortName,
            'normalizedName': item.name.toLowerCase().replaceAll(' ', '-'),
          }, 'ak'),
        ),
        isTrue,
      );
    });

    test('min price above max price matches nothing', () async {
      final page = await query(
        const CatalogFilters(minPrice: 50000, maxPrice: 10000),
      );
      expect(page.total, 0);
    });
  });

  group('sorting', () {
    test('name both directions', () async {
      final ascending = await query(
        const CatalogFilters(),
        sort: const CatalogSort(CatalogSortField.name),
      );
      final descending = await query(
        const CatalogFilters(),
        sort: const CatalogSort(CatalogSortField.name, descending: true),
      );

      final names = ascending.items
          .map((item) => item.name.toLowerCase())
          .toList();
      expect(names, orderedEquals([...names]..sort()));
      expect(
        descending.items.map((item) => item.name.toLowerCase()).toList(),
        orderedEquals(names.reversed.toList()),
      );
    });

    for (final field in [
      CatalogSortField.basePrice,
      CatalogSortField.fleaPrice,
      CatalogSortField.weight,
    ]) {
      test('${field.name} both directions with nulls last', () async {
        List<int?> valuesOf(CatalogPage page) => switch (field) {
          CatalogSortField.basePrice => [
            for (final item in page.items) item.basePrice,
          ],
          CatalogSortField.fleaPrice => [
            for (final item in page.items) item.fleaPrice,
          ],
          CatalogSortField.weight => [
            for (final item in page.items)
              item.weight == null ? null : (item.weight! * 1000).round(),
          ],
          CatalogSortField.name => throw StateError('handled above'),
        };

        final ascending = await query(
          const CatalogFilters(),
          sort: CatalogSort(field),
        );
        final descending = await query(
          const CatalogFilters(),
          sort: CatalogSort(field, descending: true),
        );

        _expectNullsLastSorted(valuesOf(ascending), descending: false);
        _expectNullsLastSorted(valuesOf(descending), descending: true);

        final ascendingPresent = valuesOf(ascending).whereType<int>().toList();
        final descendingPresent = valuesOf(descending)
            .whereType<int>()
            .toList();
        expect(
          descendingPresent,
          orderedEquals(ascendingPresent.reversed.toList()),
        );
      });
    }

    test('an explicit sort wins over search relevance', () async {
      final page = await query(
        const CatalogFilters(text: '5.56'),
        sort: const CatalogSort(CatalogSortField.basePrice, descending: true),
      );
      expect(page.items, isNotEmpty);
      _expectMonotonic([
        for (final item in page.items) item.basePrice ?? -1,
      ], descending: true);
    });
  });

  group('pagination', () {
    test('pages cover every row without duplicates', () async {
      final seen = <String>[];
      var offset = 0;
      var total = -1;
      while (true) {
        final page = await catalog.query(
          CatalogQuery(limit: 17, offset: offset),
        );
        total = page.total;
        seen.addAll(page.items.map((item) => item.id));
        if (!page.hasMore) {
          break;
        }
        expect(page.items, hasLength(17));
        offset = page.nextOffset;
      }

      expect(total, 60);
      expect(seen, hasLength(60));
      expect(seen.toSet(), hasLength(60));
    });

    test('limit and offset boundaries', () async {
      final first = await catalog.query(const CatalogQuery(limit: 10));
      expect(first.items, hasLength(10));
      expect(first.total, 60);
      expect(first.hasMore, isTrue);

      final last = await catalog.query(
        const CatalogQuery(limit: 10, offset: 55),
      );
      expect(last.items, hasLength(5));
      expect(last.hasMore, isFalse);
      expect(last.nextOffset, 60);

      final pastEnd = await catalog.query(
        const CatalogQuery(limit: 10, offset: 60),
      );
      expect(pastEnd.total, 60);
      expect(pastEnd.items, isEmpty);
      expect(pastEnd.isPageEmpty, isTrue);
      expect(pastEnd.isEmpty, isFalse, reason: 'the filters still match 60');
      expect(pastEnd.hasMore, isFalse);

      final defaultPage = await catalog.query(const CatalogQuery());
      expect(defaultPage.items, hasLength(CatalogQuery.defaultLimit));
      expect(defaultPage.limit, CatalogQuery.defaultLimit);
    });

    test('invalid pagination is clamped deterministically', () async {
      final zero = await catalog.query(
        const CatalogQuery(limit: 0, offset: -7),
      );
      expect(zero.limit, 1);
      expect(zero.offset, 0);
      expect(zero.items, hasLength(1));

      final negative = await catalog.query(
        const CatalogQuery(limit: -3, offset: -1),
      );
      expect(negative.limit, 1);
      expect(negative.offset, 0);
      expect(negative.items, hasLength(1));

      final huge = await catalog.query(
        const CatalogQuery(limit: 100000, offset: 0),
      );
      expect(huge.limit, CatalogQuery.maxLimit);
      expect(huge.items, hasLength(60));
    });

    test('no match returns an explicit empty page', () async {
      final byText = await catalog.query(
        const CatalogQuery(filters: CatalogFilters(text: 'zzzz')),
      );
      expect(byText.total, 0);
      expect(byText.isEmpty, isTrue);
      expect(byText.items, isEmpty);

      final byCategory = await catalog.query(
        const CatalogQuery(filters: CatalogFilters(categoryId: 'no-such-id')),
      );
      expect(byCategory.isEmpty, isTrue);

      final punctuation = await catalog.query(
        const CatalogQuery(filters: CatalogFilters(text: '---')),
      );
      expect(punctuation.isEmpty, isTrue);
      expect(punctuation.items, isEmpty);
    });
  });

  group('search and structured filters intersect', () {
    test(
      'text narrows, then type narrows further, then flea excludes',
      () async {
        final text = await query(const CatalogFilters(text: 'm4a1'));
        expect(text.total, 2);

        final withType = await query(
          const CatalogFilters(text: 'm4a1', type: 'gun'),
        );
        expect(_ids(withType.items), {_coltM4a1});

        final banned = await query(
          const CatalogFilters(text: 'm4a1', type: 'gun', fleaEligible: false),
        );
        expect(banned.total, 0);
        expect(banned.isEmpty, isTrue);
      },
    );

    test('filters cannot resurrect rows the search rejected', () async {
      final page = await query(
        const CatalogFilters(
          text: 'zzzz',
          categoryId: _weaponCategory,
          type: 'gun',
          fleaEligible: true,
        ),
      );
      expect(page.total, 0);
    });

    test('a search token matches shortName too', () async {
      final page = await query(const CatalogFilters(text: 'm855'));
      expect(_ids(page.items), contains(_m855Ammo));
    });
  });

  group('accent folding and unknown flea eligibility', () {
    late AppDatabase syntheticDb;
    late CatalogRepository syntheticCatalog;
    late Directory syntheticDirectory;

    setUp(() async {
      syntheticDb = await openMemoryDatabase();
      syntheticDirectory = createTemporaryDirectory(addTearDown);
      syntheticCatalog = CatalogRepository(syntheticDb);
    });

    tearDown(() => syntheticDb.close());

    test('diacritics fold through the query layer', () async {
      final dataset = writeSyntheticDataset(
        syntheticDirectory,
        DatasetKind.items,
        [
          '{"id":"item-accent","kind":"item","name":"Café Crème optic",'
              '"shortName":"Café","normalizedName":"cafe-creme-optic",'
              '"types":["mods"],"categoryIds":["cat-optic"]}',
        ],
      );
      await DatasetIngestor(syntheticDb).ingest(
        mode: GameMode.regular,
        dataset: dataset.dataset,
        compressedFile: dataset.file,
      );

      final page = await syntheticCatalog.query(
        const CatalogQuery(filters: CatalogFilters(text: 'cafe')),
      );
      expect(page.items.single.id, 'item-accent');
    });

    test(
      'a migrated row with unknown eligibility matches neither flea state',
      () async {
        final dataset = writeSyntheticDataset(
          syntheticDirectory,
          DatasetKind.items,
          [
            '{"id":"item-old","kind":"item","name":"Old item",'
                '"shortName":"Old","normalizedName":"old-item"}',
          ],
        );
        await DatasetIngestor(syntheticDb).ingest(
          mode: GameMode.regular,
          dataset: dataset.dataset,
          compressedFile: dataset.file,
        );

        final item = (await syntheticCatalog.query(const CatalogQuery()))
            .items
            .single;
        expect(item.fleaEligible, isNull);

        expect(
          (await syntheticCatalog.query(
            const CatalogQuery(filters: CatalogFilters(fleaEligible: true)),
          )).total,
          0,
        );
        expect(
          (await syntheticCatalog.query(
            const CatalogQuery(filters: CatalogFilters(fleaEligible: false)),
          )).total,
          0,
        );
      },
    );
  });

  group('performance sanity', () {
    test(
      'p95 catalog query stays under 50 ms on the committed fixture',
      () async {
        final queries = [
          const CatalogQuery(limit: 50),
          const CatalogQuery(filters: CatalogFilters(text: '5.56'), limit: 50),
          const CatalogQuery(
            filters: CatalogFilters(categoryId: _medsCategory),
            limit: 50,
          ),
          const CatalogQuery(
            filters: CatalogFilters(type: 'mods', fleaEligible: true),
            sort: CatalogSort(CatalogSortField.basePrice, descending: true),
            limit: 50,
          ),
          const CatalogQuery(
            filters: CatalogFilters(minPrice: 10000, maxPrice: 50000),
            sort: CatalogSort(CatalogSortField.weight),
            limit: 50,
            offset: 10,
          ),
        ];

        for (var warmup = 0; warmup < 5; warmup++) {
          for (final query in queries) {
            await catalog.query(query);
          }
        }

        final micros = <int>[];
        for (var iteration = 0; iteration < 40; iteration++) {
          final query = queries[iteration % queries.length];
          final stopwatch = Stopwatch()..start();
          await catalog.query(query);
          stopwatch.stop();
          micros.add(stopwatch.elapsedMicroseconds);
        }
        micros.sort();
        final p95Micros = micros[(micros.length * 0.95).ceil() - 1];
        final p95Millis = p95Micros / 1000;

        expect(
          p95Millis,
          lessThan(50),
          reason:
              'p95 was ${p95Millis.toStringAsFixed(3)} ms over '
              '${micros.length} queries',
        );
      },
    );
  });
}
