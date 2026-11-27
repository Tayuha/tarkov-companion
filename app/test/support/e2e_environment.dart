import 'dart:convert';
import 'dart:io';

import 'package:tarkov_companion/src/app_session.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// A deterministic, temporary app installation for the end-to-end widget test.
///
/// Everything lives under one directory created with `createTempSync`, so the test
/// never reads or writes the user's real `~/.local/share/tarkov_companion`.
/// The database is a real file-backed SQLite database opened through the
/// production migration runner; only the sync transport is faked.
final class E2eEnvironment {
  E2eEnvironment._({
    required this.root,
    required this.session,
    required this._close,
  });

  /// Fixed clock used by the fixture sync and the profile services.
  static DateTime get clock => DateTime.utc(2026, 11, 27, 9);

  /// Temp root holding the database and the exported progress file.
  final Directory root;

  /// The session the shell opens. Sync is the fixture bundle and there is no
  /// background update controller, so no timer or network call runs.
  final AppSessionReady session;

  final Future<void> Function() _close;

  /// Creates the temp installation and opens the database.
  ///
  /// The profile repository runs its real first-launch path, so the session
  /// starts with one active regular profile and no game data: exactly the
  /// first-run state.
  static Future<E2eEnvironment> create() async {
    final root = Directory.systemTemp.createTempSync('tarkov_e2e_');
    final databasePath = '${root.path}/db/tarkov_companion.sqlite';
    final opened = await openAppDatabase(
      databasePath,
      open: (path) => AppDatabase.atPath(path),
      clock: () => clock,
    );
    if (opened is! DatabaseOpened) {
      await opened.close();
      await root.delete(recursive: true);
      throw StateError('The end-to-end fixture database did not open.');
    }

    final database = opened.database;
    final profiles = ProfileServices(database, clock: () => clock);
    final active = await profiles.profiles.ensureFirstLaunch();
    final bundleDirectory = _fixtureBundleDirectory();
    final sync = FixtureBundleSync(
      database: database,
      directory: bundleDirectory,
      clock: () => clock,
    );

    var closed = false;
    Future<void> closeDatabase() async {
      if (closed) return;
      closed = true;
      await opened.close();
    }

    return E2eEnvironment._(
      root: root,
      close: closeDatabase,
      session: AppSessionReady(
        sync: sync,
        // The database has no applied dataset yet: this is the first run.
        hasAppliedDatasets: false,
        catalog: CatalogRepository(database),
        quests: QuestRepository(database),
        activeProfileId: active.id,
        profileServices: profiles,
        close: closeDatabase,
      ),
    );
  }

  /// Closes the database (when the tree has not already done so) and removes
  /// the whole temp installation. Safe to call more than once.
  Future<void> dispose() async {
    await _close();
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
  }
}

/// The committed bundle fixture from the data package.
///
/// `flutter test` runs from `app/`, so the data package fixture is a fixed
/// relative path. Walking up from the working directory also keeps an IDE run
/// from the repository root working; nothing here touches the network.
Directory _fixtureBundleDirectory() {
  var directory = Directory.current;
  for (var depth = 0; depth < 4; depth++) {
    final candidate = Directory(
      '${directory.path}/packages/data/test/fixtures/bundle',
    );
    if (candidate.existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('Could not find the data package bundle fixture.');
}

/// A [SyncService] that applies the committed bundle fixture instead of
/// downloading it.
///
/// The first `prepare` reports both fixture datasets as pending, so the first
/// run gate shows the estimate and Start button. `run` then feeds the committed
/// `.jsonl.zst` files to the production [DatasetIngestor], so every row the
/// screens read comes from the same pipeline output the release uses. Once the
/// run succeeds, later `prepare` calls report no pending work and the shell's
/// upstream status stays quiet.
final class FixtureBundleSync implements SyncService {
  FixtureBundleSync({
    required this.database,
    required this.directory,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final AppDatabase database;
  final Directory directory;
  final DateTime Function() _clock;

  BundleManifest? _manifest;
  bool _applied = false;

  Future<BundleManifest> _loadManifest() async {
    final existing = _manifest;
    if (existing != null) return existing;
    final decoded = jsonDecode(
      File('${directory.path}/manifest.json').readAsStringSync(),
    );
    return _manifest = BundleManifest.parse(decoded);
  }

  @override
  Future<SyncPreparation> prepare(GameMode mode) async {
    final manifest = await _loadManifest();
    return SyncPreparation(
      mode: mode,
      manifest: manifest,
      manifestUri: Uri.parse('fixture://bundle/manifest.json'),
      checkedAt: _clock(),
      manifestNotModified: false,
      applied: [
        if (_applied)
          for (final entry in manifest.datasets) entry.dataset,
      ],
      pending: _applied ? const [] : manifest.datasets,
    );
  }

  @override
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  }) async {
    final prepared = preparation ?? await prepare(mode);
    final ingestor = DatasetIngestor(database, clock: _clock);
    final applied = <DatasetKind>[];
    var bytes = 0;

    for (final dataset in prepared.pending) {
      final file = File('${directory.path}/${dataset.path}');
      await ingestor.ingest(mode: mode, dataset: dataset, compressedFile: file);
      applied.add(dataset.dataset);
      bytes += dataset.compressedBytes;
      onProgress?.call(
        SyncProgress(
          mode: mode,
          dataset: dataset.dataset,
          phase: SyncPhase.ingesting,
          datasetIndex: applied.length - 1,
          datasetCount: prepared.pending.length,
          datasetBytes: dataset.compressedBytes,
          datasetTotalBytes: dataset.compressedBytes,
          overallBytes: bytes,
          overallTotalBytes: prepared.totalBytes,
          recordsProcessed: dataset.records,
          recordsTotal: dataset.records,
        ),
      );
    }

    _applied = true;
    return SyncRunResult(
      mode: mode,
      applied: applied,
      skipped: const [],
      bytesDownloaded: 0,
      completedAt: _clock(),
    );
  }
}
