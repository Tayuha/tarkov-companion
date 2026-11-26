import '../dataset_kind.dart';
import 'bundle_contract.dart';
import 'game_mode.dart';

/// A manifest that does not match the bundle contract.
///
/// [path] is the JSON path of the offending value, using dot notation and
/// bracketed array indexes (`datasets[0].path`). It is safe to show in a sync
/// report or a log line; it never contains the whole document.
final class ManifestFormatException implements Exception {
  const ManifestFormatException(this.path, this.message);

  /// JSON path of the value that failed validation.
  final String path;

  /// Human-readable reason.
  final String message;

  @override
  String toString() => 'ManifestFormatException at $path: $message';
}

/// Provenance of the whole build (`manifest.source`).
final class ManifestSource {
  const ManifestSource({required this.baseUrl, required this.capturedAt});

  /// Upstream API base URL, or `null` for a hand-built bundle.
  final String? baseUrl;

  /// Earliest upstream fetch time in the build, or `null` when unknown.
  final DateTime? capturedAt;
}

/// Provenance of one dataset (`manifest.datasets[].source`).
final class ManifestDatasetSource {
  const ManifestDatasetSource({
    required this.url,
    required this.lastModified,
    required this.etag,
    required this.fetchedAt,
  });

  /// Upstream URL the payload came from.
  final String? url;

  /// Upstream `Last-Modified` header, verbatim (an HTTP date).
  final String? lastModified;

  /// Upstream `ETag` header, verbatim (may be weak).
  final String? etag;

  /// When this dataset was fetched upstream.
  final DateTime? fetchedAt;
}

/// Sums over a manifest's datasets (`manifest.totals`).
///
/// The totals are diagnostics. A client never uses them to decide whether to
/// download; the pipeline's validator only warns when they disagree.
final class ManifestTotals {
  const ManifestTotals({
    required this.datasets,
    required this.records,
    required this.uncompressedBytes,
    required this.compressedBytes,
  });

  final int datasets;
  final int records;
  final int uncompressedBytes;
  final int compressedBytes;
}

/// Why a dataset is absent from a bundle.
enum ManifestSkippedReason {
  /// The caller supplied no records for the dataset; keep existing rows.
  notSupplied('not-supplied');

  const ManifestSkippedReason(this.wireValue);

  final String wireValue;

  static ManifestSkippedReason? fromWire(String value) {
    for (final reason in values) {
      if (reason.wireValue == value) {
        return reason;
      }
    }
    return null;
  }
}

/// A dataset deliberately not written in this build (`manifest.skipped[]`).
final class ManifestSkippedDataset {
  const ManifestSkippedDataset({required this.dataset, required this.reason});

  final DatasetKind dataset;
  final ManifestSkippedReason reason;
}

/// One dataset entry in a manifest.
final class ManifestDataset {
  const ManifestDataset({
    required this.dataset,
    required this.path,
    required this.schemaVersion,
    required this.sha256,
    required this.compressedBytes,
    required this.uncompressedBytes,
    required this.records,
    required this.source,
  });

  /// Dataset name (`items`, `tasks`, ...).
  final DatasetKind dataset;

  /// Flat file name relative to the manifest, never containing `/` or `\`.
  final String path;

  /// Record schema version of this dataset.
  final int schemaVersion;

  /// SHA-256 of the compressed `.jsonl.zst` bytes, lowercase hex.
  final String sha256;

  /// Exact byte length of the compressed file.
  final int compressedBytes;

  /// Byte length of the JSONL payload before compression.
  final int uncompressedBytes;

  /// Number of JSONL records (lines) in the file.
  final int records;

  /// Upstream provenance; diagnostics only.
  final ManifestDatasetSource source;
}

/// Result of comparing a manifest's versions with the client's support.
enum ManifestCompatibility {
  /// The client can ingest this bundle.
  compatible,

  /// `minAppSchemaVersion` needs a newer app data schema.
  appUpdateRequired,

  /// `bundleSchemaVersion` is newer than the client implements.
  bundleUnsupported,
}

/// A compatibility decision plus the human-readable reason for it.
final class ManifestCompatibilityResult {
  const ManifestCompatibilityResult({
    required this.status,
    required this.reason,
  });

  final ManifestCompatibility status;
  final String reason;

  bool get isCompatible => status == ManifestCompatibility.compatible;

  @override
  String toString() => '${status.name}: $reason';
}

/// A validated, parsed `manifest.json`.
///
/// Use [BundleManifest.parse] for a document decoded with `jsonDecode`. The
/// parser validates every field in `docs/data-bundles.md` and throws
/// [ManifestFormatException] at the first problem instead of returning a
/// partially populated model.
final class BundleManifest {
  BundleManifest({
    required this.manifestVersion,
    required this.bundleSchemaVersion,
    required this.minAppSchemaVersion,
    required this.mode,
    required this.generatedAt,
    required this.source,
    required List<ManifestDataset> datasets,
    required this.totals,
    required List<ManifestSkippedDataset> skipped,
  }) : datasets = List.unmodifiable(datasets),
       skipped = List.unmodifiable(skipped);

  /// Manifest document version (`1` today).
  final int manifestVersion;

  /// Version of the bundle contract as a whole.
  final int bundleSchemaVersion;

  /// Oldest app data-schema version that can ingest every dataset.
  final int minAppSchemaVersion;

  /// Game mode this bundle belongs to.
  final GameMode mode;

  /// Wall-clock build time, always UTC.
  final DateTime generatedAt;

  /// Build provenance.
  final ManifestSource source;

  /// Present datasets, in the manifest's order (sorted by dataset name by the
  /// writer).
  final List<ManifestDataset> datasets;

  /// Manifest totals; diagnostics only.
  final ManifestTotals totals;

  /// Datasets deliberately absent from this build.
  final List<ManifestSkippedDataset> skipped;

  /// Parses and validates a decoded JSON document.
  ///
  /// [json] is the result of `jsonDecode`, not a JSON string: the data package
  /// does no I/O and the sync layer owns reading the response body.
  static BundleManifest parse(Object? json) {
    final root = _expectObject(json, 'manifest');
    final manifestVersion = _expectIntField(
      root,
      'manifestVersion',
      '',
      positive: true,
    );
    if (manifestVersion != BundleContract.manifestVersion) {
      throw ManifestFormatException(
        'manifestVersion',
        'Unsupported manifest version $manifestVersion; this client '
            'implements ${BundleContract.manifestVersion}.',
      );
    }

    final bundleSchemaVersion = _expectIntField(
      root,
      'bundleSchemaVersion',
      '',
      positive: true,
    );
    final minAppSchemaVersion = _expectIntField(
      root,
      'minAppSchemaVersion',
      '',
      positive: true,
    );

    final rawMode = _expectStringField(root, 'mode', '', nonEmpty: true);
    final mode = GameMode.parse(rawMode).valueOrNull;
    if (mode == null) {
      throw ManifestFormatException('mode', 'Unknown bundle mode "$rawMode".');
    }

    final generatedAt = _expectDateTimeField(root, 'generatedAt', '');
    final source = _parseSource(
      _expectObjectField(root, 'source', ''),
      'source',
    );
    final datasets = _parseDatasets(root);
    final totals = _parseTotals(
      _expectObjectField(root, 'totals', ''),
      'totals',
    );
    final skipped = _parseSkipped(root);

    return BundleManifest(
      manifestVersion: manifestVersion,
      bundleSchemaVersion: bundleSchemaVersion,
      minAppSchemaVersion: minAppSchemaVersion,
      mode: mode,
      generatedAt: generatedAt,
      source: source,
      datasets: datasets,
      totals: totals,
      skipped: skipped,
    );
  }

  /// Checks this bundle against the client's supported versions.
  ///
  /// The rule from `docs/data-bundles.md` is:
  ///
  /// * `bundleSchemaVersion <= supportedBundleSchemaVersion`;
  /// * `minAppSchemaVersion <= appDataSchemaVersion`.
  ///
  /// A lower bundle version is accepted (an older compatible bundle). A newer
  /// one is refused before any dataset is downloaded or applied.
  ManifestCompatibilityResult checkCompatibility({
    int supportedBundleSchemaVersion =
        BundleContract.supportedBundleSchemaVersion,
    int appDataSchemaVersion = BundleContract.appDataSchemaVersion,
  }) {
    if (bundleSchemaVersion > supportedBundleSchemaVersion) {
      return ManifestCompatibilityResult(
        status: ManifestCompatibility.bundleUnsupported,
        reason:
            'bundleSchemaVersion $bundleSchemaVersion is newer than the '
            'supported $supportedBundleSchemaVersion; update the app.',
      );
    }
    if (minAppSchemaVersion > appDataSchemaVersion) {
      return ManifestCompatibilityResult(
        status: ManifestCompatibility.appUpdateRequired,
        reason:
            'minAppSchemaVersion $minAppSchemaVersion is newer than the app '
            'data schema $appDataSchemaVersion; update the app.',
      );
    }
    return ManifestCompatibilityResult(
      status: ManifestCompatibility.compatible,
      reason:
          'bundleSchemaVersion $bundleSchemaVersion and minAppSchemaVersion '
          '$minAppSchemaVersion are supported.',
    );
  }
}

ManifestSource _parseSource(Map<String, Object?> json, String path) {
  return ManifestSource(
    baseUrl: _nullableStringField(json, 'baseUrl', path),
    capturedAt: _nullableDateTimeField(json, 'capturedAt', path),
  );
}

ManifestDatasetSource _parseDatasetSource(
  Map<String, Object?> json,
  String path,
) {
  return ManifestDatasetSource(
    url: _nullableStringField(json, 'url', path),
    lastModified: _nullableStringField(json, 'lastModified', path),
    etag: _nullableStringField(json, 'etag', path),
    fetchedAt: _nullableDateTimeField(json, 'fetchedAt', path),
  );
}

List<ManifestDataset> _parseDatasets(Map<String, Object?> root) {
  final values = _expectListField(root, 'datasets', '');
  if (values.isEmpty) {
    throw const ManifestFormatException(
      'datasets',
      'A manifest must contain at least one dataset.',
    );
  }

  final datasets = <ManifestDataset>[];
  final seen = <DatasetKind>{};
  for (var index = 0; index < values.length; index++) {
    final path = _at('datasets', index);
    final entry = _expectObject(values[index], path);
    final rawDataset = _expectStringField(
      entry,
      'dataset',
      path,
      nonEmpty: true,
    );
    final dataset = DatasetKind.parse(rawDataset).valueOrNull;
    if (dataset == null) {
      throw ManifestFormatException(
        '$path.dataset',
        'Unknown bundle dataset "$rawDataset".',
      );
    }
    if (!seen.add(dataset)) {
      throw ManifestFormatException(
        '$path.dataset',
        'Duplicate dataset "${dataset.id}".',
      );
    }

    datasets.add(
      ManifestDataset(
        dataset: dataset,
        path: _expectDatasetPath(entry, path),
        schemaVersion: _expectIntField(
          entry,
          'schemaVersion',
          path,
          positive: true,
        ),
        sha256: _expectSha256(entry, path),
        compressedBytes: _expectIntField(
          entry,
          'compressedBytes',
          path,
          nonNegative: true,
        ),
        uncompressedBytes: _expectIntField(
          entry,
          'uncompressedBytes',
          path,
          nonNegative: true,
        ),
        records: _expectIntField(entry, 'records', path, nonNegative: true),
        source: _parseDatasetSource(
          _expectObjectField(entry, 'source', path),
          '$path.source',
        ),
      ),
    );
  }
  return datasets;
}

ManifestTotals _parseTotals(Map<String, Object?> json, String path) {
  return ManifestTotals(
    datasets: _expectIntField(json, 'datasets', path, nonNegative: true),
    records: _expectIntField(json, 'records', path, nonNegative: true),
    uncompressedBytes: _expectIntField(
      json,
      'uncompressedBytes',
      path,
      nonNegative: true,
    ),
    compressedBytes: _expectIntField(
      json,
      'compressedBytes',
      path,
      nonNegative: true,
    ),
  );
}

List<ManifestSkippedDataset> _parseSkipped(Map<String, Object?> root) {
  final values = _expectListField(root, 'skipped', '');
  final skipped = <ManifestSkippedDataset>[];
  for (var index = 0; index < values.length; index++) {
    final path = _at('skipped', index);
    final entry = _expectObject(values[index], path);
    final rawDataset = _expectStringField(
      entry,
      'dataset',
      path,
      nonEmpty: true,
    );
    final dataset = DatasetKind.parse(rawDataset).valueOrNull;
    if (dataset == null) {
      throw ManifestFormatException(
        '$path.dataset',
        'Unknown bundle dataset "$rawDataset".',
      );
    }
    final rawReason = _expectStringField(entry, 'reason', path, nonEmpty: true);
    final reason = ManifestSkippedReason.fromWire(rawReason);
    if (reason == null) {
      throw ManifestFormatException(
        '$path.reason',
        'Unknown skipped reason "$rawReason".',
      );
    }
    skipped.add(ManifestSkippedDataset(dataset: dataset, reason: reason));
  }
  return skipped;
}

String _expectDatasetPath(Map<String, Object?> json, String parentPath) {
  final value = _expectStringField(json, 'path', parentPath, nonEmpty: true);
  final path = _child(parentPath, 'path');

  if (value == '.' || value == '..') {
    throw ManifestFormatException(
      path,
      'Dataset path must be a file name, not "$value".',
    );
  }
  if (value.contains('/') || value.contains('\\')) {
    throw ManifestFormatException(
      path,
      'Dataset path must be flat and relative; separators are not allowed.',
    );
  }
  if (value.contains('..')) {
    throw ManifestFormatException(
      path,
      'Dataset path must not contain traversal segments.',
    );
  }
  if (RegExp(r'^[A-Za-z]:').hasMatch(value)) {
    throw ManifestFormatException(
      path,
      'Dataset path must be relative; drive-qualified paths are not allowed.',
    );
  }
  if (!value.endsWith(BundleContract.datasetFileSuffix)) {
    throw ManifestFormatException(
      path,
      'Dataset path must end in "${BundleContract.datasetFileSuffix}".',
    );
  }
  return value;
}

String _expectSha256(Map<String, Object?> json, String parentPath) {
  final value = _expectStringField(json, 'sha256', parentPath, nonEmpty: true);
  if (!_sha256Pattern.hasMatch(value)) {
    throw ManifestFormatException(
      _child(parentPath, 'sha256'),
      'Expected ${BundleContract.sha256HexLength} lowercase hexadecimal '
      'characters.',
    );
  }
  return value;
}

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

Object? _required(Map<String, Object?> json, String key, String parentPath) {
  final path = _child(parentPath, key);
  if (!json.containsKey(key)) {
    throw ManifestFormatException(path, 'Missing required field.');
  }
  return json[key];
}

Map<String, Object?> _expectObjectField(
  Map<String, Object?> json,
  String key,
  String parentPath,
) {
  return _expectObject(
    _required(json, key, parentPath),
    _child(parentPath, key),
  );
}

List<Object?> _expectListField(
  Map<String, Object?> json,
  String key,
  String parentPath,
) {
  final path = _child(parentPath, key);
  return _expectList(_required(json, key, parentPath), path);
}

int _expectIntField(
  Map<String, Object?> json,
  String key,
  String parentPath, {
  bool positive = false,
  bool nonNegative = false,
}) {
  final path = _child(parentPath, key);
  final value = _required(json, key, parentPath);
  if (value is! int) {
    throw ManifestFormatException(path, 'Expected an integer.');
  }
  if (positive && value <= 0) {
    throw ManifestFormatException(path, 'Expected a positive integer.');
  }
  if (nonNegative && value < 0) {
    throw ManifestFormatException(path, 'Expected a non-negative integer.');
  }
  return value;
}

String _expectStringField(
  Map<String, Object?> json,
  String key,
  String parentPath, {
  bool nonEmpty = false,
}) {
  final path = _child(parentPath, key);
  final value = _required(json, key, parentPath);
  if (value is! String) {
    throw ManifestFormatException(path, 'Expected a string.');
  }
  if (nonEmpty && value.isEmpty) {
    throw ManifestFormatException(path, 'Expected a non-empty string.');
  }
  return value;
}

String? _nullableStringField(
  Map<String, Object?> json,
  String key,
  String parentPath,
) {
  final value = _required(json, key, parentPath);
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw ManifestFormatException(
      _child(parentPath, key),
      'Expected a string or null.',
    );
  }
  return value;
}

DateTime _expectDateTimeField(
  Map<String, Object?> json,
  String key,
  String parentPath,
) {
  return _expectDateTime(
    _required(json, key, parentPath),
    _child(parentPath, key),
  );
}

DateTime? _nullableDateTimeField(
  Map<String, Object?> json,
  String key,
  String parentPath,
) {
  final value = _required(json, key, parentPath);
  if (value == null) {
    return null;
  }
  return _expectDateTime(value, _child(parentPath, key));
}

DateTime _expectDateTime(Object? value, String path) {
  if (value is! String) {
    throw ManifestFormatException(path, 'Expected an ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null || !value.endsWith('Z')) {
    throw ManifestFormatException(
      path,
      'Expected an ISO-8601 UTC timestamp ending in Z.',
    );
  }
  return parsed.toUtc();
}

Map<String, Object?> _expectObject(Object? value, String path) {
  if (value is Map<String, Object?>) {
    return value;
  }
  throw ManifestFormatException(path, 'Expected a JSON object.');
}

List<Object?> _expectList(Object? value, String path) {
  if (value is List<Object?>) {
    return value;
  }
  throw ManifestFormatException(path, 'Expected a JSON array.');
}

String _child(String parent, String key) =>
    parent.isEmpty ? key : '$parent.$key';

String _at(String parent, int index) => '$parent[$index]';
