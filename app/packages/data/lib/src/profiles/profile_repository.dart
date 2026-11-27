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

/// A profile fact is outside its documented range.
///
/// Thrown before anything is written, so the stored profile keeps its previous
/// value when the caller tries to record an impossible one.
final class ProfileFactValidationError implements Exception {
  const ProfileFactValidationError(this.message);

  final String message;

  @override
  String toString() => 'ProfileFactValidationError: $message';
}

/// What [ProfileRepository.resetProgress] removed.
final class ProfileResetResult {
  const ProfileResetResult({
    required this.profileId,
    required this.questStatesCleared,
    required this.objectiveCountsCleared,
  });

  /// The profile whose progress was cleared.
  final String profileId;

  /// Number of `questProgress` rows deleted.
  final int questStatesCleared;

  /// Number of `objectiveProgress` rows deleted.
  final int objectiveCountsCleared;

  /// Whether the profile already had no recorded progress.
  bool get wasEmpty => questStatesCleared == 0 && objectiveCountsCleared == 0;
}

/// What [ProfileRepository.delete] removed and which profile is active after.
final class ProfileDeletionResult {
  const ProfileDeletionResult({required this.deleted, required this.active});

  /// The removed profile (its progress was removed with it).
  final Profile deleted;

  /// The profile that is active after the delete, or `null` when the deleted
  /// profile was the last one. A caller that gets `null` must offer profile
  /// creation; [ProfileRepository.ensureFirstLaunch] would recreate a regular
  /// profile on the next start.
  final Profile? active;
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
/// [updatePlayerLevel] writes an editable fact in `[minPlayerLevel,
/// maxPlayerLevel]`. Availability is derived at read time by
/// `QuestRepository`, so the next read reflects the new level without a
/// restart. There is no faction column in the shipped schema; the tracker's
/// availability inputs are level, recorded states and counts, so faction is
/// not a profile fact here.
///
/// [resetProgress] clears the profile's quest and objective rows in one
/// transaction, leaving the profile, its level and every other profile intact.
/// [delete] removes the profile and (by cascade or explicit delete) its
/// progress. When the deleted profile was active, another existing profile is
/// activated deterministically (`regular` when present, else the oldest). When
/// the last profile is deleted, no active id is left and [active] returns
/// `null`; [ensureFirstLaunch] recreates a regular profile on the next start.
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
       _idGenerator = idGenerator ?? generateProfileId;

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

  /// Smallest accepted player level.
  static const int minPlayerLevel = 1;

  /// Largest accepted player level.
  static const int maxPlayerLevel = 99;

  /// Whether [level] is a valid recorded player level.
  static bool isValidPlayerLevel(int level) =>
      level >= minPlayerLevel && level <= maxPlayerLevel;

  /// Records [level] as the profile's player level and returns the new row.
  ///
  /// Throws [ProfileNotFoundError] for an unknown profile and
  /// [ProfileFactValidationError] for a value outside
  /// [minPlayerLevel]..[maxPlayerLevel]; nothing is written in either case.
  /// Only `updatedAt` and the level change. Quest availability is derived on
  /// the next read, so a caller that refreshes its view sees newly unlocked
  /// quests immediately.
  Future<Profile> updatePlayerLevel(String id, int level) {
    if (!isValidPlayerLevel(level)) {
      throw ProfileFactValidationError(
        'Player level must be between $minPlayerLevel and $maxPlayerLevel; '
        'got $level.',
      );
    }
    return _database.transaction(() async {
      final profile = await (_database.select(
        _database.profiles,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (profile == null) {
        throw ProfileNotFoundError(id);
      }
      if (profile.playerLevel != level) {
        await (_database.update(
          _database.profiles,
        )..where((row) => row.id.equals(id))).write(
          ProfilesCompanion(
            playerLevel: Value(level),
            updatedAt: Value(_clock()),
          ),
        );
      }
      return (_database.select(
        _database.profiles,
      )..where((row) => row.id.equals(id))).getSingle();
    });
  }

  /// Clears the profile's recorded quest and objective progress.
  ///
  /// The profile itself, its player level and every other profile stay
  /// unchanged. Both deletes run in one transaction; `updatedAt` is refreshed
  /// to record the reset. Throws [ProfileNotFoundError] for an unknown profile
  /// before deleting anything.
  Future<ProfileResetResult> resetProgress(String id) {
    return _database.transaction(() async {
      final profile = await (_database.select(
        _database.profiles,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (profile == null) {
        throw ProfileNotFoundError(id);
      }

      final questStates = await (_database.delete(
        _database.questProgress,
      )..where((row) => row.profileId.equals(id))).go();
      final objectiveCounts = await (_database.delete(
        _database.objectiveProgress,
      )..where((row) => row.profileId.equals(id))).go();

      await (_database.update(_database.profiles)
            ..where((row) => row.id.equals(id)))
          .write(ProfilesCompanion(updatedAt: Value(_clock())));

      return ProfileResetResult(
        profileId: id,
        questStatesCleared: questStates,
        objectiveCountsCleared: objectiveCounts,
      );
    });
  }

  /// Deletes the profile [id] and its progress.
  ///
  /// The profile's quest and objective rows are deleted explicitly in the same
  /// transaction as the profile, so the result does not depend on the
  /// connection having foreign keys enabled. When [id] was the active profile
  /// the deterministic fallback is the `regular` profile when present, else the
  /// oldest remaining profile. When no profile remains, the active setting is
  /// removed and [ProfileDeletionResult.active] is `null`.
  ///
  /// Throws [ProfileNotFoundError] when [id] does not exist.
  Future<ProfileDeletionResult> delete(String id) {
    return _database.transaction(() async {
      final profile = await (_database.select(
        _database.profiles,
      )..where((row) => row.id.equals(id))).getSingleOrNull();
      if (profile == null) {
        throw ProfileNotFoundError(id);
      }

      final activeId = await _readActiveId();
      await (_database.delete(
        _database.objectiveProgress,
      )..where((row) => row.profileId.equals(id))).go();
      await (_database.delete(
        _database.questProgress,
      )..where((row) => row.profileId.equals(id))).go();
      await (_database.delete(
        _database.profiles,
      )..where((row) => row.id.equals(id))).go();

      final remaining = await _profilesInOrder();
      if (remaining.isEmpty) {
        await (_database.delete(
          _database.appSettings,
        )..where((row) => row.key.equals(AppSettingKeys.activeProfileId))).go();
        return ProfileDeletionResult(deleted: profile, active: null);
      }

      if (activeId == id || activeId == null) {
        final fallback = remaining.firstWhere(
          (candidate) => candidate.gameMode == GameMode.regular.wireValue,
          orElse: () => remaining.first,
        );
        await _writeActiveId(fallback.id);
        return ProfileDeletionResult(deleted: profile, active: fallback);
      }

      // A stored id that still points at a remaining profile is unchanged.
      for (final candidate in remaining) {
        if (candidate.id == activeId) {
          return ProfileDeletionResult(deleted: profile, active: candidate);
        }
      }

      // A dangling setting is repaired exactly like [active] would.
      final fallback = remaining.firstWhere(
        (candidate) => candidate.gameMode == GameMode.regular.wireValue,
        orElse: () => remaining.first,
      );
      await _writeActiveId(fallback.id);
      return ProfileDeletionResult(deleted: profile, active: fallback);
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

/// The default id generator: `profile-` plus 16 cryptographically random
/// bytes as lowercase hex.
///
/// Exposed so import code can create a profile with the same id shape without
/// duplicating the generator; tests inject their own instead.
String generateProfileId() {
  final random = Random.secure();
  final buffer = StringBuffer('profile-');
  for (var byte = 0; byte < 16; byte++) {
    buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
