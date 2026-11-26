import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/bundle_fixture.dart';
import '../support/database_helpers.dart';

void main() {
  late AppDatabase db;
  late Directory temporary;
  late HttpServer server;
  late Uri manifestUri;
  late AllowlistedHttpClient client;
  late SyncCoordinator coordinator;
  late List<String> requestedPaths;
  late List<int> itemsBytes;
  late List<int> tasksBytes;

  setUp(() async {
    db = await openMemoryDatabase();
    temporary = createTemporaryDirectory(addTearDown);
    requestedPaths = [];

    final fixture = await bundleFixtureDirectory();
    final manifestBytes = await File('${fixture.path}/manifest.json')
        .readAsBytes();
    itemsBytes = await File('${fixture.path}/items.jsonl.zst').readAsBytes();
    tasksBytes = await File('${fixture.path}/tasks.jsonl.zst').readAsBytes();

    // A real loopback HTTP server, not a mocked transport: this exercises the
    // manifest fetch, streaming download, checksum verification, and ingestion
    // over an actual socket, without reaching the public internet.
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requestedPaths.add(request.uri.path);
      final name = request.uri.pathSegments.isEmpty
          ? ''
          : request.uri.pathSegments.last;

      final List<int> bytes;
      if (name == 'manifest.json') {
        bytes = manifestBytes;
        request.response.headers.contentType = ContentType.json;
      } else if (name == 'items.jsonl.zst') {
        bytes = itemsBytes;
        request.response.headers.contentType = ContentType(
          'application',
          'octet-stream',
        );
      } else if (name == 'tasks.jsonl.zst') {
        bytes = tasksBytes;
        request.response.headers.contentType = ContentType(
          'application',
          'octet-stream',
        );
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });

    final host = server.address.address;
    manifestUri = Uri.parse('http://$host:${server.port}/manifest.json');
    client = AllowlistedHttpClient(
      // The production client is HTTPS-only. The test opts in explicitly to
      // plain HTTP on a loopback host that is still on an explicit allowlist.
      allowlist: {host},
      allowInsecureLocalhost: true,
    );
    final fetcher = ManifestFetcher(
      client,
      ManifestRepository(db),
      manifestUriFor: (_) => manifestUri,
    );
    coordinator = SyncCoordinator(
      loadManifest: (mode) async {
        final result = await fetcher.fetch(mode);
        return SyncManifestSnapshot.fromFetch(result, manifestUri: manifestUri);
      },
      downloader: DatasetDownloader(client),
      ingestor: DatasetIngestor(db, batchSize: 2),
      stateRepository: DatasetStateRepository(db),
      directory: temporary,
    );
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
    await db.close();
  });

  test('first run estimates, downloads, ingests, and then reports complete '
      'without re-downloading', () async {
    final preparation = await coordinator.prepare(GameMode.regular);

    expect(preparation.pending.map((entry) => entry.dataset), [
      DatasetKind.items,
      DatasetKind.tasks,
    ]);
    expect(preparation.applied, isEmpty);
    expect(preparation.totalBytes, 3185 + 1641);
    expect(requestedPaths, ['/manifest.json']);

    final progress = <SyncProgress>[];
    final result = await coordinator.run(
      GameMode.regular,
      preparation: preparation,
      onProgress: progress.add,
    );

    expect(result.applied, [DatasetKind.items, DatasetKind.tasks]);
    expect(result.bytesDownloaded, 3185 + 1641);
    expect(result.isNoOp, isFalse);
    expect(requestedPaths, [
      '/manifest.json',
      '/items.jsonl.zst',
      '/tasks.jsonl.zst',
    ]);

    expect(await db.select(db.items).get(), hasLength(2));
    expect(await db.select(db.tasks).get(), hasLength(2));

    final state = DatasetStateRepository(db);
    final applied = await state.appliedForMode(GameMode.regular);
    expect(applied.keys, containsAll([DatasetKind.items, DatasetKind.tasks]));
    expect(
      await state.isCurrent(
        GameMode.regular,
        datasetIn(preparation.manifest, DatasetKind.items),
      ),
      isTrue,
    );

    expect(progress.first.phase, SyncPhase.downloading);
    expect(progress.last.phase, SyncPhase.ingesting);
    expect(progress.last.fraction, 1.0);

    final again = await coordinator.prepare(GameMode.regular);
    expect(again.isComplete, isTrue);
    expect(again.pending, isEmpty);

    final datasetRequests = requestedPaths.where(
      (path) => path.endsWith('.jsonl.zst'),
    );
    expect(datasetRequests, hasLength(2));

    final noOp = await coordinator.run(GameMode.regular, preparation: again);
    expect(noOp.isNoOp, isTrue);
    expect(
      requestedPaths.where((path) => path.endsWith('.jsonl.zst')),
      hasLength(2),
    );
  });
}
