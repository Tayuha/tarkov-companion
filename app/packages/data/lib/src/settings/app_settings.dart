/// How often the client may check for a new data bundle on its own.
///
/// The values are the three user-facing choices in the update controls. The
/// scheduler interval is [interval]; [off] means no automatic check runs until
/// the user presses **Check now**.
enum UpdateSchedule {
  off('off', null),
  daily('daily', Duration(days: 1)),
  weekly('weekly', Duration(days: 7));

  const UpdateSchedule(this.wireValue, this.interval);

  /// Stable string persisted in `settings.updateSchedule`.
  final String wireValue;

  /// Minimum time between automatic checks, or `null` when disabled.
  final Duration? interval;

  /// Whether automatic checks are enabled for this schedule.
  bool get isEnabled => this != UpdateSchedule.off;

  /// Parses a stored value, returning `null` for an unknown string.
  static UpdateSchedule? fromWire(String value) {
    for (final schedule in values) {
      if (schedule.wireValue == value) {
        return schedule;
      }
    }
    return null;
  }
}

/// The result of the most recent update check attempt.
enum UpdateOutcome {
  /// The check ran to completion (whether or not data needed downloading).
  succeeded('succeeded'),

  /// The check started and failed; see the persisted error message.
  failed('failed'),

  /// The check could not run because no network was available.
  skippedOffline('skipped-offline'),

  /// The check was blocked by a preference or environment rule.
  skipped('skipped');

  const UpdateOutcome(this.wireValue);

  /// Stable string persisted in `settings.lastUpdateOutcome`.
  final String wireValue;

  /// Parses a stored value, returning `null` for an unknown string.
  static UpdateOutcome? fromWire(String value) {
    for (final outcome in values) {
      if (outcome.wireValue == value) {
        return outcome;
      }
    }
    return null;
  }
}

/// Immutable, typed application preferences.
///
/// The fields mirror the displayed preferences documented in
/// `docs/settings.md` plus the desktop window geometry saved by the app shell,
/// and are persisted by [SettingsRepository] in the `appSettings` table.
/// Defaults here are the documented defaults: a fresh database with no rows
/// behaves exactly like `const AppSettings()`.
///
/// This type performs no profile validation and no I/O; it only describes the
/// preference values and the range of `dataFreshnessHours`.
final class AppSettings {
  const AppSettings({
    this.activeProfileId,
    this.autoUpdateEnabled = defaultAutoUpdateEnabled,
    this.allowMeteredUpdates = defaultAllowMeteredUpdates,
    this.dataFreshnessHours = defaultDataFreshnessHours,
    this.windowGeometryJson,
    this.updateSchedule = defaultUpdateSchedule,
    this.lastUpdateCheckAt,
    this.lastUpdateAttemptAt,
    this.lastUpdateOutcome,
    this.lastUpdateError,
  });

  /// No profile is active until the user creates or activates one.
  static const String? defaultActiveProfileId = null;

  /// Automatic update checks run unless the user turns them off.
  static const bool defaultAutoUpdateEnabled = true;

  /// Automatic updates skip metered connections unless the user opts in.
  static const bool defaultAllowMeteredUpdates = false;

  /// Prices and datasets older than this are labelled stale.
  static const int defaultDataFreshnessHours = 24;

  /// No saved window geometry until the desktop shell records one.
  static const String? defaultWindowGeometryJson = null;

  /// Automatic update checks run daily unless the user picks another schedule.
  static const UpdateSchedule defaultUpdateSchedule = UpdateSchedule.daily;

  /// Smallest accepted freshness threshold.
  static const int minDataFreshnessHours = 1;

  /// Largest accepted freshness threshold (one week).
  static const int maxDataFreshnessHours = 168;

  /// Whether [hours] is a valid freshness threshold.
  static bool isValidDataFreshnessHours(int hours) =>
      hours >= minDataFreshnessHours && hours <= maxDataFreshnessHours;

  /// Id of the active profile, or `null` when none is active.
  final String? activeProfileId;

  /// Whether automatic data-update checks are enabled.
  final bool autoUpdateEnabled;

  /// Whether automatic updates may download on a metered connection.
  final bool allowMeteredUpdates;

  /// Age, in hours, after which prices and dataset data are stale.
  final int dataFreshnessHours;

  /// The desktop window geometry document saved by the app shell, or `null`.
  ///
  /// The settings layer treats this as an opaque string so the schema stays
  /// independent of the platform channel. The app shell writes and validates
  /// JSON; an unreadable value falls back to `null` on the next read.
  final String? windowGeometryJson;

  /// How often automatic update checks may run.
  ///
  /// [autoUpdateEnabled] remains the master switch for older settings rows; the
  /// update controls write both fields together. Use [effectiveUpdateSchedule]
  /// for display.
  final UpdateSchedule updateSchedule;

  /// When the last check completed successfully, in UTC.
  final DateTime? lastUpdateCheckAt;

  /// When the last check was attempted, in UTC, including failed and skipped
  /// attempts. This is the time the update controls display.
  final DateTime? lastUpdateAttemptAt;

  /// The result of the last attempt, or `null` before the first one.
  final UpdateOutcome? lastUpdateOutcome;

  /// A short, user-safe message for the last failed attempt.
  final String? lastUpdateError;

  /// The schedule the user is effectively on.
  ///
  /// A settings row written before schedules existed can have
  /// `autoUpdateEnabled` set without a schedule; the disabled switch always
  /// wins so automatic checks stay off.
  UpdateSchedule get effectiveUpdateSchedule =>
      autoUpdateEnabled ? updateSchedule : UpdateSchedule.off;

  /// Whether every field is inside its documented range.
  ///
  /// Only [dataFreshnessHours] can be out of range; booleans and a nullable
  /// string are valid by construction.
  bool get isValid => isValidDataFreshnessHours(dataFreshnessHours);

  /// A copy of these settings with the supplied fields replaced.
  ///
  /// Passing `activeProfileId: null` explicitly clears the active profile;
  /// omitting it keeps the current value. The parameter is `Object?` solely so
  /// the two cases can be told apart at runtime.
  AppSettings copyWith({
    Object? activeProfileId = _unset,
    bool? autoUpdateEnabled,
    bool? allowMeteredUpdates,
    int? dataFreshnessHours,
    Object? windowGeometryJson = _unset,
    UpdateSchedule? updateSchedule,
    Object? lastUpdateCheckAt = _unset,
    Object? lastUpdateAttemptAt = _unset,
    Object? lastUpdateOutcome = _unset,
    Object? lastUpdateError = _unset,
  }) {
    return AppSettings(
      activeProfileId: identical(activeProfileId, _unset)
          ? this.activeProfileId
          : activeProfileId as String?,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
      allowMeteredUpdates: allowMeteredUpdates ?? this.allowMeteredUpdates,
      dataFreshnessHours: dataFreshnessHours ?? this.dataFreshnessHours,
      windowGeometryJson: identical(windowGeometryJson, _unset)
          ? this.windowGeometryJson
          : windowGeometryJson as String?,
      updateSchedule: updateSchedule ?? this.updateSchedule,
      lastUpdateCheckAt: identical(lastUpdateCheckAt, _unset)
          ? this.lastUpdateCheckAt
          : lastUpdateCheckAt as DateTime?,
      lastUpdateAttemptAt: identical(lastUpdateAttemptAt, _unset)
          ? this.lastUpdateAttemptAt
          : lastUpdateAttemptAt as DateTime?,
      lastUpdateOutcome: identical(lastUpdateOutcome, _unset)
          ? this.lastUpdateOutcome
          : lastUpdateOutcome as UpdateOutcome?,
      lastUpdateError: identical(lastUpdateError, _unset)
          ? this.lastUpdateError
          : lastUpdateError as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.activeProfileId == activeProfileId &&
      other.autoUpdateEnabled == autoUpdateEnabled &&
      other.allowMeteredUpdates == allowMeteredUpdates &&
      other.dataFreshnessHours == dataFreshnessHours &&
      other.windowGeometryJson == windowGeometryJson &&
      other.updateSchedule == updateSchedule &&
      other.lastUpdateCheckAt == lastUpdateCheckAt &&
      other.lastUpdateAttemptAt == lastUpdateAttemptAt &&
      other.lastUpdateOutcome == lastUpdateOutcome &&
      other.lastUpdateError == lastUpdateError;

  @override
  int get hashCode => Object.hash(
    activeProfileId,
    autoUpdateEnabled,
    allowMeteredUpdates,
    dataFreshnessHours,
    windowGeometryJson,
    updateSchedule,
    lastUpdateCheckAt,
    lastUpdateAttemptAt,
    lastUpdateOutcome,
    lastUpdateError,
  );

  @override
  String toString() =>
      'AppSettings(activeProfileId: $activeProfileId, '
      'autoUpdateEnabled: $autoUpdateEnabled, '
      'allowMeteredUpdates: $allowMeteredUpdates, '
      'dataFreshnessHours: $dataFreshnessHours, '
      'windowGeometryJson: $windowGeometryJson, '
      'updateSchedule: $updateSchedule, '
      'lastUpdateCheckAt: $lastUpdateCheckAt, '
      'lastUpdateAttemptAt: $lastUpdateAttemptAt, '
      'lastUpdateOutcome: $lastUpdateOutcome, '
      'lastUpdateError: $lastUpdateError)';
}

/// Sentinel that distinguishes an omitted `copyWith` argument from `null`.
const _unset = Object();
