import 'dart:io';

import '../bundle/bundle_contract.dart';
import '../bundle/game_mode.dart';
import '../bundle/manifest.dart';
import '../database/dataset_state_repository.dart';
import '../dataset_kind.dart';
import '../net/http_errors.dart';
import 'dataset_downloader.dart';
import 'dataset_ingestor.dart';
import 'manifest_fetcher.dart';

/// Loads a manifest for [mode].
///
/// The production adapter wraps `ManifestFetcher.fetch`; tests return a
/// hand-built manifest without touching HTTP. Keeping this a function rather
/// than the concrete fetcher lets the coordinator be exercised with a fake
/// manifest while the downloader and ingestor stay real.
typedef SyncManifestLoader = Future<SyncManifestSnapshot> Function(
  GameMode mode,
);

/// Receives one event per download chunk and per ingested record.
typedef SyncProgressListener = void Function(SyncProgress progress);

/// A manifest plus the context needed to download its datasets.
final class SyncManifestSnapshot {
  const SyncManifestSnapshot({
    required this.manifest,
    required this.manifestUri,
    required this.checkedAt,
    this.notModified = false,
  });

  /// Wraps the result of a real `ManifestFetcher.fetch`.
  ///
  /// [manifestUri] is the URL the datasets are resolved against. Production
  /// passes `ManifestFetcher.uriFor(mode)`; the local-server integration test
  /// passes its loopback URL.
  factory SyncManifestSnapshot.fromFetch(
    ManifestFetchResult result, {
    required Uri manifestUri,
  }) {
    return SyncManifestSnapshot(
      manifest: result.manifest,
      manifestUri: manifestUri,
      checkedAt: result.checkedAt,
      notModified: result.isNotModified,
    );
  }

  /// The parsed, validated bundle manifest.
  final BundleManifest manifest;

  /// The manifest URL; dataset paths resolve relative to it.
  final Uri manifestUri;

  /// When the manifest was checked, from the fetcher's clock.
  final DateTime checkedAt;

  /// Whether the server answered `304 Not Modified`.
  final bool notModified;
}

/// The work [SyncCoordinator.run] would perform for a mode.
final class SyncPreparation {
  SyncPreparation({
    required this.mode,
    required this.manifest,
    required this.manifestUri,
    required this.checkedAt,
    required this.manifestNotModified,
    required List<DatasetKind> applied,
    required List<ManifestDataset> pending,
  }) : applied = List.unmodifiable(applied),
       pending = List.unmodifiable(pending);

  final GameMode mode;
  final BundleManifest manifest;
  final Uri manifestUri;
  final DateTime checkedAt;
  final bool manifestNotModified;

  /// Datasets already current in `datasetState`; [run] skips them.
  final List<DatasetKind> applied;

  /// Datasets that are not current, in manifest order.
  final List<ManifestDataset> pending;

  /// Compressed bytes that [run] would download.
  int get totalBytes =>
      pending.fold(0, (sum, entry) => sum + entry.compressedBytes);

  /// Number of datasets in [pending].
  int get datasetCount => pending.length;

  /// Whether the applied database already matches the manifest.
  bool get isComplete => pending.isEmpty;
}

/// What one [SyncCoordinator.run] applied.
final class SyncRunResult {
  SyncRunResult({
    required this.mode,
    required List<DatasetKind> applied,
    required List<DatasetKind> skipped,
    required this.bytesDownloaded,
    required this.completedAt,
  }) : applied = List.unmodifiable(applied),
       skipped = List.unmodifiable(skipped);

  final GameMode mode;

  /// Datasets downloaded and ingested by this run.
  final List<DatasetKind> applied;

  /// Datasets that were already current when the run reached them.
  final List<DatasetKind> skipped;

  /// Compressed bytes actually downloaded in this run.
  final int bytesDownloaded;

  final DateTime completedAt;

  /// Whether the run applied nothing because everything was current.
  bool get isNoOp => applied.isEmpty;
}

/// Which stage of a dataset a [SyncProgress] event describes.
enum SyncPhase { downloading, ingesting }

/// One progress event for [SyncCoordinator.run].
///
/// [datasetFraction] is progress through the current dataset; [fraction] is the
/// overall run, so a determinate bar can be driven from either.
final class SyncProgress {
  const SyncProgress({
    required this.mode,
    required this.dataset,
    required this.phase,
    required this.datasetIndex,
    required this.datasetCount,
    required this.datasetBytes,
    required this.datasetTotalBytes,
    required this.overallBytes,
    required this.overallTotalBytes,
    required this.recordsProcessed,
    required this.recordsTotal,
  });

  final GameMode mode;
  final DatasetKind dataset;
  final SyncPhase phase;

  /// Zero-based position of [dataset] in the prepared pending list.
  final int datasetIndex;

  /// Number of datasets in the prepared pending list.
  final int datasetCount;

  /// Bytes received (downloading) for [dataset].
  final int datasetBytes;

  /// Expected compressed bytes for [dataset].
  final int datasetTotalBytes;

  /// Bytes accounted for across the whole run.
  final int overallBytes;

  /// Expected compressed bytes across the whole run.
  final int overallTotalBytes;

  /// Records ingested for [dataset] while [phase] is [SyncPhase.ingesting].
  final int recordsProcessed;

  /// Records the manifest declares for [dataset].
  final int recordsTotal;

  /// One-based position, for display.
  int get datasetNumber => datasetIndex + 1;

  /// Progress through [dataset], in `0.0..1.0`.
  double get datasetFraction {
    if (datasetTotalBytes <= 0) {
      return 1;
    }
    return (datasetBytes / datasetTotalBytes).clamp(0.0, 1.0).toDouble();
  }

  /// Progress through the whole run, in `0.0..1.0`.
  double get fraction {
    if (overallTotalBytes <= 0) {
      return 1;
    }
    return (overallBytes / overallTotalBytes).clamp(0.0, 1.0).toDouble();
  }
}

/// Why a first-run or update sync could not complete.
enum SyncFailure {
  /// No usable connection: DNS, connect, or a request timeout.
  offline,

  /// The manifest needs a newer app or bundle schema.
  compatibility,

  /// A downloaded dataset did not match its size or SHA-256.
  checksum,

  /// A verified dataset failed to ingest; the transaction rolled back.
  ingest,

  /// The caller cancelled during a download.
  cancelled,

  /// Any other fetch, download, or local-storage failure.
  download,
}

/// A typed sync failure.
///
/// Every subtype leaves the database in its previous applied state: the
/// downloader removes partial files, and ingestion runs in one transaction.
sealed class SyncException implements Exception {
  const SyncException(
    this.failure, {
    required this.message,
    required this.mode,
    this.dataset,
    this.cause,
  });

  final SyncFailure failure;

  /// Human-readable reason; safe to show in the first-run screen.
  final String message;

  final GameMode mode;

  /// The dataset being processed, when the failure is dataset-scoped.
  final DatasetKind? dataset;

  final Object? cause;

  @override
  String toString() {
    final scope = dataset == null ? '' : ' (${dataset!.id})';
    return '$runtimeType$scope: $message';
  }
}

/// The network is unavailable or a request timed out.
final class SyncOfflineException extends SyncException {
  const SyncOfflineException({
    required super.mode,
    super.dataset,
    required super.message,
    super.cause,
  }) : super(SyncFailure.offline);
}

/// The manifest declares a bundle or dataset schema this client cannot read.
final class SyncCompatibilityException extends SyncException {
  SyncCompatibilityException({
    required super.mode,
    required this.status,
    required this.reason,
  }) : super(
         SyncFailure.compatibility,
         message: 'This build cannot read the published data. $reason',
       );

  final ManifestCompatibility status;
  final String reason;
}

/// A dataset was discarded because its bytes did not verify.
final class SyncChecksumException extends SyncException {
  const SyncChecksumException({
    required super.mode,
    required super.dataset,
    required super.message,
    super.cause,
  }) : super(SyncFailure.checksum);
}

/// A verified dataset could not be ingested; nothing was applied.
final class SyncIngestException extends SyncException {
  const SyncIngestException({
    required super.mode,
    required super.dataset,
    required super.message,
    super.cause,
  }) : super(SyncFailure.ingest);
}

/// The caller cancelled the sync.
///
/// A dataset that was already ingesting when cancellation arrived may finish
/// and be applied; every other dataset is untouched. The next run resumes.
final class SyncCancelled extends SyncException {
  const SyncCancelled({
    required super.mode,
    super.dataset,
    super.message = 'The data download was cancelled.',
    super.cause,
  }) : super(SyncFailure.cancelled);
}

/// A fetch, download, or local-storage failure other than the cases above.
final class SyncDownloadException extends SyncException {
  const SyncDownloadException({
    required super.mode,
    super.dataset,
    required super.message,
    super.cause,
  }) : super(SyncFailure.download);
}

/// The operations the first-run screen needs.
///
/// `SyncCoordinator` is the production implementation; widget tests implement
/// this interface directly so they never touch the network or a database.
abstract interface class SyncService {
  /// Fetches the manifest, checks compatibility, and reports what must be
  /// downloaded.
  Future<SyncPreparation> prepare(GameMode mode);

  /// Downloads and ingests the datasets in [preparation] (or prepares first).
  ///
  /// Already-current datasets are skipped even if they appear in
  /// [preparation], so a retry after a failure or cancellation resumes.
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  });
}

/// Composes manifest fetch, download, and ingestion into one resumable pass.
///
/// ## Guarantees
///
/// * **Nothing is applied partially.** A dataset becomes visible only after
///   `DatasetDownloader` verified its bytes and `DatasetIngestor` committed its
///   single transaction. `datasetState` moves in that same transaction.
/// * **Resume is implicit.** [prepare] excludes datasets whose checksum,
///   schema version and record count already match `datasetState`; [run]
///   re-checks `isCurrent` before each dataset. A retry therefore starts at the
///   first dataset that was not applied and never restarts the whole download.
/// * **Cancel is safe.** Cancellation is checked between datasets, passed to
///   the downloader, and checked again before ingestion. A cancelled download
///   leaves no `.part` and no `datasetState` row.
/// * **Failures are typed.** Offline, compatibility, checksum, ingest,
///   cancellation, and other download failures have distinct exception types
///   and names.
///
/// Dataset files live under `<directory>/<mode>/<dataset.path>`. The verified
/// file is kept after ingestion so a later diagnosis can compare it with the
/// manifest; it is never read by the UI.
final class SyncCoordinator implements SyncService {
  SyncCoordinator({
    required this.loadManifest,
    required this.downloader,
    required this.ingestor,
    required this.stateRepository,
    required this.directory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SyncManifestLoader loadManifest;
  final DatasetDownloader downloader;
  final DatasetIngestor ingestor;
  final DatasetStateRepository stateRepository;
  final Directory directory;
  final DateTime Function() _clock;

  @override
  Future<SyncPreparation> prepare(GameMode mode) async {
    final snapshot = await _fetch(mode);
    final manifest = snapshot.manifest;
    final compatibility = manifest.checkCompatibility();
    if (!compatibility.isCompatible) {
      throw SyncCompatibilityException(
        mode: mode,
        status: compatibility.status,
        reason: compatibility.reason,
      );
    }

    final applied = <DatasetKind>[];
    final pending = <ManifestDataset>[];
    for (final entry in manifest.datasets) {
      if (!BundleContract.supportsDatasetSchema(entry.schemaVersion)) {
        throw SyncCompatibilityException(
          mode: mode,
          status: ManifestCompatibility.appUpdateRequired,
          reason:
              'Dataset ${entry.dataset.id} needs schema version '
              '${entry.schemaVersion}; this client supports '
              '${BundleContract.appDataSchemaVersion}.',
        );
      }
      if (await stateRepository.isCurrent(mode, entry)) {
        applied.add(entry.dataset);
      } else {
        pending.add(entry);
      }
    }

    return SyncPreparation(
      mode: mode,
      manifest: manifest,
      manifestUri: snapshot.manifestUri,
      checkedAt: snapshot.checkedAt,
      manifestNotModified: snapshot.notModified,
      applied: applied,
      pending: pending,
    );
  }

  @override
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw SyncCancelled(mode: mode);
    }

    final plan = preparation ?? await prepare(mode);
    if (plan.mode != mode) {
      throw ArgumentError.value(
        plan.mode,
        'preparation',
        'The preparation belongs to ${plan.mode.wireValue}, not '
            '${mode.wireValue}.',
      );
    }

    final applied = <DatasetKind>[];
    final skipped = <DatasetKind>[...plan.applied];
    final totalBytes = plan.totalBytes;
    var completedBytes = 0;
    var downloadedBytes = 0;

    void emit(
      ManifestDataset entry,
      int datasetIndex,
      SyncPhase phase,
      int datasetBytes, {
      int recordsProcessed = 0,
    }) {
      final listener = onProgress;
      if (listener == null) {
        return;
      }
      final overall = completedBytes + datasetBytes;
      listener(
        SyncProgress(
          mode: mode,
          dataset: entry.dataset,
          phase: phase,
          datasetIndex: datasetIndex,
          datasetCount: plan.datasetCount,
          datasetBytes: datasetBytes,
          datasetTotalBytes: entry.compressedBytes,
          overallBytes: overall > totalBytes ? totalBytes : overall,
          overallTotalBytes: totalBytes,
          recordsProcessed: recordsProcessed,
          recordsTotal: entry.records,
        ),
      );
    }

    for (var index = 0; index < plan.pending.length; index++) {
      if (cancellation?.isCancelled ?? false) {
        throw SyncCancelled(mode: mode);
      }

      final entry = plan.pending[index];
      if (await stateRepository.isCurrent(mode, entry)) {
        // A retry can reach a dataset an earlier run already applied. Count its
        // bytes so overall progress still starts where the previous run ended.
        skipped.add(entry.dataset);
        completedBytes += entry.compressedBytes;
        continue;
      }

      emit(entry, index, SyncPhase.downloading, 0);

      final destination = _destinationFor(mode, entry);
      try {
        await downloader.download(
          manifestUri: plan.manifestUri,
          dataset: entry,
          destination: destination,
          cancellation: cancellation,
          onProgress: (progress) {
            emit(entry, index, SyncPhase.downloading, progress.downloadedBytes);
          },
        );
      } on DownloadCancelled catch (error) {
        throw SyncCancelled(
          mode: mode,
          dataset: entry.dataset,
          message: 'The download of ${entry.dataset.id} was cancelled.',
          cause: error,
        );
      } on DownloadSizeMismatchException catch (error) {
        throw SyncChecksumException(
          mode: mode,
          dataset: entry.dataset,
          message:
              '${entry.dataset.id} had ${error.actualBytes} bytes; the '
              'manifest declares ${error.expectedBytes}.',
          cause: error,
        );
      } on DownloadChecksumMismatchException catch (error) {
        throw SyncChecksumException(
          mode: mode,
          dataset: entry.dataset,
          message:
              '${entry.dataset.id} failed its SHA-256 verification and was '
              'discarded.',
          cause: error,
        );
      } on SocketException catch (error) {
        throw SyncOfflineException(
          mode: mode,
          dataset: entry.dataset,
          message: 'Could not reach the data server. Check your connection.',
          cause: error,
        );
      } on HttpTimeoutException catch (error) {
        throw SyncOfflineException(
          mode: mode,
          dataset: entry.dataset,
          message: 'The data server did not respond in time.',
          cause: error,
        );
      } on DatasetDownloadException catch (error) {
        throw SyncDownloadException(
          mode: mode,
          dataset: entry.dataset,
          message: 'Could not download ${entry.dataset.id}: ${error.message}',
          cause: error,
        );
      } on HttpClientException catch (error) {
        throw SyncDownloadException(
          mode: mode,
          dataset: entry.dataset,
          message: 'Could not download ${entry.dataset.id}: ${error.message}',
          cause: error,
        );
      } on IOException catch (error) {
        throw SyncDownloadException(
          mode: mode,
          dataset: entry.dataset,
          message: 'Could not download ${entry.dataset.id}: $error',
          cause: error,
        );
      }

      downloadedBytes += entry.compressedBytes;

      if (cancellation?.isCancelled ?? false) {
        throw SyncCancelled(
          mode: mode,
          dataset: entry.dataset,
          message:
              'Downloaded ${entry.dataset.id}, but the sync was cancelled '
              'before it was applied.',
        );
      }

      emit(entry, index, SyncPhase.ingesting, entry.compressedBytes);
      try {
        await ingestor.ingest(
          mode: mode,
          dataset: entry,
          compressedFile: destination,
          onProgress: (progress) {
            emit(
              entry,
              index,
              SyncPhase.ingesting,
              entry.compressedBytes,
              recordsProcessed: progress.recordsProcessed,
            );
          },
        );
      } on IngestError catch (error) {
        throw SyncIngestException(
          mode: mode,
          dataset: entry.dataset,
          message: 'Could not install ${entry.dataset.id}: ${error.message}',
          cause: error,
        );
      }

      applied.add(entry.dataset);
      completedBytes += entry.compressedBytes;
    }

    if (cancellation?.isCancelled ?? false) {
      throw SyncCancelled(mode: mode);
    }

    return SyncRunResult(
      mode: mode,
      applied: applied,
      skipped: skipped,
      bytesDownloaded: downloadedBytes,
      completedAt: _clock(),
    );
  }

  Future<SyncManifestSnapshot> _fetch(GameMode mode) async {
    try {
      return await loadManifest(mode);
    } on SocketException catch (error) {
      throw SyncOfflineException(
        mode: mode,
        message: 'Could not reach the data server. Check your connection.',
        cause: error,
      );
    } on HttpTimeoutException catch (error) {
      throw SyncOfflineException(
        mode: mode,
        message: 'The data server did not respond in time.',
        cause: error,
      );
    } on ManifestFetchException catch (error) {
      throw SyncDownloadException(
        mode: mode,
        message: 'Could not load the data manifest: ${error.message}',
        cause: error,
      );
    } on HttpClientException catch (error) {
      throw SyncDownloadException(
        mode: mode,
        message: 'Could not load the data manifest: ${error.message}',
        cause: error,
      );
    } on IOException catch (error) {
      throw SyncDownloadException(
        mode: mode,
        message: 'Could not load the data manifest: $error',
        cause: error,
      );
    }
  }

  File _destinationFor(GameMode mode, ManifestDataset entry) {
    return File(_join(directory.path, mode.wireValue, entry.path));
  }

  static String _join(String first, String second, [String? third]) {
    final separator = Platform.pathSeparator;
    final base = first.endsWith(separator)
        ? first.substring(0, first.length - separator.length)
        : first;
    final middle = second.startsWith(separator) ? second : '$separator$second';
    final value = '$base$middle';
    if (third == null) {
      return value;
    }
    return '$value$separator${third.startsWith(separator) ? third.substring(separator.length) : third}';
  }
}
