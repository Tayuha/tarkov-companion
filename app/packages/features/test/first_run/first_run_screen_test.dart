import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

typedef RunHandler = Future<SyncRunResult> Function({
  required GameMode mode,
  required SyncPreparation? preparation,
  required SyncProgressListener? onProgress,
  required DownloadCancellationToken? cancellation,
});

final class FakeSyncService implements SyncService {
  FakeSyncService({required this.prepareHandler, this.runHandler});

  Future<SyncPreparation> Function(GameMode mode) prepareHandler;
  RunHandler? runHandler;

  int prepareCalls = 0;
  int runCalls = 0;

  @override
  Future<SyncPreparation> prepare(GameMode mode) {
    prepareCalls++;
    return prepareHandler(mode);
  }

  @override
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  }) {
    runCalls++;
    return runHandler!(
      mode: mode,
      preparation: preparation,
      onProgress: onProgress,
      cancellation: cancellation,
    );
  }
}

void main() {
  final checkedAt = DateTime.utc(2026, 11, 26, 12);
  final manifestUri = Uri.parse(
    'https://github.com/Tayuha/tarkov-companion/releases/download/'
    'data-regular-latest/manifest.json',
  );

  ManifestDataset entry(DatasetKind kind, int bytes, {int records = 2}) {
    return ManifestDataset(
      dataset: kind,
      path: '${kind.id}.jsonl.zst',
      schemaVersion: 1,
      sha256: '0' * 64,
      compressedBytes: bytes,
      uncompressedBytes: bytes * 2,
      records: records,
      source: const ManifestDatasetSource(
        url: null,
        lastModified: null,
        etag: null,
        fetchedAt: null,
      ),
    );
  }

  SyncPreparation preparation({
    List<ManifestDataset>? pending,
    List<DatasetKind> applied = const [],
  }) {
    final entries = pending ?? [entry(DatasetKind.items, 2048)];
    final manifest = BundleManifest(
      manifestVersion: 1,
      bundleSchemaVersion: 1,
      minAppSchemaVersion: 1,
      mode: GameMode.regular,
      generatedAt: checkedAt,
      source: const ManifestSource(baseUrl: null, capturedAt: null),
      datasets: entries,
      totals: ManifestTotals(
        datasets: entries.length,
        records: entries.fold(0, (sum, item) => sum + item.records),
        uncompressedBytes: entries.fold(
          0,
          (sum, item) => sum + item.uncompressedBytes,
        ),
        compressedBytes: entries.fold(
          0,
          (sum, item) => sum + item.compressedBytes,
        ),
      ),
      skipped: const [],
    );
    return SyncPreparation(
      mode: GameMode.regular,
      manifest: manifest,
      manifestUri: manifestUri,
      checkedAt: checkedAt,
      manifestNotModified: false,
      applied: applied,
      pending: entries,
    );
  }

  SyncRunResult runResult(List<DatasetKind> applied) {
    return SyncRunResult(
      mode: GameMode.regular,
      applied: applied,
      skipped: const [],
      bytesDownloaded: 0,
      completedAt: checkedAt,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    FakeSyncService sync, {
    ValueChanged<SyncRunResult>? onReady,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FirstRunScreen(sync: sync, onReady: onReady),
      ),
    );
    await tester.pump();
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    final finder = find.byKey(key);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  testWidgets('shows the loading state while the manifest is being read', (
    tester,
  ) async {
    final completer = Completer<SyncPreparation>();
    final sync = FakeSyncService(prepareHandler: (_) => completer.future);

    await pumpScreen(tester, sync);

    expect(find.byKey(FirstRunKeys.loading), findsOneWidget);
    expect(find.textContaining('Checking for game data'), findsOneWidget);
    expect(find.byKey(FirstRunKeys.estimate), findsNothing);

    completer.complete(preparation());
    await tester.pump();
    await tester.pump();

    expect(find.byKey(FirstRunKeys.estimate), findsOneWidget);
  });

  testWidgets('shows the size estimate before downloading and starts on tap', (
    tester,
  ) async {
    final sync = FakeSyncService(
      prepareHandler: (_) async => preparation(
        pending: [
          entry(DatasetKind.items, 2048),
          entry(DatasetKind.tasks, 2048),
        ],
      ),
      runHandler: ({
        required GameMode mode,
        required SyncPreparation? preparation,
        required SyncProgressListener? onProgress,
        required DownloadCancellationToken? cancellation,
      }) async => runResult([DatasetKind.items, DatasetKind.tasks]),
    );
    var ready = false;

    await pumpScreen(tester, sync, onReady: (_) => ready = true);

    expect(find.byKey(FirstRunKeys.estimate), findsOneWidget);
    expect(find.textContaining('4.0 KB'), findsWidgets);
    expect(find.textContaining('2 datasets'), findsWidgets);
    expect(find.byKey(FirstRunKeys.cancelButton), findsNothing);
    expect(find.byKey(FirstRunKeys.startButton), findsOneWidget);

    await tapKey(tester, FirstRunKeys.startButton);
    await tester.pumpAndSettle();

    expect(sync.runCalls, 1);
    expect(ready, isTrue);
    expect(find.byKey(FirstRunKeys.ready), findsOneWidget);
  });

  testWidgets(
    'reports per-dataset progress, overall bytes, and allows cancel',
    (tester) async {
      final runCompleter = Completer<SyncRunResult>();
      final sync = FakeSyncService(
        prepareHandler: (_) async => preparation(
          pending: [
            entry(DatasetKind.items, 2048),
            entry(DatasetKind.tasks, 2048),
          ],
        ),
        runHandler:
            ({
              required GameMode mode,
              required SyncPreparation? preparation,
              required SyncProgressListener? onProgress,
              required DownloadCancellationToken? cancellation,
            }) {
              onProgress!(
                SyncProgress(
                  mode: mode,
                  dataset: DatasetKind.items,
                  phase: SyncPhase.downloading,
                  datasetIndex: 0,
                  datasetCount: 2,
                  datasetBytes: 1024,
                  datasetTotalBytes: 2048,
                  overallBytes: 1024,
                  overallTotalBytes: 4096,
                  recordsProcessed: 0,
                  recordsTotal: 7,
                ),
              );
              return runCompleter.future;
            },
      );

      await pumpScreen(tester, sync);
      await tapKey(tester, FirstRunKeys.startButton);
      await tester.pump();

      expect(find.byKey(FirstRunKeys.downloading), findsOneWidget);
      expect(find.textContaining('1.0 KB of 4.0 KB'), findsOneWidget);
      expect(find.text('Downloading Items'), findsOneWidget);
      expect(find.text('Dataset 1 of 2'), findsOneWidget);
      expect(find.byKey(FirstRunKeys.cancelButton), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(FirstRunKeys.datasetProgress),
            )
            .value,
        closeTo(0.5, 0.001),
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byKey(FirstRunKeys.overallProgress),
            )
            .value,
        closeTo(0.25, 0.001),
      );

      runCompleter.complete(runResult([DatasetKind.items]));
      await tester.pumpAndSettle();
      expect(find.byKey(FirstRunKeys.ready), findsOneWidget);
    },
  );

  testWidgets('shows cancelling, then a cancelled error with Retry', (
    tester,
  ) async {
    final runCompleter = Completer<SyncRunResult>();
    final sync = FakeSyncService(
      prepareHandler: (_) async => preparation(),
      runHandler: ({
        required GameMode mode,
        required SyncPreparation? preparation,
        required SyncProgressListener? onProgress,
        required DownloadCancellationToken? cancellation,
      }) => runCompleter.future,
    );

    await pumpScreen(tester, sync);
    await tapKey(tester, FirstRunKeys.startButton);
    await tester.pump();
    expect(find.byKey(FirstRunKeys.downloading), findsOneWidget);

    await tapKey(tester, FirstRunKeys.cancelButton);
    await tester.pump();
    expect(find.byKey(FirstRunKeys.cancelling), findsOneWidget);
    expect(find.text('Cancelling…'), findsOneWidget);

    runCompleter.completeError(
      const SyncCancelled(mode: GameMode.regular, dataset: DatasetKind.items),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(FirstRunKeys.error), findsOneWidget);
    expect(find.text('Download cancelled'), findsOneWidget);
    expect(find.byKey(FirstRunKeys.retryButton), findsOneWidget);
  });

  testWidgets('an offline failure explains the problem and Retry re-prepares '
      'from the applied datasets', (tester) async {
    var attempt = 0;
    var firstRun = true;
    SyncPreparation? resumedWith;
    final sync = FakeSyncService(
      prepareHandler: (_) async {
        attempt++;
        if (attempt == 1) {
          return preparation(
            pending: [
              entry(DatasetKind.items, 2048),
              entry(DatasetKind.tasks, 2048),
            ],
          );
        }
        return preparation(
          pending: [entry(DatasetKind.tasks, 2048)],
          applied: const [DatasetKind.items],
        );
      },
      runHandler:
          ({
            required GameMode mode,
            required SyncPreparation? preparation,
            required SyncProgressListener? onProgress,
            required DownloadCancellationToken? cancellation,
          }) {
            if (firstRun) {
              firstRun = false;
              throw const SyncOfflineException(
                mode: GameMode.regular,
                dataset: DatasetKind.items,
                message:
                    'Could not reach the data server. Check your connection.',
              );
            }
            resumedWith = preparation;
            return Future.value(runResult([DatasetKind.tasks]));
          },
    );
    var ready = false;

    await pumpScreen(tester, sync, onReady: (_) => ready = true);
    await tapKey(tester, FirstRunKeys.startButton);
    await tester.pump();
    await tester.pump();

    expect(find.byKey(FirstRunKeys.error), findsOneWidget);
    expect(
      find.textContaining('Could not reach the data server'),
      findsOneWidget,
    );

    await tapKey(tester, FirstRunKeys.retryButton);
    await tester.pump();
    await tester.pump();

    expect(sync.prepareCalls, 2);
    expect(find.byKey(FirstRunKeys.estimate), findsOneWidget);
    expect(find.textContaining('2.0 KB'), findsWidgets);

    await tapKey(tester, FirstRunKeys.startButton);
    await tester.pumpAndSettle();

    expect(resumedWith, isNotNull);
    expect(resumedWith!.pending.map((entry) => entry.dataset), [
      DatasetKind.tasks,
    ]);
    expect(ready, isTrue);
  });

  testWidgets('goes straight to ready when every dataset is already applied', (
    tester,
  ) async {
    final sync = FakeSyncService(
      prepareHandler: (_) async => preparation(
        pending: const [],
        applied: const [DatasetKind.items, DatasetKind.tasks],
      ),
    );
    var ready = false;

    await pumpScreen(tester, sync, onReady: (_) => ready = true);
    await tester.pump();

    expect(find.byKey(FirstRunKeys.ready), findsOneWidget);
    expect(sync.runCalls, 0);
    expect(ready, isTrue);
  });
}
