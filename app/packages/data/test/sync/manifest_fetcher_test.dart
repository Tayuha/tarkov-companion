import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';
import '../support/manifest_fixtures.dart';

/// A manifest document derived from the committed regular fixture.
String _manifestBody(
  Map<String, Object?> fixture, {
  GameMode mode = GameMode.regular,
  String generatedAt = '2026-11-26T10:32:14.883Z',
}) {
  final document = <String, Object?>{
    ...fixture,
    'mode': mode.wireValue,
    'generatedAt': generatedAt,
  };
  return jsonEncode(document);
}

http.Response _ok(String body, {String? etag, String? lastModified}) =>
    http.Response(
      body,
      200,
      headers: {
        'content-type': 'application/json',
        'etag': ?etag,
        'last-modified': ?lastModified,
      },
    );

http.Response _notModified() => http.Response('', 304);

http.Response _notFound() => http.Response('not found', 404);

void main() {
  late AppDatabase db;
  late ManifestRepository repository;
  late AllowlistedHttpClient client;
  late ManifestFetcher fetcher;
  late List<http.Request> requests;
  late Map<String, Object?> fixture;

  var now = DateTime.utc(2026, 11, 26, 12);
  DateTime clock() => now;

  setUp(() async {
    now = DateTime.utc(2026, 11, 26, 12);
    fixture = await readManifestFixture();
    requests = [];
    db = await openMemoryDatabase();
    repository = ManifestRepository(db, clock: clock);
  });

  tearDown(() => db.close());

  ManifestFetcher fetcherWith(MockClient mock) {
    client = AllowlistedHttpClient(innerClient: mock);
    addTearDown(client.close);
    fetcher = ManifestFetcher(client, repository, clock: clock);
    return fetcher;
  }

  MockClient responding(
    FutureOr<http.Response> Function(http.Request) handler,
  ) {
    return MockClient((request) {
      requests.add(request);
      return Future.value(handler(request));
    });
  }

  group('conditional manifest fetch', () {
    test('200 then 304 sends If-None-Match, returns the cache and requests no '
        'dataset', () async {
      final body = _manifestBody(fixture);
      var calls = 0;
      fetcherWith(
        responding((request) {
          calls++;
          return calls == 1
              ? _ok(
                  body,
                  etag: '"manifest-v1"',
                  lastModified: 'Thu, 26 Nov 2026 10:30:24 GMT',
                )
              : _notModified();
        }),
      );

      final first = await fetcher.fetch(GameMode.regular);
      expect(first, isA<ManifestFetched>());
      expect(first.isNotModified, isFalse);
      expect(first.manifest.mode, GameMode.regular);
      expect(first.cache.etag, '"manifest-v1"');
      expect(first.checkedAt, now);

      now = DateTime.utc(2026, 11, 26, 18);
      final second = await fetcher.fetch(GameMode.regular);

      expect(second, isA<ManifestNotModified>());
      expect(second.isNotModified, isTrue);
      expect(second.checkedAt, now);
      expect(second.manifest.mode, GameMode.regular);
      expect(second.manifest.generatedAt, first.manifest.generatedAt);
      expect(
        second.manifest.datasets.map((entry) => entry.sha256),
        first.manifest.datasets.map((entry) => entry.sha256),
      );
      expect(second.cache.manifestJson, first.cache.manifestJson);
      expect(second.cache.lastChangedAt, first.cache.lastChangedAt);
      expect(second.cache.lastCheckedAt, now);

      // Exactly two requests, both the manifest URL. A 304 must not start a
      // dataset download.
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.url, ManifestFetcher.uriFor(GameMode.regular));
        expect(request.url.host, 'github.com');
        expect(request.url.path, endsWith('/manifest.json'));
        expect(request.url.path, isNot(contains('.jsonl.zst')));
      }
      expect(requests.last.headers['if-none-match'], '"manifest-v1"');
      expect(
        requests.last.headers['if-modified-since'],
        'Thu, 26 Nov 2026 10:30:24 GMT',
      );

      // The last check time is exposed by both the result and the cache.
      expect(await fetcher.lastCheckedAt(GameMode.regular), now);
    });

    test('a 200 with a changed body replaces the cache', () async {
      final firstBody = _manifestBody(fixture);
      final secondBody = _manifestBody(
        fixture,
        generatedAt: '2026-11-26T11:00:00.000Z',
      );
      var calls = 0;
      fetcherWith(
        responding((request) {
          calls++;
          return calls == 1
              ? _ok(firstBody, etag: '"v1"')
              : _ok(secondBody, etag: '"v2"');
        }),
      );

      final first = await fetcher.fetch(GameMode.regular);
      now = DateTime.utc(2026, 11, 26, 13);
      final second = await fetcher.fetch(GameMode.regular);

      expect(second, isA<ManifestFetched>());
      expect(second.cache.manifestJson, secondBody);
      expect(second.cache.etag, '"v2"');
      expect(second.cache.lastChangedAt, now);
      expect(second.cache.lastChangedAt, isNot(first.cache.lastChangedAt));
      expect(second.manifest.generatedAt, DateTime.utc(2026, 11, 26, 11));
    });

    test('a 200 with the same body but a new ETag updates metadata without a '
        'change', () async {
      final body = _manifestBody(fixture);
      var calls = 0;
      fetcherWith(
        responding((request) {
          calls++;
          return calls == 1 ? _ok(body, etag: '"v1"') : _ok(body, etag: '"v2"');
        }),
      );

      final first = await fetcher.fetch(GameMode.regular);
      now = DateTime.utc(2026, 11, 26, 14);
      final second = await fetcher.fetch(GameMode.regular);

      expect(second, isA<ManifestFetched>());
      expect(second.cache.etag, '"v2"');
      expect(second.cache.lastCheckedAt, now);
      expect(second.cache.lastChangedAt, first.cache.lastChangedAt);
      expect(second.cache.contentHash, first.cache.contentHash);
    });
  });

  group('typed failures', () {
    test(
      '404 is ManifestNotFound and leaves an existing cache untouched',
      () async {
        final body = _manifestBody(fixture);
        var calls = 0;
        fetcherWith(
          responding((request) {
            calls++;
            return calls == 1 ? _ok(body, etag: '"v1"') : _notFound();
          }),
        );

        final first = await fetcher.fetch(GameMode.regular);
        now = DateTime.utc(2026, 11, 26, 13);

        await expectLater(
          fetcher.fetch(GameMode.regular),
          throwsA(isA<ManifestNotFound>()),
        );

        final cached = await repository.read(GameMode.regular);
        expect(cached!.manifestJson, first.cache.manifestJson);
        expect(cached.lastCheckedAt, first.cache.lastCheckedAt);
        expect(cached.etag, '"v1"');
      },
    );

    test(
      'malformed JSON is ManifestInvalid and leaves the cache untouched',
      () async {
        final body = _manifestBody(fixture);
        var calls = 0;
        fetcherWith(
          responding((request) {
            calls++;
            return calls == 1 ? _ok(body, etag: '"v1"') : _ok('{not json');
          }),
        );

        final first = await fetcher.fetch(GameMode.regular);

        await expectLater(
          fetcher.fetch(GameMode.regular),
          throwsA(
            isA<ManifestInvalid>().having(
              (error) => error.cause,
              'cause',
              isA<FormatException>(),
            ),
          ),
        );

        final cached = await repository.read(GameMode.regular);
        expect(cached!.manifestJson, first.cache.manifestJson);
        expect(cached.lastCheckedAt, first.cache.lastCheckedAt);
      },
    );

    test('an invalid manifest schema is ManifestInvalid', () async {
      fetcherWith(responding((request) => _ok('{"manifestVersion":1}')));

      await expectLater(
        fetcher.fetch(GameMode.regular),
        throwsA(
          isA<ManifestInvalid>().having(
            (error) => error.cause,
            'cause',
            isA<ManifestFormatException>(),
          ),
        ),
      );
      expect(await repository.read(GameMode.regular), isNull);
    });

    test('a document for another mode is ManifestModeMismatch', () async {
      final body = _manifestBody(fixture);
      fetcherWith(responding((request) => _ok(body, etag: '"v1"')));

      await expectLater(
        fetcher.fetch(GameMode.pve),
        throwsA(
          isA<ManifestModeMismatch>().having(
            (error) => error.actualMode,
            'actualMode',
            GameMode.regular,
          ),
        ),
      );
      expect(await repository.read(GameMode.pve), isNull);
    });

    test('304 without a cache is ManifestNotModifiedWithoutCache', () async {
      fetcherWith(responding((request) => _notModified()));

      await expectLater(
        fetcher.fetch(GameMode.regular),
        throwsA(isA<ManifestNotModifiedWithoutCache>()),
      );
      expect(requests, hasLength(1));
      expect(requests.single.url, ManifestFetcher.uriFor(GameMode.regular));
    });
  });

  test('per-mode URLs and caches are isolated', () async {
    final regularBody = _manifestBody(fixture);
    final pveBody = _manifestBody(fixture, mode: GameMode.pve);

    fetcherWith(
      responding((request) {
        final isPve = request.url.path.contains('data-pve-latest');
        return isPve
            ? _ok(pveBody, etag: '"pve"')
            : _ok(regularBody, etag: '"regular"');
      }),
    );

    final regular = await fetcher.fetch(GameMode.regular);
    final pve = await fetcher.fetch(GameMode.pve);

    expect(regular.manifest.mode, GameMode.regular);
    expect(pve.manifest.mode, GameMode.pve);
    expect(regular.cache.etag, '"regular"');
    expect(pve.cache.etag, '"pve"');

    expect(requests, hasLength(2));
    expect(requests[0].url, ManifestFetcher.uriFor(GameMode.regular));
    expect(requests[1].url, ManifestFetcher.uriFor(GameMode.pve));
    expect(
      requests[0].url.path,
      contains('/data-regular-latest/manifest.json'),
    );
    expect(requests[1].url.path, contains('/data-pve-latest/manifest.json'));

    expect(
      (await repository.read(GameMode.regular))!.manifestJson,
      regularBody,
    );
    expect((await repository.read(GameMode.pve))!.manifestJson, pveBody);
    expect(await repository.read(GameMode.pvpSeason), isNull);
  });
}
