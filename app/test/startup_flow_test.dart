import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion/main.dart';
import 'package:tarkov_companion/src/app_session.dart';
import 'package:tarkov_companion/src/home_shell.dart';
import 'package:tarkov_companion/src/sync_monitors.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

void main() {
  testWidgets('cached data renders before a delayed manifest check completes', (
    tester,
  ) async {
    final database = AppDatabase.memory();
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

    final manifestGate = Completer<void>();
    final sync = _DelayedSync(manifestGate.future);
    final controller = UpdateCheckController(
      settings: SettingsRepository(database),
      sync: sync,
      network: const AlwaysOnlineNetworkMonitor(),
      visibility: const AlwaysForegroundVisibilityMonitor(),
      clock: () => DateTime.utc(2026, 11, 27, 9),
    );

    await tester.pumpWidget(
      TarkovCompanionApp(
        openSession: () async => AppSessionReady(
          sync: sync,
          hasAppliedDatasets: true,
          catalog: CatalogRepository(database),
          quests: QuestRepository(database),
          activeProfileId: 'profile-regular',
          updates: controller,
          close: () async {
            await controller.dispose();
            await database.close();
          },
        ),
      ),
    );

    // The session future resolves, the shell is built from the local rows,
    // and only then does the background controller start.
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);
    expect(find.text('Opening Tarkov Companion…'), findsNothing);
    expect(manifestGate.isCompleted, isFalse);

    // Let the scheduler's due timer fire. The manifest request is still
    // delayed; the shell must stay on screen.
    await tester.pump(Duration.zero);
    await tester.pump();
    expect(manifestGate.isCompleted, isFalse);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);

    manifestGate.complete();
    await tester.pumpAndSettle();

    expect(find.byType(HomeShell), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

/// A sync service that stalls exactly where the manifest request would.
final class _DelayedSync implements SyncService {
  _DelayedSync(this._manifestGate);

  final Future<void> _manifestGate;
  int runCalls = 0;

  @override
  Future<SyncPreparation> prepare(GameMode mode) async {
    await _manifestGate;
    throw UnimplementedError('the first-run path is not used here');
  }

  @override
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  }) async {
    runCalls++;
    await _manifestGate;
    return SyncRunResult(
      mode: mode,
      applied: const [],
      skipped: const [],
      bytesDownloaded: 0,
      completedAt: DateTime.utc(2026, 11, 27, 9),
    );
  }
}
