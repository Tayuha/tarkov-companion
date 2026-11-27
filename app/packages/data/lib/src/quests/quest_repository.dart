import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'quest_labels.dart';
import 'quest_availability.dart';
import 'quest_detail.dart';
import 'quest_query.dart';

/// The profile a quest read or write was scoped to does not exist.
final class QuestProfileNotFoundError implements Exception {
  const QuestProfileNotFoundError(this.profileId);

  final String profileId;

  @override
  String toString() =>
      'QuestProfileNotFoundError: no profile with id "$profileId"';
}

/// The quest does not exist in the active `tasks` dataset.
final class QuestNotFoundError implements Exception {
  const QuestNotFoundError(this.questId);

  final String questId;

  @override
  String toString() => 'QuestNotFoundError: no quest with id "$questId"';
}

/// The objective does not belong to the quest or is absent from the dataset.
final class QuestObjectiveNotFoundError implements Exception {
  const QuestObjectiveNotFoundError(this.questId, this.objectiveId);

  final String questId;
  final String objectiveId;

  @override
  String toString() =>
      'QuestObjectiveNotFoundError: no objective "$objectiveId" on quest '
      '"$questId"';
}

/// A quest or objective progress write failed validation.
///
/// Always thrown before anything is written, inside the write transaction, so
/// the previous progress is untouched.
final class QuestProgressValidationError implements Exception {
  const QuestProgressValidationError(this.message);

  final String message;

  @override
  String toString() => 'QuestProgressValidationError: $message';
}

/// Read-side and write-side quest access over the local catalog and the active
/// profile's progress.
///
/// The repository is pure data access: it never touches widgets and works with
/// a plain in-memory database in tests.
///
/// ## Name search and sort key
///
/// The quest bundle already publishes `normalizedName` (lower-case and
/// diacritic-free) on every `task` record, but the shipped schema has no
/// `tasks.normalizedName` column and this layer deliberately does not add one.
/// The stored `tasks.payload` is the canonical JSONL record, so the query reads
/// the existing key with `json_extract` and falls back to `lower(name)` for a
/// hand-written record without it. Text search and the name sort therefore use
/// the same key, which keeps them consistent. Promoting the field to an indexed
/// column is a schema migration for a later task if quest volume ever makes the
/// JSON extraction hot; at a few hundred quests the difference is not
/// measurable.
///
/// Count and page queries run in one read transaction so a concurrent bundle
/// ingestion (which commits in a single transaction) cannot produce a page
/// whose `total` and rows disagree.
///
/// Progress is read with a `LEFT JOIN` on `questProgress` scoped to
/// `QuestQuery.profileId`. No row means [QuestProgressState.notStarted], and
/// rows for other profiles are never considered.
///
/// ## Detail, availability and progress
///
/// [detail] and [objectivesFor] are the read model for the quest screen.
/// [statuses], [status] and [availableQuests] derive availability from the
/// profile's level, recorded state and objective counts; nothing derived is
/// written back. [setQuestState] and [setObjectiveCount] persist only the
/// player's own rows, transactionally, so a dependent quest's availability
/// changes on the next read after a completion or a revert.
///
/// Rows whose quest disappeared from the dataset are preserved; use
/// [orphanedProgress] to list them. They are excluded from prerequisite math
/// because the current dataset can no longer confirm them.
///
/// ## Game modes
///
/// The bundle marks a task with a `gameMode` list. A task without the field (or
/// with an empty list) belongs to every mode, which keeps older bundles and
/// hand-written fixtures readable. When a profile is supplied, reads keep only
/// tasks whose list is empty or contains the profile's `profiles.gameMode`.
/// A PvE-only task is therefore absent from a regular profile's catalog,
/// statuses and available list, and a write for it is rejected like any other
/// quest that is not in the active dataset.
final class QuestRepository {
  /// Creates the repository over [database].
  ///
  /// [clock] supplies write timestamps and defaults to [DateTime.now]. Tests
  /// inject a fixed clock; the value is diagnostic and never affects
  /// availability.
  // A named `this._clock` parameter would be inaccessible outside this
  // library, so the initializer is explicit.
  const QuestRepository(this._database, {DateTime Function()? clock})
    // ignore: prefer_initializing_formals
    : _clock = clock;

  final AppDatabase _database;
  final DateTime Function()? _clock;

  /// The folded name key shared by text search and name sorting.
  ///
  /// `json_valid` guards a malformed payload: the ingestor writes canonical
  /// JSON, so this is defensive rather than expected. `lower(name)` keeps a
  /// record without `normalizedName` readable (ASCII case-insensitive only).
  static const String _normalizedNameSql =
      r"COALESCE(CASE WHEN json_valid(tasks.payload) "
      r"THEN json_extract(tasks.payload, '$.normalizedName') END, "
      r'lower(tasks.name))';

  /// Runs [query] and returns one typed page.
  ///
  /// Pagination is clamped through [QuestQuery.effectiveLimit] and
  /// [QuestQuery.effectiveOffset]; [QuestPage.limit] and [QuestPage.offset]
  /// report the values actually used.
  ///
  /// A text filter that contains no letter/digit token returns an empty page
  /// without issuing a query, because no token can match. An empty `text` (or
  /// whitespace) is not a filter at all.
  Future<QuestPage> query(QuestQuery query) async {
    final limit = query.effectiveLimit;
    final offset = query.effectiveOffset;
    final tokens = questSearchTokens(query.filters.text);

    if (query.hasText && tokens.isEmpty) {
      return QuestPage(
        quests: const [],
        total: 0,
        limit: limit,
        offset: offset,
      );
    }

    final gameMode = await _profileGameMode(query.profileId);
    final parts = _buildParts(query, tokens, gameMode: gameMode);

    return _database.transaction(() async {
      final totalRow = await _database
          .customSelect(
            'SELECT count(*) AS n ${parts.fromSql} ${parts.whereSql}',
            variables: parts.variables,
          )
          .getSingle();
      final total = totalRow.read<int>('n');

      if (total == 0) {
        return QuestPage(
          quests: const [],
          total: 0,
          limit: limit,
          offset: offset,
        );
      }

      final rows = await _database
          .customSelect(
            'SELECT tasks.id, tasks.name, tasks.traderId, tasks.mapId, '
            'tasks.minPlayerLevel, tasks.experience, tasks.kappaRequired, '
            '${parts.progressColumn} '
            '${parts.fromSql} ${parts.whereSql} '
            'ORDER BY ${_orderBy(query.sort)} LIMIT ? OFFSET ?',
            variables: [
              ...parts.variables,
              Variable<int>(limit),
              Variable<int>(offset),
            ],
          )
          .get();

      return QuestPage(
        quests: [for (final row in rows) _readSummary(row)],
        total: total,
        limit: limit,
        offset: offset,
      );
    });
  }

  /// The number of quests matching [query], ignoring pagination.
  ///
  /// Equivalent to `(await query(q)).total` but without reading a page.
  Future<int> count(QuestQuery query) async {
    final tokens = questSearchTokens(query.filters.text);
    if (query.hasText && tokens.isEmpty) {
      return 0;
    }

    final gameMode = await _profileGameMode(query.profileId);
    final parts = _buildParts(query, tokens, gameMode: gameMode);
    final row = await _database
        .customSelect(
          'SELECT count(*) AS n ${parts.fromSql} ${parts.whereSql}',
          variables: parts.variables,
        )
        .getSingle();
    return row.read<int>('n');
  }

  // -------------------------------------------------------------------------
  // Detail
  // -------------------------------------------------------------------------

  /// One quest's detail, or `null` when the id is not in the active dataset.
  ///
  /// Objectives come from `taskObjectives`, ordered by objective id. Unlocks
  /// are the quests whose `taskRequirements` name this quest, so they always
  /// agree with the current dataset. Trader and map display names are joined
  /// locally when those datasets are present.
  ///
  /// Passing [profileId] scopes the lookup to that profile's game mode: a task
  /// that exists for another mode reads as `null`, exactly like one removed
  /// upstream. Omitting it keeps the mode-agnostic lookup used by detail links
  /// and tests that have no profile.
  Future<QuestDetail?> detail(String id, {String? profileId}) async {
    final task = await _taskById(id);
    if (task == null) {
      return null;
    }
    final profile = await _profileByIdOrNull(profileId);
    if (profileId != null && profileId.trim().isNotEmpty && profile == null) {
      return null;
    }
    if (profile != null && !_taskVisibleInMode(task, profile.gameMode)) {
      return null;
    }
    final payload = _decodePayload(task.payload) ?? const <String, Object?>{};
    final objectives = await objectivesFor(id);
    final traderName = await _traderName(task.traderId);
    final mapName = await _mapName(task.mapId);
    final unlocks = await _unlocksFor(id, gameMode: profile?.gameMode);

    return QuestDetail.fromTaskRecord(
      id: task.id,
      name: task.name,
      payload: payload,
      traderId: task.traderId,
      traderName: traderName,
      mapId: task.mapId,
      mapName: mapName,
      minPlayerLevel: task.minPlayerLevel,
      experience: task.experience,
      kappaRequired: task.kappaRequired,
      objectives: objectives,
      unlocks: unlocks,
    );
  }

  /// Every objective of [taskId], ordered by objective id.
  ///
  /// An unknown quest or a quest without objectives returns an empty list.
  Future<List<QuestObjective>> objectivesFor(String taskId) async {
    final rows = await (_database.select(
      _database.taskObjectives,
    )..where((row) => row.taskId.equals(taskId))).get();
    rows.sort((left, right) => left.id.compareTo(right.id));
    return List.unmodifiable([
      for (final row in rows)
        QuestObjective.fromPayload(
          _decodePayload(row.payload) ?? const <String, Object?>{},
          type: row.type,
          description: row.description,
          count: row.count,
        ),
    ]);
  }

  // -------------------------------------------------------------------------
  // Availability
  // -------------------------------------------------------------------------

  /// The derived status of every quest in the dataset for [profileId].
  ///
  /// Ordered by quest id. Throws [QuestProfileNotFoundError] when the profile
  /// does not exist: without a profile there is no level and no progress to
  /// derive from.
  Future<List<QuestStatus>> statuses(String profileId) async {
    final profile = await _requireProfile(profileId);

    final allTasks = await (_database.select(
      _database.tasks,
    )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
    final tasks = _visibleTasks(allTasks, profile.gameMode);
    final objectiveRows = await _database
        .select(_database.taskObjectives)
        .get();

    final objectivesByTask = <String, List<QuestObjective>>{};
    for (final row in objectiveRows) {
      (objectivesByTask[row.taskId] ??= <QuestObjective>[]).add(
        QuestObjective.fromPayload(
          _decodePayload(row.payload) ?? const <String, Object?>{},
          type: row.type,
          description: row.description,
          count: row.count,
        ),
      );
    }
    for (final objectives in objectivesByTask.values) {
      objectives.sort((left, right) => left.id.compareTo(right.id));
    }

    final states = await _readStates(profileId);
    final counts = await _readObjectiveCounts(profileId);
    final catalog = <String>{for (final task in tasks) task.id};
    final names = <String, String>{
      for (final task in tasks) task.id: task.name,
    };
    final views = <String, _QuestView>{
      for (final task in tasks) task.id: _viewOf(task),
    };
    final edges = _unmetEdges(views, states, catalog);
    final cycles = <String, List<String>?>{};

    return List.unmodifiable([
      for (final task in tasks)
        _buildStatus(
          task: task,
          playerLevel: profile.playerLevel,
          state: states[task.id] ?? QuestProgressState.notStarted,
          counts: counts[task.id] ?? const <String, int>{},
          objectives: objectivesByTask[task.id] ?? const <QuestObjective>[],
          view: views[task.id]!,
          names: names,
          catalog: catalog,
          states: states,
          cycle: cycles.putIfAbsent(task.id, () => _findCycle(task.id, edges)),
        ),
    ]);
  }

  /// The derived status of one quest, or `null` when it is not in the dataset.
  Future<QuestStatus?> status(String profileId, String questId) async {
    final all = await statuses(profileId);
    for (final status in all) {
      if (status.id == questId) {
        return status;
      }
    }
    return null;
  }

  /// Quests the profile can start now, in deterministic order.
  ///
  /// Only [QuestAvailability.available] quests are returned: not started, and
  /// every blocking requirement met.
  ///
  /// Without [sort] the order is "recommended":
  ///
  /// 1. minimum player level ascending (quests without a level last),
  /// 2. trader id ascending (missing last),
  /// 3. normalized name ascending,
  /// 4. quest id ascending.
  ///
  /// [sort] replaces the primary criterion; ties are still broken by
  /// normalized name and then quest id, and values missing from the sorted
  /// field stay last in both directions, like [QuestQuery]'s sort. The
  /// available view exposes level, trader, map and name.
  ///
  /// Trader loyalty/reputation advisories are included in each status's
  /// reasons but never remove a quest from this list.
  Future<List<QuestStatus>> availableQuests(
    String profileId, {
    QuestSort? sort,
  }) async {
    final all = await statuses(profileId);
    final available = [
      for (final status in all)
        if (status.isAvailable) status,
    ];
    available.sort(
      sort == null
          ? _compareAvailable
          : (left, right) => _compareBySort(left, right, sort),
    );
    return List.unmodifiable(available);
  }

  /// Preserved progress rows whose quest is no longer in the dataset.
  ///
  /// The rows are returned for a separate "unavailable upstream" list and are
  /// never used to satisfy prerequisites. Both quest-level and objective-level
  /// rows are grouped by quest id. Ordered by quest id.
  Future<List<OrphanedQuestProgress>> orphanedProgress(String profileId) async {
    await _requireProfile(profileId);

    final tasks = await _database.select(_database.tasks).get();
    final taskIds = <String>{for (final task in tasks) task.id};

    final questRows = await (_database.select(
      _database.questProgress,
    )..where((row) => row.profileId.equals(profileId))).get();
    final objectiveRows = await (_database.select(
      _database.objectiveProgress,
    )..where((row) => row.profileId.equals(profileId))).get();

    final orphanIds = <String>{
      for (final row in questRows)
        if (!taskIds.contains(row.questId)) row.questId,
      for (final row in objectiveRows)
        if (!taskIds.contains(row.questId)) row.questId,
    };
    final sorted = orphanIds.toList()..sort();

    return List.unmodifiable([
      for (final questId in sorted) _orphan(questId, questRows, objectiveRows),
    ]);
  }

  // -------------------------------------------------------------------------
  // Progress recording
  // -------------------------------------------------------------------------

  /// Records [state] for [questId] in [profileId].
  ///
  /// [QuestProgressState.notStarted] deletes the quest's state row (revert);
  /// the other states are upserted. Objective counts are never touched, so
  /// undoing a completion keeps the recorded progress. Availability is derived,
  /// so dependents lock or unlock immediately after this transaction commits.
  ///
  /// Throws [QuestProfileNotFoundError] for an unknown profile and
  /// [QuestNotFoundError] for a quest absent from the active dataset, including
  /// a quest scoped to another game mode.
  Future<void> setQuestState(
    String profileId,
    String questId,
    QuestProgressState state,
  ) {
    return _database.transaction(() async {
      final profile = await _requireProfile(profileId);
      final task = await _taskById(questId);
      if (task == null || !_taskVisibleInMode(task, profile.gameMode)) {
        throw QuestNotFoundError(questId);
      }

      final stored = state.storedValue;
      if (stored == null) {
        await (_database.delete(_database.questProgress)..where(
              (row) =>
                  row.profileId.equals(profileId) & row.questId.equals(questId),
            ))
            .go();
        return;
      }

      await _database
          .into(_database.questProgress)
          .insertOnConflictUpdate(
            QuestProgressCompanion.insert(
              profileId: profileId,
              questId: questId,
              state: stored,
              updatedAt: _now(),
            ),
          );
    });
  }

  /// Records [count] for one objective of [questId] in [profileId].
  ///
  /// [count] must be `>= 0` and `<=` the objective's required count. The first
  /// positive count on a quest with no state row also records the quest as
  /// in progress, in the same transaction; it never completes the quest. A
  /// quest recorded as completed keeps that state when a count changes, and the
  /// counts never change a completion on their own.
  ///
  /// Throws [QuestProfileNotFoundError], [QuestNotFoundError],
  /// [QuestObjectiveNotFoundError] or [QuestProgressValidationError]. A quest
  /// scoped to another game mode is treated as absent from the active dataset.
  Future<void> setObjectiveCount(
    String profileId,
    String questId,
    String objectiveId,
    int count,
  ) {
    return _database.transaction(() async {
      final profile = await _requireProfile(profileId);
      final task = await _taskById(questId);
      if (task == null || !_taskVisibleInMode(task, profile.gameMode)) {
        throw QuestNotFoundError(questId);
      }

      final objective =
          await (_database.select(_database.taskObjectives)..where(
                (row) =>
                    row.id.equals(objectiveId) & row.taskId.equals(questId),
              ))
              .getSingleOrNull();
      if (objective == null) {
        throw QuestObjectiveNotFoundError(questId, objectiveId);
      }

      final required = _requiredCountOf(objective);
      if (count < 0 || count > required) {
        throw QuestProgressValidationError(
          'Objective "$objectiveId" of quest "$questId" accepts 0..$required; '
          'got $count.',
        );
      }

      final now = _now();
      await _database
          .into(_database.objectiveProgress)
          .insertOnConflictUpdate(
            ObjectiveProgressCompanion.insert(
              profileId: profileId,
              questId: questId,
              objectiveId: objectiveId,
              count: Value(count),
              updatedAt: now,
            ),
          );

      if (count > 0) {
        final existing =
            await (_database.select(_database.questProgress)..where(
                  (row) =>
                      row.profileId.equals(profileId) &
                      row.questId.equals(questId),
                ))
                .getSingleOrNull();
        if (existing == null) {
          await _database
              .into(_database.questProgress)
              .insert(
                QuestProgressCompanion.insert(
                  profileId: profileId,
                  questId: questId,
                  state: QuestProgressState.inProgress.storedValue!,
                  updatedAt: now,
                ),
              );
        }
      }
    });
  }

  // -------------------------------------------------------------------------
  // Labels
  // -------------------------------------------------------------------------

  /// Display name for [traderId] from the local `traders` table.
  ///
  /// Falls back to the id when the trader dataset is absent or has no matching
  /// row, so a quest screen never hides the reference. Returns `null` only for
  /// a null or blank id, which means "no trader recorded".
  Future<String?> traderName(String? traderId) async {
    final id = _nonBlank(traderId);
    if (id == null) {
      return null;
    }
    final row = await (_database.select(
      _database.traders,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row?.name ?? id;
  }

  /// Display name for [mapId] from the local `maps` table.
  ///
  /// Falls back to the id when the map dataset is absent or has no matching
  /// row. Returns `null` only for a null or blank id.
  Future<String?> mapName(String? mapId) async {
    final id = _nonBlank(mapId);
    if (id == null) {
      return null;
    }
    final row = await (_database.select(
      _database.maps,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
    return row?.name ?? id;
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  DateTime _now() => _clock?.call() ?? DateTime.now();

  Future<Profile> _requireProfile(String profileId) async {
    final profile = await _profileByIdOrNull(profileId);
    if (profile == null) {
      throw QuestProfileNotFoundError(profileId);
    }
    return profile;
  }

  Future<Profile?> _profileByIdOrNull(String? profileId) async {
    final id = _nonBlank(profileId);
    if (id == null) {
      return null;
    }
    return (_database.select(
      _database.profiles,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  /// The game mode of a query's profile, or `null` when there is none.
  ///
  /// An unknown profile id deliberately reads as "no mode": the catalog query
  /// has always tolerated it and reports every row as not started. Only a real
  /// profile can scope a read.
  Future<String?> _profileGameMode(String? profileId) async =>
      (await _profileByIdOrNull(profileId))?.gameMode;

  /// Tasks visible in [gameMode], preserving the incoming order.
  List<Task> _visibleTasks(List<Task> tasks, String gameMode) => [
    for (final task in tasks)
      if (_taskVisibleInMode(task, gameMode)) task,
  ];

  bool _taskVisibleInMode(Task task, String gameMode) =>
      _payloadVisibleInMode(_decodePayload(task.payload), gameMode);

  /// Whether a task payload belongs to [gameMode].
  ///
  /// A missing, non-array or empty `gameMode` is mode-agnostic: old bundles and
  /// hand-written test records predate the field, and hiding every one of them
  /// would silently empty the catalog. An explicit list is authoritative; a
  /// malformed list is treated as unscoped rather than dropping the quest.
  static bool _payloadVisibleInMode(
    Map<String, Object?>? payload,
    String gameMode,
  ) {
    final raw = payload?['gameMode'];
    if (raw == null || raw is! List || raw.isEmpty) {
      return true;
    }
    final mode = _modeKey(gameMode);
    for (final entry in raw) {
      if (entry is String && _modeKey(entry) == mode) {
        return true;
      }
    }
    return false;
  }

  /// Case-insensitive spelling of a game mode, as stored and bundled.
  static String _modeKey(String value) => value.trim().toLowerCase();

  Future<Task?> _taskById(String id) {
    return (_database.select(
      _database.tasks,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  /// Display name from `traders`, without the id fallback used by the screen
  /// lookup: [QuestDetail.traderName] documents `null` when the dataset has no
  /// such trader, so the detail read model keeps that contract.
  /// Traders for the quest filter dropdown, ordered by display name.
  Future<List<QuestLabel>> traderLabels() async {
    final rows =
        await (_database.select(_database.traders)..orderBy([
              (row) => OrderingTerm.asc(row.name),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();
    return [for (final row in rows) QuestLabel(id: row.id, name: row.name)];
  }

  /// Maps for the quest filter dropdown, ordered by display name.
  Future<List<QuestLabel>> mapLabels() async {
    final rows =
        await (_database.select(_database.maps)..orderBy([
              (row) => OrderingTerm.asc(row.name),
              (row) => OrderingTerm.asc(row.id),
            ]))
            .get();
    return [for (final row in rows) QuestLabel(id: row.id, name: row.name)];
  }

  Future<String?> _traderName(String? traderId) async {
    if (traderId == null) {
      return null;
    }
    final row = await (_database.select(
      _database.traders,
    )..where((row) => row.id.equals(traderId))).getSingleOrNull();
    return row?.name;
  }

  /// Display name from `maps`; see [_traderName] for the null contract.
  Future<String?> _mapName(String? mapId) async {
    if (mapId == null) {
      return null;
    }
    final row = await (_database.select(
      _database.maps,
    )..where((row) => row.id.equals(mapId))).getSingleOrNull();
    return row?.name;
  }

  /// Quests whose `taskRequirements` include [questId], ordered by name then id.
  ///
  /// With [gameMode], unlock rows from another mode are omitted so a detail
  /// view never names a quest the active profile cannot see.
  Future<List<QuestUnlock>> _unlocksFor(
    String questId, {
    String? gameMode,
  }) async {
    final tasks = await _database.select(_database.tasks).get();
    final unlocks = <QuestUnlock>[];
    final normalized = <String, String>{};

    for (final task in tasks) {
      if (task.id == questId) {
        continue;
      }
      if (gameMode != null && !_taskVisibleInMode(task, gameMode)) {
        continue;
      }
      final view = _viewOf(task);
      for (final prerequisite in view.prerequisites) {
        if (prerequisite.taskId != questId) {
          continue;
        }
        unlocks.add(
          QuestUnlock(
            questId: task.id,
            name: task.name,
            requiredStatuses: prerequisite.requiredStatuses,
          ),
        );
        final payload = _decodePayload(task.payload);
        normalized[task.id] =
            _string(payload?['normalizedName']) ?? task.name.toLowerCase();
      }
    }

    unlocks.sort((left, right) {
      final byName = (normalized[left.questId] ?? left.name.toLowerCase())
          .compareTo(normalized[right.questId] ?? right.name.toLowerCase());
      return byName != 0 ? byName : left.questId.compareTo(right.questId);
    });
    return List.unmodifiable(unlocks);
  }

  Future<Map<String, QuestProgressState>> _readStates(String profileId) async {
    final rows = await (_database.select(
      _database.questProgress,
    )..where((row) => row.profileId.equals(profileId))).get();
    return {
      for (final row in rows)
        row.questId: QuestProgressState.fromStoredValue(row.state),
    };
  }

  Future<Map<String, Map<String, int>>> _readObjectiveCounts(
    String profileId,
  ) async {
    final rows = await (_database.select(
      _database.objectiveProgress,
    )..where((row) => row.profileId.equals(profileId))).get();
    final counts = <String, Map<String, int>>{};
    for (final row in rows) {
      (counts[row.questId] ??= <String, int>{})[row.objectiveId] = row.count < 0
          ? 0
          : row.count;
    }
    return counts;
  }

  QuestStatus _buildStatus({
    required Task task,
    required int playerLevel,
    required QuestProgressState state,
    required Map<String, int> counts,
    required List<QuestObjective> objectives,
    required _QuestView view,
    required Map<String, String> names,
    required Set<String> catalog,
    required Map<String, QuestProgressState> states,
    required List<String>? cycle,
  }) {
    final progress = <QuestObjectiveProgress>[
      for (final objective in objectives)
        QuestObjectiveProgress(
          objective: objective,
          count: counts[objective.id] ?? 0,
          satisfied: (counts[objective.id] ?? 0) >= objective.requiredCount,
        ),
    ];
    final objectivesSatisfied = progress
        .where((entry) => !entry.optional)
        .every((entry) => entry.satisfied);

    final reasons = <QuestLockReason>[
      for (final requirement in view.traderRequirements)
        TraderRequirementAdvisory(
          traderId: requirement.traderId,
          requirementType: requirement.requirementType,
          compareMethod: requirement.compareMethod,
          value: requirement.value,
        ),
    ];

    final QuestAvailability availability;
    if (state == QuestProgressState.completed) {
      availability = QuestAvailability.completed;
    } else if (state == QuestProgressState.inProgress) {
      availability = QuestAvailability.inProgress;
    } else {
      if (view.malformedMessage != null) {
        reasons.add(MalformedPrerequisite(message: view.malformedMessage!));
      }

      if (state == QuestProgressState.failed && !view.restartable) {
        reasons.add(QuestFailed(taskId: task.id));
      } else {
        final minPlayerLevel = task.minPlayerLevel;
        if (minPlayerLevel != null && playerLevel < minPlayerLevel) {
          reasons.add(
            PlayerLevelTooLow(
              requiredLevel: minPlayerLevel,
              playerLevel: playerLevel,
            ),
          );
        }

        for (final prerequisite in view.prerequisites) {
          final inDataset = catalog.contains(prerequisite.taskId);
          final actual =
              states[prerequisite.taskId] ?? QuestProgressState.notStarted;
          if (!inDataset || !prerequisite.isSatisfiedBy(actual)) {
            reasons.add(
              MissingPrerequisite(
                taskId: prerequisite.taskId,
                taskName: names[prerequisite.taskId],
                requiredStatuses: prerequisite.requiredStatuses,
                actualState: actual,
                prerequisiteInDataset: inDataset,
              ),
            );
          }
        }

        if (cycle != null) {
          reasons.add(PrerequisiteCycle(cycle: cycle));
        }
      }

      availability = reasons.any((reason) => reason.blocksStart)
          ? QuestAvailability.locked
          : QuestAvailability.available;
    }

    return QuestStatus(
      id: task.id,
      name: task.name,
      normalizedName:
          _string(_decodePayload(task.payload)?['normalizedName']) ??
          task.name.toLowerCase(),
      traderId: task.traderId,
      mapId: task.mapId,
      minPlayerLevel: task.minPlayerLevel,
      experience: task.experience,
      kappaRequired: task.kappaRequired,
      availability: availability,
      recordedState: state,
      reasons: List.unmodifiable(reasons),
      objectives: List.unmodifiable(progress),
      objectivesSatisfied: objectivesSatisfied,
    );
  }

  OrphanedQuestProgress _orphan(
    String questId,
    List<QuestProgressEntry> questRows,
    List<ObjectiveProgressEntry> objectiveRows,
  ) {
    QuestProgressEntry? questRow;
    DateTime? updatedAt;
    for (final row in questRows) {
      if (row.questId == questId) {
        questRow = row;
        updatedAt = _newest(updatedAt, row.updatedAt);
      }
    }

    final counts = <String, int>{};
    for (final row in objectiveRows) {
      if (row.questId != questId) {
        continue;
      }
      counts[row.objectiveId] = row.count < 0 ? 0 : row.count;
      updatedAt = _newest(updatedAt, row.updatedAt);
    }

    return OrphanedQuestProgress(
      questId: questId,
      state: QuestProgressState.fromStoredValue(questRow?.state),
      objectiveCounts: Map.unmodifiable(counts),
      updatedAt: updatedAt,
    );
  }

  static DateTime? _newest(DateTime? current, DateTime candidate) {
    if (current == null || candidate.isAfter(current)) {
      return candidate;
    }
    return current;
  }

  int _compareAvailable(QuestStatus left, QuestStatus right) {
    final byLevel = _compareNullableInt(
      left.minPlayerLevel,
      right.minPlayerLevel,
    );
    if (byLevel != 0) {
      return byLevel;
    }
    final byTrader = _compareNullableString(left.traderId, right.traderId);
    if (byTrader != 0) {
      return byTrader;
    }
    final byName = left.normalizedName.compareTo(right.normalizedName);
    return byName != 0 ? byName : left.id.compareTo(right.id);
  }

  /// One primary criterion followed by the same name/id tie-breakers as the
  /// catalog, with missing values last in both directions.
  static int _compareBySort(
    QuestStatus left,
    QuestStatus right,
    QuestSort sort,
  ) {
    final primary = switch (sort.field) {
      QuestSortField.name => _compareDirectionalString(
        left.normalizedName,
        right.normalizedName,
        sort.descending,
      ),
      QuestSortField.minPlayerLevel => _compareNullableDirectionalInt(
        left.minPlayerLevel,
        right.minPlayerLevel,
        sort.descending,
      ),
      QuestSortField.traderId => _compareNullableDirectionalString(
        left.traderId,
        right.traderId,
        sort.descending,
      ),
      QuestSortField.mapId => _compareNullableDirectionalString(
        left.mapId,
        right.mapId,
        sort.descending,
      ),
    };
    if (primary != 0) {
      return primary;
    }
    final byName = left.normalizedName.compareTo(right.normalizedName);
    return byName != 0 ? byName : left.id.compareTo(right.id);
  }

  static int _compareDirectionalString(
    String left,
    String right,
    bool descending,
  ) {
    final result = left.compareTo(right);
    return descending ? -result : result;
  }

  static int _compareNullableDirectionalInt(
    int? left,
    int? right,
    bool descending,
  ) {
    if (left == right) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    final result = left.compareTo(right);
    return descending ? -result : result;
  }

  static int _compareNullableDirectionalString(
    String? left,
    String? right,
    bool descending,
  ) {
    if (left == right) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    final result = left.compareTo(right);
    return descending ? -result : result;
  }

  static int _compareNullableInt(int? left, int? right) {
    if (left == right) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  }

  static int _compareNullableString(String? left, String? right) {
    if (left == right) {
      return 0;
    }
    if (left == null) {
      return 1;
    }
    if (right == null) {
      return -1;
    }
    return left.compareTo(right);
  }

  /// Required count with the same fallback as [QuestObjective.requiredCount].
  static int _requiredCountOf(TaskObjective row) {
    final payload = _decodePayload(row.payload);
    final count = row.count ?? _int(payload?['count']);
    final level = _int(payload?['level']);
    final required = count ?? level ?? 1;
    return required < 0 ? 0 : required;
  }

  /// Parses the task payload fields availability needs.
  _QuestView _viewOf(Task task) {
    final payload = _decodePayload(task.payload);
    if (payload == null) {
      return const _QuestView(
        prerequisites: [],
        traderRequirements: [],
        restartable: false,
        malformedMessage: 'the task payload is not a JSON object',
      );
    }

    final prerequisites = <QuestPrerequisite>[];
    String? malformedMessage;
    final raw = payload['taskRequirements'];
    if (raw != null) {
      if (raw is! List) {
        malformedMessage = 'taskRequirements is not an array';
      } else {
        for (var index = 0; index < raw.length; index++) {
          final prerequisite = QuestPrerequisite.fromMap(raw[index]);
          if (prerequisite == null) {
            malformedMessage ??= 'taskRequirements[$index] has no task id';
            continue;
          }
          prerequisites.add(prerequisite);
          if (!prerequisite.hasKnownStatuses) {
            malformedMessage ??=
                'taskRequirements[$index] has no recognized status';
          }
        }
      }
    }

    return _QuestView(
      prerequisites: List.unmodifiable(prerequisites),
      traderRequirements: QuestTraderRequirement.listFrom(
        payload['traderRequirements'],
      ),
      restartable: payload['restartable'] == true,
      malformedMessage: malformedMessage,
    );
  }

  /// Prerequisite edges that are currently unsatisfied.
  ///
  /// Cycle detection follows only unmet edges: a prerequisite the profile has
  /// already satisfied cannot make a dependent quest unstartable, so a cycle
  /// behind it is not a live problem. This also means an explicit manual
  /// completion breaks a data cycle instead of locking the rest forever.
  Map<String, List<String>> _unmetEdges(
    Map<String, _QuestView> views,
    Map<String, QuestProgressState> states,
    Set<String> catalog,
  ) {
    final edges = <String, List<String>>{};
    for (final entry in views.entries) {
      final unmet = <String>[];
      for (final prerequisite in entry.value.prerequisites) {
        if (!catalog.contains(prerequisite.taskId)) {
          continue;
        }
        final actual =
            states[prerequisite.taskId] ?? QuestProgressState.notStarted;
        if (!prerequisite.isSatisfiedBy(actual)) {
          unmet.add(prerequisite.taskId);
        }
      }
      unmet.sort();
      edges[entry.key] = List.unmodifiable(unmet);
    }
    return edges;
  }

  /// Returns a cycle reachable from [start] through unmet edges, or `null`.
  ///
  /// Iterative depth-first search with a grey/black marking, so a malformed
  /// graph always terminates: each node is entered at most once per call and
  /// the path list is the only recursion state.
  static List<String>? _findCycle(
    String start,
    Map<String, List<String>> edges,
  ) {
    final grey = <String>{};
    final black = <String>{};
    final path = <String>[];
    final stack = <_CycleFrame>[];

    void enter(String node) {
      grey.add(node);
      path.add(node);
      stack.add(_CycleFrame(node, edges[node] ?? const <String>[]));
    }

    enter(start);
    while (stack.isNotEmpty) {
      final frame = stack.last;
      if (frame.index >= frame.next.length) {
        black.add(frame.node);
        grey.remove(frame.node);
        path.removeLast();
        stack.removeLast();
        continue;
      }

      final node = frame.next[frame.index++];
      if (grey.contains(node)) {
        final startIndex = path.indexOf(node);
        return List.unmodifiable([...path.sublist(startIndex), node]);
      }
      if (black.contains(node)) {
        continue;
      }
      enter(node);
    }
    return null;
  }

  _QueryParts _buildParts(
    QuestQuery query,
    List<String> tokens, {
    String? gameMode,
  }) {
    final filters = query.filters;
    final profileId = _nonBlank(query.profileId);
    final where = _WhereBuilder();

    for (final token in tokens) {
      where.add('$_normalizedNameSql LIKE ?', Variable<String>('%$token%'));
    }

    if (gameMode != null) {
      // Mirrors _payloadVisibleInMode: a missing, non-array or empty list is
      // mode-agnostic; otherwise one entry must equal the profile's mode. The
      // CASE keeps a malformed payload readable instead of failing the query.
      where.add(
        r"CASE WHEN json_valid(tasks.payload) THEN "
        r"(json_type(tasks.payload, '$.gameMode') IS NULL "
        r"OR json_type(tasks.payload, '$.gameMode') <> 'array' "
        r"OR json_array_length(tasks.payload, '$.gameMode') = 0 "
        r"OR EXISTS (SELECT 1 FROM json_each(tasks.payload, '$.gameMode') "
        r'AS gameModeEntry WHERE lower(gameModeEntry.value) = ?)) '
        r'ELSE 1 END',
        Variable<String>(_modeKey(gameMode)),
      );
    }

    final traderId = _nonBlank(filters.traderId);
    if (traderId != null) {
      where.add('tasks.traderId = ?', Variable<String>(traderId));
    }

    final mapId = _nonBlank(filters.mapId);
    if (mapId != null) {
      where.add('tasks.mapId = ?', Variable<String>(mapId));
    }

    if (filters.minPlayerLevel != null) {
      where.add(
        'tasks.minPlayerLevel = ?',
        Variable<int>(filters.minPlayerLevel!),
      );
    }

    if (filters.maxPlayerLevel != null) {
      where.add(
        'tasks.minPlayerLevel IS NOT NULL AND tasks.minPlayerLevel <= ?',
        Variable<int>(filters.maxPlayerLevel!),
      );
    }

    final state = filters.state;
    if (state != null) {
      if (profileId == null) {
        // No profile means no progress row can exist, so only `notStarted`
        // matches. Other states deliberately match nothing.
        if (state != QuestProgressState.notStarted) {
          where.addRaw('1 = 0');
        }
      } else {
        switch (state) {
          case QuestProgressState.notStarted:
            where.addRaw(
              '(qp.state IS NULL OR qp.state NOT IN '
              "('in-progress', 'completed', 'failed'))",
            );
          case QuestProgressState.inProgress:
            where.addRaw("qp.state = 'in-progress'");
          case QuestProgressState.completed:
            where.addRaw("qp.state = 'completed'");
          case QuestProgressState.failed:
            where.addRaw("qp.state = 'failed'");
        }
      }
    }

    return _QueryParts(
      fromSql: profileId == null
          ? 'FROM tasks'
          : 'FROM tasks LEFT JOIN questProgress AS qp '
                'ON qp.questId = tasks.id AND qp.profileId = ?',
      whereSql: where.isEmpty ? '' : 'WHERE ${where.sql}',
      progressColumn: profileId == null
          ? 'NULL AS progressState'
          : 'qp.state AS progressState',
      variables: [
        if (profileId != null) Variable<String>(profileId),
        ...where.variables,
      ],
    );
  }

  QuestSummary _readSummary(QueryRow row) {
    return QuestSummary(
      id: row.read<String>('id'),
      name: row.read<String>('name'),
      traderId: row.readNullable<String>('traderId'),
      mapId: row.readNullable<String>('mapId'),
      minPlayerLevel: row.readNullable<int>('minPlayerLevel'),
      experience: row.readNullable<int>('experience'),
      kappaRequired: row.read<bool>('kappaRequired'),
      progressState: QuestProgressState.fromStoredValue(
        row.readNullable<String>('progressState'),
      ),
    );
  }

  String _orderBy(QuestSort? sort) {
    final effective = sort ?? const QuestSort(QuestSortField.name);
    final direction = effective.descending ? 'DESC' : 'ASC';
    const name = _normalizedNameSql;

    // `(column IS NULL) ASC` keeps missing values last in both directions.
    // Name and id always ascend as tie-breakers, so equal primary values render
    // in the same order on every page and in both directions.
    return switch (effective.field) {
      QuestSortField.name => '$name $direction, tasks.id ASC',
      QuestSortField.minPlayerLevel =>
        '(tasks.minPlayerLevel IS NULL) ASC, '
            'tasks.minPlayerLevel $direction, $name ASC, tasks.id ASC',
      QuestSortField.traderId =>
        '(tasks.traderId IS NULL) ASC, '
            'tasks.traderId $direction, $name ASC, tasks.id ASC',
      QuestSortField.mapId =>
        '(tasks.mapId IS NULL) ASC, '
            'tasks.mapId $direction, $name ASC, tasks.id ASC',
    };
  }
}

/// The fields of one task payload the availability engine reads.
final class _QuestView {
  const _QuestView({
    required this.prerequisites,
    required this.traderRequirements,
    required this.restartable,
    required this.malformedMessage,
  });

  final List<QuestPrerequisite> prerequisites;
  final List<QuestTraderRequirement> traderRequirements;
  final bool restartable;
  final String? malformedMessage;
}

/// One node in the iterative cycle search.
final class _CycleFrame {
  _CycleFrame(this.node, this.next);

  final String node;
  final List<String> next;
  int index = 0;
}

/// The `FROM … WHERE …` fragment shared by the count and page queries.
final class _QueryParts {
  const _QueryParts({
    required this.fromSql,
    required this.whereSql,
    required this.progressColumn,
    required this.variables,
  });

  final String fromSql;
  final String whereSql;

  /// The selected `progressState` expression, or `NULL` without a profile.
  final String progressColumn;

  final List<Variable<Object>> variables;
}

/// Builds the `WHERE` fragment and its positional variables in one pass, so
/// the SQL text and the variable order cannot drift apart.
final class _WhereBuilder {
  final List<String> _clauses = <String>[];
  final List<Variable<Object>> variables = <Variable<Object>>[];

  bool get isEmpty => _clauses.isEmpty;

  String get sql => _clauses.join(' AND ');

  void add(String clause, Variable<Object> value) {
    _clauses.add(clause);
    variables.add(value);
  }

  void addRaw(String clause) => _clauses.add(clause);
}

String? _nonBlank(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}

Map<String, Object?>? _decodePayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
    if (decoded is Map) {
      return {
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
  } on FormatException {
    return null;
  }
  return null;
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;
