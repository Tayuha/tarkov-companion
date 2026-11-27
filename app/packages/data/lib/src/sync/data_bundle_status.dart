import 'dart:convert';

import '../bundle/game_mode.dart';
import '../bundle/manifest.dart';
import '../database/dataset_state_repository.dart';
import '../dataset_kind.dart';
import 'manifest_repository.dart';

/// A read-only summary of the locally applied data bundle.
///
/// The About screen renders this value. It is assembled from the
/// `datasetState` bookkeeping and the cached manifest only; it performs no
/// network request and does not open the database itself.
final class DataBundleStatus {
  const DataBundleStatus({
    required this.mode,
    required this.appliedDatasets,
    required this.expectedDatasets,
    this.oldestAppliedAt,
    this.newestAppliedAt,
    this.newestSourceUpdatedAt,
    this.manifestVersion,
    this.bundleSchemaVersion,
    this.manifestGeneratedAt,
    this.manifestCheckedAt,
  });

  /// The mode the summary describes.
  final GameMode mode;

  /// Number of datasets currently recorded as applied.
  final int appliedDatasets;

  /// Number of datasets a complete bundle contains.
  final int expectedDatasets;

  /// When the oldest currently applied dataset was installed locally.
  final DateTime? oldestAppliedAt;

  /// When the newest currently applied dataset was installed locally.
  final DateTime? newestAppliedAt;

  /// The newest upstream fetch time recorded in `datasetState`.
  final DateTime? newestSourceUpdatedAt;

  /// `manifestVersion` from the cached manifest, when one is cached.
  final int? manifestVersion;

  /// `bundleSchemaVersion` from the cached manifest, when one is cached.
  final int? bundleSchemaVersion;

  /// `generatedAt` from the cached manifest, when one is cached.
  final DateTime? manifestGeneratedAt;

  /// When the cached manifest was last checked.
  final DateTime? manifestCheckedAt;

  /// Whether every expected dataset is applied.
  bool get isComplete =>
      expectedDatasets > 0 && appliedDatasets >= expectedDatasets;

  /// The age of the oldest applied dataset at [now], or `null` when no dataset
  /// has been applied.
  Duration? datasetAgeAt(DateTime now) {
    final oldest = oldestAppliedAt;
    if (oldest == null) {
      return null;
    }
    final age = now.toUtc().difference(oldest.toUtc());
    return age.isNegative ? Duration.zero : age;
  }

  /// Builds the summary for [mode].
  ///
  /// A corrupt cached manifest only loses the manifest-version rows: the
  /// dataset bookkeeping is still returned, so About remains useful with an
  /// external cache problem.
  static Future<DataBundleStatus> read({
    required GameMode mode,
    required DatasetStateRepository stateRepository,
    required ManifestRepository manifestRepository,
  }) async {
    final applied = await stateRepository.appliedForMode(mode);
    final cache = await manifestRepository.read(mode);

    DateTime? oldest;
    DateTime? newest;
    DateTime? newestSource;
    for (final state in applied.values) {
      final installed = state.appliedAt.toUtc();
      if (oldest == null || installed.isBefore(oldest)) {
        oldest = installed;
      }
      if (newest == null || installed.isAfter(newest)) {
        newest = installed;
      }
      final source = state.sourceUpdatedAt?.toUtc();
      if (source != null &&
          (newestSource == null || source.isAfter(newestSource))) {
        newestSource = source;
      }
    }

    BundleManifest? manifest;
    if (cache != null) {
      try {
        final decoded = jsonDecode(cache.manifestJson);
        manifest = BundleManifest.parse(decoded);
      } on Object {
        manifest = null;
      }
    }

    return DataBundleStatus(
      mode: mode,
      appliedDatasets: applied.length,
      expectedDatasets: DatasetKind.values.length,
      oldestAppliedAt: oldest,
      newestAppliedAt: newest,
      newestSourceUpdatedAt: newestSource,
      manifestVersion: manifest?.manifestVersion,
      bundleSchemaVersion: manifest?.bundleSchemaVersion,
      manifestGeneratedAt: manifest?.generatedAt,
      manifestCheckedAt: cache?.lastCheckedAt.toUtc(),
    );
  }
}
