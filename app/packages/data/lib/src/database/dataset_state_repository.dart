import 'package:drift/drift.dart';

import '../bundle/bundle_contract.dart';
import '../bundle/game_mode.dart';
import '../bundle/manifest.dart';
import '../dataset_kind.dart';
import 'app_database.dart';

/// What [DatasetStateRepository.recordApplied] did to the bookkeeping row.
enum DatasetApplyOutcome {
  /// The mode/dataset pair had no row; a new row was inserted.
  inserted,

  /// The row existed with different content; it was updated.
  updated,

  /// The row already described the same dataset; it was not touched.
  unchanged,
}

/// Why [DatasetStateRepository.recordApplied] refused to write.
enum DatasetApplyRejection {
  /// The dataset needs a newer record schema than this client implements.
  schemaVersionTooNew,
}

/// The result of recording an applied dataset.
sealed class DatasetApplyResult {
  const DatasetApplyResult();
}

/// The dataset state was written (or already matched).
final class DatasetApplied extends DatasetApplyResult {
  const DatasetApplied(this.outcome);

  final DatasetApplyOutcome outcome;
}

/// The dataset was refused and nothing was written.
final class DatasetApplyRejected extends DatasetApplyResult {
  const DatasetApplyRejected({
    required this.reason,
    required this.mode,
    required this.dataset,
    required this.datasetSchemaVersion,
    required this.supportedSchemaVersion,
  });

  final DatasetApplyRejection reason;
  final GameMode mode;
  final DatasetKind dataset;
  final int datasetSchemaVersion;
  final int supportedSchemaVersion;
}

/// The applied state of one dataset, independent of the drift row class.
final class AppliedDatasetState {
  const AppliedDatasetState({
    required this.checksum,
    required this.schemaVersion,
    required this.records,
    required this.appliedAt,
    required this.sourceUpdatedAt,
  });

  /// SHA-256 of the compressed dataset file that was applied.
  final String checksum;

  /// `datasets[].schemaVersion` of the applied manifest entry.
  final int schemaVersion;

  /// Number of records in the applied dataset.
  final int records;

  /// When this client applied the dataset.
  final DateTime appliedAt;

  /// Upstream fetch time from the manifest, when it provided one.
  final DateTime? sourceUpdatedAt;
}

/// Bookkeeping over the `datasetState` table.
///
/// The table is keyed by `(mode, dataset)`, so every operation is scoped to one
/// mode. Ingestion calls [recordApplied] after the dataset's rows are committed
/// (task 4.3); a re-apply with the same checksum, schema version and record
/// count is [DatasetApplyOutcome.unchanged] and does not rewrite the row, so
/// `appliedAt` keeps its original value.
final class DatasetStateRepository {
  const DatasetStateRepository(this._database);

  final AppDatabase _database;

  /// The applied state of every dataset in [mode], keyed by dataset name.
  ///
  /// An unknown dataset name in the table is a corruption of client-owned
  /// bookkeeping, so it throws instead of being silently skipped.
  Future<Map<DatasetKind, AppliedDatasetState>> appliedForMode(
    GameMode mode,
  ) async {
    final rows = await (_database.select(
      _database.datasetStates,
    )..where((row) => row.mode.equals(mode.wireValue))).get();

    final applied = <DatasetKind, AppliedDatasetState>{};
    for (final row in rows) {
      final dataset = DatasetKind.parse(row.dataset).valueOrNull;
      if (dataset == null) {
        throw StateError(
          'datasetState contains unknown dataset "${row.dataset}" '
          'for mode "${row.mode}".',
        );
      }
      applied[dataset] = AppliedDatasetState(
        checksum: row.checksum,
        schemaVersion: row.schemaVersion,
        records: row.records,
        appliedAt: row.appliedAt,
        sourceUpdatedAt: row.sourceUpdatedAt,
      );
    }
    return Map.unmodifiable(applied);
  }

  /// Records [dataset] as applied in [mode].
  ///
  /// * A missing row is inserted ([DatasetApplyOutcome.inserted]).
  /// * The same checksum, schema version and record count is
  ///   [DatasetApplyOutcome.unchanged] and performs no write, so [appliedAt]
  ///   and the rest of the row stay exactly as they were.
  /// * Any difference is written ([DatasetApplyOutcome.updated]) with the
  ///   supplied [appliedAt] (or now).
  ///
  /// A dataset whose `schemaVersion` is newer than
  /// [BundleContract.appDataSchemaVersion] is refused with
  /// [DatasetApplyRejected] before the transaction starts. Source metadata
  /// (`ETag`, timestamps, sizes) is diagnostics only and never decides that a
  /// dataset changed.
  Future<DatasetApplyResult> recordApplied(
    ManifestDataset dataset, {
    required GameMode mode,
    DateTime? appliedAt,
  }) async {
    if (!BundleContract.supportsDatasetSchema(dataset.schemaVersion)) {
      return DatasetApplyRejected(
        reason: DatasetApplyRejection.schemaVersionTooNew,
        mode: mode,
        dataset: dataset.dataset,
        datasetSchemaVersion: dataset.schemaVersion,
        supportedSchemaVersion: BundleContract.appDataSchemaVersion,
      );
    }

    final when = appliedAt ?? DateTime.now();
    return _database.transaction(() async {
      final existing =
          await (_database.select(_database.datasetStates)..where(
                (row) =>
                    row.mode.equals(mode.wireValue) &
                    row.dataset.equals(dataset.dataset.id),
              ))
              .getSingleOrNull();

      if (existing == null) {
        await _database
            .into(_database.datasetStates)
            .insert(
              DatasetStatesCompanion.insert(
                mode: mode.wireValue,
                dataset: dataset.dataset.id,
                checksum: dataset.sha256,
                schemaVersion: dataset.schemaVersion,
                records: dataset.records,
                sourceUpdatedAt: Value(dataset.source.fetchedAt),
                appliedAt: when,
              ),
            );
        return const DatasetApplied(DatasetApplyOutcome.inserted);
      }

      final isUnchanged =
          existing.checksum == dataset.sha256 &&
          existing.schemaVersion == dataset.schemaVersion &&
          existing.records == dataset.records;
      if (isUnchanged) {
        return const DatasetApplied(DatasetApplyOutcome.unchanged);
      }

      await (_database.update(_database.datasetStates)..where(
            (row) =>
                row.mode.equals(mode.wireValue) &
                row.dataset.equals(dataset.dataset.id),
          ))
          .write(
            DatasetStatesCompanion(
              checksum: Value(dataset.sha256),
              schemaVersion: Value(dataset.schemaVersion),
              records: Value(dataset.records),
              sourceUpdatedAt: Value(dataset.source.fetchedAt),
              appliedAt: Value(when),
            ),
          );
      return const DatasetApplied(DatasetApplyOutcome.updated);
    });
  }

  /// Whether [mode] already has exactly this dataset applied.
  ///
  /// Compares the same three fields as [recordApplied]: checksum, schema
  /// version and record count.
  Future<bool> isCurrent(GameMode mode, ManifestDataset dataset) async {
    final existing =
        await (_database.select(_database.datasetStates)..where(
              (row) =>
                  row.mode.equals(mode.wireValue) &
                  row.dataset.equals(dataset.dataset.id),
            ))
            .getSingleOrNull();

    return existing != null &&
        existing.checksum == dataset.sha256 &&
        existing.schemaVersion == dataset.schemaVersion &&
        existing.records == dataset.records;
  }

  /// Deletes every applied-dataset row for [mode] and returns the row count.
  ///
  /// Other modes are untouched. This is the bookkeeping half of a future full
  /// refresh; it does not touch game-data tables.
  Future<int> clearMode(GameMode mode) {
    return (_database.delete(
      _database.datasetStates,
    )..where((row) => row.mode.equals(mode.wireValue))).go();
  }
}
