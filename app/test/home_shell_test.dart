import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion/src/home_shell.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

/// A small local catalog and quest set for the shell tests.
///
/// The shell itself has no query logic, but its tabs render the real screens.
/// A memory database keeps the test on the production repositories without a
/// SQLite file, and two items are enough to prove that a search survives a tab
/// switch.
Future<AppDatabase> _openFixtureDatabase() async {
  final database = AppDatabase.memory();
  await database.customSelect('SELECT 1').get(); // Force `beforeOpen`.

  for (final item in const [
    (
      id: 'item-rifle',
      name: 'Colt M4A1 5.56x45 assault rifle',
      shortName: 'M4A1',
      normalizedName: 'colt-m4a1-556x45-assault-rifle',
    ),
    (
      id: 'item-ak',
      name: 'Kalashnikov AK-74N 5.45x39 assault rifle',
      shortName: 'AK-74N',
      normalizedName: 'kalashnikov-ak-74n-545x39-assault-rifle',
    ),
  ]) {
    await database.customStatement(
      'INSERT INTO items ('
      'id, name, shortName, normalizedName, weight, basePrice, '
      'avg24hPrice, lastLowPrice, fleaEligible, payload'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        item.id,
        item.name,
        item.shortName,
        item.normalizedName,
        3.4,
        18397,
        40000,
        40000,
        1,
        '{}',
      ],
    );
    await database.customStatement(
      'INSERT INTO itemTypes (itemId, type) VALUES (?, ?)',
      [item.id, 'gun'],
    );
  }

  for (final quest in const [
    (id: 'quest-checking', name: 'Checking'),
    (id: 'quest-shortage', name: 'Shortage'),
  ]) {
    await database.customStatement(
      'INSERT INTO tasks (id, name, payload) VALUES (?, ?, ?)',
      [
        quest.id,
        quest.name,
        jsonEncode({'normalizedName': quest.name.toLowerCase()}),
      ],
    );
  }

  return database;
}

void main() {
  late AppDatabase database;
  late CatalogRepository catalog;
  late QuestRepository quests;

  setUp(() async {
    database = await _openFixtureDatabase();
    catalog = CatalogRepository(database);
    quests = QuestRepository(database);
  });

  tearDown(() => database.close());

  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
    ValueChanged<String>? onQuestSelected,
    UpdateCheckControl? updates,
    DataBundleStatus? dataBundle,
    UpstreamCheck? upstreamCheck,
    ItemImageCache? imageCache,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: HomeShell(
          catalog: catalog,
          quests: quests,
          activeProfileId: 'profile-regular',
          onQuestSelected: onQuestSelected,
          updates: updates,
          dataBundle: dataBundle,
          upstreamCheck: upstreamCheck,
          imageCache: imageCache,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('wide windows show the rail with Items and Quests', (
    tester,
  ) async {
    await pumpShell(tester);

    expect(find.byKey(const Key('home-navigation-rail')), findsOneWidget);
    expect(find.byKey(const Key('home-bottom-navigation')), findsNothing);
    expect(find.byKey(const Key('home-rail-items-label')), findsOneWidget);
    expect(find.byKey(const Key('home-rail-quests-label')), findsOneWidget);
    expect(find.byType(CatalogScreen), findsOneWidget);
    expect(find.byType(QuestListScreen), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('home-tab-title'))).data,
      'Items',
    );
  });

  testWidgets(
    'switching tabs changes the screen and keeps the catalog search',
    (tester) async {
      await pumpShell(tester);

      await tester.enterText(
        find.byKey(const Key('catalog-search-field')),
        'm4a1',
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);
      expect(
        find.text('Kalashnikov AK-74N 5.45x39 assault rifle'),
        findsNothing,
      );

      await tester.tap(find.byKey(const Key('home-rail-quests-label')));
      await tester.pumpAndSettle();

      expect(find.byType(QuestListScreen), findsOneWidget);
      expect(find.byType(CatalogScreen), findsNothing);
      expect(find.text('Checking'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('home-tab-title'))).data,
        'Quests',
      );

      await tester.tap(find.byKey(const Key('home-rail-items-label')));
      await tester.pumpAndSettle();

      expect(find.byType(CatalogScreen), findsOneWidget);
      expect(find.byType(QuestListScreen), findsNothing);
      final search = tester.widget<TextField>(
        find.byKey(const Key('catalog-search-field')),
      );
      expect(search.controller?.text, 'm4a1');
      expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);
    },
  );

  testWidgets('narrow windows use the bottom bar instead of the rail', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(600, 800));

    expect(find.byKey(const Key('home-bottom-navigation')), findsOneWidget);
    expect(find.byKey(const Key('home-navigation-rail')), findsNothing);

    await tester.tap(find.byKey(const Key('home-bar-quests')));
    await tester.pumpAndSettle();

    expect(find.byType(QuestListScreen), findsOneWidget);
    expect(find.byType(CatalogScreen), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('home-tab-title'))).data,
      'Quests',
    );
  });

  testWidgets('tapping an item row pushes the item detail', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('catalog-item-item-rifle')));
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsWidgets);
  });

  testWidgets('a quest tap opens the quest detail screen', (tester) async {
    await pumpShell(tester);

    await tester.tap(find.byKey(const Key('home-rail-quests-label')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quest-row-quest-checking')));
    await tester.pumpAndSettle();

    expect(find.byType(QuestDetailScreen), findsOneWidget);
  });

  testWidgets('a quest tap is reported to the shell callback', (tester) async {
    String? selected;
    await pumpShell(tester, onQuestSelected: (id) => selected = id);

    await tester.tap(find.byKey(const Key('home-rail-quests-label')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quest-row-quest-checking')));
    await tester.pump();

    expect(selected, 'quest-checking');
  });

  testWidgets('the footer keeps the status strip out of the primary rail', (
    tester,
  ) async {
    final updates = _FakeUpdateControl();

    await pumpShell(tester, updates: updates);

    expect(find.byKey(const Key('home-navigation-rail')), findsOneWidget);
    expect(find.byKey(SyncStatusKeys.bar), findsOneWidget);
    expect(find.byKey(SyncStatusKeys.about), findsOneWidget);
    expect(find.byKey(const Key('home-rail-about')), findsNothing);
    expect(find.text('DAILY'), findsOneWidget);
  });

  testWidgets('the footer About entry opens the About screen', (tester) async {
    final updates = _FakeUpdateControl();

    await pumpShell(
      tester,
      updates: updates,
      dataBundle: DataBundleStatus(
        mode: GameMode.regular,
        appliedDatasets: 7,
        expectedDatasets: 7,
        oldestAppliedAt: DateTime.utc(2026, 11, 25, 12),
        manifestVersion: 1,
        bundleSchemaVersion: 1,
        manifestGeneratedAt: DateTime.utc(2026, 11, 24, 10, 32),
      ),
    );

    await tester.tap(find.byKey(SyncStatusKeys.about));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(AboutKeys.appVersion)).data, '0.1.0');
    expect(
      tester.widget<Text>(find.byKey(AboutKeys.bundleVersion)).data,
      'manifest 1 · schema 1',
    );
  });

  testWidgets('an offline upstream surfaces the status strip over cached rows', (
    tester,
  ) async {
    await pumpShell(
      tester,
      upstreamCheck: () async => UpstreamStatus.offline(
        message: 'no connection',
        checkedAt: DateTime.utc(2026, 11, 27),
      ),
    );

    expect(find.text('OFFLINE'), findsWidgets);
    expect(find.byKey(const Key('app-status-retry')), findsWidgets);
    // Cached rows stay visible instead of being replaced by the error state.
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsWidgets);
  });

  testWidgets('the shell shares the image cache with the catalog', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp('tc-images-');
    addTearDown(() => directory.delete(recursive: true));
    final cache = ItemImageCache(directory: directory, fetcher: _NoopFetcher());

    await pumpShell(tester, imageCache: cache);

    expect(
      tester.widget<CatalogScreen>(find.byType(CatalogScreen)).imageCache,
      same(cache),
    );
  });

  testWidgets('a session without updates still exposes About', (tester) async {
    await pumpShell(tester);

    expect(find.byKey(const Key('home-footer')), findsOneWidget);
    expect(find.byKey(const Key('home-about')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-about')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
  });
}

final class _FakeUpdateControl implements UpdateCheckControl {
  final _controller = StreamController<UpdateCheckStatus>.broadcast();

  @override
  UpdateCheckStatus status = const UpdateCheckStatus();

  @override
  Stream<UpdateCheckStatus> get changes => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<UpdateCheckStatus> checkNow() async => status;

  @override
  Future<void> setSchedule(UpdateSchedule schedule) async {
    status = status.copyWith(schedule: schedule);
    _controller.add(status);
  }

  @override
  Future<void> dispose() => _controller.close();
}

final class _NoopFetcher implements ItemImageFetcher {
  @override
  Future<Uint8List> fetch(Uri uri) async => Uint8List(0);
}
