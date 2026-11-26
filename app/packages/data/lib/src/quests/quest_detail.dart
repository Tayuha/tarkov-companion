/// Read models for one quest's catalog detail.
///
/// A [QuestDetail] is built from the canonical `task` bundle record: the
/// columns the catalog queries and the `payload` that keeps every field the
/// pipeline published. It never exposes a drift row, so the quest screen can
/// render objectives, requirements, rewards and unlocks without knowing the
/// local schema.
///
/// The models are read-only and deliberately tolerant: an upstream field that
/// is missing or has an unexpected type is treated as absent instead of
/// throwing. The ingestion layer already rejects a malformed bundle, so this is
/// defence for a hand-written or partially migrated row.
library;

import 'quest_query.dart';

/// Everything the quest detail view renders for one quest.
final class QuestDetail {
  const QuestDetail({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.description,
    required this.traderId,
    required this.traderName,
    required this.mapId,
    required this.mapName,
    required this.minPlayerLevel,
    required this.experience,
    required this.kappaRequired,
    required this.restartable,
    required this.lightkeeperRequired,
    required this.wikiLink,
    required this.taskImageLink,
    required this.objectives,
    required this.prerequisites,
    required this.traderRequirements,
    required this.rewards,
    required this.unlocks,
  });

  /// Builds a detail from a decoded task payload and its split-out rows.
  ///
  /// [objectives] come from `taskObjectives` and [unlocks] from the reverse
  /// `taskRequirements` scan, because neither is part of this record alone.
  factory QuestDetail.fromTaskRecord({
    required String id,
    required String name,
    required Map<String, Object?> payload,
    required String? traderId,
    required String? traderName,
    required String? mapId,
    required String? mapName,
    required int? minPlayerLevel,
    required int? experience,
    required bool kappaRequired,
    required List<QuestObjective> objectives,
    required List<QuestUnlock> unlocks,
  }) {
    final normalizedName = _string(payload['normalizedName']) ?? name;
    return QuestDetail(
      id: id,
      name: name,
      normalizedName: normalizedName,
      description: _string(payload['description']),
      traderId: traderId,
      traderName: traderName,
      mapId: mapId,
      mapName: mapName,
      minPlayerLevel: minPlayerLevel,
      experience: experience,
      kappaRequired: kappaRequired,
      restartable: payload['restartable'] == true,
      lightkeeperRequired: payload['lightkeeperRequired'] == true,
      wikiLink: _string(payload['wikiLink']),
      taskImageLink: _string(payload['taskImageLink']),
      objectives: List.unmodifiable(objectives),
      prerequisites: QuestPrerequisite.listFrom(payload['taskRequirements']),
      traderRequirements: QuestTraderRequirement.listFrom(
        payload['traderRequirements'],
      ),
      rewards: QuestRewards.fromPayload(payload['finishRewards']),
      unlocks: List.unmodifiable(unlocks),
    );
  }

  final String id;
  final String name;

  /// The bundle's case- and diacritic-folded search key.
  final String normalizedName;

  /// Quest description, when upstream publishes one.
  final String? description;

  final String? traderId;

  /// Trader display name from the local `traders` table, when available.
  final String? traderName;

  final String? mapId;

  /// Map display name from the local `maps` table, when available.
  final String? mapName;

  final int? minPlayerLevel;
  final int? experience;
  final bool kappaRequired;
  final bool restartable;
  final bool lightkeeperRequired;

  final String? wikiLink;
  final String? taskImageLink;

  final List<QuestObjective> objectives;
  final List<QuestPrerequisite> prerequisites;
  final List<QuestTraderRequirement> traderRequirements;
  final QuestRewards rewards;

  /// Quests in the current dataset whose requirements name this quest.
  final List<QuestUnlock> unlocks;
}

/// One objective as the detail view and the progress tracker read it.
final class QuestObjective {
  const QuestObjective({
    required this.id,
    required this.type,
    required this.description,
    required this.requiredCount,
    required this.countable,
    required this.optional,
    required this.mapIds,
    required this.itemIds,
    required this.questItemId,
    required this.traderIds,
    required this.taskId,
    required this.stationId,
    required this.skill,
    required this.targetNames,
    required this.requiredKeyItemIds,
    required this.level,
    required this.stationLevel,
    required this.payload,
  });

  /// Builds an objective from its canonical payload.
  ///
  /// [type], [description] and [count] are the split-out table columns and are
  /// used only when the payload omits them, so a hand-written row still reads.
  factory QuestObjective.fromPayload(
    Map<String, Object?> payload, {
    String? type,
    String? description,
    int? count,
  }) {
    final rawCount = _int(payload['count']) ?? count;
    final level = _int(payload['level']);
    final required = rawCount ?? level ?? 1;
    return QuestObjective(
      id: _string(payload['id']) ?? '',
      type: _string(payload['type']) ?? type ?? '',
      description: _string(payload['description']) ?? description ?? '',
      requiredCount: required < 0 ? 0 : required,
      countable: rawCount != null,
      optional: payload['optional'] == true,
      mapIds: _strings(payload['mapIds']),
      itemIds: _strings(payload['itemIds']),
      questItemId: _string(payload['questItemId']),
      traderIds: _strings(payload['traderIds']),
      taskId: _string(payload['taskId']),
      stationId: _string(payload['stationId']),
      skill: _string(payload['skill']),
      targetNames: _strings(payload['targetNames']),
      requiredKeyItemIds: _strings(payload['requiredKeyItemIds']),
      level: level,
      stationLevel: _int(payload['stationLevel']),
      payload: Map.unmodifiable(payload),
    );
  }

  final String id;
  final String type;
  final String description;

  /// The number of steps needed to satisfy the objective.
  ///
  /// `count` from the bundle, else the objective's `level` (skill/trader
  /// level), else `1` for a binary objective. Never negative.
  final int requiredCount;

  /// Whether the bundle published an explicit `count` for this objective.
  final bool countable;

  /// Optional objectives are tracked but never gate quest completion.
  final bool optional;

  final List<String> mapIds;
  final List<String> itemIds;
  final String? questItemId;
  final List<String> traderIds;
  final String? taskId;
  final String? stationId;
  final String? skill;
  final List<String> targetNames;
  final List<String> requiredKeyItemIds;
  final int? level;
  final int? stationLevel;

  /// The complete objective record; kept for fields this model does not type.
  final Map<String, Object?> payload;

  @override
  String toString() => 'QuestObjective($id, $type, $requiredCount)';
}

/// One `taskStatus` requirement on the quest.
///
/// `requiredStatuses` is the upstream list verbatim: `complete`, `active` or
/// `failed`. The list is a disjunction, so `["active", "complete"]` accepts
/// either recorded state.
final class QuestPrerequisite {
  const QuestPrerequisite({
    required this.taskId,
    required this.requiredStatuses,
    this.notes,
  });

  /// The upstream status names the quest recognizes.
  static const Set<String> knownStatuses = {'complete', 'active', 'failed'};

  /// Reads one `taskRequirements[]` entry; `null` when it has no quest id.
  static QuestPrerequisite? fromMap(Object? value) {
    final map = _map(value);
    if (map == null) {
      return null;
    }
    final taskId = _string(map['taskId']);
    if (taskId == null || taskId.isEmpty) {
      return null;
    }
    return QuestPrerequisite(
      taskId: taskId,
      requiredStatuses: _strings(map['status']),
      notes: _string(map['notes']),
    );
  }

  /// Every valid entry of a `taskRequirements` payload value.
  static List<QuestPrerequisite> listFrom(Object? value) {
    if (value is! List) {
      return const [];
    }
    final result = <QuestPrerequisite>[];
    for (final entry in value) {
      final prerequisite = QuestPrerequisite.fromMap(entry);
      if (prerequisite != null) {
        result.add(prerequisite);
      }
    }
    return List.unmodifiable(result);
  }

  final String taskId;
  final List<String> requiredStatuses;
  final String? notes;

  /// Whether the list is non-empty and every name is recognized.
  bool get hasKnownStatuses =>
      requiredStatuses.isNotEmpty &&
      requiredStatuses.every(knownStatuses.contains);

  /// Whether [state] satisfies any accepted status.
  bool isSatisfiedBy(QuestProgressState state) {
    if (state == QuestProgressState.notStarted) {
      return false;
    }
    return requiredStatuses.any((status) => _stateForStatus(status) == state);
  }

  @override
  String toString() =>
      'QuestPrerequisite($taskId, ${requiredStatuses.join('|')})';
}

/// One `traderRequirements[]` entry: a loyalty level or reputation gate.
///
/// The local schema has no per-trader loyalty or reputation value, so the
/// availability engine reports these as non-blocking advisories. See
/// `docs/quest-engine.md`.
final class QuestTraderRequirement {
  const QuestTraderRequirement({
    required this.id,
    required this.traderId,
    required this.requirementType,
    required this.compareMethod,
    required this.value,
  });

  static QuestTraderRequirement? fromMap(Object? value) {
    final map = _map(value);
    if (map == null) {
      return null;
    }
    final traderId = _string(map['traderId']);
    if (traderId == null || traderId.isEmpty) {
      return null;
    }
    return QuestTraderRequirement(
      id: _string(map['id']),
      traderId: traderId,
      requirementType: _string(map['requirementType']),
      compareMethod: _string(map['compareMethod']),
      value: _num(map['value']),
    );
  }

  static List<QuestTraderRequirement> listFrom(Object? value) {
    if (value is! List) {
      return const [];
    }
    final result = <QuestTraderRequirement>[];
    for (final entry in value) {
      final requirement = QuestTraderRequirement.fromMap(entry);
      if (requirement != null) {
        result.add(requirement);
      }
    }
    return List.unmodifiable(result);
  }

  final String? id;
  final String traderId;

  /// `level` (loyalty level) or `reputation`, as published upstream.
  final String? requirementType;

  /// The upstream comparison, usually `>=`.
  final String? compareMethod;

  final num? value;

  /// Whether this is a trader loyalty level requirement.
  bool get isLoyaltyLevel => requirementType == 'level';

  @override
  String toString() =>
      'QuestTraderRequirement($traderId, $requirementType $compareMethod $value)';
}

/// A quest the current dataset says this quest unlocks.
final class QuestUnlock {
  const QuestUnlock({
    required this.questId,
    required this.name,
    required this.requiredStatuses,
  });

  final String questId;
  final String name;

  /// The statuses the unlocked quest accepts for this quest.
  final List<String> requiredStatuses;

  @override
  String toString() => 'QuestUnlock($questId, $name)';
}

/// The `finishRewards` block, minus the fields the tracker does not render.
final class QuestRewards {
  const QuestRewards({
    required this.items,
    required this.traderStanding,
    required this.skills,
    required this.achievementIds,
    required this.traderUnlockIds,
    required this.traderDialogueUnlockIds,
    required this.locationUnlockIds,
    required this.offerUnlocks,
    required this.craftUnlocks,
    required this.customizations,
  });

  /// No reward of any kind.
  static const QuestRewards empty = QuestRewards(
    items: [],
    traderStanding: [],
    skills: [],
    achievementIds: [],
    traderUnlockIds: [],
    traderDialogueUnlockIds: [],
    locationUnlockIds: [],
    offerUnlocks: [],
    craftUnlocks: [],
    customizations: [],
  );

  factory QuestRewards.fromPayload(Object? value) {
    final map = _map(value);
    if (map == null) {
      return empty;
    }

    final items = <QuestItemReward>[];
    for (final entry in _maps(map['items'])) {
      final itemId = _string(entry['itemId']);
      if (itemId != null) {
        items.add(
          QuestItemReward(itemId: itemId, count: _int(entry['count']) ?? 1),
        );
      }
    }

    final standing = <QuestStandingReward>[];
    for (final entry in _maps(map['traderStanding'])) {
      final traderId = _string(entry['traderId']);
      if (traderId != null) {
        standing.add(
          QuestStandingReward(
            traderId: traderId,
            standing: _num(entry['standing']) ?? 0,
          ),
        );
      }
    }

    final skills = <QuestSkillReward>[];
    for (final entry in _maps(map['skillLevelReward'])) {
      final skill = _string(entry['skill']);
      if (skill != null) {
        skills.add(
          QuestSkillReward(skill: skill, level: _int(entry['level']) ?? 1),
        );
      }
    }

    final offers = <QuestOfferUnlock>[];
    for (final entry in _maps(map['offerUnlock'])) {
      final id = _string(entry['id']);
      if (id != null) {
        offers.add(
          QuestOfferUnlock(
            id: id,
            itemId: _string(entry['itemId']),
            traderId: _string(entry['traderId']),
            level: _int(entry['level']),
          ),
        );
      }
    }

    final crafts = <QuestCraftUnlock>[];
    for (final entry in _maps(map['craftUnlock'])) {
      final stationId = _string(entry['stationId']);
      if (stationId != null) {
        crafts.add(
          QuestCraftUnlock(
            stationId: stationId,
            itemId: _string(entry['itemId']),
            level: _int(entry['level']),
            count: _int(entry['count']),
          ),
        );
      }
    }

    final customizations = <QuestCustomizationReward>[];
    for (final entry in _maps(map['customization'])) {
      final id = _string(entry['id']);
      if (id != null) {
        customizations.add(
          QuestCustomizationReward(
            id: id,
            name: _string(entry['name']),
            type: _string(entry['customizationType']),
          ),
        );
      }
    }

    return QuestRewards(
      items: List.unmodifiable(items),
      traderStanding: List.unmodifiable(standing),
      skills: List.unmodifiable(skills),
      achievementIds: _strings(map['achievementIds']),
      traderUnlockIds: _strings(map['traderUnlockIds']),
      traderDialogueUnlockIds: _strings(map['traderDialogueUnlockIds']),
      locationUnlockIds: _strings(map['locationUnlockIds']),
      offerUnlocks: List.unmodifiable(offers),
      craftUnlocks: List.unmodifiable(crafts),
      customizations: List.unmodifiable(customizations),
    );
  }

  final List<QuestItemReward> items;
  final List<QuestStandingReward> traderStanding;
  final List<QuestSkillReward> skills;
  final List<String> achievementIds;
  final List<String> traderUnlockIds;
  final List<String> traderDialogueUnlockIds;
  final List<String> locationUnlockIds;
  final List<QuestOfferUnlock> offerUnlocks;
  final List<QuestCraftUnlock> craftUnlocks;
  final List<QuestCustomizationReward> customizations;

  /// Whether any reward is present.
  bool get isEmpty =>
      items.isEmpty &&
      traderStanding.isEmpty &&
      skills.isEmpty &&
      achievementIds.isEmpty &&
      traderUnlockIds.isEmpty &&
      traderDialogueUnlockIds.isEmpty &&
      locationUnlockIds.isEmpty &&
      offerUnlocks.isEmpty &&
      craftUnlocks.isEmpty &&
      customizations.isEmpty;
}

/// A stack of an item granted on completion.
final class QuestItemReward {
  const QuestItemReward({required this.itemId, required this.count});

  final String itemId;
  final int count;
}

/// Trader standing granted (or removed) on completion.
final class QuestStandingReward {
  const QuestStandingReward({required this.traderId, required this.standing});

  final String traderId;
  final num standing;
}

/// A skill level granted on completion.
final class QuestSkillReward {
  const QuestSkillReward({required this.skill, required this.level});

  final String skill;
  final int level;
}

/// A trader offer unlocked on completion.
final class QuestOfferUnlock {
  const QuestOfferUnlock({
    required this.id,
    required this.itemId,
    required this.traderId,
    required this.level,
  });

  final String id;
  final String? itemId;
  final String? traderId;
  final int? level;
}

/// A hideout craft unlocked on completion.
final class QuestCraftUnlock {
  const QuestCraftUnlock({
    required this.stationId,
    required this.itemId,
    required this.level,
    required this.count,
  });

  final String stationId;
  final String? itemId;
  final int? level;
  final int? count;
}

/// A hideout customization granted on completion.
final class QuestCustomizationReward {
  const QuestCustomizationReward({
    required this.id,
    required this.name,
    required this.type,
  });

  final String id;
  final String? name;
  final String? type;
}

QuestProgressState? _stateForStatus(String status) => switch (status) {
  'complete' => QuestProgressState.completed,
  'active' => QuestProgressState.inProgress,
  'failed' => QuestProgressState.failed,
  _ => null,
};

Map<String, Object?>? _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }
  return null;
}

Iterable<Map<String, Object?>> _maps(Object? value) sync* {
  if (value is! List) {
    return;
  }
  for (final entry in value) {
    final map = _map(entry);
    if (map != null) {
      yield map;
    }
  }
}

String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is num ? value.toInt() : null;

num? _num(Object? value) => value is num ? value : null;

List<String> _strings(Object? value) {
  if (value is! List) {
    return const [];
  }
  final result = <String>[];
  for (final entry in value) {
    if (entry is String && entry.isNotEmpty) {
      result.add(entry);
    }
  }
  return List.unmodifiable(result);
}
