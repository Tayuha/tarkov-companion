import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import 'bundle_fixture.dart';

/// The committed, pipeline-produced task corpus at
/// `test/fixtures/normalized/tasks.jsonl`.
///
/// Quest query tests must not rely on hand-written rows alone: this is the same
/// corpus the pipeline golden tests use, so a filter that works here works on
/// published data. The file is resolved from the package URI rather than the
/// working directory, because CI runs tests from `app/`.
Future<File> normalizedTasksFixtureFile() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:tarkov_companion_data/tarkov_companion_data.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Could not resolve the data package URI.');
  }
  return File.fromUri(
    libraryUri.resolve('../../../../test/fixtures/normalized/tasks.jsonl'),
  );
}

/// Every `task` record of the committed normalized fixture, decoded.
///
/// The file also carries `achievement`, `questItem` and `prestige` records;
/// they belong to the same `tasks` dataset but are not quests.
Future<List<Map<String, Object?>>> readNormalizedTasksFixture() async {
  final file = await normalizedTasksFixtureFile();
  final records = <Map<String, Object?>>[];
  for (final line in await file.readAsLines()) {
    if (line.trim().isEmpty) {
      continue;
    }
    final decoded = jsonDecode(line) as Map<String, Object?>;
    if (decoded['kind'] == 'task') {
      records.add(decoded);
    }
  }
  return records;
}

/// Wraps the committed normalized fixture in a bundle frame and ingests it with
/// the production [DatasetIngestor], so the quest queries read exactly the rows
/// the pipeline publishes.
///
/// The whole file is ingested, including the auxiliary record kinds, because a
/// real `tasks` dataset carries them. Only the `task` rows are returned by
/// [readNormalizedTasksFixture] for expectations.
///
/// [temporary] is a caller-owned directory that survives until the test's tear
/// down; the frame is written there.
Future<void> ingestNormalizedTasksFixture(
  AppDatabase database,
  Directory temporary,
) async {
  final file = await normalizedTasksFixtureFile();
  final lines = [
    for (final line in await file.readAsLines())
      if (line.trim().isNotEmpty) line,
  ];
  final dataset = writeSyntheticDataset(temporary, DatasetKind.tasks, lines);
  await DatasetIngestor(database).ingest(
    mode: GameMode.regular,
    dataset: dataset.dataset,
    compressedFile: dataset.file,
  );
}
