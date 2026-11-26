import 'dart:async';

import '../settings/app_settings.dart';
import '../settings/settings_repository.dart';

/// Reads the current wall-clock time.
///
/// Injected so tests and diagnostics can drive the scheduler with a fake clock.
typedef SyncClock = DateTime Function();

/// Creates the one-shot timer the scheduler uses for its next check.
///
/// The default is [Timer.new]. Tests inject a manual queue so no real time
/// passes and no socket is opened.
typedef SyncTimerFactory = Timer Function(
  Duration delay,
  void Function() callback,
);

/// Reports connectivity and the cost of the current connection.
///
/// The Flutter shell supplies an implementation backed by its connectivity
/// plugin. The scheduler never inspects a platform channel itself, which keeps
/// the data package pure Dart.
abstract interface class NetworkMonitor {
  /// Whether a request could currently reach the network.
  bool get isOnline;

  /// Whether the current connection is metered (mobile hotspot, cellular).
  ///
  /// Only meaningful while [isOnline] is true.
  bool get isMetered;

  /// Emits when [isOnline] or [isMetered] may have changed.
  ///
  /// The event carries no payload; the scheduler re-reads both getters.
  Stream<void> get changes;
}

/// Reports whether the application window is in the foreground.
abstract interface class VisibilityMonitor {
  /// Whether the app is visible and interactive.
  bool get isForeground;

  /// Emits when [isForeground] may have changed.
  Stream<void> get changes;
}

/// Performs one update check: manifest fetch, download and ingestion.
///
/// The scheduler owns *when* a check runs; the runner owns *what* it does. A
/// thrown error is treated as a failed check and starts the retry backoff.
abstract interface class SyncRunner {
  /// Runs a single check and completes when it succeeded or failed.
  Future<void> run();
}

/// Persists the time of the last successful check.
///
/// The Flutter shell can adapt `ManifestFetcher.lastCheckedAt` or the
/// `remoteManifest` cache to this interface. The scheduler only needs one
/// timestamp, independent of game mode.
abstract interface class SyncStateStore {
  /// The last successful check time, or `null` if none was recorded.
  Future<DateTime?> lastCheckedAt();

  /// Records a successful check that completed at [at].
  Future<void> recordCheckedAt(DateTime at);
}

/// The typed outcome of [SyncScheduler.checkNow].
enum SyncDecisionType {
  /// The runner completed and the check time was recorded.
  ran,

  /// Automatic checks are disabled by the user preference.
  skippedAutoUpdateDisabled,

  /// The app is not in the foreground, so no automatic check may run.
  skippedBackground,

  /// No network connection is available.
  skippedOffline,

  /// The connection is metered and the user forbids metered updates.
  skippedMetered,

  /// The previous check is newer than the configured interval.
  skippedNotDue,

  /// A failure backoff is still active.
  skippedBackoff,

  /// Another check is already running.
  skippedInFlight,

  /// The runner threw; a retry is scheduled at [SyncDecision.retryAt].
  failed,
}

/// What [SyncScheduler.checkNow] decided and when it will act next.
final class SyncDecision {
  const SyncDecision._({
    required this.type,
    required this.at,
    required this.manual,
    this.lastCheckedAt,
    this.nextRunAt,
    this.retryAt,
    this.error,
  });

  /// The typed outcome.
  final SyncDecisionType type;

  /// The time of the decision, from the injected clock.
  final DateTime at;

  /// Whether the user triggered this check explicitly.
  final bool manual;

  /// The last successful check time known before this decision.
  final DateTime? lastCheckedAt;

  /// When the scheduler intends to check again, or `null` when it is waiting
  /// for a network, visibility or settings change.
  final DateTime? nextRunAt;

  /// For [SyncDecisionType.failed], the earliest retry time.
  final DateTime? retryAt;

  /// For [SyncDecisionType.failed], the error the runner threw.
  final Object? error;

  /// Whether the runner actually executed.
  bool get ran => type == SyncDecisionType.ran;

  /// Whether the runner threw.
  bool get failed => type == SyncDecisionType.failed;

  /// Whether any preference, environment or schedule rule blocked the check.
  bool get skipped =>
      type != SyncDecisionType.ran && type != SyncDecisionType.failed;

  @override
  String toString() =>
      'SyncDecision(${type.name}, manual: $manual, at: $at, '
      'nextRunAt: $nextRunAt)';
}

/// Tunable intervals for the scheduler.
///
/// The defaults match the documented policy: check every six hours, matching
/// the six-hourly upstream pipeline, and retry a failed check after 15, 30 and
/// 60 minutes before falling back to the normal interval.
final class SyncPolicy {
  const SyncPolicy({
    this.checkInterval = const Duration(hours: 6),
    this.backoffBase = const Duration(minutes: 15),
    this.backoffMax = const Duration(hours: 2),
    this.maxBackoffAttempts = 3,
  }) : assert(maxBackoffAttempts > 0);

  /// Minimum time between two automatic checks.
  final Duration checkInterval;

  /// Delay after the first consecutive failure.
  final Duration backoffBase;

  /// Upper bound for a single backoff delay.
  final Duration backoffMax;

  /// Number of exponential retries before waiting [checkInterval] again.
  final int maxBackoffAttempts;
}

/// Decides when an update check may run and drives it through a [SyncRunner].
///
/// ## Policy
///
/// A manual check only requires connectivity; it bypasses every preference and
/// the schedule. An automatic check runs only when all of these hold:
///
/// 1. `autoUpdateEnabled` is true;
/// 2. the app is in the foreground;
/// 3. the network is online;
/// 4. the connection is unmetered or `allowMeteredUpdates` is true;
/// 5. no failure backoff is active;
/// 6. the last successful check is at least [SyncPolicy.checkInterval] old.
///
/// A successful check records the clock time and schedules the next one after
/// the interval. A failure increments the retry sequence (15 min, 30 min,
/// 60 min, then the normal interval) and schedules [SyncDecision.retryAt].
///
/// ## Scheduling
///
/// [start] arms a single one-shot timer for the next due check and subscribes
/// to [NetworkMonitor.changes] and [VisibilityMonitor.changes]. An event that
/// arrives while the app is foreground and online calls [checkNow], so a
/// reconnect or a return to the foreground is not delayed until the next timer
/// tick. When a rule blocks a due check, the scheduler waits for the relevant
/// change instead of spinning on a timer.
///
/// This class performs no I/O and owns no platform channel; every dependency is
/// injected so the policy is testable with a fake clock, fake timers and fake
/// monitors.
final class SyncScheduler {
  SyncScheduler({
    required this.settings,
    required this.stateStore,
    required this.runner,
    required this.network,
    required this.visibility,
    SyncClock? clock,
    SyncTimerFactory? timerFactory,
    this.policy = const SyncPolicy(),
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new;

  /// Typed application preferences, read before every decision.
  final SettingsRepository settings;

  /// Persists the last successful check time.
  final SyncStateStore stateStore;

  /// Performs the update check when the policy allows it.
  final SyncRunner runner;

  /// Connectivity and connection cost.
  final NetworkMonitor network;

  /// Whether the app window is in the foreground.
  final VisibilityMonitor visibility;

  final SyncClock _clock;
  final SyncTimerFactory _timerFactory;

  /// The intervals this scheduler follows.
  final SyncPolicy policy;

  Timer? _timer;
  StreamSubscription<void>? _networkSubscription;
  StreamSubscription<void>? _visibilitySubscription;

  bool _started = false;
  bool _disposed = false;
  bool _inFlight = false;

  int _consecutiveFailures = 0;
  DateTime? _backoffUntil;
  DateTime? _nextRunAt;
  DateTime? _lastCheckedAt;

  /// When the next automatic check is planned, or `null` while waiting for a
  /// network, visibility or settings change.
  DateTime? get nextRunAt => _nextRunAt;

  /// The last successful check time read from [SyncStateStore].
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// How many checks have failed since the last success.
  int get consecutiveFailures => _consecutiveFailures;

  /// Whether [start] has run and [dispose] has not.
  bool get isRunning => _started && !_disposed;

  /// Reads the last check time, subscribes to environment changes and arms the
  /// next due check.
  ///
  /// Calling [start] twice is a no-op. When the app is in the background or
  /// offline, no timer is armed: the matching change event triggers the check
  /// instead. When automatic updates are disabled, nothing is scheduled until
  /// the user asks for a manual check.
  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;

    _networkSubscription = network.changes.listen(
      (_) => _onEnvironmentChanged(),
      onError: _ignoreStreamError,
    );
    _visibilitySubscription = visibility.changes.listen(
      (_) => _onEnvironmentChanged(),
      onError: _ignoreStreamError,
    );

    _lastCheckedAt = await stateStore.lastCheckedAt();
    if (_disposed) {
      return;
    }

    final current = await settings.read();
    if (_disposed) {
      return;
    }

    if (!current.autoUpdateEnabled ||
        !visibility.isForeground ||
        !network.isOnline) {
      _arm(null);
      return;
    }

    _arm(_nextDueFrom(_lastCheckedAt, _clock()));
  }

  /// Cancels the pending timer and both change subscriptions.
  ///
  /// A runner that is already executing is not interrupted; its completion is
  /// ignored and schedules nothing.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _started = false;

    _timer?.cancel();
    _timer = null;
    _nextRunAt = null;

    final subscriptions = <StreamSubscription<void>>[
      ?_networkSubscription,
      ?_visibilitySubscription,
    ];
    _networkSubscription = null;
    _visibilitySubscription = null;

    await Future.wait([
      for (final subscription in subscriptions) subscription.cancel(),
    ]);
  }

  /// Runs the policy once and returns the typed decision.
  ///
  /// A manual check passes every preference and the schedule, but still
  /// requires a network connection. Automatic checks apply the full table.
  ///
  /// Throws [StateError] after [dispose]. Concurrent calls do not queue: the
  /// second returns [SyncDecisionType.skippedInFlight].
  Future<SyncDecision> checkNow({bool manual = false}) async {
    if (_disposed) {
      throw StateError('SyncScheduler has been disposed.');
    }

    if (_inFlight) {
      return SyncDecision._(
        type: SyncDecisionType.skippedInFlight,
        at: _clock(),
        manual: manual,
        lastCheckedAt: _lastCheckedAt,
        nextRunAt: _nextRunAt,
      );
    }

    _inFlight = true;
    try {
      return await _check(manual: manual);
    } finally {
      _inFlight = false;
    }
  }

  Future<SyncDecision> _check({required bool manual}) async {
    final at = _clock();
    final current = await settings.read();
    final lastCheckedAt = await stateStore.lastCheckedAt();
    _lastCheckedAt = lastCheckedAt;

    if (manual) {
      if (!network.isOnline) {
        return _settle(
          SyncDecision._(
            type: SyncDecisionType.skippedOffline,
            at: at,
            manual: true,
            lastCheckedAt: lastCheckedAt,
          ),
          automaticEnabled: current.autoUpdateEnabled,
        );
      }
    } else {
      final skip = _automaticSkip(at, current, lastCheckedAt);
      if (skip != null) {
        return _settle(skip, automaticEnabled: current.autoUpdateEnabled);
      }
    }

    try {
      await runner.run();
      await stateStore.recordCheckedAt(at);
    } on Object catch (error) {
      _consecutiveFailures++;
      final retryAt = at.add(_retryDelay(_consecutiveFailures));
      _backoffUntil = retryAt;
      return _settle(
        SyncDecision._(
          type: SyncDecisionType.failed,
          at: at,
          manual: manual,
          lastCheckedAt: lastCheckedAt,
          nextRunAt: retryAt,
          retryAt: retryAt,
          error: error,
        ),
        automaticEnabled: current.autoUpdateEnabled,
      );
    }

    _consecutiveFailures = 0;
    _backoffUntil = null;
    _lastCheckedAt = at;

    return _settle(
      SyncDecision._(
        type: SyncDecisionType.ran,
        at: at,
        manual: manual,
        lastCheckedAt: at,
        nextRunAt: at.add(policy.checkInterval),
      ),
      automaticEnabled: current.autoUpdateEnabled,
    );
  }

  /// Returns the skip decision an automatic check would produce, or `null`
  /// when it may run.
  SyncDecision? _automaticSkip(
    DateTime at,
    AppSettings current,
    DateTime? lastCheckedAt,
  ) {
    SyncDecision skip(SyncDecisionType type, {DateTime? nextRunAt}) =>
        SyncDecision._(
          type: type,
          at: at,
          manual: false,
          lastCheckedAt: lastCheckedAt,
          nextRunAt: nextRunAt,
        );

    if (!current.autoUpdateEnabled) {
      return skip(SyncDecisionType.skippedAutoUpdateDisabled);
    }
    if (!visibility.isForeground) {
      return skip(SyncDecisionType.skippedBackground);
    }
    if (!network.isOnline) {
      return skip(SyncDecisionType.skippedOffline);
    }
    if (network.isMetered && !current.allowMeteredUpdates) {
      return skip(SyncDecisionType.skippedMetered);
    }

    final backoffUntil = _backoffUntil;
    if (backoffUntil != null && at.isBefore(backoffUntil)) {
      return skip(SyncDecisionType.skippedBackoff, nextRunAt: backoffUntil);
    }

    final dueAt = _nextDueFrom(lastCheckedAt, at);
    if (at.isBefore(dueAt)) {
      return skip(SyncDecisionType.skippedNotDue, nextRunAt: dueAt);
    }

    return null;
  }

  DateTime _nextDueFrom(DateTime? lastCheckedAt, DateTime now) {
    if (lastCheckedAt == null) {
      return now;
    }
    final due = lastCheckedAt.add(policy.checkInterval);
    return due.isAfter(now) ? due : now;
  }

  Duration _retryDelay(int failures) {
    if (failures > policy.maxBackoffAttempts) {
      return policy.checkInterval;
    }
    final delay = policy.backoffBase * (1 << (failures - 1));
    return delay > policy.backoffMax ? policy.backoffMax : delay;
  }

  SyncDecision _settle(
    SyncDecision decision, {
    required bool automaticEnabled,
  }) {
    _arm(automaticEnabled ? decision.nextRunAt : null);
    return decision;
  }

  /// Points the timer at [at], cancelling any previous one.
  ///
  /// A `null` target means the scheduler is waiting for an external event. The
  /// timer is only created once [start] has run; [nextRunAt] is still reported
  /// when the scheduler is driven directly by [checkNow] in tests.
  void _arm(DateTime? at) {
    _timer?.cancel();
    _timer = null;

    if (at == null) {
      _nextRunAt = null;
      return;
    }

    final now = _clock();
    final target = at.isAfter(now) ? at : now;
    _nextRunAt = target;

    if (!_started || _disposed) {
      return;
    }

    _timer = _timerFactory(target.difference(now), _handleTimer);
  }

  void _handleTimer() {
    _timer = null;
    unawaited(_runAutomatic());
  }

  Future<void> _runAutomatic() async {
    try {
      await checkNow();
    } on Object catch (_) {
      // A check reports its own failures; nothing thrown here is actionable
      // and an unhandled async error would reach the zone handler.
    }
  }

  void _onEnvironmentChanged() {
    if (!_started || _disposed || _inFlight) {
      return;
    }
    if (!network.isOnline || !visibility.isForeground) {
      return;
    }
    unawaited(_runAutomatic());
  }

  void _ignoreStreamError(Object error, StackTrace stackTrace) {
    // Monitor streams are advisory; a failed event must not stop scheduling.
  }
}
