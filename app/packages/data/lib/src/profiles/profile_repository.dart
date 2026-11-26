import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../bundle/game_mode.dart';
import '../database/app_database.dart';
import '../settings/settings_repository.dart';

/// The profile id was not found in the `profiles` table.
///
/// [ProfileRepository.activate] throws this instead of silently changing the
/// active profile to something else, so a caller that holds a stale id can
/// report the problem. Nothing is written before the throw.
final class ProfileNotFoundError implements Exception {
  const ProfileNotFoundError(this.profileId);

  /// The id that does not exist.
  final String profileId;

  @override
  String toString() => 'ProfileNotFoundError: no profile with id "$profileId"';
}

/// The result of [ProfileRepository.createForMode].
///
/// Creation is a typed result rather than a throw because "this mode already
/// has a profile" is an ordinary outcome of a user action, not a programmer
/// error. The caller gets the existing profile either way and can switch to it
/// explicitly with [ProfileRepository.activate].
sealed class ProfileCreationResult {
  const ProfileCreationResult(this.profile);

  /// The newly created profile, or the existing profile for the mode.
  final Profile profile;

  /// Whether a row was inserted by this call.
  bool get created;
}

/// A profile was inserted for the requested mode and is now active.
final class ProfileCreated extends ProfileCreationResult {
  const ProfileCreated(super.profile);

  @override
  bool get created => true;
}

/// The mode already had a profile; nothing was inserted or activated.
final class ProfileAlreadyExists extends ProfileCreationResult {
  const ProfileAlreadyExists(super.profile);

  @override
  bool get created => false;
}

/// Lifecycle of the local player profiles (`profiles` table).
///
/// The rules are the `local-profiles` spec:
///
/// * at most one profile per [GameMode] (the table's `UNIQUE` constraint on
///   `gameMode` enforces it);
/// * exactly one active profile, stored as `settings.activeProfileId` in
///   `appSettings` — the key is the table's primary key, so there can never be
///   two active ids;
/// * player data is local-only and never touched by dataset ingestion.
///
/// ## Lifecycle
///
/// [ensureFirstLaunch] is the startup entry point. With no profiles it creates
/// and activates a `regular` profile at player level 1. With profiles it is a
/// no-op except for repairing the active id (see below). Calling it twice is
/// safe and leaves the first profile's id and timestamps unchanged.
///
/// [createForMode] creates a profile for an explicit mode and activates it in
/// the same transaction. A mode that already has a profile returns
/// [ProfileAlreadyExists] with the existing row and does **not** change the
/// active profile; switching is always an explicit [activate] call.
///
/// [activate] validates that the id exists and then stores it as the single
/// active profile. A missing id throws [ProfileNotFoundError] and leaves the
/// previous active profile untouched.
///
/// ## Repair
///
/// [active] never throws for stored data that disagrees with the table. When
/// the stored id is missing, unreadable, or points at a deleted profile, it
/// falls back deterministically to the `regular` profile, else the oldest
/// profile (`createdAt`, then `id` for ties), rewrites the setting, and reports
/// the repair through [onRepair]. A corrupt settings value is therefore
/// indistinguishable from a missing one, as in [SettingsRepository].
///
/// ## Transactions, ids and clock
///
/// Every write that touches both `profiles` and `appSettings` (first launch,
/// creation + activation) runs in one database transaction, so a failure
/// cannot leave an active id pointing at a profile that was not inserted.
/// Ids come from [idGenerator] (cryptographically random hex by default) and
/// timestamps from [clock], both injectable for deterministic tests. No new
/// dependency is required.
final class ProfileRepository {
  /// Creates the repository over [_database].
  ///
  /// [clock] defaults to [DateTime.now]; [idGenerator] defaults to
  /// `profile-` followed by 16 random bytes in lowercase hex. [onRepair]
  /// receives one message per automatic active-profile repair; wire it to the
  /// application logger.
  ProfileRepository(
    this._database, {
    DateTime Function()? clock,
    String Function()? idGenerator,
    this.onRepair,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? _generateProfileId;

  final AppDatabase _database;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  /// Callback for an automatic active-profile repair; see the class docs.
  final void Function(String message)? onRepair;

  /// Every profile, oldest first (`createdAt`, then `id`).
  Future<List<Profile>> list() async {
    final rows =
        await (_database.select(_database.profiles)..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();
    return List.unmodifiable(rows);
  }

  /// The profile with [id], or `null` when it does not exist.
  Future<Profile?> byId(String id) {
    return (_database.select(
      _database.profiles,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  /// The active profile, repairing a missing or corrupt active id.
  ///
  /// Returns `null` only when the table has no profiles at all. Otherwise a
  /// missing setting, an unreadable value, or an id that no longer exists is
  /// replaced with [regular][GameMode.regular] if present, else the oldest
  /// profile. This method is idempotent and performs a write only when the
  /// stored value disagrees with the table.
  Future<Profile?> active() {
    return _database.transaction(() async {
      final profiles = await _profilesInOrder();
      if (profiles.isEmpty) {
        return null;
      }
      return _resolveActive(profiles);
    });
  }

  /// Ensures the app has a usable active profile after startup.
  ///
  /// * No profiles: inserts a `regular` profile at player level 1 and activates
  ///   it, in one transaction.
  /// * Profiles exist: returns the active one, repairing a missing or corrupt
  ///   active id exactly like [active]. No profile is created.
  ///
  /// Idempotent: a second call returns the same profile without changing its
  /// id, level or timestamps.
  Future<Profile> ensureFirstLaunch() {
    return _database.transaction(() async {
      final profiles = await _profilesInOrder();
      if (profiles.isEmpty) {
        final profile = await _insert(GameMode.regular);
        await _writeActiveId(profile.id);
        return profile;
      }
      return _resolveActive(profiles);
    });
  }

  /// Creates a profile for [mode] and makes it the active profile.
  ///
  /// At most one profile exists per mode. When [mode] already has one, the
  /// existing row is returned as [ProfileAlreadyExists] and the active profile
  /// is **not** changed; use [activate] to switch to it. The insert and the
  /// active-setting write share one transaction, so either both are visible or
  /// neither is.
  Future<ProfileCreationResult> createForMode(GameMode mode) {
    return _database.transaction(() async {
      final existing = await (_database.select(
        _database.profiles,
      )..where((row) => row.gameMode.equals(mode.wireValue))).getSingleOrNull();
      if (existing != null) {
        return ProfileAlreadyExists(existing);
      }

      final profile = await _insert(mode);
      await _writeActiveId(profile.id);
      return ProfileCreated(profile);
    });
  }

  /// Makes the existing profile [id] the single active profile.
  ///
  /// Throws [ProfileNotFoundError] when [id] does not exist; the previous
  /// active profile and every other row are left unchanged.
  Future<Profile> activate(String id) {
    return _database.transaction(() async {
      final profile = await (_database.select(
        _database.profiles,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (profile == null) {
        throw ProfileNotFoundError(id);
      }
      await _writeActiveId(profile.id);
      return profile;
    });
  }

  Future<List<Profile>> _profilesInOrder() async {
    final rows =
        await (_database.select(_database.profiles)..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();
    return rows;
  }

  /// The stored active setting, or `null` when missing or unreadable.
  Future<String?> _readActiveId() async {
    final row =
        await (_database.select(_database.appSettings)
              ..where((row) => row.key.equals(AppSettingKeys.activeProfileId)))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    try {
      final value = jsonDecode(row.value);
      return value is String && value.isNotEmpty ? value : null;
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeActiveId(String profileId) async {
    await _database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.activeProfileId,
            value: jsonEncode(profileId),
          ),
        );
  }

  /// Returns the profile the stored setting points at, or repairs the setting.
  ///
  /// [profiles] must be non-empty and ordered oldest first. The repair target
  /// is the `regular` profile when present, else `profiles.first` (the oldest,
  /// with `id` as the deterministic tie-breaker).
  Future<Profile> _resolveActive(List<Profile> profiles) async {
    final storedId = await _readActiveId();
    if (storedId != null) {
      for (final profile in profiles) {
        if (profile.id == storedId) {
          return profile;
        }
      }
    }

    final fallback = profiles.firstWhere(
      (profile) => profile.gameMode == GameMode.regular.wireValue,
      orElse: () => profiles.first,
    );

    final reason = storedId == null
        ? 'no readable active profile id'
        : 'active profile id "$storedId" no longer exists';
    onRepair?.call(
      'Repairing the active profile: $reason; using "${fallback.id}" '
      '(${fallback.gameMode}).',
    );
    await _writeActiveId(fallback.id);
    return fallback;
  }

  /// Inserts a profile for [mode] with a fresh id and the injected clock.
  ///
  /// The row is read back inside the transaction so the returned values are
  /// exactly what SQLite stored (notably the default player level and drift's
  /// timestamp representation).
  Future<Profile> _insert(GameMode mode) async {
    final now = _clock();
    final id = await _uniqueId();
    await _database
        .into(_database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: id,
            gameMode: mode.wireValue,
            createdAt: now,
            updatedAt: now,
          ),
        );
    return await (_database.select(
      _database.profiles,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  /// An id from [_idGenerator] that no profile uses yet.
  ///
  /// Random ids collide with negligible probability, but an injected generator
  /// may repeat a value. Retrying keeps the "ids are unique" promise without a
  /// database exception; a generator that cannot produce a new id is a bug and
  /// raises [StateError].
  Future<String> _uniqueId() async {
    const attempts = 8;
    for (var attempt = 0; attempt < attempts; attempt++) {
      final candidate = _idGenerator();
      if (candidate.isEmpty) {
        throw StateError('The profile id generator returned an empty id.');
      }
      final existing = await (_database.select(
        _database.profiles,
      )..where((row) => row.id.equals(candidate))).getSingleOrNull();
      if (existing == null) {
        return candidate;
      }
    }
    throw StateError(
      'The profile id generator produced $attempts ids that are all in use.',
    );
  }
}

/// `profile-` plus 16 cryptographically random bytes as lowercase hex.
String _generateProfileId() {
  final random = Random.secure();
  final buffer = StringBuffer('profile-');
  for (var byte = 0; byte < 16; byte++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
