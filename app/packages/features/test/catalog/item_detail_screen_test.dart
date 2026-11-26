import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/item_detail_fixture.dart';

/// One fixed theme and surface size for every golden.
///
/// Goldens are committed for Linux desktop. A theme built from an explicit
/// seed keeps typography and elevation deterministic across test runs.
final _goldenTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF3F51B5),
    brightness: Brightness.light,
  ),
);

void main() {
  late AppDatabase database;
  late CatalogRepository repository;

  setUp(() async {
    database = await openItemDetailFixtureDatabase();
    repository = CatalogRepository(database);
  });

  tearDown(() => database.close());

  Future<void> pumpDetail(
    WidgetTester tester,
    String itemId, {
    VoidCallback? onBack,
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
        theme: _goldenTheme,
        home: ItemDetailScreen(
          repository: repository,
          itemId: itemId,
          onBack: onBack,
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

  group('states', () {
    testWidgets('renders a loading indicator before the lookup completes', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(960, 1500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: _goldenTheme,
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
