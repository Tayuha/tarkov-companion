import 'dart:async';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';

void main() {
  group('SyncScheduler preference matrix (metered connection)', () {
    for (final autoUpdate in [true, false]) {
      for (final allowMetered in [true, false]) {
        for (final foreground in [true, false]) {
          for (final online in [true, false]) {
            test('autoUpdate=$autoUpdate allowMetered=$allowMetered '
                'foreground=$foreground online=$online', () async {
              final fixture = await _createFixture(
                autoUpdate: autoUpdate,
                allowMetered: allowMetered,
                foreground: foreground,
                online: online,
                metered: true,
              );

              final decision = await fixture.scheduler.checkNow();
              final expected = _expectedAutomatic(
                autoUpdate: autoUpdate,
                allowMetered: allowMetered,
                foreground: foreground,
                online: online,
                metered: true,
              );

              expect(decision.type, expected);
              expect(decision.manual, isFalse);
              expect(decision.at, fixture.time.now);
              expect(
                fixture.fakeRunner.calls,
                expected == SyncDecisionType.ran ? 1 : 0,
              );
              expect(
                fixture.stateStore.recorded,
                expected == SyncDecisionType.ran ? [fixture.time.now] : isEmpty,
              );
            });
          }
        }
      }
    }
  });

  group('SyncScheduler policy', () {
    test(
      'an unmetered connection runs despite a metered restriction',
      () async {
        final fixture = await _createFixture(
          allowMetered: false,
          metered: false,
        );

        final decision = await fixture.scheduler.checkNow();

        expect(decision.type, SyncDecisionType.ran);
        expect(fixture.fakeRunner.calls, 1);
      },
    );

    test(
      'a check before the interval is skipped and reports the due time',
      () async {
        final fixture = await _createFixture();
        fixture.stateStore.checkedAt = fixture.time.now.subtract(
          const Duration(hours: 5, minutes: 59),
        );

        final decision = await fixture.scheduler.checkNow();

        expect(decision.type, SyncDecisionType.skippedNotDue);
        expect(
          decision.nextRunAt,
          fixture.stateStore.checkedAt!.add(const Duration(hours: 6)),
        );
        expect(fixture.fakeRunner.calls, 0);
      },
    );

    test('a check at the interval boundary runs', () async {
      final fixture = await _createFixture();
      fixture.stateStore.checkedAt = fixture.time.now.subtract(
        const Duration(hours: 6),
      );

      final decision = await fixture.scheduler.checkNow();

      expect(decision.type, SyncDecisionType.ran);
      expect(fixture.fakeRunner.calls, 1);
    });

    test('a manual check bypasses every preference and the schedule', () async {
      final fixture = await _createFixture(
        autoUpdate: false,
        allowMetered: false,
        metered: true,
        foreground: false,
      );
      fixture.stateStore.checkedAt = fixture.time.now;

      final decision = await fixture.scheduler.checkNow(manual: true);

      expect(decision.type, SyncDecisionType.ran);
      expect(decision.manual, isTrue);
      expect(fixture.fakeRunner.calls, 1);
      expect(fixture.stateStore.recorded.single, fixture.time.now);
    });

    test('a manual check still requires a connection', () async {
      final fixture = await _createFixture(
        autoUpdate: false,
        foreground: false,
        online: false,
      );

      final decision = await fixture.scheduler.checkNow(manual: true);

      expect(decision.type, SyncDecisionType.skippedOffline);
      expect(fixture.fakeRunner.calls, 0);
    });

    test('a manual check bypasses an active failure backoff', () async {
      final fixture = await _createFixture();
      fixture.fakeRunner.failure = StateError('upstream outage');

      final automatic = await fixture.scheduler.checkNow();
      expect(automatic.type, SyncDecisionType.failed);

      fixture.fakeRunner.failure = null;
      final manual = await fixture.scheduler.checkNow(manual: true);

      expect(manual.type, SyncDecisionType.ran);
      expect(fixture.scheduler.consecutiveFailures, 0);
      expect(fixture.stateStore.recorded.single, fixture.time.now);
    });

    test(
      'failures back off 15, 30 and 60 minutes, then resume the interval',
      () async {
        final fixture = await _createFixture();
        fixture.fakeRunner.failure = StateError('upstream outage');

        final first = await fixture.scheduler.checkNow();
        expect(first.type, SyncDecisionType.failed);
        expect(
          first.retryAt,
          fixture.time.now.add(const Duration(minutes: 15)),
        );
        expect(fixture.scheduler.nextRunAt, first.retryAt);
        expect(fixture.scheduler.consecutiveFailures, 1);
        expect(fixture.stateStore.recorded, isEmpty);

        fixture.time.now = first.retryAt!;
        final second = await fixture.scheduler.checkNow();
        expect(second.type, SyncDecisionType.failed);
        expect(
          second.retryAt,
          fixture.time.now.add(const Duration(minutes: 30)),
        );

        fixture.time.now = second.retryAt!;
        final third = await fixture.scheduler.checkNow();
        expect(third.type, SyncDecisionType.failed);
        expect(
          third.retryAt,
          fixture.time.now.add(const Duration(minutes: 60)),
        );

        fixture.time.now = third.retryAt!;
        final fourth = await fixture.scheduler.checkNow();
        expect(fourth.type, SyncDecisionType.failed);
        expect(fourth.retryAt, fixture.time.now.add(const Duration(hours: 6)));
        expect(fixture.scheduler.consecutiveFailures, 4);
      },
    );

    test('a check inside the backoff window is skipped', () async {
      final fixture = await _createFixture();
      fixture.fakeRunner.failure = StateError('upstream outage');

      final failed = await fixture.scheduler.checkNow();
      fixture.time.now = failed.retryAt!.subtract(const Duration(minutes: 5));

      final decision = await fixture.scheduler.checkNow();

      expect(decision.type, SyncDecisionType.skippedBackoff);
      expect(decision.nextRunAt, failed.retryAt);
      expect(fixture.fakeRunner.calls, 1);
    });

    test('a success resets the failure sequence', () async {
      final fixture = await _createFixture();
      fixture.fakeRunner.failure = StateError('upstream outage');

      final failed = await fixture.scheduler.checkNow();
      expect(failed.type, SyncDecisionType.failed);

      fixture.time.now = failed.retryAt!;
      fixture.fakeRunner.failure = null;
      final recovered = await fixture.scheduler.checkNow();
      expect(recovered.type, SyncDecisionType.ran);
      expect(fixture.scheduler.consecutiveFailures, 0);

      fixture.time.now = fixture.time.now.add(const Duration(hours: 6));
      fixture.fakeRunner.failure = StateError('second outage');
      final nextFailure = await fixture.scheduler.checkNow();
      expect(nextFailure.type, SyncDecisionType.failed);
      expect(
        nextFailure.retryAt,
        fixture.time.now.add(const Duration(minutes: 15)),
      );
    });

    test('recordCheckedAt uses the injected clock', () async {
      final fixture = await _createFixture();

      final decision = await fixture.scheduler.checkNow();

      expect(decision.at, fixture.time.now);
      expect(fixture.stateStore.recorded.single, fixture.time.now);
      expect(fixture.stateStore.checkedAt, fixture.time.now);
    });

    test('a concurrent check is reported instead of starting twice', () async {
      final gate = Completer<void>();
      final runner = _BlockingRunner(gate);
      final fixture = await _createFixture(runner: runner);

      final first = fixture.scheduler.checkNow();
      await fixture.time.elapse(Duration.zero);

      final second = await fixture.scheduler.checkNow();
      expect(second.type, SyncDecisionType.skippedInFlight);
      expect(runner.calls, 1);

      gate.complete();
      expect((await first).type, SyncDecisionType.ran);
    });
  });

  group('SyncScheduler scheduling', () {
    test(
      'the scheduled check runs at the interval from the injected clock',
      () async {
        final fixture = await _createFixture();
        fixture.stateStore.checkedAt = fixture.time.now;

        await fixture.scheduler.start();
        expect(fixture.fakeRunner.calls, 0);

        await fixture.time.elapse(const Duration(hours: 6));

        expect(fixture.fakeRunner.calls, 1);
        expect(
          fixture.stateStore.recorded.single,
          DateTime.utc(2026, 1, 1, 18),
        );
        expect(fixture.scheduler.nextRunAt, DateTime.utc(2026, 1, 2));
      },
    );

    test(
      'a network change triggers a due check without a timer tick',
      () async {
        final fixture = await _createFixture(online: false);

        await fixture.scheduler.start();
        expect(fixture.scheduler.nextRunAt, isNull);
        await fixture.time.elapse(Duration.zero);
        expect(fixture.fakeRunner.calls, 0);

        fixture.network.isOnline = true;
        fixture.network.emit();
        await fixture.time.elapse(Duration.zero);

        expect(fixture.fakeRunner.calls, 1);
        expect(fixture.stateStore.recorded.single, fixture.time.now);
      },
    );

    test('returning to the foreground triggers a due check', () async {
      final fixture = await _createFixture(foreground: false);

      await fixture.scheduler.start();
      expect(fixture.scheduler.nextRunAt, isNull);

      fixture.visibility.isForeground = true;
      fixture.visibility.emit();
      await fixture.time.elapse(Duration.zero);

      expect(fixture.fakeRunner.calls, 1);
    });

    test(
      'an environment change inside the interval does not check early',
      () async {
        final fixture = await _createFixture();
        fixture.stateStore.checkedAt = fixture.time.now;

        await fixture.scheduler.start();
        fixture.network.emit();
        await fixture.time.elapse(Duration.zero);

        expect(fixture.fakeRunner.calls, 0);
        expect(
          fixture.scheduler.nextRunAt,
          fixture.time.now.add(const Duration(hours: 6)),
        );
      },
    );

    test('dispose cancels a pending check and ignores later events', () async {
      final fixture = await _createFixture();

      await fixture.scheduler.start();
      await fixture.scheduler.dispose();

      fixture.network.emit();
      fixture.visibility.emit();
      await fixture.time.elapse(const Duration(hours: 24));

      expect(fixture.fakeRunner.calls, 0);
      expect(fixture.scheduler.nextRunAt, isNull);
    });
  });
}

SyncDecisionType _expectedAutomatic({
  required bool autoUpdate,
  required bool allowMetered,
  required bool foreground,
  required bool online,
  required bool metered,
}) {
  if (!autoUpdate) {
    return SyncDecisionType.skippedAutoUpdateDisabled;
  }
  if (!foreground) {
    return SyncDecisionType.skippedBackground;
  }
  if (!online) {
    return SyncDecisionType.skippedOffline;
  }
  if (metered && !allowMetered) {
    return SyncDecisionType.skippedMetered;
  }
  return SyncDecisionType.ran;
}

Future<_Fixture> _createFixture({
  bool autoUpdate = true,
  bool allowMetered = false,
  bool foreground = true,
  bool online = true,
  bool metered = false,
  SyncRunner? runner,
}) async {
  final db = await openMemoryDatabase();
  final settings = SettingsRepository(db);
  await settings.write(
    AppSettings(
      autoUpdateEnabled: autoUpdate,
      allowMeteredUpdates: allowMetered,
    ),
  );

  final fixture = _Fixture(
    db: db,
    settings: settings,
    time: FakeTime(DateTime.utc(2026, 1, 1, 12)),
    network: FakeNetworkMonitor(isOnline: online, isMetered: metered),
    visibility: FakeVisibilityMonitor(isForeground: foreground),
    runner: runner ?? FakeSyncRunner(),
  );
  addTearDown(fixture.dispose);
  return fixture;
}

final class _Fixture {
  _Fixture({
    required this.db,
    required this.settings,
    required this.time,
    required this.network,
    required this.visibility,
    required this.runner,
  }) : stateStore = FakeSyncStateStore() {
    scheduler = SyncScheduler(
      settings: settings,
      stateStore: stateStore,
      runner: runner,
      network: network,
      visibility: visibility,
      clock: time.clock,
      timerFactory: time.timers,
    );
  }

  final AppDatabase db;
  final SettingsRepository settings;
  final FakeTime time;
  final FakeNetworkMonitor network;
  final FakeVisibilityMonitor visibility;
  final SyncRunner runner;
  final FakeSyncStateStore stateStore;
  late final SyncScheduler scheduler;

  FakeSyncRunner get fakeRunner => runner as FakeSyncRunner;

  Future<void> dispose() async {
    await scheduler.dispose();
    await network.close();
    await visibility.close();
    await db.close();
  }
}

final class FakeNetworkMonitor implements NetworkMonitor {
  FakeNetworkMonitor({required this.isOnline, required this.isMetered});

  @override
  bool isOnline;

  @override
  bool isMetered;

  final _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _controller.stream;

  void emit() => _controller.add(null);

  Future<void> close() => _controller.close();
}

final class FakeVisibilityMonitor implements VisibilityMonitor {
  FakeVisibilityMonitor({required this.isForeground});

  @override
  bool isForeground;

  final _controller = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _controller.stream;

  void emit() => _controller.add(null);

  Future<void> close() => _controller.close();
}

final class FakeSyncRunner implements SyncRunner {
  int calls = 0;
  Object? failure;

  @override
  Future<void> run() async {
    calls++;
    final error = failure;
    if (error != null) {
      throw error;
    }
  }
}

final class _BlockingRunner implements SyncRunner {
  _BlockingRunner(this._gate);

  final Completer<void> _gate;
  int calls = 0;

  @override
  Future<void> run() {
    calls++;
    return _gate.future;
  }
}

final class FakeSyncStateStore implements SyncStateStore {
  FakeSyncStateStore({this.checkedAt});

  DateTime? checkedAt;
  final List<DateTime> recorded = [];

  @override
  Future<DateTime?> lastCheckedAt() async => checkedAt;

  @override
  Future<void> recordCheckedAt(DateTime at) async {
    checkedAt = at;
    recorded.add(at);
  }
}

/// A wall clock and timer queue advanced by hand.
///
/// Nothing fires on its own: the test decides exactly how much time passes.
final class FakeTime {
  FakeTime(this.now);

  DateTime now;
  final List<_FakeTimer> _timers = [];

  SyncClock get clock =>
      () => now;

  SyncTimerFactory get timers => _create;

  Timer _create(Duration delay, void Function() callback) {
    final timer = _FakeTimer(now.add(delay), callback);
    _timers.add(timer);
    return timer;
  }

  /// Advances the clock to [duration] from now, firing every due timer in
  /// chronological order and letting the scheduler's async work settle.
  Future<void> elapse(Duration duration) async {
    final target = now.add(duration);

    while (true) {
      final active = _timers.where((timer) => timer.isActive).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      if (active.isEmpty || active.first.dueAt.isAfter(target)) {
        break;
      }

      final next = active.first;
      if (next.dueAt.isAfter(now)) {
        now = next.dueAt;
      }
      next.fire();
      await _settle();
    }

    if (target.isAfter(now)) {
      now = target;
    }
    await _settle();
  }

  Future<void> _settle() async {
    for (var i = 0; i < 8; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this.dueAt, this._callback);

  final DateTime dueAt;
  final void Function() _callback;
  bool _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
  }

  void fire() {
    if (!_active) {
      return;
    }
    _active = false;
    _callback();
  }
}
