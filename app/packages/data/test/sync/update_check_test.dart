import 'dart:async';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;
  late FakeSyncService sync;
  late _RecordingTimers timers;
  final now = DateTime.utc(2026, 11, 27, 9);

  setUp(() async {
    db = await openMemoryDatabase();
    settings = SettingsRepository(db);
    sync = FakeSyncService();
    timers = _RecordingTimers();
  });

  tearDown(() => db.close());

  UpdateCheckController create({bool online = true}) {
    return UpdateCheckController(
      settings: settings,
      sync: sync,
      network: _OnlineNetworkMonitor(online: online),
      visibility: const _ForegroundVisibilityMonitor(),
      clock: () => now,
      timerFactory: timers.create,
    );
  }

  test('start reads settings and arms a timer without running sync', () async {
    await settings.write(
      const AppSettings(
        updateSchedule: UpdateSchedule.weekly,
        lastUpdateOutcome: UpdateOutcome.succeeded,
      ),
    );
    final controller = create();
    addTearDown(controller.dispose);

    await controller.start();

    expect(sync.runs, 0);
    expect(controller.status.schedule, UpdateSchedule.weekly);
    expect(controller.status.outcome, UpdateOutcome.succeeded);
    expect(timers.timers, hasLength(1));
  });

  test('a manual check succeeds and persists the outcome and time', () async {
    final controller = create();
    addTearDown(controller.dispose);
    await controller.start();

    final status = await controller.checkNow();

    expect(sync.runs, 1);
    expect(status.outcome, UpdateOutcome.succeeded);
    expect(status.lastCheckAt, now);
    expect(status.errorMessage, isNull);
    final stored = await settings.read();
    expect(stored.lastUpdateOutcome, UpdateOutcome.succeeded);
    expect(stored.lastUpdateCheckAt, now);
    expect(stored.lastUpdateAttemptAt, now);
  });

  test('a failed manual check persists a non-modal error', () async {
    sync.failure = StateError('manifest unreachable');
    final controller = create();
    addTearDown(controller.dispose);
    await controller.start();

    final status = await controller.checkNow();

    expect(sync.runs, 1);
    expect(status.outcome, UpdateOutcome.failed);
    expect(status.errorMessage, contains('manifest unreachable'));
    final stored = await settings.read();
    expect(stored.lastUpdateOutcome, UpdateOutcome.failed);
    expect(stored.lastUpdateError, contains('manifest unreachable'));
    expect(stored.lastUpdateCheckAt, isNull);
    expect(stored.lastUpdateAttemptAt, now);
  });

  test('an offline manual check is reported as skipped', () async {
    final controller = create(online: false);
    addTearDown(controller.dispose);
    await controller.start();

    final status = await controller.checkNow();

    expect(sync.runs, 0);
    expect(status.outcome, UpdateOutcome.skippedOffline);
    expect(
      (await settings.read()).lastUpdateOutcome,
      UpdateOutcome.skippedOffline,
    );
  });

  test('the schedule choice persists and toggles automatic checks', () async {
    final controller = create();
    addTearDown(controller.dispose);
    await controller.start();

    await controller.setSchedule(UpdateSchedule.off);
    expect(controller.status.schedule, UpdateSchedule.off);
    expect(controller.status.automaticEnabled, isFalse);
    var stored = await settings.read();
    expect(stored.updateSchedule, UpdateSchedule.off);
    expect(stored.autoUpdateEnabled, isFalse);
    expect(stored.effectiveUpdateSchedule, UpdateSchedule.off);

    await controller.setSchedule(UpdateSchedule.weekly);
    expect(controller.status.schedule, UpdateSchedule.weekly);
    stored = await settings.read();
    expect(stored.updateSchedule, UpdateSchedule.weekly);
    expect(stored.autoUpdateEnabled, isTrue);
    expect(stored.effectiveUpdateSchedule, UpdateSchedule.weekly);
  });

  test('a disabled legacy switch still reports the off schedule', () async {
    await settings.write(
      const AppSettings(
        autoUpdateEnabled: false,
        updateSchedule: UpdateSchedule.daily,
      ),
    );
    final controller = create();
    addTearDown(controller.dispose);

    await controller.start();

    expect(controller.status.schedule, UpdateSchedule.off);
    expect(controller.status.automaticEnabled, isFalse);
    expect(timers.timers, isEmpty);
  });

  test('status changes are broadcast to the strip', () async {
    final controller = create();
    addTearDown(controller.dispose);
    await controller.start();

    final seen = <UpdateCheckStatus>[];
    final subscription = controller.changes.listen(seen.add);
    addTearDown(subscription.cancel);

    await controller.checkNow();
    await Future<void>.delayed(Duration.zero);

    expect(seen, isNotEmpty);
    expect(seen.last.outcome, UpdateOutcome.succeeded);
  });
}

final class FakeSyncService implements SyncService {
  int runs = 0;
  Object? failure;

  @override
  Future<SyncPreparation> prepare(GameMode mode) async {
    throw UnimplementedError('prepare is not used by the update controller');
  }

  @override
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  }) async {
    runs++;
    onProgress?.call(
      SyncProgress(
        mode: mode,
        dataset: DatasetKind.items,
        phase: SyncPhase.downloading,
        datasetIndex: 0,
        datasetCount: 1,
        datasetBytes: 50,
        datasetTotalBytes: 100,
        overallBytes: 50,
        overallTotalBytes: 100,
        recordsProcessed: 0,
        recordsTotal: 1,
      ),
    );
    final error = failure;
    if (error != null) {
      throw error;
    }
    return SyncRunResult(
      mode: mode,
      applied: const [],
      skipped: const [],
      bytesDownloaded: 0,
      completedAt: DateTime.utc(2026, 11, 27),
    );
  }
}

final class _OnlineNetworkMonitor implements NetworkMonitor {
  const _OnlineNetworkMonitor({required this.online});

  final bool online;

  @override
  bool get isOnline => online;

  @override
  bool get isMetered => false;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

final class _ForegroundVisibilityMonitor implements VisibilityMonitor {
  const _ForegroundVisibilityMonitor();

  @override
  bool get isForeground => true;

  @override
  Stream<void> get changes => const Stream<void>.empty();
}

/// Records timer requests but never fires them, so tests stay deterministic.
final class _RecordingTimers {
  final List<_RecordingTimer> timers = [];

  Timer create(Duration delay, void Function() callback) {
    final timer = _RecordingTimer();
    timers.add(timer);
    return timer;
  }
}

final class _RecordingTimer implements Timer {
  @override
  void cancel() {}

  @override
  bool get isActive => true;

  @override
  int get tick => 0;
}
