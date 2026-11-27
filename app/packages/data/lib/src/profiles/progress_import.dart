import 'dart:convert';

import 'package:drift/drift.dart';

import '../bundle/game_mode.dart';
import '../database/app_database.dart';
import '../quests/quest_query.dart';
import '../settings/settings_repository.dart';
import 'profile_repository.dart';
import 'progress_format.dart';

/// How an import treats the target profile's existing progress.
enum ProgressImportStrategy {
  /// Add what is missing. Never deletes a row and never lowers an objective
  /// count. Quest-state conflicts keep the local value unless a resolution
  /// overrides them. This is the non-destructive default.
  merge,

  /// Replace the target profile's progress with the file's progress. The
  /// delete and the insert share one transaction, so a failure keeps the
  /// previous state.
  replace,
}

/// How one merge conflict is resolved.
enum ProgressConflictResolution {
  /// Keep the value already stored (the default).
  keepLocal,

  /// Store the value from the file.
  useImported,
}

/// A quest whose local and imported states differ during a merge preview.
final class ProgressQuestConflict {
  const ProgressQuestConflict({
    required this.gameMode,
    required this.questId,
    required this.localState,
    required this.importedState,
  });

  final GameMode gameMode;
  final String questId;
  final QuestProgressState localState;
  final QuestProgressState importedState;

  /// The key used in [ProgressImporter.apply]'s `resolutions` map.
  String get key => progressConflictKey(gameMode, questId);
}

/// An objective whose local and imported counts differ during a merge preview.
final class ProgressObjectiveConflict {
  const ProgressObjectiveConflict({
    required this.gameMode,
    required this.questId,
    required this.objectiveId,
    required this.localCount,
    required this.importedCount,
  });

  final GameMode gameMode;
  final String questId;
  final String objectiveId;
  final int localCount;
  final int importedCount;

  /// Whether a merge would write the imported count (it is higher).
  bool get mergeRaisesCount => importedCount > localCount;
}

/// The per-profile part of an import preview.
final class ProgressImportProfilePreview {
  const ProgressImportProfilePreview({
    required this.gameMode,
    required this.existingPlayerLevel,
    required this.importedPlayerLevel,
    required this.newQuestStates,
    required this.conflictingQuestStates,
    required this.newObjectiveCounts,
    required this.conflictingObjectiveCounts,
  });

  final GameMode gameMode;

  /// The stored level, or `null` when the import creates this profile.
  final int? existingPlayerLevel;
  final int importedPlayerLevel;

  final int newQuestStates;
  final int conflictingQuestStates;
  final int newObjectiveCounts;
  final int conflictingObjectiveCounts;

  /// Whether the import creates a profile for this mode.
  bool get createsProfile => existingPlayerLevel == null;
}

/// What an import file would do, computed without writing anything.
final class ProgressImportPreview {
  const ProgressImportPreview({
    required this.document,
    required this.profiles,
    required this.questConflicts,
    required this.objectiveConflicts,
  });

  final ProgressExportDocument document;
  final List<ProgressImportProfilePreview> profiles;
  final List<ProgressQuestConflict> questConflicts;
  final List<ProgressObjectiveConflict> objectiveConflicts;

  /// Number of profiles in the file.
  int get profileCount => profiles.length;

  /// Number of profiles the import creates.
  int get createdProfiles =>
      profiles.where((profile) => profile.createsProfile).length;

  /// Quest state rows in the file.
  int get questStateCount => document.questCount;

  /// Objective count rows in the file.
  int get objectiveCount => document.objectiveCount;

  /// Quest state rows the file adds to a profile with no such row.
  int get newQuestStates =>
      profiles.fold(0, (total, profile) => total + profile.newQuestStates);

  /// Quest state rows that differ from the stored value.
  int get conflictingQuestStates => questConflicts.length;

  /// Objective rows the file adds to a profile with no such row.
  int get newObjectiveCounts =>
      profiles.fold(0, (total, profile) => total + profile.newObjectiveCounts);

  /// Objective rows whose stored count differs from the file.
  int get conflictingObjectiveCounts => objectiveConflicts.length;

  /// Whether a merge would need a conflict decision.
  bool get hasConflicts =>
      questConflicts.isNotEmpty || objectiveConflicts.isNotEmpty;
}

/// The outcome of applying an import.
final class ProgressImportResult {
  const ProgressImportResult({
    required this.preview,
    required this.profilesCreated,
    required this.profilesUpdated,
    required this.questStatesWritten,
    required this.objectiveCountsWritten,
    required this.conflictsKept,
    required this.activeProfileId,
  });

  final ProgressImportPreview preview;
  final int profilesCreated;
  final int profilesUpdated;

  /// Rows inserted or updated (replace counts every file row as written).
  final int questStatesWritten;
  final int objectiveCountsWritten;

  /// Quest conflicts resolved to the local value.
  final int conflictsKept;

  /// The active profile after the import, or `null` when no profile exists.
  final String? activeProfileId;

  /// Total progress rows written.
  int get rowsWritten => questStatesWritten + objectiveCountsWritten;
}

/// Reads, previews and applies a progress file.
///
/// [preview] is read-only. [apply] is a single database transaction: every
/// profile, quest and objective write either commits together or rolls back,
/// leaving the previous state intact on any throw. [beforeCommit] is a test
/// seam that runs inside the transaction after all writes and before the
/// commit; throwing from it exercises the rollback path.
final class ProgressImporter {
  ProgressImporter(
    this._database, {
    DateTime Function()? clock,
    String Function()? idGenerator,
    this.beforeCommit,
  }) : _clock = clock ?? DateTime.now,
       _idGenerator = idGenerator ?? generateProfileId;

  final AppDatabase _database;
  final DateTime Function() _clock;
  final String Function() _idGenerator;

  /// Test seam; see the class documentation.
  final void Function()? beforeCommit;

  /// Compares [document] with stored data without writing anything.
  ///
  /// Profile modes with no stored profile are reported as creations, and all
  /// of their rows count as new. Quest states and objective counts that differ
  /// from stored values are listed as conflicts; merge applies the default
  /// keep-local rule, while replace overwrites everything.
  Future<ProgressImportPreview> preview(ProgressExportDocument document) async {
    final stored = await _profilesByMode();
    final profiles = <ProgressImportProfilePreview>[];
    final questConflicts = <ProgressQuestConflict>[];
    final objectiveConflicts = <ProgressObjectiveConflict>[];

    for (final record in document.profiles) {
      final profile = stored[record.gameMode.wireValue];
      if (profile == null) {
        profiles.add(
          ProgressImportProfilePreview(
            gameMode: record.gameMode,
            existingPlayerLevel: null,
            importedPlayerLevel: record.playerLevel,
            newQuestStates: record.quests.length,
            conflictingQuestStates: 0,
            newObjectiveCounts: record.objectives.length,
            conflictingObjectiveCounts: 0,
          ),
        );
        continue;
      }

      final localStates = await _localStates(profile.id);
      final localCounts = await _localCounts(profile.id);
      var newQuestStates = 0;
      var profileQuestConflicts = 0;
      for (final quest in record.quests) {
        final local = localStates[quest.questId];
        if (local == null) {
          newQuestStates++;
        } else if (local != quest.state) {
          profileQuestConflicts++;
          questConflicts.add(
            ProgressQuestConflict(
              gameMode: record.gameMode,
              questId: quest.questId,
              localState: local,
              importedState: quest.state,
            ),
          );
        }
      }

      var newObjectiveCounts = 0;
      var profileObjectiveConflicts = 0;
      for (final objective in record.objectives) {
        final local =
            localCounts[_objectiveKey(
              objective.questId,
              objective.objectiveId,
            )];
        if (local == null) {
          newObjectiveCounts++;
        } else if (local != objective.count) {
          profileObjectiveConflicts++;
          objectiveConflicts.add(
            ProgressObjectiveConflict(
              gameMode: record.gameMode,
              questId: objective.questId,
              objectiveId: objective.objectiveId,
              localCount: local,
              importedCount: objective.count,
            ),
          );
        }
      }

      profiles.add(
        ProgressImportProfilePreview(
          gameMode: record.gameMode,
          existingPlayerLevel: profile.playerLevel,
          importedPlayerLevel: record.playerLevel,
          newQuestStates: newQuestStates,
          conflictingQuestStates: profileQuestConflicts,
          newObjectiveCounts: newObjectiveCounts,
          conflictingObjectiveCounts: profileObjectiveConflicts,
        ),
      );
    }

    return ProgressImportPreview(
      document: document,
      profiles: List.unmodifiable(profiles),
      questConflicts: List.unmodifiable(questConflicts),
      objectiveConflicts: List.unmodifiable(objectiveConflicts),
    );
  }

  /// Applies [document] in one transaction.
  ///
  /// [strategy] defaults to [ProgressImportStrategy.merge]. [resolution] is the
  /// merge default for every conflict; [resolutions] overrides it per
  /// [ProgressQuestConflict.key]. Replace ignores both. Merge keeps the higher
  /// objective count and never deletes a row. Omitted profiles are not touched.
  ///
  /// The document is re-validated (format, version, checksum and ranges) before
  /// the transaction starts, so a programmatically built document cannot bypass
  /// validation.
  Future<ProgressImportResult> apply(
    ProgressExportDocument document, {
    ProgressImportStrategy strategy = ProgressImportStrategy.merge,
    ProgressConflictResolution resolution =
        ProgressConflictResolution.keepLocal,
    Map<String, ProgressConflictResolution> resolutions = const {},
  }) {
    // Re-parse: the constructors are intentionally validation-free and this is
    // the single gate before a write.
    final validated = ProgressExportDocument.parse(document.canonicalJson);

    return _database.transaction(() async {
      final previewResult = await preview(validated);
      final stored = await _profilesByMode();
      final now = _clock();
      var profilesCreated = 0;
      var profilesUpdated = 0;
      var questStatesWritten = 0;
      var objectiveCountsWritten = 0;
      var conflictsKept = 0;

      for (final record in validated.profiles) {
        final existing = stored[record.gameMode.wireValue];
        final Profile profile;
        final bool created;
        if (existing == null) {
          profile = await _insertProfile(record, now);
          created = true;
          profilesCreated++;
        } else {
          profile = existing;
          created = false;
          profilesUpdated++;
        }
        final localStates = await _localStates(profile.id);
        final localCounts = await _localCounts(profile.id);

        if (strategy == ProgressImportStrategy.replace) {
          await (_database.delete(
            _database.questProgress,
          )..where((row) => row.profileId.equals(profile.id))).go();
          await (_database.delete(
            _database.objectiveProgress,
          )..where((row) => row.profileId.equals(profile.id))).go();
        }

        final level = created || strategy == ProgressImportStrategy.replace
            ? record.playerLevel
            : (record.playerLevel > profile.playerLevel
                  ? record.playerLevel
                  : profile.playerLevel);
        if (level != profile.playerLevel) {
          await (_database.update(
            _database.profiles,
          )..where((row) => row.id.equals(profile.id))).write(
            ProfilesCompanion(playerLevel: Value(level), updatedAt: Value(now)),
          );
        }

        for (final quest in record.quests) {
          final local = localStates[quest.questId];
          final write = switch (strategy) {
            ProgressImportStrategy.replace => true,
            ProgressImportStrategy.merge =>
              local == null ||
                  (local != quest.state &&
                      (resolutions[progressConflictKey(
                                record.gameMode,
                                quest.questId,
                              )] ??
                              resolution) ==
                          ProgressConflictResolution.useImported),
          };
          if (!write) {
            if (local != null && local != quest.state) {
              conflictsKept++;
            }
            continue;
          }
          await _database
              .into(_database.questProgress)
              .insertOnConflictUpdate(
                QuestProgressCompanion.insert(
                  profileId: profile.id,
                  questId: quest.questId,
                  state: quest.state.storedValue!,
                  updatedAt: now,
                ),
              );
          questStatesWritten++;
        }

        for (final objective in record.objectives) {
          final key = _objectiveKey(objective.questId, objective.objectiveId);
          final local = localCounts[key];
          if (strategy == ProgressImportStrategy.merge &&
              local != null &&
              local >= objective.count) {
            continue;
          }
          await _database
              .into(_database.objectiveProgress)
              .insertOnConflictUpdate(
                ObjectiveProgressCompanion.insert(
                  profileId: profile.id,
                  questId: objective.questId,
                  objectiveId: objective.objectiveId,
                  count: Value(objective.count),
                  updatedAt: now,
                ),
              );
          objectiveCountsWritten++;
        }
      }

      final activeProfileId = await _ensureActive();
      beforeCommit?.call();

      return ProgressImportResult(
        preview: previewResult,
        profilesCreated: profilesCreated,
        profilesUpdated: profilesUpdated,
        questStatesWritten: questStatesWritten,
        objectiveCountsWritten: objectiveCountsWritten,
        conflictsKept: conflictsKept,
        activeProfileId: activeProfileId,
      );
    });
  }

  Future<Profile> _insertProfile(
    ProgressProfileRecord record,
    DateTime now,
  ) async {
    final id = await _uniqueId();
    await _database
        .into(_database.profiles)
        .insert(
          ProfilesCompanion.insert(
            id: id,
            gameMode: record.gameMode.wireValue,
            playerLevel: Value(record.playerLevel),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (_database.select(
      _database.profiles,
    )..where((row) => row.id.equals(id))).getSingle();
  }

  Future<String> _uniqueId() async {
    for (var attempt = 0; attempt < 8; attempt++) {
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
    throw StateError('The profile id generator produced only ids in use.');
  }

  Future<Map<String, Profile>> _profilesByMode() async {
    final rows = await _database.select(_database.profiles).get();
    return {for (final row in rows) row.gameMode: row};
  }

  Future<Map<String, QuestProgressState>> _localStates(String profileId) async {
    final rows = await (_database.select(
      _database.questProgress,
    )..where((row) => row.profileId.equals(profileId))).get();
    return {
      for (final row in rows)
        row.questId: QuestProgressState.fromStoredValue(row.state),
    };
  }

  Future<Map<String, int>> _localCounts(String profileId) async {
    final rows = await (_database.select(
      _database.objectiveProgress,
    )..where((row) => row.profileId.equals(profileId))).get();
    return {
      for (final row in rows)
        _objectiveKey(row.questId, row.objectiveId): row.count < 0
            ? 0
            : row.count,
    };
  }

  /// Repairs a missing active id after an import and returns it.
  ///
  /// The stored id is kept when it points at an existing profile. Otherwise the
  /// regular profile is preferred, then the oldest profile.
  Future<String?> _ensureActive() async {
    final profiles =
        await (_database.select(_database.profiles)..orderBy([
              (row) => OrderingTerm.asc(row.createdAt),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();
    if (profiles.isEmpty) {
      return null;
    }

    final row =
        await (_database.select(_database.appSettings)
              ..where((row) => row.key.equals(AppSettingKeys.activeProfileId)))
            .getSingleOrNull();
    if (row != null) {
      final storedId = _decodeActiveId(row.value);
      if (storedId != null) {
        for (final profile in profiles) {
          if (profile.id == storedId) {
            return profile.id;
          }
        }
      }
    }

    final fallback = profiles.firstWhere(
      (profile) => profile.gameMode == GameMode.regular.wireValue,
      orElse: () => profiles.first,
    );
    await (_database
        .into(_database.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.activeProfileId,
            value: jsonEncode(fallback.id),
          ),
        ));
    return fallback.id;
  }
}

/// Reads the JSON-encoded active id; an unreadable value is treated as missing.
String? _decodeActiveId(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is String && decoded.isNotEmpty ? decoded : null;
  } on FormatException {
    return null;
  }
}

/// The key that identifies a quest conflict across modes.
String progressConflictKey(GameMode mode, String questId) =>
    '${mode.wireValue}:$questId';

String _objectiveKey(String questId, String objectiveId) =>
    '$questId\u0000$objectiveId';
