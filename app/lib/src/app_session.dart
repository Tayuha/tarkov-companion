import 'dart:async';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import 'app_paths.dart';
import 'sync_monitors.dart';

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
    this.catalog,
    this.quests,
    this.activeProfileId,
    this.profileServices,
    this.settings,
    this.updates,
    this.dataBundle,
    required super.close,
  });

  /// Manifest fetch, download, and ingestion, ready for the first-run gate or
  /// a background update.
  final SyncService sync;

  /// Whether the active mode already has at least one applied dataset.
  ///
  /// Any applied dataset is enough to render the shell from local data. A
  /// partial install opens the shell too; the background update check resumes
  /// the missing datasets without a blocking gate.
  final bool hasAppliedDatasets;

  /// Query facade for the catalog, when a real database is open.
  ///
  /// Optional so shell widget tests can build a session without SQLite; the
  /// production session always provides it.
  final CatalogRepository? catalog;

  /// Query facade for the quest list. Optional for the same reason.
  final QuestRepository? quests;

  /// Active profile id used for quest progress badges, when available.
  final String? activeProfileId;

  /// Profile management services for the Profiles tab.
  ///
  /// The shell shows the tab only when this is non-null, so a session built in
  /// a test without SQLite keeps the original two-tab layout.
  final ProfileServices? profileServices;

  /// Typed access to local app preferences, when a real database is open.
  ///
  /// The desktop shell uses this for persisted window geometry; tests may
  /// omit it.
  final SettingsRepository? settings;

  /// Background update controls and their persisted status.
  ///
  /// Optional so shell widget tests can build a session without a scheduler.
  /// The production session always provides it; [AppRoot] starts it after the
  /// first local-data frame.
  final UpdateCheckControl? updates;

  /// A read-only summary of the locally applied data bundle for About.
  final DataBundleStatus? dataBundle;
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
  NetworkMonitor? networkMonitor,
  VisibilityMonitor? visibilityMonitor,
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
  final settings = SettingsRepository(
    database,
    onWarning: (message) => unawaited(logger.warn(message)),
  );

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

    final profileServices = ProfileServices(database);
    final activeProfile = await profileServices.profiles.ensureFirstLaunch();

    final dataBundle = await DataBundleStatus.read(
      mode: GameMode.regular,
      stateRepository: stateRepository,
      manifestRepository: manifestRepository,
    );

    // Any applied dataset is enough to open the shell from local data. A
    // partial install is repaired by the background update check instead of
    // blocking the user behind the first-run gate. Only a database with no
    // dataset at all still needs the first-run download.
    final hasAppliedDatasets = applied.isNotEmpty;

    final updates = UpdateCheckController(
      settings: settings,
      sync: coordinator,
      network: networkMonitor ?? const AlwaysOnlineNetworkMonitor(),
      visibility:
          visibilityMonitor ?? const AlwaysForegroundVisibilityMonitor(),
      clock: clock,
    );

    return AppSessionReady(
      sync: coordinator,
      hasAppliedDatasets: hasAppliedDatasets,
      catalog: CatalogRepository(database),
      quests: QuestRepository(database),
      activeProfileId: activeProfile.id,
      profileServices: profileServices,
      settings: settings,
      updates: updates,
      dataBundle: dataBundle,
      close: () async {
        await updates.dispose();
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
