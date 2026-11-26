import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';
import '../support/database_helpers.dart';

/// A transport fake that serves caller-supplied bytes by file name.
///
/// No socket is opened. It can be switched to a custom handler so a test can
/// stream chunks, stall, or throw a transport error deterministically.
final class _FakeBundleClient extends http.BaseClient {
  _FakeBundleClient(this.resources, {this.handler});

  final Map<String, List<int>> resources;
  final FutureOr<http.StreamedResponse> Function(http.BaseRequest)? handler;
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final handler = this.handler;
    if (handler != null) {
      return handler(request);
    }

    final name = request.url.pathSegments.last;
    final bytes = resources[name];
    if (bytes == null) {
      return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
    }
    return http.StreamedResponse(
      Stream<List<int>>.fromIterable([bytes]),
      200,
      contentLength: bytes.length,
    );
  }

  @override
  void close() {}
}

void main() {
  final manifestUri = Uri.parse(
    'https://github.com/Tayuha/tarkov-companion/releases/download/'
    'data-regular-latest/manifest.json',
  );
  final checkedAt = DateTime.utc(2026, 11, 26, 12);

  late AppDatabase db;
  late Directory temporary;
  late BundleManifest fixtureManifest;
  late List<int> itemsBytes;
  late List<int> tasksBytes;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
    fixtureManifest = await readBundleFixtureManifest();
    final fixtureDirectory = await bundleFixtureDirectory();
    itemsBytes = await File('${fixtureDirectory.path}/items.jsonl.zst')
        .readAsBytes();
    tasksBytes = await File('${fixtureDirectory.path}/tasks.jsonl.zst')
        .readAsBytes();
  });

  tearDown(() => db.close());

  SyncManifestSnapshot snapshot(
    BundleManifest manifest, {
    Uri? uri,
    bool notModified = false,
  }) {
    return SyncManifestSnapshot(
      manifest: manifest,
      manifestUri: uri ?? manifestUri,
      checkedAt: checkedAt,
      notModified: notModified,
    );
  }

  ({
    SyncCoordinator coordinator,
    _FakeBundleClient fake,
    AllowlistedHttpClient client,
  })
  build(
    _FakeBundleClient fake, {
    SyncManifestLoader? loadManifest,
    BundleManifest? manifest,
  }) {
    final client = AllowlistedHttpClient(
      innerClient: fake,
      timeout: const Duration(seconds: 5),
    );
    addTearDown(client.close);
    final coordinator = SyncCoordinator(
      loadManifest:
          loadManifest ?? (_) async => snapshot(manifest ?? fixtureManifest),
      downloader: DatasetDownloader(client),
      ingestor: DatasetIngestor(db, batchSize: 2, clock: () => checkedAt),
      stateRepository: DatasetStateRepository(db),
      directory: temporary,
      clock: () => checkedAt,
    );
    return (coordinator: coordinator, fake: fake, client: client);
  }

  Map<String, List<int>> fixtureResources() => {
    'items.jsonl.zst': itemsBytes,
    'tasks.jsonl.zst': tasksBytes,
  };

  ManifestDataset datasetEntry(DatasetKind kind) =>
      datasetIn(fixtureManifest, kind);

  test(
    'prepare skips datasets already recorded as current and run is a no-op',
    () async {
      final state = DatasetStateRepository(db);
      for (final entry in fixtureManifest.datasets) {
        await state.recordApplied(
          entry,
          mode: GameMode.regular,
          appliedAt: checkedAt,
        );
      }

      final harnessed = build(_FakeBundleClient(fixtureResources()));
      final preparation = await harnessed.coordinator.prepare(GameMode.regular);

      expect(preparation.pending, isEmpty);
      expect(preparation.isComplete, isTrue);
      expect(preparation.applied, [DatasetKind.items, DatasetKind.tasks]);
      expect(preparation.totalBytes, 0);

      final result = await harnessed.coordinator.run(
        GameMode.regular,
        preparation: preparation,
      );

      expect(result.applied, isEmpty);
      expect(result.isNoOp, isTrue);
      expect(result.skipped, [DatasetKind.items, DatasetKind.tasks]);
      expect(result.bytesDownloaded, 0);
      expect(harnessed.fake.requests, isEmpty);
    },
  );

  test('run downloads and ingests in manifest order and reports progress that '
      'never moves backwards', () async {
    final harnessed = build(_FakeBundleClient(fixtureResources()));
    final progress = <SyncProgress>[];

    final result = await harnessed.coordinator.run(
      GameMode.regular,
      onProgress: progress.add,
    );

    expect(result.applied, [DatasetKind.items, DatasetKind.tasks]);
    expect(result.bytesDownloaded, 3185 + 1641);
    expect(
      harnessed.fake.requests
          .map((request) => request.url.pathSegments.last)
          .toList(),
      ['items.jsonl.zst', 'tasks.jsonl.zst'],
    );

    expect(progress.first.dataset, DatasetKind.items);
    expect(progress.first.phase, SyncPhase.downloading);
    expect(progress.first.datasetBytes, 0);

    final lastItems = progress.lastIndexWhere(
      (event) => event.dataset == DatasetKind.items,
    );
    final firstTasks = progress.indexWhere(
      (event) => event.dataset == DatasetKind.tasks,
    );
    expect(lastItems, lessThan(firstTasks));
    expect(
      progress
          .where(
            (event) =>
                event.dataset == DatasetKind.items &&
                event.phase == SyncPhase.ingesting,
          )
          .isNotEmpty,
      isTrue,
    );

    for (var index = 1; index < progress.length; index++) {
      expect(
        progress[index].fraction,
        greaterThanOrEqualTo(progress[index - 1].fraction),
        reason: 'overall progress must never move backwards',
      );
      expect(progress[index].datasetFraction, greaterThanOrEqualTo(0.0));
    }
    expect(progress.last.dataset, DatasetKind.tasks);
    expect(progress.last.phase, SyncPhase.ingesting);
    expect(progress.last.fraction, 1.0);
    expect(progress.last.recordsProcessed, 4);

    expect(await db.select(db.items).get(), hasLength(2));
    expect(await db.select(db.tasks).get(), hasLength(2));
    expect(
      await DatasetStateRepository(db)
          .isCurrent(GameMode.regular, datasetEntry(DatasetKind.items)),
      isTrue,
    );
  });

  test('cancelling mid-download leaves no partial state and the next run '
      'resumes from the beginning of the unfinished dataset', () async {
    final controller = StreamController<List<int>>();
    addTearDown(controller.close);
    var serveSlowly = true;

    final fake = _FakeBundleClient(
      fixtureResources(),
      handler: (request) async {
        final name = request.url.pathSegments.last;
        if (serveSlowly && name == 'items.jsonl.zst') {
          return http.StreamedResponse(controller.stream, 200);
        }
        final bytes = fixtureResources()[name]!;
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([bytes]),
          200,
        );
      },
    );
    final harnessed = build(fake);
    final preparation = await harnessed.coordinator.prepare(GameMode.regular);

    controller.add(itemsBytes.sublist(0, 64));

    final token = DownloadCancellationToken();
    final progress = <SyncProgress>[];
    await expectLater(
      harnessed.coordinator.run(
        GameMode.regular,
        preparation: preparation,
        cancellation: token,
        onProgress: (event) {
          progress.add(event);
          if (event.dataset == DatasetKind.items &&
              event.phase == SyncPhase.downloading &&
              event.datasetBytes > 0) {
            token.cancel();
          }
        },
      ),
      throwsA(
        isA<SyncCancelled>()
            .having((error) => error.mode, 'mode', GameMode.regular)
            .having((error) => error.dataset, 'dataset', DatasetKind.items),
      ),
    );

    expect(token.isCancelled, isTrue);
    expect(
      await DatasetStateRepository(db).appliedForMode(GameMode.regular),
      isEmpty,
    );
    expect(await db.select(db.items).get(), isEmpty);
    expect(
      await File('${temporary.path}/regular/items.jsonl.zst').exists(),
      isFalse,
    );
    expect(
      await File('${temporary.path}/regular/items.jsonl.zst.part').exists(),
      isFalse,
    );

    // Resume: the same preparation still lists both datasets, but run
    // re-checks isCurrent and applies both from the start of items.
    serveSlowly = false;
    final resumed = await harnessed.coordinator.run(
      GameMode.regular,
      preparation: preparation,
    );

    expect(resumed.applied, [DatasetKind.items, DatasetKind.tasks]);
    expect(await db.select(db.items).get(), hasLength(2));
    expect(
      await DatasetStateRepository(db)
          .isCurrent(GameMode.regular, datasetEntry(DatasetKind.tasks)),
      isTrue,
    );
  });

  test('a checksum failure keeps prior datasets and a retry downloads only the '
      'failed dataset', () async {
    final corruptedTasks = List<int>.of(tasksBytes)..[0] ^= 0xFF;
    var corrupt = true;
    final fake = _FakeBundleClient(
      fixtureResources(),
      handler: (request) async {
        final name = request.url.pathSegments.last;
        final bytes = name == 'tasks.jsonl.zst' && corrupt
            ? corruptedTasks
            : fixtureResources()[name];
        if (bytes == null) {
          return http.StreamedResponse(const Stream<List<int>>.empty(), 404);
        }
        return http.StreamedResponse(
          Stream<List<int>>.fromIterable([bytes]),
          200,
        );
      },
    );
    final harnessed = build(fake);
    final preparation = await harnessed.coordinator.prepare(GameMode.regular);

    await expectLater(
      harnessed.coordinator.run(GameMode.regular, preparation: preparation),
      throwsA(
        isA<SyncChecksumException>().having(
          (error) => error.dataset,
          'dataset',
          DatasetKind.tasks,
        ),
      ),
    );

    final state = DatasetStateRepository(db);
    expect(
      await state.isCurrent(GameMode.regular, datasetEntry(DatasetKind.items)),
      isTrue,
    );
    expect(
      await state.isCurrent(GameMode.regular, datasetEntry(DatasetKind.tasks)),
      isFalse,
    );
    expect(await db.select(db.tasks).get(), isEmpty);
    expect(fake.requests, hasLength(2));

    corrupt = false;
    final resumed = await harnessed.coordinator.run(
      GameMode.regular,
      preparation: preparation,
    );

    expect(resumed.applied, [DatasetKind.tasks]);
    expect(resumed.skipped, contains(DatasetKind.items));
    expect(fake.requests, hasLength(3));
    expect(fake.requests.last.url.pathSegments.last, 'tasks.jsonl.zst');
    expect(await db.select(db.tasks).get(), hasLength(2));
  });

  test(
    'an ingest failure is typed, applies nothing, and leaves no state',
    () async {
      final badBytes = <int>[0x00, 0x01, 0x02, 0x03];
      final badEntry = ManifestDataset(
        dataset: DatasetKind.items,
        path: 'bad.jsonl.zst',
        schemaVersion: 1,
        sha256: sha256.convert(badBytes).toString(),
        compressedBytes: badBytes.length,
        uncompressedBytes: 0,
        records: 1,
        source: const ManifestDatasetSource(
          url: null,
          lastModified: null,
          etag: null,
          fetchedAt: null,
        ),
      );
      final badManifest = BundleManifest(
        manifestVersion: fixtureManifest.manifestVersion,
        bundleSchemaVersion: fixtureManifest.bundleSchemaVersion,
        minAppSchemaVersion: fixtureManifest.minAppSchemaVersion,
        mode: GameMode.regular,
        generatedAt: fixtureManifest.generatedAt,
        source: fixtureManifest.source,
        datasets: [badEntry],
        totals: const ManifestTotals(
          datasets: 1,
          records: 1,
          uncompressedBytes: 0,
          compressedBytes: 4,
        ),
        skipped: const [],
      );
      final fake = _FakeBundleClient({'bad.jsonl.zst': badBytes});
      final harnessed = build(fake, manifest: badManifest);

      await expectLater(
        harnessed.coordinator.run(GameMode.regular),
        throwsA(
          isA<SyncIngestException>().having(
            (error) => error.dataset,
            'dataset',
            DatasetKind.items,
          ),
        ),
      );

      expect(await db.select(db.items).get(), isEmpty);
      expect(
        await DatasetStateRepository(db).appliedForMode(GameMode.regular),
        isEmpty,
      );
      expect(
        await File('${temporary.path}/regular/bad.jsonl.zst').exists(),
        isTrue,
        reason: 'the verified file remains, but no state claims it was applied',
      );
    },
  );

  test('an incompatible bundle is refused before any download', () async {
    final incompatible = BundleManifest(
      manifestVersion: fixtureManifest.manifestVersion,
      bundleSchemaVersion: 2,
      minAppSchemaVersion: fixtureManifest.minAppSchemaVersion,
      mode: GameMode.regular,
      generatedAt: fixtureManifest.generatedAt,
      source: fixtureManifest.source,
      datasets: fixtureManifest.datasets,
      totals: fixtureManifest.totals,
      skipped: fixtureManifest.skipped,
    );
    final fake = _FakeBundleClient(fixtureResources());
    final harnessed = build(fake, manifest: incompatible);

    await expectLater(
      harnessed.coordinator.prepare(GameMode.regular),
      throwsA(
        isA<SyncCompatibilityException>()
            .having(
              (error) => error.status,
              'status',
              ManifestCompatibility.bundleUnsupported,
            )
            .having(
              (error) => error.failure,
              'failure',
              SyncFailure.compatibility,
            ),
      ),
    );

    expect(fake.requests, isEmpty);
    expect(
      await DatasetStateRepository(db).appliedForMode(GameMode.regular),
      isEmpty,
    );
  });

  test(
    'offline manifest and offline download both produce SyncOfflineException',
    () async {
      final offlineFake = _FakeBundleClient(fixtureResources());
      final offline = build(
        offlineFake,
        loadManifest: (_) async => throw const SocketException('no network'),
      );

      await expectLater(
        offline.coordinator.prepare(GameMode.regular),
        throwsA(
          isA<SyncOfflineException>().having(
            (error) => error.failure,
            'failure',
            SyncFailure.offline,
          ),
        ),
      );
      expect(offlineFake.requests, isEmpty);

      final downloadFake = _FakeBundleClient(
        fixtureResources(),
        handler: (_) async => throw const SocketException('connection refused'),
      );
      final download = build(downloadFake);

      await expectLater(
        download.coordinator.run(GameMode.regular),
        throwsA(
          isA<SyncOfflineException>().having(
            (error) => error.dataset,
            'dataset',
            DatasetKind.items,
          ),
        ),
      );
      expect(
        await DatasetStateRepository(db).appliedForMode(GameMode.regular),
        isEmpty,
      );
    },
  );
}
