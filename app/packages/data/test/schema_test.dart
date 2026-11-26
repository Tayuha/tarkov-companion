import 'dart:io';

import 'package:drift/drift.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/database_helpers.dart';

/// Every table the schema contract promises, including the FTS5 index and its
/// shadow tables created by SQLite.
const expectedTables = <String>{
  // Game data.
  'datasetState',
  'items',
  'tasks',
  'taskObjectives',
  'traders',
  'hideoutStations',
  'crafts',
  'barters',
  'maps',
  'priceHistory',
  // Player data.
  'profiles',
  'questProgress',
  'objectiveProgress',
  'appSettings',
  // Item search (FTS5 external content).
  'items_fts',
  'items_fts_data',
  'items_fts_idx',
  'items_fts_docsize',
  'items_fts_config',
};

/// Indexes declared through `@TableIndex` and drift's primary keys.
const expectedIndexes = <String>{
  'itemsNormalizedName',
  'itemsLastLowPrice',
  'itemsAvg24hPrice',
  'tasksTraderId',
  'tasksMapId',
  'tasksMinPlayerLevel',
  'taskObjectivesTaskId',
  'tradersNormalizedName',
  'craftsStationId',
  'craftsProductItemId',
  'mapsNormalizedName',
  'priceHistoryItemId',
  'questProgressQuestId',
  'objectiveProgressQuestId',
};

/// The FTS sync triggers.
const expectedTriggers = <String>{
  'items_fts_ai',
  'items_fts_ad',
  'items_fts_au',
};

Future<Set<String>> namesOfType(AppDatabase db, String type) async {
  final rows = await db
      .customSelect(
        'SELECT name FROM sqlite_master WHERE type = ?',
        variables: [Variable<String>(type)],
      )
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  group('fresh schema', () {
    late AppDatabase db;

    setUp(() async {
      db = await openMemoryDatabase();
    });

    tearDown(() => db.close());

    test('creates every game-data and player-data table', () async {
      final tables = await namesOfType(db, 'table');

      expect(tables, containsAll(expectedTables));
      expect(
        tables.difference({...expectedTables, ...ftsShadowTables}),
        isEmpty,
        reason: 'an undeclared table would be invisible to the drift schema',
      );
    });

    test(
      'creates every declared index plus the primary-key auto-indexes',
      () async {
        final indexes = await namesOfType(db, 'index');

        expect(indexes, containsAll(expectedIndexes));
        // Each composite/unique primary key gets an implicit auto-index.
        expect(
          indexes.where((name) => name.startsWith('sqlite_autoindex_')),
          isNotEmpty,
        );
      },
    );

    test('creates the FTS5 table and its three sync triggers', () async {
      expect(await namesOfType(db, 'trigger'), containsAll(expectedTriggers));

      final ftsSql = await db
          .customSelect(
            "SELECT sql FROM sqlite_master WHERE name = 'items_fts'",
          )
          .getSingle();
      final sql = ftsSql.read<String>('sql');

      expect(sql, contains('fts5'));
      expect(sql, contains("content = 'items'"));
      expect(sql, contains('remove_diacritics 2'));
    });

    test(
      'records the schema version and enables the expected pragmas',
      () async {
        expect(await readPragma(db, 'PRAGMA user_version'), 1);
        expect(await readPragma(db, 'PRAGMA foreign_keys'), 1);
        expect(await readPragma(db, 'PRAGMA synchronous'), 1); // NORMAL
      },
    );

    test('matches the committed sqlite_master snapshot', () async {
      final snapshot = renderSchemaSnapshot(await readSchemaObjects(db));
      final golden = await schemaGoldenFile();

      if (regeneratingGoldens) {
        golden.parent.createSync(recursive: true);
        golden.writeAsStringSync(snapshot);
        stdout.writeln('Wrote schema golden to ${golden.path}');
      }

      expect(
        golden.existsSync(),
        isTrue,
        reason:
            'test/goldens/schema.sql is missing; regenerate it with '
            'UPDATE_GOLDENS=1 dart test',
      );
      expect(
        snapshot,
        golden.readAsStringSync(),
        reason:
            'the schema changed; review the diff, then regenerate with '
            'UPDATE_GOLDENS=1 dart test',
      );
    });

    test('the snapshot golden is not empty and lists the search objects', () async {
      // Guards against a golden that was regenerated while the schema failed to
      // build: the file must still describe the FTS contract.
      final golden = (await schemaGoldenFile()).readAsStringSync();

      expect(golden, contains('table items_fts'));
      for (final trigger in expectedTriggers) {
        expect(golden, contains('trigger $trigger'));
      }
    });
  });
}
