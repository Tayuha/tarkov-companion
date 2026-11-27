import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import 'bundle_fixture.dart';

/// The committed, pipeline-produced item corpus at
/// `test/fixtures/normalized/items.jsonl`.
///
/// Catalog query tests must not rely on hand-written rows alone: this is the
/// same 577-record corpus the pipeline golden tests use, so a filter that works
/// here works on published data. The file is resolved from the package URI
/// rather than the working directory, because CI runs tests from `app/`.
Future<File> normalizedItemsFixtureFile() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:tarkov_companion_data/tarkov_companion_data.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Could not resolve the data package URI.');
  }
  return File.fromUri(
    libraryUri.resolve('../../../../test/fixtures/normalized/items.jsonl'),
  );
}

/// Every `item` record of the committed normalized fixture, decoded.
Future<List<Map<String, Object?>>> readNormalizedItemsFixture() async {
  final file = await normalizedItemsFixtureFile();
  final records = <Map<String, Object?>>[];
  for (final line in await file.readAsLines()) {
    if (line.trim().isEmpty) {
      continue;
    }
    final decoded = jsonDecode(line) as Map<String, Object?>;
    if (decoded['kind'] == 'item') {
      records.add(decoded);
    }
  }
  return records;
}

/// Wraps the committed normalized fixture in a bundle frame and ingests it with
/// the production [DatasetIngestor], so the catalog queries read exactly the
/// rows the pipeline publishes.
///
/// [temporary] is a caller-owned directory that survives until the test's tear
/// down; the frame is written there.
Future<void> ingestNormalizedItemsFixture(
  AppDatabase database,
  Directory temporary,
) async {
  final file = await normalizedItemsFixtureFile();
  final lines = [
    for (final line in await file.readAsLines())
      if (line.trim().isNotEmpty) line,
  ];
  final dataset = writeSyntheticDataset(temporary, DatasetKind.items, lines);
  await DatasetIngestor(database).ingest(
    mode: GameMode.regular,
    dataset: dataset.dataset,
    compressedFile: dataset.file,
  );
}

/// The committed normalized file for one dataset
/// (`test/fixtures/normalized/<dataset>.jsonl`).
Future<File> normalizedDatasetFixtureFile(DatasetKind kind) async {
  final itemsFile = await normalizedItemsFixtureFile();
  return File('${itemsFile.parent.path}/${kind.id}.jsonl');
}

/// Ingests one committed normalized fixture through the production ingestor,
/// so relation and price tests read exactly the shape the pipeline publishes.
Future<void> ingestNormalizedDataset(
  AppDatabase database,
  Directory temporary,
  DatasetKind kind,
) async {
  final file = await normalizedDatasetFixtureFile(kind);
  final lines = [
    for (final line in await file.readAsLines())
      if (line.trim().isNotEmpty) line,
  ];
  final dataset = writeSyntheticDataset(temporary, kind, lines);
  await DatasetIngestor(database).ingest(
    mode: GameMode.regular,
    dataset: dataset.dataset,
    compressedFile: dataset.file,
  );
}
