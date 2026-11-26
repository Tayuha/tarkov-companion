import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import 'app_paths.dart';

/// An opened application, or a database that needs recovery.
///
/// The shell only needs the sync service, the first-run decision, and a way to
/// release the handles. Keeping the database private to this file is what lets
/// `AppRoot` be tested with a hand-built session and no SQLite file.
sealed class AppSession {
  AppSession({required this.close});

  /// Releases the database, HTTP client, and log sink.
  final Future<void> Function() close;
}

/// A normally opened session.
final class AppSessionReady extends AppSession {
  AppSessionReady({
    required this.sync,
    required this.hasAppliedDatasets,
    required super.close,
  });

  /// Manifest fetch, download, and ingestion, ready for the first-run gate or
  /// a background update.
  final SyncService sync;

  /// Whether the active mode already has at least one applied dataset.
  final bool hasAppliedDatasets;
}

/// The database could not be opened and is available read-only.
final class AppSessionRecovery extends AppSession {
  AppSessionRecovery({
    required this.message,
    required this.failure,
    required super.close,
  });

  final String message;
  final Object failure;
}

/// Opens the database through the migration lifecycle and builds the sync
/// stack over it.
///
/// [databaseFactory] and [httpClient] are injectable for tests. Production
/// omits both: the database runs on a background isolate and the HTTP client is
/// the HTTPS-only allowlisted client.
Future<AppSession> openAppSession({
  required AppPaths paths,
  AppDatabaseFactory? databaseFactory,
  AllowlistedHttpClient? httpClient,
  DateTime Function()? clock,
}) async {
  await paths.ensureCreated();

  final logSink = RotatingFileLogSink(directory: paths.logsDirectory);
  final logger = Logger(sink: logSink);

  final opened = await openAppDatabase(
    paths.databasePath,
    open: databaseFactory,
    clock: clock,
  );

  if (opened is DatabaseRecovery) {
    await logger.error(
      'The database opened in read-only recovery mode.',
      context: {'path': opened.databasePath, 'failure': '${opened.failure}'},
    );
    return AppSessionRecovery(
      message:
          'The local database could not be opened. It was left untouched and '
          'is available read-only. ${opened.failure}',
      failure: opened.failure,
      close: () async {
        await opened.close();
        await logger.close();
      },
    );
  }

  final database = (opened as DatabaseOpened).database;
  final stateRepository = DatasetStateRepository(database);
  final client = httpClient ?? AllowlistedHttpClient();

  try {
    final applied = await stateRepository.appliedForMode(GameMode.regular);
    final manifestRepository = ManifestRepository(database, clock: clock);
    final fetcher = ManifestFetcher(client, manifestRepository, clock: clock);
    final coordinator = SyncCoordinator(
      loadManifest: (mode) async {
        final result = await fetcher.fetch(mode);
        return SyncManifestSnapshot.fromFetch(
          result,
          manifestUri: ManifestFetcher.uriFor(mode),
        );
      },
      downloader: DatasetDownloader(client),
      ingestor: DatasetIngestor(database, clock: clock),
      stateRepository: stateRepository,
      directory: paths.downloadsDirectory,
      clock: clock,
    );

    await logger.info(
      'Application session opened.',
      context: {
        'database': paths.databasePath,
        'appliedDatasets': applied.length,
      },
    );

    return AppSessionReady(
      sync: coordinator,
      hasAppliedDatasets: applied.isNotEmpty,
      close: () async {
        client.close();
        await opened.close();
        await logger.close();
      },
    );
  } on Object catch (error) {
    client.close();
    await opened.close();
    await logger.error(
      'Application session setup failed.',
      context: {'failure': '$error'},
    );
    await logger.close();
    rethrow;
  }
}
