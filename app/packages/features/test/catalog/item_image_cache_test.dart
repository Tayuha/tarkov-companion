import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../theme/support/load_fonts.dart';

/// A 1x1 transparent PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNg'
  'YGBgAAAABQABeqhXUAAAAABJRU5ErkJggg==',
);

final class _FakeFetcher implements ItemImageFetcher {
  _FakeFetcher({this.bytes, this.fail = false});

  final Uint8List? bytes;
  final bool fail;
  int calls = 0;

  @override
  Future<Uint8List> fetch(Uri uri) async {
    calls++;
    if (fail) {
      throw const SocketException('offline');
    }
    return bytes ?? _png;
  }
}

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('item-image-cache-');
  });

  tearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });

  group('disk cache', () {
    test('a cached image is served offline without a fetch', () async {
      const url = 'https://assets.tarkov.dev/item-icon.webp';
      final online = _FakeFetcher();
      final cache = ItemImageCache(directory: directory, fetcher: online);
      expect(await cache.load(url), _png);
      expect(online.calls, 1);

      final offline = _FakeFetcher(fail: true);
      final offlineCache = ItemImageCache(
        directory: directory,
        fetcher: offline,
      );
      expect(await offlineCache.load(url), _png);
      expect(offline.calls, 0);
      expect(cache.fileCount(), 1);
    });

    test('a failed fetch returns null and leaves the placeholder', () async {
      final fetcher = _FakeFetcher(fail: true);
      final cache = ItemImageCache(directory: directory, fetcher: fetcher);

      expect(
        await cache.load('https://assets.tarkov.dev/missing.webp'),
        isNull,
      );
      expect(fetcher.calls, 1);
      expect(cache.fileCount(), 0);
    });

    test('a malformed URL is a miss without a fetch', () async {
      final fetcher = _FakeFetcher();
      final cache = ItemImageCache(directory: directory, fetcher: fetcher);

      expect(await cache.load('not a url'), isNull);
      expect(fetcher.calls, 0);
    });

    test('eviction keeps the directory inside the byte budget', () async {
      final fetcher = _FakeFetcher(bytes: Uint8List(60));
      final cache = ItemImageCache(
        directory: directory,
        fetcher: fetcher,
        maxBytes: 100,
        memoryEntries: 0,
      );

      await cache.load('https://assets.tarkov.dev/a.webp');
      expect(cache.diskBytes(), 60);
      await cache.load('https://assets.tarkov.dev/b.webp');
      expect(cache.diskBytes(), 60);
      await cache.load('https://assets.tarkov.dev/c.webp');

      expect(cache.diskBytes(), 60);
      expect(cache.fileCount(), 1);
      final newest = File(
        '${directory.path}/${ItemImageCache.cacheKey('https://assets.tarkov.dev/c.webp')}.img',
      );
      expect(newest.existsSync(), isTrue);
      expect(
        File(
          '${directory.path}/${ItemImageCache.cacheKey('https://assets.tarkov.dev/a.webp')}.img',
        ).existsSync(),
        isFalse,
      );
    });

    test(
      'an image larger than the budget is served but not retained',
      () async {
        final cache = ItemImageCache(
          directory: directory,
          fetcher: _FakeFetcher(bytes: Uint8List(60)),
          maxBytes: 10,
          memoryEntries: 0,
        );

        expect(
          await cache.load('https://assets.tarkov.dev/huge.webp'),
          isNotNull,
        );
        expect(cache.diskBytes(), 0);
        expect(cache.fileCount(), 0);
      },
    );

    test('cache keys are stable across instances', () {
      expect(
        ItemImageCache.cacheKey('https://assets.tarkov.dev/a.webp'),
        ItemImageCache.cacheKey('https://assets.tarkov.dev/a.webp'),
      );
      expect(
        ItemImageCache.cacheKey('https://assets.tarkov.dev/a.webp'),
        isNot(ItemImageCache.cacheKey('https://assets.tarkov.dev/b.webp')),
      );
    });
  });

  group('ItemImage widget', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await loadDesignFonts();
    });

    testWidgets('loads lazily when built and falls back to the placeholder', (
      tester,
    ) async {
      final fetcher = _FakeFetcher();
      final cache = ItemImageCache(directory: directory, fetcher: fetcher);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Center(
            child: ItemImage(
              cache: cache,
              url: 'https://assets.tarkov.dev/a.webp',
              size: 40,
              placeholderKey: const Key('placeholder'),
              imageKey: const Key('image'),
            ),
          ),
        ),
      );

      expect(fetcher.calls, 1, reason: 'the image loads when it is built');
      expect(find.byKey(const Key('placeholder')), findsOneWidget);
      expect(find.byKey(const Key('image')), findsNothing);
    });

    testWidgets('a cache hit renders the image slot', (tester) async {
      final cache = ItemImageCache(
        directory: directory,
        fetcher: _FakeFetcher(),
      );
      await tester.runAsync(() async {
        await cache.load('https://assets.tarkov.dev/a.webp');
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Center(
            child: ItemImage(
              cache: cache,
              url: 'https://assets.tarkov.dev/a.webp',
              size: 40,
              placeholderKey: const Key('placeholder'),
              imageKey: const Key('image'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('image')), findsOneWidget);
    });

    testWidgets('a failed fetch keeps the placeholder', (tester) async {
      final cache = ItemImageCache(
        directory: directory,
        fetcher: _FakeFetcher(fail: true),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Center(
            child: ItemImage(
              cache: cache,
              url: 'https://assets.tarkov.dev/a.webp',
              size: 40,
              placeholderKey: const Key('placeholder'),
              imageKey: const Key('image'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('placeholder')), findsOneWidget);
      expect(find.byKey(const Key('image')), findsNothing);
    });

    testWidgets('no cache or no URL never performs I/O', (tester) async {
      final fetcher = _FakeFetcher();
      final cache = ItemImageCache(directory: directory, fetcher: fetcher);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Column(
            children: [
              ItemImage(
                cache: null,
                url: 'https://assets.tarkov.dev/a.webp',
                size: 40,
                placeholderKey: const Key('no-cache'),
              ),
              ItemImage(
                cache: cache,
                url: null,
                size: 40,
                placeholderKey: const Key('no-url'),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(fetcher.calls, 0);
      expect(find.byKey(const Key('no-cache')), findsOneWidget);
      expect(find.byKey(const Key('no-url')), findsOneWidget);
    });
  });
}
