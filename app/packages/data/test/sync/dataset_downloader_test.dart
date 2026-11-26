import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

/// A transport fake that returns a caller-supplied [http.StreamedResponse].
///
/// Nothing reaches a socket or a real DNS resolver: the downloader only ever
/// sees the stream the test builds, which is what makes cancellation and a
/// corrupted body deterministic.
final class FakeStreamingClient extends http.BaseClient {
  FakeStreamingClient(this._handler);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  /// Every request the downloader sent, in order.
  final List<http.BaseRequest> requests = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return _handler(request);
  }

  @override
  void close() {}
}

void main() {
  final manifestUri = Uri.parse(
    'https://github.com/Tayuha/tarkov-companion/releases/download/'
    'data-regular-latest/manifest.json',
  );

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('dataset-downloader-');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  ({DatasetDownloader downloader, FakeStreamingClient client}) harness(
    FutureOr<http.StreamedResponse> Function(http.BaseRequest request) handler,
  ) {
    final fake = FakeStreamingClient(handler);
    final client = AllowlistedHttpClient(innerClient: fake);
    addTearDown(client.close);
    return (downloader: DatasetDownloader(client), client: fake);
  }

  ManifestDataset datasetFor(
    List<int> bytes, {
    String path = 'items-0123456789ab.jsonl.zst',
    DatasetKind kind = DatasetKind.items,
    int? compressedBytes,
    String? sha256Hex,
  }) {
    return ManifestDataset(
      dataset: kind,
      path: path,
      schemaVersion: 1,
      sha256: sha256Hex ?? sha256.convert(bytes).toString(),
      compressedBytes: compressedBytes ?? bytes.length,
      uncompressedBytes: bytes.length * 2,
      records: 1,
      source: const ManifestDatasetSource(
        url: null,
        lastModified: null,
        etag: null,
        fetchedAt: null,
      ),
    );
  }

  List<List<int>> inChunks(List<int> bytes, int size) => [
    for (var offset = 0; offset < bytes.length; offset += size)
      bytes.sublist(offset, min(offset + size, bytes.length)),
  ];

  http.StreamedResponse ok(
    List<List<int>> chunks, {
    Map<String, String> headers = const {},
  }) =>
      http.StreamedResponse(Stream.fromIterable(chunks), 200, headers: headers);

  List<int> samplePayload() =>
      List<int>.generate(2048, (index) => (index * 31) % 256);

  File destinationIn(String name) => File('${tempDir.path}/regular/$name');

  group('valid download', () {
    test('writes every chunk, verifies the digest and reports monotonic '
        'progress that ends at 1.0', () async {
      final payload = samplePayload();
      final dataset = datasetFor(payload);
      final destination = destinationIn('items.jsonl.zst');
      final harnessed = harness((request) async {
        expect(request.method, 'GET');
        expect(request.url, manifestUri.resolve(dataset.path));
        expect(request.headers['accept-encoding'], 'identity');
        return ok(
          inChunks(payload, 512),
          headers: {'Content-Length': '${payload.length}'},
        );
      });

      final progress = <DownloadProgress>[];
      await harnessed.downloader.download(
        manifestUri: manifestUri,
        dataset: dataset,
        destination: destination,
        onProgress: progress.add,
      );

      expect(await destination.exists(), isTrue);
      expect(await destination.readAsBytes(), payload);
      expect(
        sha256.convert(await destination.readAsBytes()).toString(),
        dataset.sha256,
      );
      expect(harnessed.client.requests, hasLength(1));

      expect(progress, isNotEmpty);
      for (var index = 1; index < progress.length; index++) {
        expect(
          progress[index].downloadedBytes,
          greaterThanOrEqualTo(progress[index - 1].downloadedBytes),
          reason: 'progress must never move backwards',
        );
      }
      expect(progress.first.downloadedBytes, 512);
      expect(progress.last.downloadedBytes, payload.length);
      expect(progress.last.totalBytes, payload.length);
      expect(progress.last.fraction, 1.0);

      expect(await File('${destination.path}.part').exists(), isFalse);
    });

    test('creates missing parent directories', () async {
      final payload = samplePayload();
      final destination = File(
        '${tempDir.path}/nested/regular/2026-11/items.jsonl.zst',
      );
      final harnessed = harness((_) async => ok(inChunks(payload, 700)));

      await harnessed.downloader.download(
        manifestUri: manifestUri,
        dataset: datasetFor(payload),
        destination: destination,
      );

      expect(await destination.exists(), isTrue);
      expect(await destination.parent.exists(), isTrue);
    });
  });

  group('verification failures', () {
    test(
      'a flipped byte fails the checksum and removes the partial file',
      () async {
        final payload = samplePayload();
        final corrupted = [...payload];
        corrupted[17] ^= 0xFF;
        expect(corrupted, hasLength(payload.length));

        final destination = destinationIn('items.jsonl.zst');
        final harnessed = harness((_) async => ok(inChunks(corrupted, 512)));

        await expectLater(
          harnessed.downloader.download(
            manifestUri: manifestUri,
            dataset: datasetFor(payload),
            destination: destination,
          ),
          throwsA(
            isA<DownloadChecksumMismatchException>()
                .having(
                  (error) => error.expectedSha256,
                  'expectedSha256',
                  sha256.convert(payload).toString(),
                )
                .having(
                  (error) => error.actualSha256,
                  'actualSha256',
                  sha256.convert(corrupted).toString(),
                ),
          ),
        );

        expect(await destination.exists(), isFalse);
        expect(await File('${destination.path}.part').exists(), isFalse);
      },
    );

    test('a wrong byte count fails the size check before hashing', () async {
      final payload = samplePayload();
      final destination = destinationIn('items.jsonl.zst');
      final harnessed = harness((_) async => ok(inChunks(payload, 512)));

      await expectLater(
        harnessed.downloader.download(
          manifestUri: manifestUri,
          dataset: datasetFor(payload, compressedBytes: payload.length + 64),
          destination: destination,
        ),
        throwsA(
          isA<DownloadSizeMismatchException>()
              .having(
                (error) => error.expectedBytes,
                'expected',
                payload.length + 64,
              )
              .having((error) => error.actualBytes, 'actual', payload.length),
        ),
      );

      expect(await destination.exists(), isFalse);
      expect(await File('${destination.path}.part').exists(), isFalse);
    });

    test('a 404 propagates HttpStatusException and writes nothing', () async {
      final destination = destinationIn('items.jsonl.zst');
      final harnessed = harness(
        (_) async =>
            http.StreamedResponse(const Stream<List<int>>.empty(), 404),
      );

      await expectLater(
        harnessed.downloader.download(
          manifestUri: manifestUri,
          dataset: datasetFor(samplePayload()),
          destination: destination,
        ),
        throwsA(
          isA<HttpStatusException>()
              .having((error) => error.statusCode, 'statusCode', 404)
              .having(
                (error) => error.uri,
                'uri',
                manifestUri.resolve('items-0123456789ab.jsonl.zst'),
              ),
        ),
      );

      expect(await destination.exists(), isFalse);
      expect(await File('${destination.path}.part').exists(), isFalse);
    });

    test(
      'an asset URL outside the allowlist is rejected before any request',
      () async {
        final harnessed = harness(
          (_) async => fail('a disallowed asset URL must not be requested'),
        );

        await expectLater(
          harnessed.downloader.download(
            manifestUri: Uri.parse(
              'https://evil.example/bundles/regular/manifest.json',
            ),
            dataset: datasetFor(samplePayload()),
            destination: destinationIn('items.jsonl.zst'),
          ),
          throwsA(isA<DisallowedHostException>()),
        );

        expect(harnessed.client.requests, isEmpty);
      },
    );
  });

  group('cancellation', () {
    test('cancelling after the first chunk aborts the subscription and '
        'deletes the partial file', () async {
      final payload = samplePayload();
      final controller = StreamController<List<int>>();
      var transportCancelled = false;
      controller.onCancel = () => transportCancelled = true;

      final harnessed = harness(
        (_) async => http.StreamedResponse(controller.stream, 200),
      );
      addTearDown(controller.close);

      // Buffered before the listener attaches, so both chunks are ready as
      // soon as the download starts.
      controller.add(payload.sublist(0, 512));
      controller.add(payload.sublist(512, 1024));

      final token = DownloadCancellationToken();
      final destination = destinationIn('items.jsonl.zst');
      final progress = <DownloadProgress>[];

      await expectLater(
        harnessed.downloader.download(
          manifestUri: manifestUri,
          dataset: datasetFor(payload),
          destination: destination,
          cancellation: token,
          onProgress: (event) {
            progress.add(event);
            token.cancel();
          },
        ),
        throwsA(
          isA<DownloadCancelled>()
              .having((error) => error.dataset, 'dataset', DatasetKind.items)
              .having((error) => error.downloadedBytes, 'downloaded', 512),
        ),
      );

      expect(progress, hasLength(1), reason: 'no progress after cancellation');
      expect(token.isCancelled, isTrue);
      expect(transportCancelled, isTrue);
      expect(controller.hasListener, isFalse);
      expect(await destination.exists(), isFalse);
      expect(await File('${destination.path}.part').exists(), isFalse);
    });

    test('an already-cancelled token sends no request', () async {
      final harnessed = harness(
        (_) async => fail('a cancelled download must not request the asset'),
      );
      final token = DownloadCancellationToken()..cancel();

      await expectLater(
        harnessed.downloader.download(
          manifestUri: manifestUri,
          dataset: datasetFor(samplePayload()),
          destination: destinationIn('items.jsonl.zst'),
          cancellation: token,
        ),
        throwsA(isA<DownloadCancelled>()),
      );

      expect(harnessed.client.requests, isEmpty);
    });
  });

  group('replacing an existing dataset', () {
    test('a failed update keeps the previous file and a verified update '
        'replaces it', () async {
      final previous = utf8.encode('previous verified dataset');
      final next = samplePayload();
      final destination = destinationIn('items.jsonl.zst');
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(previous);

      final corrupted = [...next];
      corrupted[0] ^= 0x01;
      final failing = harness((_) async => ok(inChunks(corrupted, 512)));

      await expectLater(
        failing.downloader.download(
          manifestUri: manifestUri,
          dataset: datasetFor(next),
          destination: destination,
        ),
        throwsA(isA<DownloadChecksumMismatchException>()),
      );

      expect(
        await destination.readAsBytes(),
        previous,
        reason: 'the old dataset must survive a failed update',
      );
      expect(await File('${destination.path}.part').exists(), isFalse);

      final succeeding = harness((_) async => ok(inChunks(next, 512)));
      await succeeding.downloader.download(
        manifestUri: manifestUri,
        dataset: datasetFor(next),
        destination: destination,
      );

      expect(await destination.readAsBytes(), next);
      expect(await File('${destination.path}.part').exists(), isFalse);
    });
  });
}
