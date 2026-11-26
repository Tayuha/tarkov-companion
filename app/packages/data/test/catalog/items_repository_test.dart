import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';
import '../support/database_helpers.dart';

void main() {
  late AppDatabase db;
  late Directory temporary;
  late ItemsRepository repository;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
    repository = ItemsRepository(db);
  });

  tearDown(() => db.close());

  Future<void> ingestItemFixture() async {
    final directory = await bundleFixtureDirectory();
    final manifest = await readBundleFixtureManifest();
    final entry = datasetIn(manifest, DatasetKind.items);
    await DatasetIngestor(db).ingest(
      mode: GameMode.regular,
      dataset: entry,
      compressedFile: File('${directory.path}/${entry.path}'),
    );
  }

  test('uses the committed fixture observation time and reports stale past '
      'the threshold', () async {
    await ingestItemFixture();
    const id = '5447a9cd4bdc2dbd208b4567';
    final observedAt = DateTime.utc(2026, 11, 25, 17, 8, 2);

    final item = await (db.select(
      db.items,
    )..where((row) => row.id.equals(id))).getSingle();
    expect(item.priceObservedAt, isNotNull);
    expect(item.priceObservedAt!.toUtc(), observedAt);

    final policy = FreshnessPolicy.defaults();
    final fresh = await repository.priceFreshness(
      id,
      policy,
      observedAt.add(const Duration(hours: 23, minutes: 59)),
    );
    expect(fresh.status, FreshnessStatus.fresh);
    expect(fresh.observedAt!.toUtc(), observedAt);

    final stale = await repository.priceFreshness(
      id,
      policy,
      observedAt.add(const Duration(hours: 24, seconds: 1)),
    );
    expect(stale.status, FreshnessStatus.stale);
    expect(stale.isStale, isTrue);
    expect(stale.observedAt!.toUtc(), observedAt);
    expect(stale.age, const Duration(hours: 24, seconds: 1));
    expect(stale.requiresObservationTime, isTrue);
  });

  test(
    'changing dataFreshnessHours changes the verdict without re-ingesting',
    () async {
      await ingestItemFixture();
      const id = '5447ac644bdc2d6c208b4567';
      final observedAt = DateTime.utc(2026, 11, 25, 17, 28, 2);
      final now = observedAt.add(const Duration(hours: 30));

      final dayPolicy = FreshnessPolicy.fromSettings(const AppSettings());
      expect(
        (await repository.priceFreshness(id, dayPolicy, now)).status,
        FreshnessStatus.stale,
      );

      final weekPolicy = FreshnessPolicy.fromSettings(
        const AppSettings().copyWith(dataFreshnessHours: 168),
      );
      expect(
        (await repository.priceFreshness(id, weekPolicy, now)).status,
        FreshnessStatus.fresh,
      );

      expect(
        await db.select(db.items).get(),
        hasLength(2),
        reason: 'evaluating freshness must not re-ingest or mutate rows',
      );
    },
  );

  test('a missing item is unknown', () async {
    final verdict = await repository.priceFreshness(
      'item-does-not-exist',
      FreshnessPolicy.defaults(),
      DateTime.utc(2026, 11, 26, 12),
    );

    expect(verdict.status, FreshnessStatus.unknown);
    expect(verdict.observedAt, isNull);
    expect(verdict.age, isNull);
  });

  test('an item without a price observation is unknown', () async {
    final dataset = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"item-no-price","kind":"item","name":"No price",'
          '"shortName":"None","normalizedName":"no-price"}',
    ]);
    await DatasetIngestor(db).ingest(
      mode: GameMode.regular,
      dataset: dataset.dataset,
      compressedFile: dataset.file,
    );

    final item = await db.select(db.items).getSingle();
    expect(item.priceObservedAt, isNull);

    final verdict = await repository.priceFreshness(
      'item-no-price',
      FreshnessPolicy.defaults(),
      DateTime.utc(2026, 11, 26, 12),
    );
    expect(verdict.status, FreshnessStatus.unknown);
    expect(verdict.observedAt, isNull);
  });
}
