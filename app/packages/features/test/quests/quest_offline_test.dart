import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/quest_screen_fixture.dart';

/// Quest network-state tests.
///
/// Rows and availability come from the real repository; only the upstream check
/// fails. Saved quests must stay usable, and the available segment must say
/// that its local derivation is still valid during an outage.
void main() {
  late AppDatabase database;
  late QuestRepository repository;

  setUp(() async {
    database = await openQuestFixtureDatabase();
    repository = QuestRepository(database);
  });

  tearDown(() => database.close());

  Future<void> pumpQuests(
    WidgetTester tester, {
    required UpstreamCheck? upstreamCheck,
    Size size = const Size(1000, 1400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: QuestListScreen(
          repository: repository,
          profileId: fixtureProfileRegular,
          traderOptions: fixtureTraderOptions,
          mapOptions: fixtureMapOptions,
          upstreamCheck: upstreamCheck,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('saved quests stay visible when the upstream is offline', (
    tester,
  ) async {
    var checks = 0;
    Future<UpstreamStatus> failing() async {
      checks++;
      return const UpstreamStatus.offline();
    }

    await pumpQuests(tester, upstreamCheck: failing);

    expect(checks, 1);
    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);
    expect(find.text('Debut'), findsOneWidget);
    expect(find.byKey(const Key('quest-upstream-status')), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.byKey(const Key('app-status-retry')), findsOneWidget);
    expect(find.byKey(const Key('quest-error-banner')), findsNothing);
  });

  testWidgets('retry re-runs the check and keeps the catalog intact', (
    tester,
  ) async {
    var checks = 0;
    Future<UpstreamStatus> failing() async {
      checks++;
      return const UpstreamStatus.failed(message: 'HTTP 503 response.');
    }

    await pumpQuests(tester, upstreamCheck: failing);
    expect(checks, 1);
    expect(find.text('UPSTREAM UNAVAILABLE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-status-retry')));
    await tester.pumpAndSettle();

    expect(checks, 2);
    expect(find.text('Showing 14 of 14 quests'), findsOneWidget);
    expect(find.text('Debut'), findsOneWidget);
  });

  testWidgets('the available segment keeps working through an outage', (
    tester,
  ) async {
    await pumpQuests(
      tester,
      upstreamCheck: () async => const UpstreamStatus.offline(),
    );

    await tester.tap(find.byKey(const Key('quest-view-available')));
    await tester.pumpAndSettle();

    expect(find.text('Available quests'), findsOneWidget);
    expect(find.text('6 available quests'), findsOneWidget);
    expect(find.text('Café Crème'), findsOneWidget);
    expect(find.byKey(const Key('quest-upstream-status')), findsOneWidget);
  });

  testWidgets('an empty catalog shows the offline state and retries', (
    tester,
  ) async {
    await database.customStatement('DELETE FROM questProgress');
    await database.customStatement('DELETE FROM objectiveProgress');
    await database.customStatement('DELETE FROM tasks');

    var checks = 0;
    Future<UpstreamStatus> failing() async {
      checks++;
      return const UpstreamStatus.offline();
    }

    await pumpQuests(tester, upstreamCheck: failing);

    expect(checks, 1);
    expect(find.byKey(const Key('quest-offline-empty-title')), findsOneWidget);
    expect(find.byKey(const Key('quest-offline-empty-detail')), findsOneWidget);
    expect(
      find.textContaining('reads from the local dataset first'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('quest-offline-retry')), findsOneWidget);
    expect(find.byKey(const Key('quest-upstream-status')), findsNothing);

    await tester.tap(find.byKey(const Key('quest-offline-retry')));
    await tester.pumpAndSettle();
    expect(checks, 2);
  });

  testWidgets('the available segment explains its offline empty result', (
    tester,
  ) async {
    await database.customStatement('DELETE FROM questProgress');
    await database.customStatement('DELETE FROM objectiveProgress');
    await database.customStatement('DELETE FROM tasks');

    var checks = 0;
    Future<UpstreamStatus> failing() async {
      checks++;
      return const UpstreamStatus.offline();
    }

    await pumpQuests(tester, upstreamCheck: failing);
    await tester.tap(find.byKey(const Key('quest-view-available')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('quest-available-offline-empty')),
      findsOneWidget,
    );
    expect(
      find.textContaining('Availability is computed from saved progress'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('quest-available-offline-retry')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('quest-available-offline-retry')));
    await tester.pumpAndSettle();
    expect(checks, 2);
  });
}
