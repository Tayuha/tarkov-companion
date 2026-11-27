import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/item_detail_fixture.dart';
import '../theme/support/load_fonts.dart';

void main() {
  late AppDatabase database;
  late CatalogRepository repository;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadDesignFonts();
  });

  setUp(() async {
    database = await openItemDetailFixtureDatabase();
    repository = CatalogRepository(database);
  });

  tearDown(() => database.close());

  Future<void> pumpDetail(
    WidgetTester tester,
    String itemId, {
    VoidCallback? onBack,
    ItemImageCache? imageCache,
    PriceHistoryRepository? priceHistory,
    bool offline = false,
    UpstreamCheck? upstreamCheck,
    Size size = const Size(960, 1500),
  }) async {
    await tester.binding.setSurfaceSize(size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.view.reset();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: ItemDetailScreen(
          repository: repository,
          itemId: itemId,
          onBack: onBack,
          imageCache: imageCache,
          priceHistory: priceHistory,
          offline: offline,
          upstreamCheck: upstreamCheck,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('golden', () {
    testWidgets('weapon', (tester) async {
      await pumpDetail(tester, weaponItemId);

      expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsWidgets);
      await expectLater(
        find.byType(ItemDetailScreen),
        matchesGoldenFile('goldens/weapon.png'),
      );
    });

    testWidgets('ammunition', (tester) async {
      await pumpDetail(tester, ammunitionItemId);

      expect(find.text('5.56x45mm M855'), findsWidgets);
      await expectLater(
        find.byType(ItemDetailScreen),
        matchesGoldenFile('goldens/ammunition.png'),
      );
    });

    testWidgets('armor', (tester) async {
      await pumpDetail(tester, armorItemId);

      expect(find.text('6B43 Zabralo-Sh body armor (EMR)'), findsWidgets);
      await expectLater(
        find.byType(ItemDetailScreen),
        matchesGoldenFile('goldens/armor.png'),
      );
    });

    testWidgets('barter-only item', (tester) async {
      await pumpDetail(tester, barterItemId);

      expect(find.text('Leatherman Multitool'), findsWidgets);
      await expectLater(
        find.byType(ItemDetailScreen),
        matchesGoldenFile('goldens/barter.png'),
      );
    });
  });

  group('layout', () {
    Finder panelAround(String key) => find
        .ancestor(of: find.byKey(Key(key)), matching: find.byType(AppPanel))
        .first;

    testWidgets('wide windows keep facts and links in two columns', (
      tester,
    ) async {
      await pumpDetail(tester, weaponItemId, size: const Size(1440, 1200));

      final properties = tester.getTopLeft(
        find.byKey(const Key('item-detail-section-properties')),
      );
      final categories = tester.getTopLeft(
        panelAround('item-detail-categories'),
      );

      expect(categories.dx, greaterThan(properties.dx));
      expect((categories.dy - properties.dy).abs(), lessThan(1));
      expect(find.byKey(const Key('item-detail-wiki-link')), findsOneWidget);
    });

    testWidgets('narrow windows keep the single ordered column', (
      tester,
    ) async {
      await pumpDetail(tester, weaponItemId);

      final properties = tester.getTopLeft(
        find.byKey(const Key('item-detail-section-properties')),
      );
      final categories = tester.getTopLeft(
        panelAround('item-detail-categories'),
      );

      expect(categories.dx, properties.dx);
      expect(categories.dy, greaterThan(properties.dy));
    });
  });

  group('type-specific properties', () {
    testWidgets('a weapon renders caliber, fire rate, recoil and slots', (
      tester,
    ) async {
      await pumpDetail(tester, weaponItemId);

      expect(
        find.byKey(const Key('item-detail-section-weapon')),
        findsOneWidget,
      );
      expect(find.text('5.56x45 NATO'), findsOneWidget);
      expect(find.text('800 rpm'), findsOneWidget);
      expect(find.text('48'), findsOneWidget);
      expect(find.text('Vertical 119 · Horizontal 342'), findsOneWidget);
      expect(find.text('500 m'), findsOneWidget);
      expect(find.text('Single fire · Full auto'), findsOneWidget);
      expect(find.text('Pistol Grip · required'), findsOneWidget);
      expect(find.text('Magazine'), findsOneWidget);
    });

    testWidgets('a weapon omits ammunition, armor and medical properties', (
      tester,
    ) async {
      await pumpDetail(tester, weaponItemId);

      expect(
        find.byKey(const Key('item-detail-section-ammunition')),
        findsNothing,
      );
      expect(find.byKey(const Key('item-detail-section-armor')), findsNothing);
      expect(
        find.byKey(const Key('item-detail-section-medical')),
        findsNothing,
      );
      expect(find.text('Damage'), findsNothing);
      expect(find.text('Penetration'), findsNothing);
      expect(find.text('Armor damage'), findsNothing);
      expect(find.text('Protected zones'), findsNothing);
    });

    testWidgets('an ammunition item renders only ballistic properties', (
      tester,
    ) async {
      await pumpDetail(tester, ammunitionItemId);

      expect(
        find.byKey(const Key('item-detail-section-ammunition')),
        findsOneWidget,
      );
      expect(find.text('Damage'), findsOneWidget);
      expect(find.text('54'), findsOneWidget);
      expect(find.text('Penetration'), findsOneWidget);
      expect(find.text('31'), findsOneWidget);
      expect(find.text('Armor damage'), findsOneWidget);
      expect(find.text('37'), findsOneWidget);

      expect(find.byKey(const Key('item-detail-section-weapon')), findsNothing);
      expect(find.text('Fire rate'), findsNothing);
      expect(find.text('Ergonomics'), findsNothing);
      expect(find.text('Recoil'), findsNothing);
    });

    testWidgets('an armor item renders class, durability, zones and material', (
      tester,
    ) async {
      await pumpDetail(tester, armorItemId);

      expect(
        find.byKey(const Key('item-detail-section-armor')),
        findsOneWidget,
      );
      expect(find.text('Class 6'), findsOneWidget);
      expect(find.text('510'), findsOneWidget);
      expect(
        find.text('Front plate, Back plate, Stomach, Thorax'),
        findsOneWidget,
      );
      expect(find.text('Aramid'), findsOneWidget);

      expect(find.byKey(const Key('item-detail-section-weapon')), findsNothing);
      expect(
        find.byKey(const Key('item-detail-section-ammunition')),
        findsNothing,
      );
    });

    testWidgets('a medkit renders healing and effects but omits missing uses', (
      tester,
    ) async {
      await pumpDetail(tester, medicalItemId);

      expect(
        find.byKey(const Key('item-detail-section-medical')),
        findsOneWidget,
      );
      expect(find.text('400 HP · 85 HP per use'), findsOneWidget);
      expect(find.text('Light bleeding, Heavy bleeding'), findsOneWidget);
      expect(find.text('3 s'), findsOneWidget);
      expect(find.text('Uses'), findsNothing);
    });

    testWidgets(
      'a barter-only item keeps base properties and no typed section',
      (tester) async {
        await pumpDetail(tester, barterItemId);

        expect(
          find.byKey(const Key('item-detail-section-weapon')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('item-detail-section-ammunition')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('item-detail-section-armor')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('item-detail-section-medical')),
          findsNothing,
        );

        expect(find.text('0.142 kg'), findsOneWidget);
        expect(find.text('1 × 1 slots'), findsOneWidget);
        expect(find.text('Barter items'), findsOneWidget);
        expect(
          find.textContaining('https://tarkov.dev/item/leatherman-multitool'),
          findsOneWidget,
        );
        expect(find.text('Caliber'), findsNothing);
        expect(find.text('Damage'), findsNothing);
        expect(find.text('Class'), findsNothing);
        expect(find.text('Uses'), findsNothing);
      },
    );
  });

  group('prices', () {
    testWidgets('a complete snapshot shows source, observation and 48 h '
        'direction', (tester) async {
      await pumpDetail(tester, completePriceItemId);

      expect(
        find.byKey(const Key('item-detail-section-prices')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('item-detail-price-flea')), findsOneWidget);
      expect(find.text('40,000 ₽'), findsOneWidget);
      expect(find.byKey(const Key('item-detail-price-avg')), findsOneWidget);
      expect(find.text('111,351 ₽'), findsOneWidget);
      expect(find.text('Rising · +16.9% · +16,102 ₽'), findsOneWidget);
      expect(
        find.byKey(const Key('item-detail-price-observed')),
        findsOneWidget,
      );
      expect(find.text('2026-11-25 17:08 UTC'), findsOneWidget);
      expect(find.byKey(const Key('item-detail-price-base')), findsOneWidget);
      expect(find.text('18,397 ₽'), findsOneWidget);
      expect(find.byKey(const Key('item-detail-price-zero')), findsNothing);
      expect(find.byKey(const Key('item-detail-price-missing')), findsNothing);
    });

    testWidgets('a missing flea observation is named, not shown as zero', (
      tester,
    ) async {
      await pumpDetail(tester, missingPriceItemId);

      expect(
        find.byKey(const Key('item-detail-price-missing')),
        findsOneWidget,
      );
      expect(find.text('No flea price observed yet.'), findsOneWidget);
      expect(find.byKey(const Key('item-detail-price-flea')), findsNothing);
      expect(find.byKey(const Key('item-detail-price-zero')), findsNothing);
      expect(find.text('0 ₽'), findsNothing);
      expect(
        find.byKey(const Key('item-detail-price-observed')),
        findsOneWidget,
      );
    });

    testWidgets('a zero price is a real observation with its own state', (
      tester,
    ) async {
      await pumpDetail(tester, zeroPriceItemId);

      expect(find.byKey(const Key('item-detail-price-zero')), findsOneWidget);
      expect(find.text('No flea offers (0 ₽)'), findsOneWidget);
      expect(find.byKey(const Key('item-detail-price-missing')), findsNothing);
      expect(find.text('No flea price observed yet.'), findsNothing);
    });
  });

  group('acquisition and disposition', () {
    testWidgets('acquisition renders trader buy, barter, craft and quest '
        'rows from relationships', (tester) async {
      await pumpDetail(tester, relationsItemId);

      expect(
        find.byKey(const Key('item-detail-section-acquisition')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('item-detail-buy-trader-prapor')),
        findsOneWidget,
      );
      expect(find.text('22,000 ₽'), findsOneWidget);
      expect(find.textContaining('LL 2 · limit 3'), findsOneWidget);
      expect(
        find.byKey(const Key('item-detail-barter-barter-offer')),
        findsOneWidget,
      );
      expect(
        find.text('2 × 5.56x45mm M855 → 1 × Expeditionary fuel tank'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('item-detail-craft-craft-make')),
        findsOneWidget,
      );
      expect(
        find.text(
          '1 × Salewa first aid kit → 1 × Expeditionary fuel tank · 20 min',
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('item-detail-quest-quest-relations-objective')),
        findsOneWidget,
      );
      expect(find.text('Hand over the fuel tank'), findsOneWidget);
    });

    testWidgets('disposition renders trader sell and input uses', (
      tester,
    ) async {
      await pumpDetail(tester, relationsItemId);

      expect(
        find.byKey(const Key('item-detail-section-disposition')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('item-detail-sell-trader-therapist')),
        findsOneWidget,
      );
      expect(find.text('9,000 ₽'), findsOneWidget);
      expect(
        find.byKey(const Key('item-detail-barter-input-barter-consume')),
        findsOneWidget,
      );
      expect(
        find.text('Used for 1 × Colt M4A1 5.56x45 assault rifle'),
        findsWidgets,
      );
      expect(
        find.byKey(const Key('item-detail-craft-input-craft-use')),
        findsOneWidget,
      );
    });

    testWidgets('an item with no relationships omits every section', (
      tester,
    ) async {
      await pumpDetail(tester, barterItemId);

      expect(
        find.byKey(const Key('item-detail-section-acquisition')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('item-detail-section-disposition')),
        findsNothing,
      );
      expect(find.byKey(const Key('item-detail-section-prices')), findsNothing);
      expect(
        find.byKey(const Key('item-detail-section-history')),
        findsNothing,
      );
    });
  });

  group('price history', () {
    PriceHistoryRepository history(PriceHistorySource source) =>
        PriceHistoryRepository(
          database,
          source: source,
          ttl: const Duration(hours: 6),
          clock: () => DateTime.utc(2026, 11, 27, 12),
        );

    testWidgets('an online load renders the chart', (tester) async {
      await tester.binding.setSurfaceSize(const Size(960, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final points = [
        for (var hours = 2; hours >= 0; hours--)
          PriceHistoryPoint(
            observedAt: DateTime.utc(2026, 11, 27, 10 + (2 - hours)),
            price: 12000 + (2 - hours) * 1500,
            priceMin: null,
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ItemDetailScreen(
            repository: repository,
            itemId: weaponItemId,
            priceHistory: history(_FakeHistorySource(points)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('item-detail-section-history')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('price-history-chart')), findsOneWidget);
    });

    testWidgets('offline without a cache shows the unavailable state', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ItemDetailScreen(
            repository: repository,
            itemId: weaponItemId,
            priceHistory: history(_FakeHistorySource(const [])),
            offline: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('item-detail-section-history')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('price-history-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('price-history-plot')), findsNothing);
      expect(find.byKey(const Key('price-history-retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('price-history-retry')));
      await tester.pumpAndSettle();
      expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsWidgets);
      expect(
        find.byKey(const Key('price-history-unavailable')),
        findsOneWidget,
      );
    });
  });

  testWidgets('a failed upstream check leaves the saved item visible', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      weaponItemId,
      upstreamCheck: () async => const UpstreamStatus.offline(),
    );

    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsWidgets);
    expect(
      find.byKey(const Key('item-detail-upstream-status')),
      findsOneWidget,
    );
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.byKey(const Key('item-detail-error')), findsNothing);
  });

  group('images', () {
    testWidgets('the header uses the cache image instead of the placeholder', (
      tester,
    ) async {
      final directory = Directory.systemTemp.createTempSync('detail-images-');
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final cache = ItemImageCache(
        directory: directory,
        fetcher: _HeaderPngFetcher(),
      );
      await tester.runAsync(() async {
        await cache.load('https://assets.tarkov.dev/fuel-tank-icon.webp');
      });

      await pumpDetail(tester, relationsItemId, imageCache: cache);

      expect(find.byKey(const Key('item-detail-icon')), findsOneWidget);
      expect(
        find.byKey(const Key('item-detail-icon-placeholder')),
        findsNothing,
      );
    });

    testWidgets('an item without an icon keeps the placeholder', (
      tester,
    ) async {
      await pumpDetail(tester, weaponItemId);

      expect(
        find.byKey(const Key('item-detail-icon-placeholder')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('item-detail-icon')), findsNothing);
    });
  });

  group('states', () {
    testWidgets('renders a loading indicator before the lookup completes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: ItemDetailScreen(repository: repository, itemId: weaponItemId),
        ),
      );

      expect(find.byKey(const Key('item-detail-loading')), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byKey(const Key('item-detail-loading')), findsNothing);
      expect(find.byKey(const Key('item-detail-name')), findsOneWidget);
    });

    testWidgets(
      'a missing item shows the not-found state with back navigation',
      (tester) async {
        var backs = 0;
        await pumpDetail(tester, 'removed-item', onBack: () => backs++);

        expect(find.byKey(const Key('item-detail-not-found')), findsOneWidget);
        expect(find.text('Item no longer available'), findsOneWidget);
        expect(find.textContaining('removed-item'), findsOneWidget);

        await tester.tap(find.byKey(const Key('item-detail-back')));
        expect(backs, 1);
      },
    );

    testWidgets('corrupt payload data shows the error state and retries', (
      tester,
    ) async {
      await database.customStatement(
        'INSERT INTO items (id, name, shortName, normalizedName, payload) '
        "VALUES ('corrupt', 'Corrupt item', 'Corrupt', 'corrupt-item', 'nope')",
      );

      await pumpDetail(tester, 'corrupt');

      expect(find.byKey(const Key('item-detail-error')), findsOneWidget);
      expect(find.text('Could not load this item.'), findsOneWidget);
      expect(find.byKey(const Key('item-detail-retry')), findsOneWidget);
    });
  });
}

final class _FakeHistorySource implements PriceHistorySource {
  const _FakeHistorySource(this.points);

  final List<PriceHistoryPoint> points;

  @override
  Future<List<PriceHistoryPoint>> fetch(String itemId) async => points;
}

final class _HeaderPngFetcher implements ItemImageFetcher {
  @override
  Future<Uint8List> fetch(Uri uri) async => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNg'
    'YGBgAAAABQABeqhXUAAAAABJRU5ErkJggg==',
  );
}
