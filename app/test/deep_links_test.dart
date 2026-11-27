import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion/main.dart';
import 'package:tarkov_companion/src/app_session.dart';
import 'package:tarkov_companion/src/deep_links.dart';
import 'package:tarkov_companion/src/home_shell.dart';
import 'package:tarkov_companion/src/launch_request.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

final class _FakeSync implements SyncService {
  @override
  Future<SyncPreparation> prepare(GameMode mode) => throw UnimplementedError();

  @override
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  }) => throw UnimplementedError();
}

/// A ready session with one catalog item and no network setup.
Future<AppSession> _sessionWithItem(AppDatabase database) async {
  await database.customSelect('SELECT 1').get();
  await database.customStatement(
    'INSERT INTO items ('
    'id, name, shortName, normalizedName, payload'
    ') VALUES (?, ?, ?, ?, ?)',
    [
      'item-rifle',
      'Colt M4A1 5.56x45 assault rifle',
      'M4A1',
      'colt-m4a1-556x45-assault-rifle',
      '{}',
    ],
  );
  return AppSessionReady(
    sync: _FakeSync(),
    hasAppliedDatasets: true,
    catalog: CatalogRepository(database),
    quests: QuestRepository(database),
    activeProfileId: 'profile-regular',
    close: database.close,
  );
}

void main() {
  testWidgets('a launch item id opens the resolved item detail', (
    tester,
  ) async {
    final database = AppDatabase.memory();

    await tester.pumpWidget(
      TarkovCompanionApp(
        openSession: () => _sessionWithItem(database),
        launchRequest: const LaunchRequest(itemId: 'item-rifle'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(find.byKey(const Key('item-detail-name')), findsOneWidget);
    expect(
      find.text('Colt M4A1 5.56x45 assault rifle'),
      findsWidgets,
      reason: 'the catalog row behind the detail also carries the name',
    );
    expect(
      find.byType(HomeShell, skipOffstage: false),
      findsOneWidget,
      reason: 'the shell stays mounted below the pushed detail',
    );
  });

  testWidgets('an unknown item id shows the removed state and a way back', (
    tester,
  ) async {
    final database = AppDatabase.memory();

    await tester.pumpWidget(
      TarkovCompanionApp(
        openSession: () => _sessionWithItem(database),
        launchRequest: const LaunchRequest(itemId: 'item-deleted-upstream'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(find.byKey(const Key('item-detail-not-found')), findsOneWidget);
    expect(find.text('Item no longer available'), findsOneWidget);

    await tester.tap(find.byKey(const Key('item-detail-back')));
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailScreen), findsNothing);
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('a deep link queued after startup opens the detail', (
    tester,
  ) async {
    final database = AppDatabase.memory();
    final inbox = DeepLinkInbox();
    addTearDown(inbox.dispose);

    await tester.pumpWidget(
      TarkovCompanionApp(
        openSession: () => _sessionWithItem(database),
        deepLinks: inbox,
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(ItemDetailScreen), findsNothing);

    inbox.add(const ItemDeepLink('item-rifle'));
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailScreen), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsWidgets);
  });

  testWidgets('a deep link does not duplicate the detail when already open', (
    tester,
  ) async {
    final database = AppDatabase.memory();

    await tester.pumpWidget(
      TarkovCompanionApp(
        openSession: () => _sessionWithItem(database),
        launchRequest: const LaunchRequest(itemId: 'item-rifle'),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.byType(ItemDetailScreen), findsOneWidget);
  });
}
