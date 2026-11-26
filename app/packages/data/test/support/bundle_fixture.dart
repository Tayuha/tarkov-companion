import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// The committed ingestion bundle at `test/fixtures/bundle/`.
Future<Directory> bundleFixtureDirectory() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:tarkov_companion_data/tarkov_companion_data.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Could not resolve the data package URI.');
  }
  return Directory.fromUri(libraryUri.resolve('../test/fixtures/bundle/'));
}

/// Parses the committed fixture manifest.
Future<BundleManifest> readBundleFixtureManifest() async {
  final directory = await bundleFixtureDirectory();
  final decoded = jsonDecode(
    await File('${directory.path}/manifest.json').readAsString(),
  );
  return BundleManifest.parse(decoded);
}

/// The manifest entry for [kind] in a parsed fixture manifest.
ManifestDataset datasetIn(BundleManifest manifest, DatasetKind kind) {
  return manifest.datasets.singleWhere((entry) => entry.dataset == kind);
}

/// A compressed dataset written by a test, with a matching manifest entry.
final class SyntheticDatasetFile {
  const SyntheticDatasetFile({required this.dataset, required this.file});

  final ManifestDataset dataset;
  final File file;
}

/// Compresses [lines] exactly as the pipeline writes a dataset and builds the
/// manifest entry the ingestor expects.
///
/// [lines] are joined with `\n` plus one trailing newline. A deliberately
/// malformed line is allowed here so a test can prove ingestion rejects it.
SyntheticDatasetFile writeSyntheticDataset(
  Directory directory,
  DatasetKind kind,
  List<String> lines, {
  int schemaVersion = 1,
}) {
  final payload = utf8.encode('${lines.join('\n')}\n');
  final frame = ZstdEncoder(level: 3).encodeBytes(payload);
  return writeSyntheticFrame(
    directory,
    kind,
    Uint8List.fromList(frame),
    records: lines.length,
    schemaVersion: schemaVersion,
  );
}

/// Writes an arbitrary frame and derives the manifest entry from its bytes.
SyntheticDatasetFile writeSyntheticFrame(
  Directory directory,
  DatasetKind kind,
  Uint8List frame, {
  required int records,
  int schemaVersion = 1,
}) {
  final path = 'synthetic-${kind.id}.jsonl.zst';
  final file = File('${directory.path}/$path')..writeAsBytesSync(frame);
  return SyntheticDatasetFile(
    dataset: ManifestDataset(
      dataset: kind,
      path: path,
      schemaVersion: schemaVersion,
      sha256: sha256.convert(frame).toString(),
      compressedBytes: frame.length,
      uncompressedBytes: 0,
      records: records,
      source: const ManifestDatasetSource(
        url: null,
        lastModified: null,
        etag: null,
        fetchedAt: null,
      ),
    ),
    file: file,
  );
}
