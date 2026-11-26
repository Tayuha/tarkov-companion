import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/quest_detail_fixture.dart';

void main() {
  late AppDatabase database;
  late QuestRepository repository;
  late CatalogRepository catalog;

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
  }) async {
    await tester.binding.setSurfaceSize(const Size(1200, 3000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
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
    expect(stateBadge('Not started'), findsOneWidget);
    expect(availabilityBadge('Locked'), findsOneWidget);
    expect(find.text('Trader: Prapor'), findsOneWidget);
    expect(find.text('Map: Customs'), findsOneWidget);
    expect(find.text('Level 10'), findsOneWidget);
    expect(find.text('5000 XP'), findsOneWidget);
    expect(find.text('Kappa required'), findsOneWidget);
    expect(find.byKey(const Key('quest-detail-wiki-link')), findsOneWidget);

    expect(find.text('Eliminate Scavs on Customs'), findsOneWidget);
    expect(find.text('Hand over a Salewa first aid kit'), findsOneWidget);
    expect(find.text('Optional: visit the dormitory'), findsOneWidget);
    expect(find.text('0 of 2 required objectives satisfied.'), findsOneWidget);

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

  testWidgets('renders level, cycle, malformed and advisory reasons', (
    tester,
  ) async {
    await pumpDetail(tester, questId: qdLevelLockedQuest);
    expect(availabilityBadge('Locked'), findsOneWidget);
    expect(find.textContaining('Requires player level 50'), findsOneWidget);

    await pumpDetail(tester, questId: qdCycleAQuest);
    expect(availabilityBadge('Locked'), findsOneWidget);
    expect(find.textContaining('Malformed prerequisite cycle'), findsOneWidget);

    await pumpDetail(tester, questId: qdMalformedQuest);
    expect(availabilityBadge('Locked'), findsOneWidget);
    expect(find.textContaining('Malformed prerequisite data'), findsOneWidget);

    await pumpDetail(tester, questId: qdAdvisoryQuest);
    expect(availabilityBadge('Available'), findsOneWidget);
    expect(find.textContaining('not enforced locally'), findsOneWidget);
  });

  testWidgets('status change persists and updates the badge and availability', (
    tester,
  ) async {
    await pumpDetail(tester, questId: qdAvailableQuest);
    expect(availabilityBadge('Available'), findsOneWidget);
    expect(stateBadge('Not started'), findsOneWidget);

    await tapVisible(
      tester,
      find.byKey(const Key('quest-status-mark-in-progress')),
    );
    expect(stateBadge('In progress'), findsOneWidget);
    expect(availabilityBadge('In progress'), findsOneWidget);
    expect(
      (await repository.status(
        qdProfileRegular,
        qdAvailableQuest,
      ))!.recordedState,
      QuestProgressState.inProgress,
    );

    await tapVisible(tester, find.byKey(const Key('quest-status-revert')));
    expect(stateBadge('Not started'), findsOneWidget);
    expect(availabilityBadge('Available'), findsOneWidget);
    expect(
      (await repository.status(
        qdProfileRegular,
        qdAvailableQuest,
      ))!.recordedState,
      QuestProgressState.notStarted,
    );

    await tapVisible(tester, find.byKey(const Key('quest-status-mark-failed')));
    expect(stateBadge('Failed'), findsOneWidget);
    expect(availabilityBadge('Locked'), findsOneWidget);

    await tapVisible(
      tester,
      find.byKey(const Key('quest-status-mark-completed')),
    );
    expect(stateBadge('Completed'), findsOneWidget);
    expect(availabilityBadge('Completed'), findsOneWidget);
  });

  testWidgets('objective controls persist, change the hint and accept text', (
    tester,
  ) async {
    await pumpDetail(tester, questId: qdCountQuest);

    expect(fieldText(tester, qdObjectiveCountA), '0');
    expect(find.text('0 of 2 required objectives satisfied.'), findsOneWidget);

    for (var index = 0; index < 3; index++) {
      await tapVisible(
        tester,
        find.byKey(ValueKey('quest-objective-increment-$qdObjectiveCountA')),
      );
    }
    expect(fieldText(tester, qdObjectiveCountA), '3');
    expect(find.text('1 of 2 required objectives satisfied.'), findsOneWidget);
    expect(find.textContaining('requires a manual override'), findsOneWidget);

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
    expect(stateBadge('Not started'), findsOneWidget);
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

    expect(stateBadge('Completed'), findsOneWidget);
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
        matching: find.text('In progress'),
      ),
      findsOneWidget,
    );
    expect(find.text('$qdObjectiveRemoved: 2'), findsOneWidget);
  });

  testWidgets('profiles keep status and objective counts isolated', (
    tester,
  ) async {
    await pumpDetail(tester);
    expect(availabilityBadge('Locked'), findsOneWidget);

    await pumpDetail(tester, profileId: qdProfilePve);
    expect(availabilityBadge('Available'), findsOneWidget);

    await pumpDetail(tester, questId: qdCountQuest);
    expect(stateBadge('Not started'), findsOneWidget);
    expect(fieldText(tester, qdObjectiveCountA), '0');

    await pumpDetail(tester, questId: qdCountQuest, profileId: qdProfilePve);
    expect(stateBadge('In progress'), findsOneWidget);
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
}
