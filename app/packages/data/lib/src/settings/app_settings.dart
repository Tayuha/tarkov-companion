/// Immutable, typed application preferences.
///
/// The fields mirror the four values documented in `docs/settings.md` and are
/// persisted by [SettingsRepository] in the `appSettings` table. Defaults here
/// are the documented defaults: a fresh database with no rows behaves exactly
/// like `const AppSettings()`.
///
/// This type performs no profile validation and no I/O; it only describes the
/// preference values and the range of `dataFreshnessHours`.
final class AppSettings {
  const AppSettings({
    this.activeProfileId,
    this.autoUpdateEnabled = defaultAutoUpdateEnabled,
    this.allowMeteredUpdates = defaultAllowMeteredUpdates,
    this.dataFreshnessHours = defaultDataFreshnessHours,
  });

  /// No profile is active until the user creates or activates one.
  static const String? defaultActiveProfileId = null;

  /// Automatic update checks run unless the user turns them off.
  static const bool defaultAutoUpdateEnabled = true;

  /// Automatic updates skip metered connections unless the user opts in.
  static const bool defaultAllowMeteredUpdates = false;

  /// Prices and datasets older than this are labelled stale.
  static const int defaultDataFreshnessHours = 24;

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
  }) {
    return AppSettings(
      activeProfileId: identical(activeProfileId, _unset)
          ? this.activeProfileId
          : activeProfileId as String?,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
      allowMeteredUpdates: allowMeteredUpdates ?? this.allowMeteredUpdates,
      dataFreshnessHours: dataFreshnessHours ?? this.dataFreshnessHours,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.activeProfileId == activeProfileId &&
      other.autoUpdateEnabled == autoUpdateEnabled &&
      other.allowMeteredUpdates == allowMeteredUpdates &&
      other.dataFreshnessHours == dataFreshnessHours;

  @override
  int get hashCode => Object.hash(
    activeProfileId,
    autoUpdateEnabled,
    allowMeteredUpdates,
    dataFreshnessHours,
  );

  @override
  String toString() =>
      'AppSettings(activeProfileId: $activeProfileId, '
      'autoUpdateEnabled: $autoUpdateEnabled, '
      'allowMeteredUpdates: $allowMeteredUpdates, '
      'dataFreshnessHours: $dataFreshnessHours)';
}

/// Sentinel that distinguishes an omitted `copyWith` argument from `null`.
const _unset = Object();
