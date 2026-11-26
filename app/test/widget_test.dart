import 'package:flutter_test/flutter_test.dart';
import 'package:tarkov_companion/main.dart';
import 'package:tarkov_companion/src/app_root.dart';
import 'package:tarkov_companion/src/app_session.dart';
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
    expect(find.byType(HomePlaceholder), findsNothing);
  });

  testWidgets('an applied dataset opens the placeholder home without a gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      TarkovCompanionApp(openSession: () async => _readySession(hasData: true)),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(HomePlaceholder), findsOneWidget);
    expect(find.byKey(FirstRunKeys.estimate), findsNothing);
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
    expect(find.byType(HomePlaceholder), findsNothing);

    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(find.byType(HomePlaceholder), findsOneWidget);
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

    expect(find.byType(HomePlaceholder), findsOneWidget);
    expect(attempts, 2);
  });
}
