import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

/// A fake inner client that counts every `send` call.
///
/// Wrapping [MockClient] rather than counting inside the handler proves that a
/// policy rejection happens before the transport is touched at all.
final class CountingClient extends http.BaseClient {
  CountingClient(this._inner);

  final http.Client _inner;
  final List<http.BaseRequest> requests = [];

  int get calls => requests.length;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

void main() {
  final manifestUrl = Uri.parse(
    'https://github.com/Tayuha/tarkov-companion/releases/download/'
    'data-regular-latest/manifest.json',
  );

  AllowlistedHttpClient buildClient(
    CountingClient counting, {
    Duration timeout = AllowlistedHttpClient.defaultTimeout,
    int maxRedirects = AllowlistedHttpClient.defaultMaxRedirects,
  }) {
    final client = AllowlistedHttpClient(
      innerClient: counting,
      timeout: timeout,
      maxRedirects: maxRedirects,
    );
    addTearDown(client.close);
    return client;
  }

  CountingClient buildCounting(
    Future<http.Response> Function(http.Request) handler,
  ) {
    return CountingClient(MockClient(handler));
  }

  group('allowlist', () {
    test('contains exactly the documented production hosts', () {
      expect(NetworkAllowlist.productionHosts, {
        'github.com',
        'objects.githubusercontent.com',
        'release-assets.githubusercontent.com',
        'assets.tarkov.dev',
      });
    });
  });

  group('pre-flight validation', () {
    test('rejects a disallowed host before any request is sent', () async {
      final counting = buildCounting((_) async {
        fail('the inner client must not be called for a disallowed host');
      });
      final client = buildClient(counting);

      await expectLater(
        client.get(Uri.parse('https://evil.example/manifest.json')),
        throwsA(
          isA<DisallowedHostException>()
              .having((error) => error.host, 'host', 'evil.example')
              .having((error) => error.uri.host, 'uri host', 'evil.example'),
        ),
      );

      expect(counting.calls, 0);
    });

    test('rejects lookalike and subdomain hosts', () async {
      final counting = buildCounting((_) async {
        fail('the inner client must not be called for a lookalike host');
      });
      final client = buildClient(counting);

      for (final host in [
        'evilgithub.com',
        'api.github.com',
        'github.com.evil.example',
      ]) {
        await expectLater(
          client.get(Uri.parse('https://$host/manifest.json')),
          throwsA(
            isA<DisallowedHostException>().having(
              (error) => error.host,
              'host',
              host,
            ),
          ),
        );
      }
      expect(counting.calls, 0);
    });

    test('rejects a URI with no host', () async {
      final counting = buildCounting((_) async {
        fail('the inner client must not be called without a host');
      });
      final client = buildClient(counting);

      await expectLater(
        client.get(Uri.parse('https:///manifest.json')),
        throwsA(
          isA<DisallowedHostException>().having(
            (error) => error.host,
            'host',
            isEmpty,
          ),
        ),
      );
      expect(counting.calls, 0);
    });

    test('rejects credentials in the URL before any request is sent', () async {
      final counting = buildCounting((_) async {
        fail('the inner client must not be called with URL credentials');
      });
      final client = buildClient(counting);

      await expectLater(
        client.get(Uri.parse('https://user:secret@github.com/manifest.json')),
        throwsA(isA<UserInfoNotAllowedException>()),
      );
      expect(counting.calls, 0);
    });

    test('rejects plain HTTP before any request is sent', () async {
      final counting = buildCounting((_) async {
        fail('the inner client must not be called over plain HTTP');
      });
      final client = buildClient(counting);

      await expectLater(
        client.get(Uri.parse('http://github.com/manifest.json')),
        throwsA(isA<InsecureSchemeException>()),
      );
      expect(counting.calls, 0);
    });
  });

  group('requests', () {
    test('returns the body and sends the documenting user agent', () async {
      final counting = buildCounting((request) async {
        expect(request.method, 'GET');
        expect(request.url, manifestUrl);
        expect(request.followRedirects, isFalse);
        expect(request.maxRedirects, 0);
        expect(
          request.headers['user-agent'],
          'tarkov-companion/0.1.0 '
          '(+https://github.com/Tayuha/tarkov-companion)',
        );
        return http.Response(
          '{"manifestVersion":1}',
          200,
          headers: {'Content-Type': 'application/json'},
        );
      });
      final client = buildClient(counting);

      final response = await client.get(manifestUrl);

      expect(response.statusCode, 200);
      expect(response.bodyText, '{"manifestVersion":1}');
      expect(response.headers['content-type'], 'application/json');
      expect(response.finalUri, manifestUrl);
      expect(response.bodyBytes, utf8.encode('{"manifestVersion":1}'));
      expect(counting.calls, 1);
    });

    test('getText and getBytes return the same 2xx payload', () async {
      final counting = buildCounting(
        (_) async => http.Response.bytes([0x68, 0x69], 200),
      );
      final client = buildClient(counting);

      expect(await client.getText(manifestUrl), 'hi');
      expect(await client.getBytes(manifestUrl), [0x68, 0x69]);
      expect(counting.calls, 2);
    });

    test('throws HttpStatusException carrying 404', () async {
      final counting = buildCounting(
        (_) async => http.Response('not found', 404),
      );
      final client = buildClient(counting);

      await expectLater(
        client.get(manifestUrl),
        throwsA(
          isA<HttpStatusException>()
              .having((error) => error.statusCode, 'statusCode', 404)
              .having((error) => error.isNotFound, 'isNotFound', isTrue)
              .having((error) => error.uri, 'uri', manifestUrl),
        ),
      );
    });

    test('throws HttpTimeoutException when a response never arrives', () async {
      final counting = buildCounting((_) => Completer<http.Response>().future);
      final client = buildClient(
        counting,
        timeout: const Duration(milliseconds: 10),
      );

      await expectLater(
        client.get(manifestUrl),
        throwsA(
          isA<HttpTimeoutException>().having(
            (error) => error.timeout,
            'timeout',
            const Duration(milliseconds: 10),
          ),
        ),
      );
    });
  });

  group('redirects', () {
    test('follows a redirect to another allowlisted host', () async {
      final target = Uri.parse(
        'https://objects.githubusercontent.com/github-production-release-asset/'
        'manifest.json',
      );
      final counting = buildCounting((request) async {
        if (request.url.host == 'github.com') {
          return http.Response(
            '',
            302,
            headers: {'Location': target.toString()},
          );
        }
        expect(request.url, target);
        return http.Response('manifest-bytes', 200);
      });
      final client = buildClient(counting);

      final response = await client.get(manifestUrl);

      expect(response.statusCode, 200);
      expect(response.bodyText, 'manifest-bytes');
      expect(response.finalUri, target);
      expect(counting.calls, 2);
      expect(counting.requests.last.url, target);
    });

    test(
      'rejects a redirect to a disallowed host before the next request',
      () async {
        final counting = buildCounting(
          (_) async => http.Response(
            '',
            302,
            headers: {'location': 'https://evil.example/manifest.json'},
          ),
        );
        final client = buildClient(counting);

        await expectLater(
          client.get(manifestUrl),
          throwsA(
            isA<DisallowedHostException>().having(
              (error) => error.host,
              'host',
              'evil.example',
            ),
          ),
        );

        expect(counting.calls, 1);
      },
    );

    test('rejects a protocol-relative redirect to an unknown host', () async {
      final counting = buildCounting(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': '//evil.example/manifest.json'},
        ),
      );
      final client = buildClient(counting);

      await expectLater(
        client.get(manifestUrl),
        throwsA(isA<DisallowedHostException>()),
      );
      expect(counting.calls, 1);
    });

    test('throws after the redirect limit is exceeded', () async {
      final counting = buildCounting(
        (request) async => http.Response(
          '',
          302,
          headers: {'location': request.url.toString()},
        ),
      );
      final client = buildClient(counting, maxRedirects: 2);

      await expectLater(
        client.get(manifestUrl),
        throwsA(
          isA<TooManyRedirectsException>()
              .having((error) => error.maxRedirects, 'maxRedirects', 2)
              .having((error) => error.lastUri, 'lastUri', manifestUrl),
        ),
      );

      // Three requests: the original plus the two allowed hops.
      expect(counting.calls, 3);
    });

    test('resolves a relative Location against the current URL', () async {
      final assetName = 'items-bc330ec05ae3.jsonl.zst';
      final counting = buildCounting((request) async {
        if (request.url.path.endsWith('manifest.json')) {
          return http.Response('', 302, headers: {'location': assetName});
        }
        return http.Response('dataset-bytes', 200);
      });
      final client = buildClient(counting);

      final response = await client.get(manifestUrl);

      expect(response.finalUri, manifestUrl.resolve(assetName));
      expect(response.finalUri.host, 'github.com');
      expect(
        response.finalUri.path,
        contains('/data-regular-latest/$assetName'),
      );
      expect(response.bodyText, 'dataset-bytes');
    });

    test('rejects an HTTPS to HTTP downgrade', () async {
      final counting = buildCounting(
        (_) async => http.Response(
          '',
          301,
          headers: {'location': 'http://github.com/manifest.json'},
        ),
      );
      final client = buildClient(counting);

      await expectLater(
        client.get(manifestUrl),
        throwsA(isA<InsecureSchemeException>()),
      );
      expect(counting.calls, 1);
    });

    test(
      'drops credentials but keeps conditional headers on redirect',
      () async {
        final target = Uri.parse(
          'https://release-assets.githubusercontent.com/manifest.json',
        );
        final counting = buildCounting((request) async {
          if (request.url.host == 'github.com') {
            expect(request.headers['authorization'], 'Bearer test-token');
            expect(request.headers['host'], isNull);
            return http.Response(
              '',
              302,
              headers: {'Location': target.toString()},
            );
          }
          expect(request.headers['authorization'], isNull);
          expect(request.headers['if-none-match'], '"abc123"');
          return http.Response('ok', 200);
        });
        final client = buildClient(counting);

        await client.get(
          manifestUrl,
          headers: {
            'Authorization': 'Bearer test-token',
            'If-None-Match': '"abc123"',
            'Host': 'evil.example',
          },
        );

        expect(counting.calls, 2);
      },
    );
  });
}
