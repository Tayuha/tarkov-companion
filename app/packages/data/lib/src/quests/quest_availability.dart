/// Derived quest availability and objective progress.
///
/// Availability is **never stored**: it is computed from the active profile's
/// recorded quest state, objective counts, the profile's player level and the
/// quest's prerequisites in the current dataset. Marking a quest complete (or
/// reverting it) therefore changes every dependent quest on the next read with
/// no cache to invalidate.
///
/// A [QuestStatus] is the unit the catalog, the available-quests view and the
/// detail screen consume. Lock reasons are structured so the UI can name the
/// exact unmet requirement instead of rendering a generic "locked" badge.
library;

import 'quest_detail.dart';
import 'quest_query.dart';

/// The four availability states the tracker presents.
enum QuestAvailability {
  /// One or more blocking requirements are unmet.
  locked,

  /// Not started and every blocking requirement is met.
  available,

  /// The profile recorded the quest as in progress.
  inProgress,

  /// The profile recorded the quest as completed.
  completed;

  bool get isLocked => this == QuestAvailability.locked;
  bool get isAvailable => this == QuestAvailability.available;
  bool get isInProgress => this == QuestAvailability.inProgress;
  bool get isCompleted => this == QuestAvailability.completed;
}

/// Why a quest is reported as locked, or why the tracker cannot fully judge it.
///
/// [blocksStart] distinguishes a real gate from a reason that is only reported:
/// trader loyalty/reputation requirements are advisories because the schema has
/// no local value to compare against (see `docs/quest-engine.md`).
sealed class QuestLockReason {
  const QuestLockReason();

  /// Whether this reason prevents the quest from being available.
  bool get blocksStart;

  /// A short, display-ready explanation.
  String get description;
}

/// A prerequisite quest has not reached one of the statuses it requires.
final class MissingPrerequisite extends QuestLockReason {
  const MissingPrerequisite({
    required this.taskId,
    required this.taskName,
    required this.requiredStatuses,
    required this.actualState,
    required this.prerequisiteInDataset,
  });

  final String taskId;

  /// Name from the current dataset, or `null` when the quest is missing.
  final String? taskName;

  final List<String> requiredStatuses;
  final QuestProgressState actualState;

  /// Whether the prerequisite still exists in the active dataset.
  ///
  /// A missing prerequisite is never satisfied by an orphaned progress row:
  /// such rows are preserved but excluded from dependency math.
  final bool prerequisiteInDataset;

  @override
  bool get blocksStart => true;

  @override
  String get description {
    final name = taskName ?? taskId;
    if (!prerequisiteInDataset) {
      return 'Prerequisite quest "$name" is missing from the current dataset.';
    }
    final required = requiredStatuses.isEmpty
        ? 'a recorded status'
        : requiredStatuses.join(' or ');
    if (actualState == QuestProgressState.notStarted) {
      return 'Prerequisite quest "$name" must be $required.';
    }
    return 'Prerequisite quest "$name" must be $required; '
        'it is ${actualState.name}.';
  }
}

/// The profile's player level is below the quest's minimum.
final class PlayerLevelTooLow extends QuestLockReason {
  const PlayerLevelTooLow({
    required this.requiredLevel,
    required this.playerLevel,
  });

  final int requiredLevel;
  final int playerLevel;

  @override
  bool get blocksStart => true;

  @override
  String get description =>
      'Requires player level $requiredLevel; the profile is level '
      '$playerLevel.';
}

/// The quest's prerequisite graph contains a cycle of unmet requirements.
final class PrerequisiteCycle extends QuestLockReason {
  const PrerequisiteCycle({required this.cycle});

  /// The cycle in traversal order; the first id is repeated at the end.
  final List<String> cycle;

  @override
  bool get blocksStart => true;

  @override
  String get description =>
      'Malformed prerequisite cycle: ${cycle.join(' -> ')}.';
}

/// A prerequisite entry cannot be interpreted.
final class MalformedPrerequisite extends QuestLockReason {
  const MalformedPrerequisite({required this.message});

  final String message;

  @override
  bool get blocksStart => true;

  @override
  String get description => 'Malformed prerequisite data: $message';
}

/// The quest is recorded as failed and upstream says it cannot be restarted.
final class QuestFailed extends QuestLockReason {
  const QuestFailed({required this.taskId});

  final String taskId;

  @override
  bool get blocksStart => true;

  @override
  String get description =>
      'The quest is recorded as failed and is not restartable.';
}

/// A trader loyalty/reputation requirement reported without blocking.
///
/// The local schema stores no trader loyalty or reputation value, so the
/// tracker cannot decide whether the requirement is met. Reporting it keeps the
/// information visible without guessing.
final class TraderRequirementAdvisory extends QuestLockReason {
  const TraderRequirementAdvisory({
    required this.traderId,
    required this.requirementType,
    required this.compareMethod,
    required this.value,
  });

  final String traderId;
  final String? requirementType;
  final String? compareMethod;
  final num? value;

  @override
  bool get blocksStart => false;

  @override
  String get description {
    final kind = requirementType == 'level'
        ? 'trader loyalty level'
        : requirementType == 'reputation'
        ? 'trader reputation'
        : 'trader requirement';
    final comparison = compareMethod ?? '>=';
    return 'Needs $kind $comparison ${value ?? '?'} with trader '
        '"$traderId"; not enforced locally (no loyalty data).';
  }
}

/// One objective plus the active profile's recorded count.
final class QuestObjectiveProgress {
  const QuestObjectiveProgress({
    required this.objective,
    required this.count,
    required this.satisfied,
  });

  final QuestObjective objective;

  /// Recorded count, clamped to `>= 0` when read.
  final int count;

  /// Whether the recorded count reaches [QuestObjectiveProgress.requiredCount].
  final bool satisfied;

  int get requiredCount => objective.requiredCount;
  bool get optional => objective.optional;

  /// Whether the objective is a required one that still blocks completion.
  bool get incompleteRequired => !optional && !satisfied;

  @override
  String toString() =>
      'QuestObjectiveProgress(${objective.id}, $count/${objective.requiredCount})';
}

/// The derived status of one quest for one profile.
final class QuestStatus {
  const QuestStatus({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.traderId,
    required this.mapId,
    required this.minPlayerLevel,
    required this.experience,
    required this.kappaRequired,
    required this.availability,
    required this.recordedState,
    required this.reasons,
    required this.objectives,
    required this.objectivesSatisfied,
  });

  final String id;
  final String name;

  /// The bundle's folded search/sort key.
  final String normalizedName;

  final String? traderId;
  final String? mapId;
  final int? minPlayerLevel;

  /// Experience reward, when upstream provides one.
  final int? experience;

  /// Whether the quest counts towards the Kappa container.
  final bool kappaRequired;

  final QuestAvailability availability;

  /// The state stored in `questProgress`, or [QuestProgressState.notStarted].
  final QuestProgressState recordedState;

  /// Every structured reason: blocking gates first-class and non-blocking
  /// advisories in the same list.
  final List<QuestLockReason> reasons;

  /// Progress for every objective, including optional ones.
  final List<QuestObjectiveProgress> objectives;

  /// Whether every **required** objective has reached its required count.
  final bool objectivesSatisfied;

  bool get isLocked => availability.isLocked;
  bool get isAvailable => availability.isAvailable;
  bool get isInProgress => availability.isInProgress;
  bool get isCompleted => availability.isCompleted;

  /// Reasons that actually gate the quest.
  List<QuestLockReason> get blockingReasons => [
    for (final reason in reasons)
      if (reason.blocksStart) reason,
  ];

  /// Reasons that are only reported (currently the trader advisory).
  List<QuestLockReason> get advisories => [
    for (final reason in reasons)
      if (!reason.blocksStart) reason,
  ];

  /// Whether the completion was recorded while required objectives were still
  /// unsatisfied (the explicit manual override).
  bool get manuallyCompleted =>
      recordedState == QuestProgressState.completed && !objectivesSatisfied;

  /// Whether every required objective is satisfied, so the quest can be
  /// reported complete without an override.
  bool get derivedCompletionReady => objectivesSatisfied;

  /// Whether the UI should offer "mark complete" for the current state.
  bool get canMarkComplete => !isCompleted && objectivesSatisfied;

  /// This status as a catalog row.
  ///
  /// The available-quests view renders the same table and compact rows as the
  /// catalog, so it needs a [QuestSummary]. Converting from the status keeps
  /// the derived availability separate: the summary only carries the recorded
  /// state, exactly like a catalog row read for the same profile.
  QuestSummary toSummary() => QuestSummary(
    id: id,
    name: name,
    traderId: traderId,
    mapId: mapId,
    minPlayerLevel: minPlayerLevel,
    experience: experience,
    kappaRequired: kappaRequired,
    progressState: recordedState,
  );

  @override
  String toString() =>
      'QuestStatus($id, ${availability.name}, ${reasons.length} reason(s))';
}

/// A quest progress row whose quest no longer exists in the active dataset.
///
/// The row is preserved and listed separately. It never participates in
/// prerequisite satisfaction because the current dataset cannot confirm the
/// quest or its objectives.
final class OrphanedQuestProgress {
  const OrphanedQuestProgress({
    required this.questId,
    required this.state,
    required this.objectiveCounts,
    required this.updatedAt,
  });

  final String questId;

  /// Recorded state; an unrecognized stored value reads as
  /// [QuestProgressState.notStarted], like the catalog does.
  final QuestProgressState state;

  /// Recorded counts for objective ids that belonged to the removed quest.
  final Map<String, int> objectiveCounts;

  /// The newest update among the preserved rows, when known.
  final DateTime? updatedAt;

  @override
  String toString() =>
      'OrphanedQuestProgress($questId, ${state.name}, '
      '${objectiveCounts.length} objective(s))';
}
