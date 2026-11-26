@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Variable;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';

/// The compressed size budget from design D7: one game mode must download in
/// under 10 MiB compressed. This fixture is the items dataset alone, so it must
/// stay under the whole-mode budget with the other six datasets still to come.
const int compressedBudgetBytes = 10 * 1024 * 1024;

/// Coarse peak-memory ceiling for one ingestion run.
///
/// `ProcessInfo.maxRss` is a process-lifetime high-water mark, not an allocator
/// measurement, and the test runner, the pure-Dart zstd decoder and SQLite all
/// share the same process. The budget is deliberately loose: it catches an
/// accidental whole-dataset materialisation, not a few megabytes of noise.
const int rssGrowthBudgetBytes = 256 * 1024 * 1024;

/// Wall-clock ceiling for one full items ingest.
///
/// Local Linux measurements on 2026-11-26 (x86_64 desktop, `dart test`):
/// 955 ms, 1,060 ms and 1,092 ms, so ~1.06 s median and ~1.09 s worst. 4 s is
/// about 3.7x the local median: enough headroom for the slower shared
/// `windows-latest` runner, while still failing on an order-of-magnitude
/// regression. See `docs/benchmark.md`.
const int ingestTimeBudgetMilliseconds = 4000;

/// A known record in the published dataset (Colt M4A1 assault rifle).
const String knownItemId = '5447a9cd4bdc2dbd208b4567';
const String knownItemQuery = 'm4a1';

Future<List<String>> _searchItems(AppDatabase db, String query) async {
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

/// Number of JSONL lines whose `kind` is [kind], read with the same streaming
/// decoder ingestion uses so the fixture is never held in memory.
int _countKindLines(File file, String kind) {
  final reader = JsonlLineReader(file);
  var count = 0;
  try {
    while (true) {
      final line = reader.nextLine();
      if (line == null) {
        break;
      }
      final decoded = jsonDecode(line);
      if (decoded is Map<String, Object?> && decoded['kind'] == kind) {
        count++;
      }
    }
  } finally {
    reader.close();
  }
  return count;
}

/// Growth of a monotonic (or near-monotonic) RSS sample, never negative.
int _positiveDelta(int before, int after) => math.max(0, after - before);

void main() {
  late Directory temporary;
  AppDatabase? database;

  setUp(() async {
    temporary = Directory.systemTemp.createTempSync(
      'tarkov_companion_benchmark_',
    );
  });

  tearDown(() async {
    await database?.close();
    database = null;
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  test('full items bundle ingests within the size, memory and time budgets', () async {
    final directory = await fixtureDirectory('benchmark');
    final manifest = BundleManifest.parse(
      jsonDecode(await File('${directory.path}/manifest.json').readAsString()),
    );
    final entry = datasetIn(manifest, DatasetKind.items);
    final asset = File('${directory.path}/${entry.path}');

    // The committed asset is byte-identical to what the app downloads.
    expect(asset.existsSync(), isTrue, reason: 'missing ${entry.path}');
    expect(
      asset.lengthSync(),
      entry.compressedBytes,
      reason: 'fixture size drifted from the manifest',
    );
    expect(
      asset.lengthSync(),
      lessThanOrEqualTo(compressedBudgetBytes),
      reason:
          'compressed items asset exceeds the 10 MiB design D7 budget: '
          '${asset.lengthSync()} bytes',
    );

    // Expected dedicated rows, computed from the fixture rather than hardcoded.
    // This runs before the RSS baseline and before the timer, using the same
    // streaming reader, so it neither inflates the measured growth nor counts
    // as ingest time.
    final itemLines = _countKindLines(asset, 'item');
    expect(itemLines, greaterThan(0));

    database = AppDatabase.atPath('${temporary.path}/benchmark.sqlite');
    // Force drift to open the file and create the schema before measuring.
    await database!.customSelect('SELECT 1').get();

    final rssCurrentBefore = ProcessInfo.currentRss;
    final rssMaxBefore = ProcessInfo.maxRss;

    final stopwatch = Stopwatch()..start();
    final result = await DatasetIngestor(database!)
        .ingest(mode: GameMode.regular, dataset: entry, compressedFile: asset);
    stopwatch.stop();

    final rssCurrentAfter = ProcessInfo.currentRss;
    final rssMaxAfter = ProcessInfo.maxRss;

    final rssCurrentDelta = _positiveDelta(rssCurrentBefore, rssCurrentAfter);
    final rssMaxDelta = _positiveDelta(rssMaxBefore, rssMaxAfter);

    // The manifest's record count, the ingest result and the stored dataset
    // state must agree.
    expect(result.records, entry.records);
    final state = (await DatasetStateRepository(database!)
        .appliedForMode(GameMode.regular))[DatasetKind.items];
    expect(state, isNotNull);
    expect(state!.records, entry.records);
    expect(state.checksum, entry.sha256);

    // Exactly one `items` row per `item` line; auxiliary kinds go elsewhere.
    final itemRows = await database!
        .customSelect('SELECT COUNT(*) AS count FROM items')
        .getSingle();
    expect(itemRows.read<int>('count'), itemLines);

    // The FTS triggers ran during the same transaction.
    expect(
      await _searchItems(database!, knownItemQuery),
      contains(knownItemId),
    );

    expect(
      stopwatch.elapsedMilliseconds,
      lessThanOrEqualTo(ingestTimeBudgetMilliseconds),
      reason:
          'full items ingest took ${stopwatch.elapsedMilliseconds} ms, over '
          'the $ingestTimeBudgetMilliseconds ms budget',
    );
    expect(
      rssMaxDelta,
      lessThanOrEqualTo(rssGrowthBudgetBytes),
      reason:
          'RSS high-water mark grew $rssMaxDelta bytes, over the '
          '$rssGrowthBudgetBytes byte ceiling',
    );

    // One line per run so a CI log carries the numbers without `--reporter`.
    // ignore: avoid_print
    print(
      'ingest-benchmark: '
      'compressed=${asset.lengthSync()}B '
      'records=${result.records} '
      'items=$itemLines '
      'ingest=${stopwatch.elapsedMilliseconds}ms '
      'rssCurrentDelta=$rssCurrentDelta '
      'rssMaxDelta=$rssMaxDelta '
      '(budgets: ${compressedBudgetBytes}B, '
      '${ingestTimeBudgetMilliseconds}ms, ${rssGrowthBudgetBytes}B)',
    );
  }, timeout: Timeout.none);
}
