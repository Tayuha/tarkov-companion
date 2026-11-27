import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/quest_detail_fixture.dart';
import '../theme/support/load_fonts.dart';

void main() {
  late AppDatabase database;
  late QuestRepository repository;
  late CatalogRepository catalog;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadDesignFonts();
  });

  setUp(() async {
    database = await openQuestDetailFixtureDatabase();
    repository = QuestRepository(database);
    catalog = CatalogRepository(database);
  });

  tearDown(() => database.close());

  Future<void> pumpDetail(
    WidgetTester tester, {
    String questId = qdMainQuest,
    String? profileId = qdProfileRegular,
    Size size = const Size(1200, 3000),
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
        home: QuestDetailScreen(
          repository: repository,
          catalog: catalog,
          questId: questId,
          profileId: profileId,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder stateBadge(String label) => find.descendant(
    of: find.byKey(const Key('quest-detail-state')),
    matching: find.text(label),
  );

  Finder availabilityBadge(String label) => find.descendant(
    of: find.byKey(const Key('quest-detail-availability')),
    matching: find.text(label),
  );

  String fieldText(WidgetTester tester, String objectiveId) {
    final field = tester.widget<TextField>(
      find.byKey(ValueKey('quest-objective-count-$objectiveId')),
    );
    return field.controller!.text;
  }

  testWidgets('renders header, objectives, requirements and locked reasons', (
    tester,
  ) async {
    await pumpDetail(tester);

    expect(find.text('Big Customer'), findsWidgets);
    expect(stateBadge('NOT STARTED'), findsOneWidget);
    expect(availabilityBadge('LOCKED'), findsOneWidget);
    expect(find.text('Trader: Prapor'), findsOneWidget);
    expect(find.text('Map: Customs'), findsOneWidget);
    expect(find.text('Level 10'), findsOneWidget);
    expect(find.text('5000 XP'), findsOneWidget);
    expect(find.text('Kappa required'), findsOneWidget);
    expect(find.byKey(const Key('quest-detail-wiki-link')), findsOneWidget);
    expect(find.byKey(const Key('quest-detail-section-notes')), findsOneWidget);

    expect(find.text('Eliminate Scavs on Customs'), findsOneWidget);
    expect(find.text('Hand over a Salewa first aid kit'), findsOneWidget);
    expect(find.text('Optional: visit the dormitory'), findsOneWidget);
    expect(find.text('0 of 2 required objectives satisfied.'), findsOneWidget);
    expect(
      find.byKey(const Key('quest-detail-section-rewards')),
      findsOneWidget,
    );
    // No quest in the fixture requires Big Customer, so the panel is omitted.
    expect(find.byKey(const Key('quest-detail-section-unlocks')), findsNothing);

    expect(find.text('First Job'), findsOneWidget);
    expect(
      find.text('Requires complete · currently Not started'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Prerequisite quest "First Job" must be complete'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('quest-lock-reasons-title')), findsOneWidget);
  });

  testWidgets('missing fields omit their panels instead of placeholders', (
    tester,
  ) async {
    await pumpDetail(tester, questId: qdAdvisoryQuest);

    expect(find.byKey(const Key('quest-detail-description')), findsNothing);
    expect(find.byKey(const Key('quest-detail-section-notes')), findsNothing);
    expect(find.byKey(const Key('quest-detail-section-rewards')), findsNothing);
    expect(find.byKey(const Key('quest-detail-section-items')), findsNothing);
    expect(find.byKey(const Key('quest-detail-section-unlocks')), findsNothing);

    // The requirements and status panels are core, derived UI; they stay.
    expect(
      find.byKey(const Key('quest-detail-section-requirements')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('quest-detail-section-status')),
      findsOneWidget,
    );
    expect(find.textContaining('advisory only'), findsOneWidget);
  });

  testWidgets('renders level, cycle, malformed and advisory reasons', (
    tester,
  ) async {
    await pumpDetail(tester, questId: qdLevelLockedQuest);
    expect(availabilityBadge('LOCKED'), findsOneWidget);
    expect(find.textContaining('Requires player level 50'), findsOneWidget);

    await pumpDetail(tester, questId: qdCycleAQuest);
    expect(availabilityBadge('LOCKED'), findsOneWidget);
    expect(find.textContaining('Malformed prerequisite cycle'), findsOneWidget);

    await pumpDetail(tester, questId: qdMalformedQuest);
    expect(availabilityBadge('LOCKED'), findsOneWidget);
    expect(find.textContaining('Malformed prerequisite data'), findsOneWidget);

    await pumpDetail(tester, questId: qdAdvisoryQuest);
    expect(availabilityBadge('AVAILABLE'), findsOneWidget);
    expect(find.textContaining('not enforced locally'), findsOneWidget);
  });

  testWidgets('status change persists and updates the badge and availability', (
    tester,
  ) async {
    await pumpDetail(tester, questId: qdAvailableQuest);
    expect(availabilityBadge('AVAILABLE'), findsOneWidget);
    expect(stateBadge('NOT STARTED'), findsOneWidget);

    await tapVisible(
      tester,
      find.byKey(const Key('quest-status-mark-in-progress')),
    );
    expect(stateBadge('IN PROGRESS'), findsOneWidget);
    expect(availabilityBadge('IN PROGRESS'), findsOneWidget);
    expect(
      (await repository.status(
        qdProfileRegular,
        qdAvailableQuest,
      ))!.recordedState,
      QuestProgressState.inProgress,
    );

    await tapVisible(tester, find.byKey(const Key('quest-status-revert')));
    expect(stateBadge('NOT STARTED'), findsOneWidget);
    expect(availabilityBadge('AVAILABLE'), findsOneWidget);
    expect(
      (await repository.status(
        qdProfileRegular,
        qdAvailableQuest,
      ))!.recordedState,
      QuestProgressState.notStarted,
    );

    await tapVisible(tester, find.byKey(const Key('quest-status-mark-failed')));
    expect(stateBadge('FAILED'), findsOneWidget);
    expect(availabilityBadge('LOCKED'), findsOneWidget);

    await tapVisible(
      tester,
      find.byKey(const Key('quest-status-mark-completed')),
    );
    expect(stateBadge('COMPLETED'), findsOneWidget);
    expect(availabilityBadge('COMPLETED'), findsOneWidget);
  });

  testWidgets('objective controls persist, change the hint and accept text', (
    tester,
  ) async {
    await pumpDetail(tester, questId: qdCountQuest);

    expect(fieldText(tester, qdObjectiveCountA), '0');
    expect(find.text('0 of 2 required objectives satisfied.'), findsOneWidget);
    AppProgressBar barFor(String objectiveId) => tester.widget<AppProgressBar>(
      find.descendant(
        of: find.byKey(ValueKey('quest-objective-$objectiveId')),
        matching: find.byType(AppProgressBar),
      ),
    );
    expect(barFor(qdObjectiveCountA).value, 0);

    for (var index = 0; index < 3; index++) {
      await tapVisible(
        tester,
        find.byKey(ValueKey('quest-objective-increment-$qdObjectiveCountA')),
      );
    }
    expect(fieldText(tester, qdObjectiveCountA), '3');
    expect(find.text('1 of 2 required objectives satisfied.'), findsOneWidget);
    expect(find.textContaining('requires a manual override'), findsOneWidget);
    expect(barFor(qdObjectiveCountA).value, 1);

    for (var index = 0; index < 2; index++) {
      await tapVisible(
        tester,
        find.byKey(ValueKey('quest-objective-increment-$qdObjectiveCountB')),
      );
    }
    expect(find.text('All required objectives are satisfied.'), findsOneWidget);
    expect(
      find.textContaining('can be recorded without an override'),
      findsOneWidget,
    );

    await tapVisible(
      tester,
      find.byKey(ValueKey('quest-objective-decrement-$qdObjectiveCountA')),
    );
    expect(fieldText(tester, qdObjectiveCountA), '2');
    expect(find.text('1 of 2 required objectives satisfied.'), findsOneWidget);
    expect(barFor(qdObjectiveCountA).value, closeTo(2 / 3, 0.001));

    await tester.enterText(
      find.byKey(ValueKey('quest-objective-count-$qdObjectiveCountA')),
      '1',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(fieldText(tester, qdObjectiveCountA), '1');
    final status = (await repository.status(qdProfileRegular, qdCountQuest))!;
    expect(
      status.objectives
          .singleWhere((entry) => entry.objective.id == qdObjectiveCountA)
          .count,
      1,
    );
  });

  testWidgets('manual override confirms without changing objective counts', (
    tester,
  ) async {
    await pumpDetail(tester, questId: qdOverrideQuest);
    expect(fieldText(tester, qdObjectiveOverride), '0');

    await tapVisible(
      tester,
      find.byKey(const Key('quest-status-mark-completed')),
    );
    expect(find.byKey(const Key('quest-override-dialog')), findsOneWidget);
    expect(
      find.textContaining('Objective counts are not changed'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('quest-override-cancel')));
    await tester.pumpAndSettle();
    expect(stateBadge('NOT STARTED'), findsOneWidget);
    expect(
      (await repository.status(
        qdProfileRegular,
        qdOverrideQuest,
      ))!.recordedState,
      QuestProgressState.notStarted,
    );

    await tapVisible(
      tester,
      find.byKey(const Key('quest-status-mark-completed')),
    );
    await tester.tap(find.byKey(const Key('quest-override-confirm')));
    await tester.pumpAndSettle();

    expect(stateBadge('COMPLETED'), findsOneWidget);
    expect(
      find.byKey(const Key('quest-detail-manual-override')),
      findsOneWidget,
    );
    expect(fieldText(tester, qdObjectiveOverride), '0');

    final status = (await repository.status(
      qdProfileRegular,
      qdOverrideQuest,
    ))!;
    expect(status.manuallyCompleted, isTrue);
    expect(status.objectives.single.count, 0);
  });

  testWidgets('reward and turn-in item links open the item detail screen', (
    tester,
  ) async {
    await pumpDetail(tester);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('quest-item-link-$qdRewardItem')),
    );
    expect(find.byKey(const Key('item-detail-screen')), findsOneWidget);
    expect(find.text(qdRewardItemName), findsWidgets);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await tapVisible(
      tester,
      find.byKey(const ValueKey('quest-item-link-$qdTurnInItem')),
    );
    expect(find.byKey(const Key('item-detail-screen')), findsOneWidget);
    expect(find.text(qdTurnInItemName), findsWidgets);
  });

  testWidgets('prerequisite and unlock links push another quest detail', (
    tester,
  ) async {
    await pumpDetail(tester);

    await tapVisible(
      tester,
      find.byKey(const ValueKey('quest-prerequisite-$qdPrereqQuest')),
    );
    expect(find.text('First Job'), findsWidgets);
    expect(find.byKey(const Key('quest-detail-screen')), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    await pumpDetail(tester, questId: qdPrereqQuest);
    await tapVisible(
      tester,
      find.byKey(const ValueKey('quest-unlock-$qdMainQuest')),
    );
    expect(find.text('Big Customer'), findsWidgets);
  });

  testWidgets('not-found and orphaned states are distinct', (tester) async {
    await pumpDetail(tester, questId: qdMissingQuest);
    expect(find.byKey(const Key('quest-detail-not-found')), findsOneWidget);
    expect(find.textContaining(qdMissingQuest), findsOneWidget);

    await pumpDetail(tester, questId: qdRemovedQuest);
    expect(find.byKey(const Key('quest-detail-orphaned')), findsOneWidget);
    expect(find.text('Quest unavailable upstream'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('quest-orphan-state')),
        matching: find.text('IN PROGRESS'),
      ),
      findsOneWidget,
    );
    expect(find.text('$qdObjectiveRemoved: 2'), findsOneWidget);
  });

  testWidgets('profiles keep status and objective counts isolated', (
    tester,
  ) async {
    await pumpDetail(tester);
    expect(availabilityBadge('LOCKED'), findsOneWidget);

    await pumpDetail(tester, profileId: qdProfilePve);
    expect(availabilityBadge('AVAILABLE'), findsOneWidget);

    await pumpDetail(tester, questId: qdCountQuest);
    expect(stateBadge('NOT STARTED'), findsOneWidget);
    expect(fieldText(tester, qdObjectiveCountA), '0');

    await pumpDetail(tester, questId: qdCountQuest, profileId: qdProfilePve);
    expect(stateBadge('IN PROGRESS'), findsOneWidget);
    expect(fieldText(tester, qdObjectiveCountA), '1');

    await tapVisible(
      tester,
      find.byKey(ValueKey('quest-objective-increment-$qdObjectiveCountA')),
    );
    expect(fieldText(tester, qdObjectiveCountA), '2');

    await pumpDetail(tester, questId: qdCountQuest);
    expect(fieldText(tester, qdObjectiveCountA), '0');

    final regular = (await repository.status(qdProfileRegular, qdCountQuest))!;
    final pve = (await repository.status(qdProfilePve, qdCountQuest))!;
    expect(
      regular.objectives
          .singleWhere((entry) => entry.objective.id == qdObjectiveCountA)
          .count,
      0,
    );
    expect(
      pve.objectives
          .singleWhere((entry) => entry.objective.id == qdObjectiveCountA)
          .count,
      2,
    );
  });

  testWidgets('no profile renders a read-only detail without status controls', (
    tester,
  ) async {
    await pumpDetail(tester, profileId: null);

    expect(find.byKey(const Key('quest-detail-no-profile')), findsOneWidget);
    expect(find.byKey(const Key('quest-status-no-profile')), findsOneWidget);
    expect(find.byKey(const Key('quest-status-mark-completed')), findsNothing);
    expect(find.byKey(const Key('quest-detail-availability')), findsNothing);
    expect(find.text('Requires complete'), findsOneWidget);
  });

  testWidgets('label lookups fall back to the id when rows are missing', (
    tester,
  ) async {
    await database.customStatement('DELETE FROM traders');
    await database.customStatement('DELETE FROM maps');

    await pumpDetail(tester);

    expect(find.text('Trader: $qdPrapor'), findsOneWidget);
    expect(find.text('Map: $qdCustoms'), findsOneWidget);
  });

  group('layout', () {
    testWidgets('wide windows split objectives and rewards into columns', (
      tester,
    ) async {
      await pumpDetail(tester, size: const Size(1440, 1600));

      final objectives = tester.getTopLeft(
        find.byKey(const Key('quest-detail-section-objectives')),
      );
      final rewards = tester.getTopLeft(
        find.byKey(const Key('quest-detail-section-rewards')),
      );

      expect(rewards.dx, greaterThan(objectives.dx));
      expect((rewards.dy - objectives.dy).abs(), lessThan(2));
      expect(tester.getSize(find.byType(QuestDetailScreen)).width, 1440);
    });

    testWidgets('narrow windows keep one ordered column', (tester) async {
      await pumpDetail(tester, size: const Size(900, 2000));

      final objectives = tester.getTopLeft(
        find.byKey(const Key('quest-detail-section-objectives')),
      );
      final rewards = tester.getTopLeft(
        find.byKey(const Key('quest-detail-section-rewards')),
      );

      expect(rewards.dx, closeTo(objectives.dx, 0.1));
      expect(rewards.dy, greaterThan(objectives.dy));
    });

    testWidgets('content is capped at 1180 on an ultra-wide window', (
      tester,
    ) async {
      await pumpDetail(tester, size: const Size(2000, 1600));

      final scroll = find.byKey(const Key('quest-detail-scroll'));
      expect(tester.getSize(scroll).width, 2000);
      final header = tester.getTopLeft(
        find.byKey(const Key('quest-detail-name')),
      );
      // (2000 - 1180) / 2 = 410 px of centred margin.
      expect(header.dx, closeTo(410, 1));
    });
  });

  group('golden', () {
    testWidgets('quest detail two column at 1440', (tester) async {
      await pumpDetail(tester, size: const Size(1440, 1200));

      await expectLater(
        find.byType(QuestDetailScreen),
        matchesGoldenFile('goldens/quest_detail_1440.png'),
      );
    });

    testWidgets('quest detail single column at 900', (tester) async {
      await pumpDetail(tester, size: const Size(900, 1600));

      await expectLater(
        find.byType(QuestDetailScreen),
        matchesGoldenFile('goldens/quest_detail_900.png'),
      );
    });
  });
}
