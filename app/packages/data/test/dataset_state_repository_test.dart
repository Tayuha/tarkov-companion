import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';
import 'support/manifest_fixtures.dart';

void main() {
  late AppDatabase db;
  late DatasetStateRepository repository;

  final firstApplyAt = DateTime.utc(2026, 11, 26, 12);
  final secondApplyAt = DateTime.utc(2026, 11, 26, 13);

  setUp(() async {
    db = await openMemoryDatabase();
    repository = DatasetStateRepository(db);
  });

  tearDown(() => db.close());

  test('an empty mode has no applied datasets', () async {
    expect(await repository.appliedForMode(GameMode.regular), isEmpty);
  });

  test(
    'first apply inserts a row with checksum, schema and appliedAt',
    () async {
      final dataset = _dataset(fetchedAt: DateTime.utc(2026, 11, 26, 11));

      final result = await repository.recordApplied(
        dataset,
        mode: GameMode.regular,
        appliedAt: firstApplyAt,
      );

      expect(_outcome(result), DatasetApplyOutcome.inserted);
      final applied = await repository.appliedForMode(GameMode.regular);
      expect(applied, hasLength(1));
      final items = applied[DatasetKind.items]!;
      expect(items.checksum, _shaA);
      expect(items.schemaVersion, BundleContract.appDataSchemaVersion);
      expect(items.records, 10);
      expect(items.appliedAt.isAtSameMomentAs(firstApplyAt), isTrue);
      expect(
        items.sourceUpdatedAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 26, 11)),
        isTrue,
      );
    },
  );

  test(
    're-applying identical content is unchanged and keeps appliedAt',
    () async {
      final dataset = _dataset();
      await repository.recordApplied(
        dataset,
        mode: GameMode.regular,
        appliedAt: firstApplyAt,
      );

      final result = await repository.recordApplied(
        dataset,
        mode: GameMode.regular,
        appliedAt: secondApplyAt,
      );

      expect(_outcome(result), DatasetApplyOutcome.unchanged);
      final rows = await db.select(db.datasetStates).get();
      expect(rows, hasLength(1));
      expect(
        rows.single.appliedAt.isAtSameMomentAs(firstApplyAt),
        isTrue,
        reason: 'unchanged must not rewrite the row',
      );
    },
  );

  test('a changed checksum is updated and moves appliedAt', () async {
    await repository.recordApplied(
      _dataset(),
      mode: GameMode.regular,
      appliedAt: firstApplyAt,
    );

    final result = await repository.recordApplied(
      _dataset(checksum: _shaB),
      mode: GameMode.regular,
      appliedAt: secondApplyAt,
    );

    expect(_outcome(result), DatasetApplyOutcome.updated);
    final items = (await repository.appliedForMode(
      GameMode.regular,
    ))[DatasetKind.items]!;
    expect(items.checksum, _shaB);
    expect(items.appliedAt.isAtSameMomentAs(secondApplyAt), isTrue);
  });

  test(
    'a changed record count is updated even with the same checksum',
    () async {
      await repository.recordApplied(
        _dataset(),
        mode: GameMode.regular,
        appliedAt: firstApplyAt,
      );

      final result = await repository.recordApplied(
        _dataset(records: 11),
        mode: GameMode.regular,
        appliedAt: secondApplyAt,
      );

      expect(_outcome(result), DatasetApplyOutcome.updated);
      final items = (await repository.appliedForMode(
        GameMode.regular,
      ))[DatasetKind.items]!;
      expect(items.records, 11);
    },
  );

  test('source metadata alone is not a change', () async {
    await repository.recordApplied(
      _dataset(fetchedAt: DateTime.utc(2026, 11, 26, 11)),
      mode: GameMode.regular,
      appliedAt: firstApplyAt,
    );

    final result = await repository.recordApplied(
      _dataset(fetchedAt: DateTime.utc(2026, 11, 26, 12)),
      mode: GameMode.regular,
      appliedAt: secondApplyAt,
    );

    expect(_outcome(result), DatasetApplyOutcome.unchanged);
    final items = (await repository.appliedForMode(
      GameMode.regular,
    ))[DatasetKind.items]!;
    expect(
      items.sourceUpdatedAt!.isAtSameMomentAs(DateTime.utc(2026, 11, 26, 11)),
      isTrue,
    );
    expect(items.appliedAt.isAtSameMomentAs(firstApplyAt), isTrue);
  });

  test('the same dataset in two modes is isolated', () async {
    await repository.recordApplied(
      _dataset(),
      mode: GameMode.regular,
      appliedAt: firstApplyAt,
    );
    await repository.recordApplied(
      _dataset(checksum: _shaB),
      mode: GameMode.pve,
      appliedAt: firstApplyAt,
    );

    expect(await repository.appliedForMode(GameMode.regular), hasLength(1));
    expect(await repository.appliedForMode(GameMode.pve), hasLength(1));

    await repository.recordApplied(
      _dataset(checksum: _shaB),
      mode: GameMode.regular,
      appliedAt: secondApplyAt,
    );

    final regular = await repository.appliedForMode(GameMode.regular);
    final pve = await repository.appliedForMode(GameMode.pve);
    expect(regular[DatasetKind.items]!.checksum, _shaB);
    expect(pve[DatasetKind.items]!.checksum, _shaB);
    expect(
      pve[DatasetKind.items]!.appliedAt.isAtSameMomentAs(firstApplyAt),
      isTrue,
      reason: 'updating regular must not touch pve',
    );
  });

  test('a newer dataset schema is refused with no write', () async {
    final newer = _dataset(
      schemaVersion: BundleContract.appDataSchemaVersion + 1,
    );

    final result = await repository.recordApplied(
      newer,
      mode: GameMode.regular,
      appliedAt: firstApplyAt,
    );

    expect(result, isA<DatasetApplyRejected>());
    final rejected = result as DatasetApplyRejected;
    expect(rejected.reason, DatasetApplyRejection.schemaVersionTooNew);
    expect(rejected.dataset, DatasetKind.items);
    expect(rejected.mode, GameMode.regular);
    expect(
      rejected.datasetSchemaVersion,
      BundleContract.appDataSchemaVersion + 1,
    );
    expect(
      rejected.supportedSchemaVersion,
      BundleContract.appDataSchemaVersion,
    );
    expect(await db.select(db.datasetStates).get(), isEmpty);
  });

  test('a refused dataset does not overwrite an applied row', () async {
    await repository.recordApplied(
      _dataset(),
      mode: GameMode.regular,
      appliedAt: firstApplyAt,
    );

    final result = await repository.recordApplied(
      _dataset(
        checksum: _shaB,
        schemaVersion: BundleContract.appDataSchemaVersion + 1,
      ),
      mode: GameMode.regular,
      appliedAt: secondApplyAt,
    );

    expect(result, isA<DatasetApplyRejected>());
    final rows = await db.select(db.datasetStates).get();
    expect(rows, hasLength(1));
    expect(rows.single.checksum, _shaA);
    expect(rows.single.appliedAt.isAtSameMomentAs(firstApplyAt), isTrue);
  });

  test('isCurrent tracks checksum, schema and record count', () async {
    final dataset = _dataset();
    expect(await repository.isCurrent(GameMode.regular, dataset), isFalse);

    await repository.recordApplied(
      dataset,
      mode: GameMode.regular,
      appliedAt: firstApplyAt,
    );

    expect(await repository.isCurrent(GameMode.regular, dataset), isTrue);
    expect(
      await repository.isCurrent(GameMode.regular, _dataset(checksum: _shaB)),
      isFalse,
    );
    expect(
      await repository.isCurrent(GameMode.regular, _dataset(records: 11)),
      isFalse,
    );
    expect(await repository.isCurrent(GameMode.pve, dataset), isFalse);
  });

  test('clearMode removes only the requested mode', () async {
    await repository.recordApplied(
      _dataset(),
      mode: GameMode.regular,
      appliedAt: firstApplyAt,
    );
    await repository.recordApplied(
      _dataset(dataset: DatasetKind.tasks),
      mode: GameMode.regular,
      appliedAt: firstApplyAt,
    );
    await repository.recordApplied(
      _dataset(),
      mode: GameMode.pve,
      appliedAt: firstApplyAt,
    );

    expect(await repository.clearMode(GameMode.regular), 2);

    expect(await repository.appliedForMode(GameMode.regular), isEmpty);
    expect(await repository.appliedForMode(GameMode.pve), hasLength(1));
    expect(await db.select(db.datasetStates).get(), hasLength(1));
    expect(await repository.clearMode(GameMode.regular), 0);
  });

  test('records every dataset of the published fixture', () async {
    final manifest = BundleManifest.parse(await readManifestFixture());

    for (final dataset in manifest.datasets) {
      final result = await repository.recordApplied(
        dataset,
        mode: manifest.mode,
        appliedAt: firstApplyAt,
      );
      expect(_outcome(result), DatasetApplyOutcome.inserted);
    }

    final applied = await repository.appliedForMode(manifest.mode);
    expect(
      applied.keys,
      containsAll(<DatasetKind>[DatasetKind.items, DatasetKind.tasks]),
    );
    for (final dataset in manifest.datasets) {
      final state = applied[dataset.dataset]!;
      expect(state.checksum, dataset.sha256);
      expect(state.schemaVersion, dataset.schemaVersion);
      expect(state.records, dataset.records);
      expect(await repository.isCurrent(manifest.mode, dataset), isTrue);
    }
  });
}

const _shaA =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _shaB =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ManifestDataset _dataset({
  DatasetKind dataset = DatasetKind.items,
  String checksum = _shaA,
  int? schemaVersion,
  int records = 10,
  DateTime? fetchedAt,
}) {
  return ManifestDataset(
    dataset: dataset,
    path: '${dataset.id}.jsonl.zst',
    schemaVersion: schemaVersion ?? BundleContract.appDataSchemaVersion,
    sha256: checksum,
    compressedBytes: 100,
    uncompressedBytes: 200,
    records: records,
    source: ManifestDatasetSource(
      url: 'https://json.tarkov.dev/regular/${dataset.id}',
      lastModified: null,
      etag: null,
      fetchedAt: fetchedAt,
    ),
  );
}

DatasetApplyOutcome _outcome(DatasetApplyResult result) => switch (result) {
  DatasetApplied(:final outcome) => outcome,
  DatasetApplyRejected() => throw StateError('Dataset was rejected: $result'),
};
