import 'dart:async';

import '../bundle/game_mode.dart';
import '../settings/app_settings.dart';
import '../settings/settings_repository.dart';
import 'scheduler.dart';
import 'sync_coordinator.dart';

/// Whether an update check is currently running.
enum UpdateCheckPhase { idle, checking }

/// The user-visible state of the background update check.
///
/// This is a pure value object: the strip in the shell listens to
/// [UpdateCheckControl.changes] and renders it without starting any work.
final class UpdateCheckStatus {
  const UpdateCheckStatus({
    this.schedule = AppSettings.defaultUpdateSchedule,
    this.phase = UpdateCheckPhase.idle,
    this.lastCheckAt,
    this.lastSuccessAt,
    this.outcome,
    this.errorMessage,
    this.progress,
    this.nextCheckAt,
  });

  /// The schedule the user selected.
  final UpdateSchedule schedule;

  /// Whether a check is running right now.
  final UpdateCheckPhase phase;

  /// When the last check was attempted, including failed and skipped attempts.
  final DateTime? lastCheckAt;

  /// When the last check completed successfully.
  final DateTime? lastSuccessAt;

  /// The outcome of the last attempt, or `null` before the first attempt.
  final UpdateOutcome? outcome;

  /// A short, user-safe reason for the last failed attempt.
  final String? errorMessage;

  /// Download/ingest progress in `0.0..1.0` while [phase] is checking.
  final double? progress;

  /// The next automatic check time, or `null` when automatic checks are off or
  /// waiting for a network or foreground change.
  final DateTime? nextCheckAt;

  /// Whether a check is running.
  bool get isChecking => phase == UpdateCheckPhase.checking;

  /// Whether automatic checks are enabled.
  bool get automaticEnabled => schedule.isEnabled;

  /// A copy with the supplied fields replaced.
  ///
  /// Nullable fields use a sentinel so [progress], [errorMessage] and the
  /// timestamps can be cleared explicitly.
  UpdateCheckStatus copyWith({
    UpdateSchedule? schedule,
    UpdateCheckPhase? phase,
    Object? lastCheckAt = _unset,
    Object? lastSuccessAt = _unset,
    Object? outcome = _unset,
    Object? errorMessage = _unset,
    Object? progress = _unset,
    Object? nextCheckAt = _unset,
  }) {
    return UpdateCheckStatus(
      schedule: schedule ?? this.schedule,
      phase: phase ?? this.phase,
      lastCheckAt: identical(lastCheckAt, _unset)
          ? this.lastCheckAt
          : lastCheckAt as DateTime?,
      lastSuccessAt: identical(lastSuccessAt, _unset)
          ? this.lastSuccessAt
          : lastSuccessAt as DateTime?,
      outcome: identical(outcome, _unset)
          ? this.outcome
          : outcome as UpdateOutcome?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
      progress: identical(progress, _unset)
          ? this.progress
          : progress as double?,
      nextCheckAt: identical(nextCheckAt, _unset)
          ? this.nextCheckAt
          : nextCheckAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UpdateCheckStatus &&
      other.schedule == schedule &&
      other.phase == phase &&
      other.lastCheckAt == lastCheckAt &&
      other.lastSuccessAt == lastSuccessAt &&
      other.outcome == outcome &&
      other.errorMessage == errorMessage &&
      other.progress == progress &&
      other.nextCheckAt == nextCheckAt;

  @override
  int get hashCode => Object.hash(
    schedule,
    phase,
    lastCheckAt,
    lastSuccessAt,
    outcome,
    errorMessage,
    progress,
    nextCheckAt,
  );

  @override
  String toString() =>
      'UpdateCheckStatus(schedule: $schedule, phase: $phase, '
      'outcome: $outcome, lastCheckAt: $lastCheckAt)';
}

/// The controls the shell and its status strip use.
///
/// The production implementation is [UpdateCheckController]. Widget tests use
/// a small fake so they can render every outcome without a database, a timer or
/// a network.
abstract interface class UpdateCheckControl {
  /// The current status; always available after construction.
  UpdateCheckStatus get status;

  /// Emits whenever [status] changes.
  Stream<UpdateCheckStatus> get changes;

  /// Reads persisted preferences and arms the background schedule.
  ///
  /// This never awaits a network request. The shell calls it after the first
  /// local-data frame, so startup stays non-blocking.
  Future<void> start();

  /// Runs one check now, bypassing the preference table.
  Future<UpdateCheckStatus> checkNow();

  /// Persists a new schedule and re-arms the background timer.
  Future<void> setSchedule(UpdateSchedule schedule);

  /// Stops the timer and releases the status stream.
  Future<void> dispose();
}

/// Owns the background update schedule and the persisted last outcome.
///
/// ## Startup
///
/// [start] only reads settings and arms [SyncScheduler]. It never performs a
/// network request on the calling path: a due check runs through the
/// scheduler's timer, so the shell's first frame is already built from the
/// local database.
///
/// ## Outcomes
///
/// Every completed or failed attempt is written to the settings table through
/// [SettingsRepository.recordUpdateOutcome]. The status strip therefore shows
/// the last result after a restart without any extra cache.
///
/// ## Preferences
///
/// [setSchedule] writes both the new schedule and the legacy
/// `autoUpdateEnabled` switch, then recreates the scheduler with the matching
/// interval. A schedule change made while a check is running is honoured after
/// that check settles.
final class UpdateCheckController implements UpdateCheckControl {
  UpdateCheckController({
    required this.settings,
    required this.sync,
    required this.network,
    required this.visibility,
    this.mode = GameMode.regular,
    SyncClock? clock,
    SyncTimerFactory? timerFactory,
  }) : _clock = clock ?? DateTime.now,
       _timerFactory = timerFactory ?? Timer.new {
    _runner = _TrackingRunner(this);
  }

  /// Persisted preferences and last outcome.
  final SettingsRepository settings;

  /// The sync stack used by one check.
  final SyncService sync;

  /// Connectivity reported to the scheduler.
  final NetworkMonitor network;

  /// Foreground state reported to the scheduler.
  final VisibilityMonitor visibility;

  /// Game mode whose datasets are checked.
  final GameMode mode;

  final SyncClock _clock;
  final SyncTimerFactory _timerFactory;

  late final _TrackingRunner _runner;
  final StreamController<UpdateCheckStatus> _changes =
      StreamController<UpdateCheckStatus>.broadcast();

  UpdateCheckStatus _status = const UpdateCheckStatus();
  SyncScheduler? _scheduler;
  bool _started = false;
  bool _disposed = false;

  @override
  UpdateCheckStatus get status => _status;

  @override
  Stream<UpdateCheckStatus> get changes => _changes.stream;

  @override
  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;

    final current = await settings.read();
    if (_disposed) {
      return;
    }
    _status = UpdateCheckStatus(
      schedule: current.effectiveUpdateSchedule,
      lastCheckAt: current.lastUpdateAttemptAt ?? current.lastUpdateCheckAt,
      lastSuccessAt: current.lastUpdateCheckAt,
      outcome: current.lastUpdateOutcome,
      errorMessage: current.lastUpdateError,
    );
    _emit();

    await _armScheduler();
  }

  @override
  Future<UpdateCheckStatus> checkNow() async {
    if (_disposed) {
      throw StateError('UpdateCheckController has been disposed.');
    }
    if (!_started) {
      await start();
    }

    final scheduler = _scheduler;
    if (scheduler == null) {
      return _status;
    }

    _emit(
      _status.copyWith(
        phase: UpdateCheckPhase.checking,
        progress: null,
        errorMessage: null,
      ),
    );

    final decision = await scheduler.checkNow(manual: true);
    if (_disposed) {
      return _status;
    }

    switch (decision.type) {
      case SyncDecisionType.ran:
      case SyncDecisionType.failed:
        // The tracking runner already persisted the outcome and emitted the
        // terminal status while the check was running.
        break;
      case SyncDecisionType.skippedOffline:
        await _recordSkipped(
          UpdateOutcome.skippedOffline,
          'No network connection is available.',
        );
      case SyncDecisionType.skippedInFlight:
        // Keep the checking state; the running check owns the next emit.
        break;
      case SyncDecisionType.skippedAutoUpdateDisabled:
      case SyncDecisionType.skippedBackground:
      case SyncDecisionType.skippedMetered:
      case SyncDecisionType.skippedNotDue:
      case SyncDecisionType.skippedBackoff:
        // Manual checks bypass these rules, so they only occur here if the
        // scheduler is driven by an unusual custom policy.
        await _recordSkipped(UpdateOutcome.skipped, null);
    }

    if (_status.isChecking &&
        decision.type != SyncDecisionType.skippedInFlight) {
      _emit(_status.copyWith(phase: UpdateCheckPhase.idle));
    }
    _emit(_status.copyWith(nextCheckAt: scheduler.nextRunAt));
    return _status;
  }

  @override
  Future<void> setSchedule(UpdateSchedule schedule) async {
    if (_disposed) {
      return;
    }
    await settings.setUpdateSchedule(schedule);
    if (_disposed) {
      return;
    }
    _status = _status.copyWith(
      schedule: schedule,
      nextCheckAt: schedule.isEnabled ? _status.nextCheckAt : null,
    );
    _emit();

    if (_started) {
      await _armScheduler();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final scheduler = _scheduler;
    _scheduler = null;
    await scheduler?.dispose();
    await _changes.close();
  }

  Future<void> _armScheduler() async {
    final previous = _scheduler;
    _scheduler = null;
    await previous?.dispose();
    if (_disposed) {
      return;
    }

    final interval = _status.schedule.interval ?? const Duration(days: 1);
    final scheduler = SyncScheduler(
      settings: settings,
      stateStore: _SettingsSyncStateStore(settings),
      runner: _runner,
      network: network,
      visibility: visibility,
      clock: _clock,
      timerFactory: _timerFactory,
      policy: SyncPolicy(checkInterval: interval),
    );
    _scheduler = scheduler;

    await scheduler.start();
    if (_disposed) {
      await scheduler.dispose();
      return;
    }
    _emit(_status.copyWith(nextCheckAt: scheduler.nextRunAt));
  }

  Future<void> _runSync() async {
    if (_disposed) {
      return;
    }
    _emit(
      _status.copyWith(
        phase: UpdateCheckPhase.checking,
        progress: null,
        errorMessage: null,
      ),
    );

    try {
      await sync.run(
        mode,
        onProgress: (progress) {
          if (_disposed) {
            return;
          }
          _emit(_status.copyWith(progress: progress.fraction));
        },
      );
    } on Object catch (error) {
      final at = _clock();
      await settings.recordUpdateOutcome(
        outcome: UpdateOutcome.failed,
        at: at,
        error: _safeMessage(error),
      );
      _emit(
        _status.copyWith(
          phase: UpdateCheckPhase.idle,
          lastCheckAt: at,
          outcome: UpdateOutcome.failed,
          errorMessage: _safeMessage(error),
          progress: null,
        ),
      );
      rethrow;
    }

    final at = _clock();
    await settings.recordUpdateOutcome(
      outcome: UpdateOutcome.succeeded,
      at: at,
    );
    _emit(
      _status.copyWith(
        phase: UpdateCheckPhase.idle,
        lastCheckAt: at,
        lastSuccessAt: at,
        outcome: UpdateOutcome.succeeded,
        errorMessage: null,
        progress: null,
      ),
    );
  }

  Future<void> _recordSkipped(UpdateOutcome outcome, String? message) async {
    final at = _clock();
    await settings.recordUpdateOutcome(outcome: outcome, at: at);
    _emit(
      _status.copyWith(
        phase: UpdateCheckPhase.idle,
        lastCheckAt: at,
        outcome: outcome,
        errorMessage: message,
        progress: null,
      ),
    );
  }

  void _emit([UpdateCheckStatus? status]) {
    if (_disposed) {
      return;
    }
    if (status != null) {
      _status = status;
    }
    if (!_changes.isClosed) {
      _changes.add(_status);
    }
  }

  static String _safeMessage(Object error) {
    final text = error.toString();
    return text.length <= 240 ? text : '${text.substring(0, 237)}...';
  }
}

/// Adapts [SettingsRepository] to the scheduler's last-success store.
final class _SettingsSyncStateStore implements SyncStateStore {
  const _SettingsSyncStateStore(this._settings);

  final SettingsRepository _settings;

  @override
  Future<DateTime?> lastCheckedAt() async =>
      (await _settings.read()).lastUpdateCheckAt;

  @override
  Future<void> recordCheckedAt(DateTime at) =>
      _settings.recordUpdateOutcome(outcome: UpdateOutcome.succeeded, at: at);
}

/// Lets [UpdateCheckController] observe the runner the scheduler drives.
final class _TrackingRunner implements SyncRunner {
  const _TrackingRunner(this._controller);

  final UpdateCheckController _controller;

  @override
  Future<void> run() => _controller._runSync();
}

/// Sentinel that distinguishes an omitted nullable field from an explicit null.
const _unset = Object();
