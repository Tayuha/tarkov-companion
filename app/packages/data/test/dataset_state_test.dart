import 'package:drift/drift.dart' show Value;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

void main() {
  late AppDatabase db;
  final appliedAt = DateTime.utc(2026, 11, 26, 12);

  setUp(() async {
    db = await openMemoryDatabase();
  });

  tearDown(() => db.close());

  DatasetStatesCompanion state({
    String mode = 'regular',
    String dataset = 'items',
    String checksum = 'sha256-a',
    int records = 10,
    DateTime? sourceUpdatedAt,
  }) {
    return DatasetStatesCompanion.insert(
      mode: mode,
      dataset: dataset,
      checksum: checksum,
      schemaVersion: 1,
      records: records,
      sourceUpdatedAt: Value(sourceUpdatedAt),
      appliedAt: appliedAt,
    );
  }

  test('a duplicate (mode, dataset) upserts instead of duplicating', () async {
    await db.into(db.datasetStates).insert(state(checksum: 'sha256-a'));
    await db
        .into(db.datasetStates)
        .insertOnConflictUpdate(state(checksum: 'sha256-b', records: 42));

    final rows = await db.select(db.datasetStates).get();
    expect(rows, hasLength(1));
    expect(rows.single.checksum, 'sha256-b');
    expect(rows.single.records, 42);
  });

  test('re-applying the same checksum is a no-op that keeps the row', () async {
    await db.into(db.datasetStates).insert(state());
    final first = await db.select(db.datasetStates).getSingle();

    await db
        .into(db.datasetStates)
        .insertOnConflictUpdate(state(checksum: first.checksum));

    final rows = await db.select(db.datasetStates).get();
    expect(rows, hasLength(1));
    expect(rows.single.checksum, first.checksum);
    expect(rows.single.appliedAt, first.appliedAt);
  });

  test('upserting one dataset leaves the others untouched', () async {
    await db.into(db.datasetStates).insert(state(dataset: 'items'));
    await db
        .into(db.datasetStates)
        .insert(state(dataset: 'tasks', checksum: 'sha256-tasks'));
    await db
        .into(db.datasetStates)
        .insert(state(mode: 'pve', dataset: 'items', checksum: 'sha256-pve'));

    await db
        .into(db.datasetStates)
        .insertOnConflictUpdate(
          state(dataset: 'items', checksum: 'sha256-items-v2'),
        );

    final rows = await db.select(db.datasetStates).get();
    expect(rows, hasLength(3));

    final byKey = {
      for (final row in rows) '${row.mode}/${row.dataset}': row.checksum,
    };
    expect(byKey['regular/items'], 'sha256-items-v2');
    expect(byKey['regular/tasks'], 'sha256-tasks');
    expect(byKey['pve/items'], 'sha256-pve');
  });

  test('the same dataset in another mode is an independent row', () async {
    await db.into(db.datasetStates).insert(state(dataset: 'items'));
    await db
        .into(db.datasetStates)
        .insert(state(mode: 'pve', dataset: 'items', checksum: 'sha256-pve'));

    expect(await db.select(db.datasetStates).get(), hasLength(2));
  });

  test('a nullable upstream timestamp round-trips', () async {
    final sourceUpdatedAt = DateTime.utc(2026, 11, 25, 18, 22, 15);
    await db
        .into(db.datasetStates)
        .insert(state(sourceUpdatedAt: sourceUpdatedAt));

    final row = await db.select(db.datasetStates).getSingle();
    expect(row.sourceUpdatedAt, isNotNull);
    expect(
      row.sourceUpdatedAt!.isAtSameMomentAs(sourceUpdatedAt),
      isTrue,
      reason: 'DateTime columns store epoch seconds (drift default)',
    );
  });
}
