import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion/main.dart';
import 'package:tarkov_companion/src/app_session.dart';
import 'package:tarkov_companion/src/home_shell.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

final class _FakeSync implements SyncService {
  _FakeSync(this.preparation);

  final SyncPreparation preparation;

  @override
  Future<SyncPreparation> prepare(GameMode mode) async => preparation;

  @override
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  }) async {
    return SyncRunResult(
      mode: mode,
      applied: const [],
      skipped: const [],
      bytesDownloaded: 0,
      completedAt: DateTime.utc(2026, 11, 26),
    );
  }
}

SyncPreparation _preparation({required bool complete}) {
  final entry = ManifestDataset(
    dataset: DatasetKind.items,
    path: 'items.jsonl.zst',
    schemaVersion: 1,
    sha256: '0' * 64,
    compressedBytes: 2048,
    uncompressedBytes: 4096,
    records: 7,
    source: const ManifestDatasetSource(
      url: null,
      lastModified: null,
      etag: null,
      fetchedAt: null,
    ),
  );
  final manifest = BundleManifest(
    manifestVersion: 1,
    bundleSchemaVersion: 1,
    minAppSchemaVersion: 1,
    mode: GameMode.regular,
    generatedAt: DateTime.utc(2026, 11, 26),
    source: const ManifestSource(baseUrl: null, capturedAt: null),
    datasets: [entry],
    totals: const ManifestTotals(
      datasets: 1,
      records: 7,
      uncompressedBytes: 4096,
      compressedBytes: 2048,
    ),
    skipped: const [],
  );
  return SyncPreparation(
    mode: GameMode.regular,
    manifest: manifest,
    manifestUri: Uri.parse(
      'https://github.com/Tayuha/tarkov-companion/releases/download/'
      'data-regular-latest/manifest.json',
    ),
    checkedAt: DateTime.utc(2026, 11, 26),
    manifestNotModified: false,
    applied: complete ? const [DatasetKind.items] : const [],
    pending: complete ? const [] : [entry],
  );
}

AppSession _readySession({required bool hasData}) {
  return AppSessionReady(
    sync: _FakeSync(_preparation(complete: hasData)),
    hasAppliedDatasets: hasData,
    close: () async {},
  );
}

/// A ready session over a memory database with one catalog row.
Future<AppSession> _sessionWithItem() async {
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
  return AppSessionReady(
    sync: _FakeSync(_preparation(complete: true)),
    hasAppliedDatasets: true,
    catalog: CatalogRepository(database),
    quests: QuestRepository(database),
    activeProfileId: 'profile-regular',
    close: database.close,
  );
}

void main() {
  testWidgets('no applied dataset shows the first-run gate, not a catalog', (
    tester,
  ) async {
    await tester.pumpWidget(
      TarkovCompanionApp(
        openSession: () async => _readySession(hasData: false),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(FirstRunKeys.estimate), findsOneWidget);
    expect(
      find.textContaining('Download game data to get started'),
      findsOneWidget,
    );
    expect(find.byType(HomeShell), findsNothing);
  });

  testWidgets('an applied dataset opens the navigation shell without a gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      TarkovCompanionApp(openSession: () async => _readySession(hasData: true)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byKey(FirstRunKeys.estimate), findsNothing);
    expect(find.byKey(const Key('home-navigation-rail')), findsOneWidget);
    expect(find.byKey(const Key('home-rail-items-label')), findsOneWidget);
    expect(find.byKey(const Key('home-rail-quests-label')), findsOneWidget);
  });

  testWidgets('the app installs the phosphor design system', (tester) async {
    await tester.pumpWidget(
      TarkovCompanionApp(openSession: () async => _readySession(hasData: true)),
    );
    await tester.pump();
    await tester.pump();

    final theme = Theme.of(tester.element(find.byType(HomeShell)));
    final tokens = theme.extension<AppTokens>();

    expect(tokens, isNotNull);
    expect(theme.brightness, Brightness.dark);
    expect(theme.scaffoldBackgroundColor, tokens!.background);
    expect(theme.colorScheme.primary, tokens.accent);
    expect(theme.colorScheme.surface, tokens.surface);
    expect(theme.textTheme.bodyMedium?.fontFamily, tokens.uiFontFamily);
  });

  testWidgets('the first frame is a local loading shell while the database '
      'opens', (tester) async {
    await tester.pumpWidget(
      TarkovCompanionApp(
        openSession: () => Future<AppSession>.delayed(
          const Duration(milliseconds: 50),
          () => _readySession(hasData: true),
        ),
      ),
    );

    expect(find.text('Opening Tarkov Companion…'), findsOneWidget);
    expect(find.byType(HomeShell), findsNothing);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.byType(HomeShell), findsOneWidget);
  });

  testWidgets('a session failure offers a retry', (tester) async {
    var attempts = 0;
    await tester.pumpWidget(
      TarkovCompanionApp(
        openSession: () async {
          attempts++;
          if (attempts == 1) {
            throw StateError('database unavailable');
          }
          return _readySession(hasData: true);
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('The app could not start'), findsOneWidget);
    expect(find.textContaining('database unavailable'), findsOneWidget);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomeShell), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets(
    'Escape returns from a pushed item detail through the navigator',
    (tester) async {
      await tester.pumpWidget(
        TarkovCompanionApp(openSession: _sessionWithItem),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('catalog-item-item-rifle')));
      await tester.pumpAndSettle();
      expect(find.byType(ItemDetailScreen), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ItemDetailScreen), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
    },
  );
}
