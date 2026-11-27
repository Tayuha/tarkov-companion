import 'dart:convert';

import 'package:tarkov_companion_core/tarkov_companion_core.dart';

import '../bundle/game_mode.dart';
import '../database/app_database.dart';
import '../quests/quest_query.dart';
import 'profile_repository.dart';
import 'progress_format.dart';

/// A single-profile export was requested but no profile is active.
final class NoActiveProfileError implements Exception {
  const NoActiveProfileError();

  @override
  String toString() => 'NoActiveProfileError: there is no active profile';
}

/// Reads profiles and their progress into a portable [ProgressExport].
///
/// The active profile is exported by default; `allProfiles: true` exports every
/// profile in one file. Rows are sorted (mode, then quest/objective id) so the
/// same database always produces byte-identical output for a fixed clock.
final class ProgressExportWriter {
  ProgressExportWriter(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  /// Builds the document and its pretty, canonical JSON.
  ///
  /// [appVersion] is the user-visible app version and is required so this pure
  /// data layer never reads platform metadata. [exportedAt] defaults to the
  /// injected clock and is always written in UTC.
  Future<ProgressExport> build({
    required String appVersion,
    bool allProfiles = false,
    DateTime? exportedAt,
  }) async {
    final profiles = ProfileRepository(_database, clock: _clock);
    final List<Profile> selected;
    if (allProfiles) {
      selected = await profiles.list();
    } else {
      final active = await profiles.active();
      if (active == null) {
        throw const NoActiveProfileError();
      }
      selected = [active];
    }

    final records = <ProgressProfileRecord>[
      for (final profile in _sortedForExport(selected))
        await _recordFor(profile),
    ];

    final document = ProgressExportDocument(
      appVersion: appVersion,
      exportedAt: (exportedAt ?? _clock()).toUtc(),
      profiles: List.unmodifiable(records),
    );
    final canonical =
        jsonDecode(document.canonicalJson) as Map<String, Object?>;

    return ProgressExport(
      document: document,
      checksum: document.checksum,
      json: '${prettyCanonicalJson(canonical)}\n',
    );
  }

  Future<ProgressProfileRecord> _recordFor(Profile profile) async {
    final questRows = await (_database.select(
      _database.questProgress,
    )..where((row) => row.profileId.equals(profile.id))).get();
    final objectiveRows = await (_database.select(
      _database.objectiveProgress,
    )..where((row) => row.profileId.equals(profile.id))).get();

    questRows.sort((left, right) => left.questId.compareTo(right.questId));
    objectiveRows.sort((left, right) {
      final byQuest = left.questId.compareTo(right.questId);
      return byQuest != 0
          ? byQuest
          : left.objectiveId.compareTo(right.objectiveId);
    });

    final mode = _modeOf(profile);
    return ProgressProfileRecord(
      gameMode: mode,
      playerLevel: profile.playerLevel,
      quests: List.unmodifiable([
        for (final row in questRows)
          if (_stateOf(row.state) != null)
            ProgressQuestEntry(
              questId: row.questId,
              state: _stateOf(row.state)!,
            ),
      ]),
      objectives: List.unmodifiable([
        for (final row in objectiveRows)
          ProgressObjectiveEntry(
            questId: row.questId,
            objectiveId: row.objectiveId,
            count: row.count < 0 ? 0 : row.count,
          ),
      ]),
    );
  }
}

List<Profile> _sortedForExport(List<Profile> profiles) {
  final ordered = List<Profile>.of(profiles);
  ordered.sort((left, right) {
    final byMode = left.gameMode.compareTo(right.gameMode);
    return byMode != 0 ? byMode : left.id.compareTo(right.id);
  });
  return ordered;
}

/// Parses a stored mode; unknown values are corruption, not an export state.
GameMode _modeOf(Profile profile) {
  final parsed = GameMode.parse(profile.gameMode);
  if (parsed is Ok<GameMode>) {
    return parsed.value;
  }
  throw StateError(
    'Profile "${profile.id}" has unknown game mode "${profile.gameMode}".',
  );
}

/// The persisted states only; an unexpected row is skipped rather than
/// re-encoded as a different state.
QuestProgressState? _stateOf(String stored) => switch (stored) {
  'in-progress' => QuestProgressState.inProgress,
  'completed' => QuestProgressState.completed,
  'failed' => QuestProgressState.failed,
  _ => null,
};
