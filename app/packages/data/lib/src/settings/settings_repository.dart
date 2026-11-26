import 'dart:convert';

import '../database/app_database.dart';
import 'app_settings.dart';

/// The `appSettings` key names owned by this client.
///
/// Every key uses the `settings.` prefix so an older or unrelated row cannot be
/// mistaken for a current setting. The repository owns the whole table: a key
/// outside this set is obsolete and is deleted by [SettingsRepository.write]
/// and [SettingsRepository.reset].
abstract final class AppSettingKeys {
  static const String activeProfileId = 'settings.activeProfileId';
  static const String autoUpdateEnabled = 'settings.autoUpdateEnabled';
  static const String allowMeteredUpdates = 'settings.allowMeteredUpdates';
  static const String dataFreshnessHours = 'settings.dataFreshnessHours';

  /// Every key this client reads and writes.
  static const Set<String> all = {
    activeProfileId,
    autoUpdateEnabled,
    allowMeteredUpdates,
    dataFreshnessHours,
  };
}

/// Typed access to the `appSettings` key/value table.
///
/// ## Storage
///
/// Each value is a JSON-encoded string: `"profile-id"`, `true`, `false`, `24`
/// or `null`. JSON keeps the stored type explicit, and a row written by a
/// different app version still decodes or fails in a predictable way.
/// Settings are local-only and hold no player progress and no secrets.
///
/// ## Missing, corrupt and unknown values
///
/// * A missing key reads as its documented default.
/// * A value that is not valid JSON, has the wrong JSON type, or is outside the
///   freshness range reads as that field's default and reports a warning
///   through [onWarning]. `read()` never throws for bad stored data.
/// * Unknown keys are ignored by [read] and left in place, so a downgrade does
///   not destroy data it does not understand. The table is still owned by this
///   repository: [write] deletes every key outside [AppSettingKeys.all] and
///   [reset] deletes every row.
final class SettingsRepository {
  /// Creates the repository over [database].
  ///
  /// [onWarning] receives one human-readable message per invalid stored value,
  /// including the key and the expected shape but not the raw contents. Wire it
  /// to the application logger; it is deliberately synchronous so [read] stays
  /// a single round trip.
  const SettingsRepository(this._database, {this.onWarning});

  final AppDatabase _database;

  /// Callback for invalid stored values; see the class documentation.
  final void Function(String message)? onWarning;

  /// Reads every setting, substituting defaults for missing or invalid values.
  ///
  /// Rows outside [AppSettingKeys.all] are ignored and not deleted.
  Future<AppSettings> read() async {
    final rows = await _database.select(_database.appSettings).get();
    final stored = <String, String>{
      for (final row in rows)
        if (AppSettingKeys.all.contains(row.key)) row.key: row.value,
    };

    return AppSettings(
      activeProfileId: _decodeActiveProfileId(stored),
      autoUpdateEnabled: _decodeBool(
        stored,
        AppSettingKeys.autoUpdateEnabled,
        AppSettings.defaultAutoUpdateEnabled,
      ),
      allowMeteredUpdates: _decodeBool(
        stored,
        AppSettingKeys.allowMeteredUpdates,
        AppSettings.defaultAllowMeteredUpdates,
      ),
      dataFreshnessHours: _decodeFreshness(stored),
    );
  }

  /// Validates and writes every setting in one transaction.
  ///
  /// Throws [ArgumentError] before touching the database when
  /// [AppSettings.dataFreshnessHours] is outside
  /// [AppSettings.minDataFreshnessHours]..[AppSettings.maxDataFreshnessHours];
  /// a failed write leaves the previous rows untouched.
  ///
  /// Any existing key outside [AppSettingKeys.all] is deleted in the same
  /// transaction, so obsolete keys from an older app version cannot survive a
  /// write by this version.
  Future<void> write(AppSettings settings) async {
    if (!AppSettings.isValidDataFreshnessHours(settings.dataFreshnessHours)) {
      throw ArgumentError.value(
        settings.dataFreshnessHours,
        'dataFreshnessHours',
        'must be between ${AppSettings.minDataFreshnessHours} and '
            '${AppSettings.maxDataFreshnessHours} hours',
      );
    }

    final encoded = <String, String>{
      AppSettingKeys.activeProfileId: jsonEncode(settings.activeProfileId),
      AppSettingKeys.autoUpdateEnabled: jsonEncode(settings.autoUpdateEnabled),
      AppSettingKeys.allowMeteredUpdates: jsonEncode(
        settings.allowMeteredUpdates,
      ),
      AppSettingKeys.dataFreshnessHours: jsonEncode(
        settings.dataFreshnessHours,
      ),
    };

    await _database.transaction(() async {
      await (_database.delete(
        _database.appSettings,
      )..where((row) => row.key.isNotIn(AppSettingKeys.all))).go();
      for (final entry in encoded.entries) {
        await _database
            .into(_database.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(key: entry.key, value: entry.value),
            );
      }
    });
  }

  /// Sets the active profile id, or clears it with `null`.
  Future<void> setActiveProfileId(String? profileId) async {
    final current = await read();
    await write(current.copyWith(activeProfileId: profileId));
  }

  /// Enables or disables automatic update checks.
  Future<void> setAutoUpdateEnabled(bool enabled) async {
    final current = await read();
    await write(current.copyWith(autoUpdateEnabled: enabled));
  }

  /// Allows or forbids automatic downloads on a metered connection.
  Future<void> setAllowMeteredUpdates(bool allowed) async {
    final current = await read();
    await write(current.copyWith(allowMeteredUpdates: allowed));
  }

  /// Sets the freshness threshold; throws [ArgumentError] outside 1–168.
  Future<void> setDataFreshnessHours(int hours) async {
    final current = await read();
    await write(current.copyWith(dataFreshnessHours: hours));
  }

  /// Deletes every settings row and returns the documented defaults.
  Future<AppSettings> reset() async {
    await _database.delete(_database.appSettings).go();
    return const AppSettings();
  }

  String? _decodeActiveProfileId(Map<String, String> stored) {
    final raw = stored[AppSettingKeys.activeProfileId];
    if (raw == null) {
      return AppSettings.defaultActiveProfileId;
    }
    final decoded = _decodeJson(raw, AppSettingKeys.activeProfileId);
    if (!decoded.isValid) {
      return AppSettings.defaultActiveProfileId;
    }
    final value = decoded.value;
    if (value == null || value is String) {
      return value as String?;
    }
    _warn(
      AppSettingKeys.activeProfileId,
      'expected a string or null, found ${_typeName(value)}',
    );
    return AppSettings.defaultActiveProfileId;
  }

  bool _decodeBool(Map<String, String> stored, String key, bool fallback) {
    final raw = stored[key];
    if (raw == null) {
      return fallback;
    }
    final decoded = _decodeJson(raw, key);
    if (!decoded.isValid) {
      return fallback;
    }
    final value = decoded.value;
    if (value is bool) {
      return value;
    }
    _warn(key, 'expected a boolean, found ${_typeName(value)}');
    return fallback;
  }

  int _decodeFreshness(Map<String, String> stored) {
    const key = AppSettingKeys.dataFreshnessHours;
    final raw = stored[key];
    if (raw == null) {
      return AppSettings.defaultDataFreshnessHours;
    }
    final decoded = _decodeJson(raw, key);
    if (!decoded.isValid) {
      return AppSettings.defaultDataFreshnessHours;
    }
    final value = decoded.value;
    if (value is! int) {
      _warn(key, 'expected an integer, found ${_typeName(value)}');
      return AppSettings.defaultDataFreshnessHours;
    }
    if (!AppSettings.isValidDataFreshnessHours(value)) {
      _warn(
        key,
        'value $value is outside '
        '${AppSettings.minDataFreshnessHours}–'
        '${AppSettings.maxDataFreshnessHours}',
      );
      return AppSettings.defaultDataFreshnessHours;
    }
    return value;
  }

  ({bool isValid, Object? value}) _decodeJson(String raw, String key) {
    try {
      return (isValid: true, value: jsonDecode(raw));
    } on FormatException {
      _warn(key, 'not valid JSON');
      return (isValid: false, value: null);
    }
  }

  void _warn(String key, String problem) {
    onWarning?.call(
      'Ignoring app setting "$key": $problem; using the default.',
    );
  }
}

String _typeName(Object? value) => switch (value) {
  null => 'null',
  String() => 'a string',
  bool() => 'a boolean',
  int() => 'an integer',
  double() => 'a number',
  List<Object?>() => 'a list',
  Map<Object?, Object?>() => 'an object',
  _ => value.runtimeType.toString(),
};
