import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';
import '../support/database_helpers.dart';

Future<List<String>> searchItems(AppDatabase db, String query) async {
  final rows = await db
      .customSelect(
        '''
        SELECT items.id
        FROM items
        JOIN items_fts ON items_fts.rowid = items.rowid
        WHERE items_fts MATCH ?
        ORDER BY items.id
        ''',
        variables: [Variable<String>(query)],
      )
      .get();
  return rows.map((row) => row.read<String>('id')).toList();
}

Future<Map<String, int>> gameRecordCounts(AppDatabase db) async {
  final rows = await db.select(db.gameRecords).get();
  final counts = <String, int>{};
  for (final row in rows) {
    counts[row.kind] = (counts[row.kind] ?? 0) + 1;
  }
  return counts;
}

void main() {
  final appliedAt = DateTime.utc(2026, 11, 26, 12);
  late AppDatabase db;
  late Directory temporary;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
  });

  tearDown(() => db.close());

  test('ingests the item fixture: rows, columns, payload, FTS, gameRecords and '
      'datasetState match the manifest', () async {
    final directory = await bundleFixtureDirectory();
    final manifest = await readBundleFixtureManifest();
    final entry = datasetIn(manifest, DatasetKind.items);

    // Player data is present before ingestion and must survive it.
    await insertProfile(db, now: appliedAt);
    await db
        .into(db.questProgress)
        .insert(
          QuestProgressCompanion.insert(
            profileId: 'profile-regular',
            questId: 'quest-debut',
            state: 'completed',
            updatedAt: appliedAt,
          ),
        );

    final result =
        await DatasetIngestor(db, batchSize: 2, clock: () => appliedAt).ingest(
          mode: GameMode.regular,
          dataset: entry,
          compressedFile: File('${directory.path}/${entry.path}'),
        );

    expect(result.records, 7);
    expect(result.stateOutcome, DatasetApplyOutcome.inserted);
    expect(await db.select(db.items).get(), hasLength(2));

    final items = await db.select(db.items).get();
    final m4a1 = items.singleWhere(
      (row) => row.id == '5447a9cd4bdc2dbd208b4567',
    );
    expect(m4a1.name, 'Colt M4A1 5.56x45 assault rifle');
    expect(m4a1.shortName, 'M4A1');
    expect(m4a1.normalizedName, 'colt-m4a1-556x45-assault-rifle');
    expect(m4a1.weight, 0.75);
    expect(m4a1.width, 1);
    expect(m4a1.height, 1);
    expect(m4a1.basePrice, 18397);
    expect(m4a1.avg24hPrice, 111351);
    expect(m4a1.lastLowPrice, 40000);
    expect(m4a1.changeLast48hPercent, 16.91);
    expect(
      m4a1.priceObservedAt!.toUtc(),
      DateTime.utc(2026, 11, 25, 17, 8, 2),
      reason: 'price.observedAt is the newest price observation',
    );
    expect(m4a1.iconLink, contains('5447a9cd4bdc2dbd208b4567-icon'));
    expect(m4a1.gridImageLink, contains('5447a9cd4bdc2dbd208b4567-grid'));
    expect(m4a1.minLevelForFlea, 25);
    expect(m4a1.fleaEligible, isTrue);

    final m4a1Types = await (db.select(
      db.itemTypes,
    )..where((row) => row.itemId.equals(m4a1.id))).get();
    expect(m4a1Types.map((row) => row.type).toSet(), {'gun', 'wearable'});

    final m4a1Categories = await (db.select(
      db.itemCategories,
    )..where((row) => row.itemId.equals(m4a1.id))).get();
    expect(
      m4a1Categories.map((row) => row.categoryId).toSet(),
      contains('5422acb9af1c889c16000029'),
    );
    expect(
      m4a1Categories
          .where((row) => row.categoryKind == 'handbook')
          .map((row) => row.categoryId),
      isNotEmpty,
    );

    final ammoPack = items.singleWhere(
      (row) => row.id == '5447ac644bdc2d6c208b4567',
    );
    expect(ammoPack.minLevelForFlea, 25);
    expect(ammoPack.fleaEligible, isTrue);

    final payload = jsonDecode(m4a1.payload) as Map<String, Object?>;
    expect(payload['kind'], 'item');
    expect(payload['properties'], isNotNull);
    expect(
      m4a1.payload,
      canonicalJsonEncode(payload),
      reason: 'payload must be canonical JSON',
    );

    expect(await gameRecordCounts(db), {
      'armorMaterial': 2,
      'playerLevel': 1,
      'setting': 1,
      'fleaMarket': 1,
    });

    expect(await searchItems(db, 'colt'), ['5447a9cd4bdc2dbd208b4567']);
    expect(await searchItems(db, 'm4a1'), ['5447a9cd4bdc2dbd208b4567']);
    expect(await searchItems(db, 'm855'), ['5447ac644bdc2d6c208b4567']);

    final state = (await DatasetStateRepository(db)
        .appliedForMode(GameMode.regular))[DatasetKind.items]!;
    expect(state.checksum, entry.sha256);
    expect(state.schemaVersion, entry.schemaVersion);
    expect(state.records, entry.records);
    expect(state.appliedAt.toUtc(), appliedAt);
    expect(state.sourceUpdatedAt, isNull);

    // Never touched by ingestion.
    expect(await db.select(db.questProgress).get(), hasLength(1));
    expect(await db.select(db.profiles).get(), hasLength(1));
  });

  test('re-ingesting the same dataset is idempotent', () async {
    final directory = await bundleFixtureDirectory();
    final manifest = await readBundleFixtureManifest();
    final entry = datasetIn(manifest, DatasetKind.items);
    final file = File('${directory.path}/${entry.path}');

    final first = DatasetIngestor(
      db,
      clock: () => appliedAt,
    ).ingest(mode: GameMode.regular, dataset: entry, compressedFile: file);
    expect((await first).stateOutcome, DatasetApplyOutcome.inserted);

    final second = await DatasetIngestor(
      db,
      clock: () => appliedAt.add(const Duration(hours: 1)),
    ).ingest(mode: GameMode.regular, dataset: entry, compressedFile: file);

    expect(second.stateOutcome, DatasetApplyOutcome.unchanged);
    expect(await db.select(db.items).get(), hasLength(2));
    expect(await db.select(db.gameRecords).get(), hasLength(5));
    expect(await db.select(db.itemTypes).get(), hasLength(3));
    expect(await db.select(db.itemCategories).get(), hasLength(11));

    final state = (await DatasetStateRepository(db)
        .appliedForMode(GameMode.regular))[DatasetKind.items]!;
    expect(state.appliedAt.toUtc(), appliedAt);
  });

  test('an ingested accented name is searchable without diacritics', () async {
    final synthetic = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"item-accent","kind":"item","name":"Café Crème optic",'
          '"shortName":"Café","normalizedName":"cafe-creme-optic"}',
    ]);

    await DatasetIngestor(db, clock: () => appliedAt).ingest(
      mode: GameMode.regular,
      dataset: synthetic.dataset,
      compressedFile: synthetic.file,
    );

    expect(await searchItems(db, 'cafe'), ['item-accent']);
  });

  test('accepts an item whose shortName is empty', () async {
    // The published items bundle contains "Sealed weapon case" with an empty
    // upstream shortName. The pipeline contract keeps it as a string, so the
    // ingestor must store "" instead of rejecting the whole dataset.
    final synthetic = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"item-empty-short","kind":"item","name":"Sealed weapon case",'
          '"shortName":"","normalizedName":"sealed-weapon-case"}',
    ]);

    await DatasetIngestor(db, clock: () => appliedAt).ingest(
      mode: GameMode.regular,
      dataset: synthetic.dataset,
      compressedFile: synthetic.file,
    );

    final row = await db.select(db.items).getSingle();
    expect(row.id, 'item-empty-short');
    expect(row.shortName, isEmpty);
  });

  test('a corrupt line rolls back the partial insert, the deletes and '
      'datasetState', () async {
    final directory = await bundleFixtureDirectory();
    final manifest = await readBundleFixtureManifest();
    final entry = datasetIn(manifest, DatasetKind.items);
    await DatasetIngestor(db, clock: () => appliedAt).ingest(
      mode: GameMode.regular,
      dataset: entry,
      compressedFile: File('${directory.path}/${entry.path}'),
    );

    final before = await DatasetStateRepository(db)
        .appliedForMode(GameMode.regular);

    final corrupt = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"synthetic-new","kind":"item","name":"New","shortName":"New",'
          '"normalizedName":"new"}',
      '{"id":"broken","kind":"item",',
    ]);

    await expectLater(
      DatasetIngestor(
        db,
        clock: () => appliedAt.add(const Duration(days: 1)),
      ).ingest(
        mode: GameMode.regular,
        dataset: corrupt.dataset,
        compressedFile: corrupt.file,
      ),
      throwsA(
        isA<IngestError>()
            .having(
              (error) => error.failure,
              'failure',
              IngestFailure.malformedJson,
            )
            .having((error) => error.line, 'line', 2),
      ),
    );

    // The previous dataset is intact: no new row, no lost rows, same state.
    final items = await db.select(db.items).get();
    expect(items, hasLength(2));
    expect(items.map((row) => row.id), isNot(contains('synthetic-new')));
    expect(await db.select(db.gameRecords).get(), hasLength(5));

    final after = await DatasetStateRepository(db)
        .appliedForMode(GameMode.regular);
    expect(after[DatasetKind.items]!.checksum, entry.sha256);
    expect(after[DatasetKind.items]!.records, entry.records);
    expect(
      after[DatasetKind.items]!.appliedAt,
      before[DatasetKind.items]!.appliedAt,
    );
  });

  test('a record-count mismatch rolls back after inserting', () async {
    final valid = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"synthetic-one","kind":"item","name":"One","shortName":"One",'
          '"normalizedName":"one"}',
    ]);
    // The manifest claims two records; the file has one. The ingestor inserts
    // the row, detects the mismatch, then rolls the insert back.
    final mismatched = SyntheticDatasetFile(
      dataset: ManifestDataset(
        dataset: valid.dataset.dataset,
        path: valid.dataset.path,
        schemaVersion: valid.dataset.schemaVersion,
        sha256: valid.dataset.sha256,
        compressedBytes: valid.dataset.compressedBytes,
        uncompressedBytes: valid.dataset.uncompressedBytes,
        records: 2,
        source: valid.dataset.source,
      ),
      file: valid.file,
    );

    await expectLater(
      DatasetIngestor(db).ingest(
        mode: GameMode.regular,
        dataset: mismatched.dataset,
        compressedFile: mismatched.file,
      ),
      throwsA(
        isA<IngestError>().having(
          (error) => error.failure,
          'failure',
          IngestFailure.recordCountMismatch,
        ),
      ),
    );

    expect(await db.select(db.items).get(), isEmpty);
    expect(await db.select(db.datasetStates).get(), isEmpty);
  });

  test('a decompression failure is typed and writes nothing', () async {
    final broken = writeSyntheticFrame(
      temporary,
      DatasetKind.items,
      Uint8List.fromList(utf8.encode('this is not a zstd frame')),
      records: 1,
    );

    await expectLater(
      DatasetIngestor(db).ingest(
        mode: GameMode.regular,
        dataset: broken.dataset,
        compressedFile: broken.file,
      ),
      throwsA(
        isA<IngestError>().having(
          (error) => error.failure,
          'failure',
          IngestFailure.decompression,
        ),
      ),
    );

    expect(await db.select(db.items).get(), isEmpty);
    expect(await db.select(db.gameRecords).get(), isEmpty);
    expect(await db.select(db.datasetStates).get(), isEmpty);
  });

  test('a missing dataset file is typed and writes nothing', () async {
    final written = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"synthetic-one","kind":"item","name":"One","shortName":"One",'
          '"normalizedName":"one"}',
    ]);
    written.file.deleteSync();

    await expectLater(
      DatasetIngestor(db).ingest(
        mode: GameMode.regular,
        dataset: written.dataset,
        compressedFile: written.file,
      ),
      throwsA(
        isA<IngestError>().having(
          (error) => error.failure,
          'failure',
          IngestFailure.missingFile,
        ),
      ),
    );

    expect(await db.select(db.items).get(), isEmpty);
    expect(await db.select(db.datasetStates).get(), isEmpty);
  });

  test('a newer dataset schema is refused before any write', () async {
    final newer = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"synthetic-one","kind":"item","name":"One","shortName":"One",'
          '"normalizedName":"one"}',
    ], schemaVersion: BundleContract.appDataSchemaVersion + 1);

    await expectLater(
      DatasetIngestor(db).ingest(
        mode: GameMode.regular,
        dataset: newer.dataset,
        compressedFile: newer.file,
      ),
      throwsA(
        isA<IngestError>().having(
          (error) => error.failure,
          'failure',
          IngestFailure.unsupportedSchema,
        ),
      ),
    );

    expect(await db.select(db.items).get(), isEmpty);
    expect(await db.select(db.datasetStates).get(), isEmpty);
  });

  test('a duplicate record is rejected and rolled back', () async {
    final duplicate = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"synthetic-one","kind":"item","name":"One","shortName":"One",'
          '"normalizedName":"one"}',
      '{"id":"synthetic-one","kind":"item","name":"One again",'
          '"shortName":"One","normalizedName":"one"}',
    ]);

    await expectLater(
      DatasetIngestor(db).ingest(
        mode: GameMode.regular,
        dataset: duplicate.dataset,
        compressedFile: duplicate.file,
      ),
      throwsA(
        isA<IngestError>()
            .having(
              (error) => error.failure,
              'failure',
              IngestFailure.duplicateRecord,
            )
            .having((error) => error.line, 'line', 2),
      ),
    );

    expect(await db.select(db.items).get(), isEmpty);
    expect(await db.select(db.datasetStates).get(), isEmpty);
  });

  test(
    'a record missing a required field is refused and rolled back',
    () async {
      final invalid = writeSyntheticDataset(temporary, DatasetKind.items, [
        '{"id":"synthetic-one","kind":"item","name":"One","shortName":"One",'
            '"normalizedName":"one"}',
        '{"id":"synthetic-two","kind":"item","shortName":"Two",'
            '"normalizedName":"two"}',
      ]);

      await expectLater(
        DatasetIngestor(db).ingest(
          mode: GameMode.regular,
          dataset: invalid.dataset,
          compressedFile: invalid.file,
        ),
        throwsA(
          isA<IngestError>()
              .having(
                (error) => error.failure,
                'failure',
                IngestFailure.invalidRecord,
              )
              .having((error) => error.line, 'line', 2),
        ),
      );

      expect(await db.select(db.items).get(), isEmpty);
      expect(await db.select(db.datasetStates).get(), isEmpty);
    },
  );

  test('a line that is not UTF-8 is typed and writes nothing', () async {
    final frame = ZstdEncoder(level: 3)
        .encodeBytes(Uint8List.fromList(<int>[0xFF, 0x0A]));
    final invalid = writeSyntheticFrame(
      temporary,
      DatasetKind.items,
      Uint8List.fromList(frame),
      records: 1,
    );

    await expectLater(
      DatasetIngestor(db).ingest(
        mode: GameMode.regular,
        dataset: invalid.dataset,
        compressedFile: invalid.file,
      ),
      throwsA(
        isA<IngestError>()
            .having(
              (error) => error.failure,
              'failure',
              IngestFailure.invalidUtf8,
            )
            .having((error) => error.line, 'line', 1),
      ),
    );

    expect(await db.select(db.items).get(), isEmpty);
    expect(await db.select(db.datasetStates).get(), isEmpty);
  });

  test(
    'tasks ingestion creates objectives and replacement cascades them',
    () async {
      final v1 = writeSyntheticDataset(temporary, DatasetKind.tasks, [
        jsonEncode({
          'id': 'task-1',
          'kind': 'task',
          'name': 'Test Quest',
          'traderId': 'trader-1',
          'mapId': null,
          'minPlayerLevel': 5,
          'experience': 1000,
          'kappaRequired': true,
          'objectives': [
            {
              'id': 'objective-1',
              'type': 'shoot',
              'description': 'Kill 5 Scavs',
              'count': 5,
            },
            {
              'id': 'objective-2',
              'type': 'visit',
              'description': 'Visit the pier',
            },
          ],
        }),
        jsonEncode({
          'id': 'achievement-1',
          'kind': 'achievement',
          'name': 'Test achievement',
        }),
      ]);

      await DatasetIngestor(db, clock: () => appliedAt).ingest(
        mode: GameMode.regular,
        dataset: v1.dataset,
        compressedFile: v1.file,
      );

      final task = await db.select(db.tasks).getSingle();
      expect(task.name, 'Test Quest');
      expect(task.traderId, 'trader-1');
      expect(task.minPlayerLevel, 5);
      expect(task.experience, 1000);
      expect(task.kappaRequired, isTrue);

      final objectives = await db.select(db.taskObjectives).get();
      expect(objectives, hasLength(2));
      final shoot = objectives.singleWhere((row) => row.id == 'objective-1');
      expect(shoot.taskId, 'task-1');
      expect(shoot.type, 'shoot');
      expect(shoot.description, 'Kill 5 Scavs');
      expect(shoot.count, 5);
      expect(
        shoot.payload,
        canonicalJsonEncode(jsonDecode(shoot.payload) as Map<String, Object?>),
      );
      expect(await gameRecordCounts(db), {'achievement': 1});

      // A newer tasks dataset keeps objective-1 and drops objective-2. Deleting
      // the task row cascades the old objectives before the replacement is
      // inserted.
      final v2 = writeSyntheticDataset(temporary, DatasetKind.tasks, [
        jsonEncode({
          'id': 'task-1',
          'kind': 'task',
          'name': 'Test Quest',
          'objectives': [
            {
              'id': 'objective-1',
              'type': 'shoot',
              'description': 'Kill 5 Scavs',
              'count': 5,
            },
          ],
        }),
        jsonEncode({
          'id': 'achievement-1',
          'kind': 'achievement',
          'name': 'Test achievement',
        }),
      ]);

      await DatasetIngestor(
        db,
        clock: () => appliedAt.add(const Duration(days: 1)),
      ).ingest(
        mode: GameMode.regular,
        dataset: v2.dataset,
        compressedFile: v2.file,
      );

      expect(await db.select(db.tasks).get(), hasLength(1));
      final remaining = await db.select(db.taskObjectives).get();
      expect(remaining.map((row) => row.id), ['objective-1']);
      expect(await gameRecordCounts(db), {'achievement': 1});
    },
  );

  test('unknown kinds are stored in gameRecords and replace cleanly', () async {
    final dataset = writeSyntheticDataset(temporary, DatasetKind.items, [
      '{"id":"synthetic-item","kind":"item","name":"One","shortName":"One",'
          '"normalizedName":"one"}',
      '{"id":"future-1","kind":"futureThing","payload":{"v":1}}',
    ]);

    Future<void> ingest() => DatasetIngestor(db, clock: () => appliedAt).ingest(
      mode: GameMode.regular,
      dataset: dataset.dataset,
      compressedFile: dataset.file,
    );

    await ingest();
    expect(await db.select(db.items).get(), hasLength(1));
    final record = await db.select(db.gameRecords).getSingle();
    expect(record.kind, 'futureThing');
    expect(record.id, 'future-1');
    expect(jsonDecode(record.payload), {
      'id': 'future-1',
      'kind': 'futureThing',
      'payload': {'v': 1},
    });

    await ingest();
    expect(await db.select(db.gameRecords).get(), hasLength(1));
  });

  test('streams datasets larger than one decompression chunk', () async {
    final longDescription = 'Café ${'x' * (70 * 1024)}';
    final lines = <String>[
      for (var index = 0; index < 20; index++)
        jsonEncode({
          'id': 'item-$index',
          'kind': 'item',
          'name': 'Item $index',
          'shortName': 'I$index',
          'normalizedName': 'item-$index',
          'description': index == 0 ? longDescription : 'short',
        }),
    ];
    final dataset = writeSyntheticDataset(temporary, DatasetKind.items, lines);

    final progress = <int>[];
    final result = await DatasetIngestor(db).ingest(
      mode: GameMode.regular,
      dataset: dataset.dataset,
      compressedFile: dataset.file,
      onProgress: (update) => progress.add(update.recordsProcessed),
    );

    expect(result.records, 20);
    expect(progress, List<int>.generate(20, (index) => index + 1));
    expect(await db.select(db.items).get(), hasLength(20));
    final first = await (db.select(
      db.items,
    )..where((row) => row.id.equals('item-0'))).getSingle();
    final payload = jsonDecode(first.payload) as Map<String, Object?>;
    expect(payload['description'], longDescription);
  });

  test('canonical JSON sorts object keys recursively', () {
    expect(
      canonicalJsonEncode({
        'b': 1,
        'a': {
          'd': 2,
          'c': [
            {'z': 3, 'y': 4},
          ],
        },
      }),
      '{"a":{"c":[{"y":4,"z":3}],"d":2},"b":1}',
    );
  });
}
