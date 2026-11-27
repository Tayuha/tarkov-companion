@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';

/// The p95 catalog latency budget from task 5.9.
const int queryP95BudgetMilliseconds = 50;

/// Number of measured queries. Enough for a stable p95 without a long run.
const int sampleCount = 200;

int _p95(List<int> samples) {
  final sorted = [...samples]..sort();
  final index = (sorted.length * 0.95).ceil() - 1;
  return sorted[index.clamp(0, sorted.length - 1)];
}

void main() {
  late Directory temporary;
  late AppDatabase database;
  late CatalogRepository repository;

  setUpAll(() async {
    temporary = Directory.systemTemp.createTempSync('catalog_query_benchmark_');
    database = AppDatabase.memory();
    await database.customSelect('SELECT 1').get(); // Force `beforeOpen`.

    final directory = await fixtureDirectory('benchmark');
    final manifest = BundleManifest.parse(
      jsonDecode(await File('${directory.path}/manifest.json').readAsString()),
    );
    final entry = datasetIn(manifest, DatasetKind.items);
    await DatasetIngestor(database).ingest(
      mode: GameMode.regular,
      dataset: entry,
      compressedFile: File('${directory.path}/${entry.path}'),
    );
    repository = CatalogRepository(database);
  });

  tearDownAll(() async {
    await database.close();
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  test('the full fixture catalog answers p95 queries under 50 ms', () async {
    final total = await repository.count(const CatalogQuery());
    expect(total, greaterThan(5000));

    final queries = <CatalogQuery>[
      const CatalogQuery(),
      const CatalogQuery(limit: 50, offset: 500),
      const CatalogQuery(filters: CatalogFilters(text: 'm4a1')),
      const CatalogQuery(
        filters: CatalogFilters(categoryId: '5422acb9af1c889c16000029'),
      ),
      const CatalogQuery(
        filters: CatalogFilters(fleaEligible: true),
        sort: CatalogSort(CatalogSortField.fleaPrice, descending: true),
      ),
      const CatalogQuery(sort: CatalogSort(CatalogSortField.weight)),
      const CatalogQuery(
        filters: CatalogFilters(type: 'ammo'),
        sort: CatalogSort(CatalogSortField.basePrice),
      ),
    ];

    // Warm the statement cache and FTS index so the first sample is not a
    // cold-start outlier that the p95 metric would hide anyway.
    for (final query in queries) {
      await repository.query(query);
    }

    final samples = <int>[];
    final stopwatch = Stopwatch();
    for (var index = 0; index < sampleCount; index++) {
      final query = queries[index % queries.length];
      stopwatch
        ..reset()
        ..start();
      await repository.query(query);
      stopwatch.stop();
      samples.add(stopwatch.elapsedMicroseconds);
    }

    final p95 = _p95(samples);
    // ignore: avoid_print
    print(
      'catalog query p95: ${(p95 / 1000).toStringAsFixed(2)} ms '
      'over $sampleCount queries ($total items)',
    );
    expect(
      p95,
      lessThan(queryP95BudgetMilliseconds * 1000),
      reason:
          'catalog query p95 ${(p95 / 1000).toStringAsFixed(2)} ms '
          'exceeds the $queryP95BudgetMilliseconds ms budget',
    );
  });
}
