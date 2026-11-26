import 'dart:convert';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// Stable ids used by the quest detail screen tests.
const qdProfileRegular = 'qd-profile-regular';
const qdProfilePve = 'qd-profile-pve';

const qdPrapor = 'qd-trader-prapor';
const qdCustoms = 'qd-map-customs';

const qdMainQuest = 'qd-main';
const qdPrereqQuest = 'qd-prereq';
const qdLevelLockedQuest = 'qd-level-locked';
const qdCycleAQuest = 'qd-cycle-a';
const qdCycleBQuest = 'qd-cycle-b';
const qdMalformedQuest = 'qd-malformed';
const qdAdvisoryQuest = 'qd-advisory';
const qdAvailableQuest = 'qd-available';
const qdDependentQuest = 'qd-dependent';
const qdCountQuest = 'qd-count';
const qdOverrideQuest = 'qd-override';
const qdRemovedQuest = 'qd-removed';
const qdMissingQuest = 'qd-not-in-dataset';

const qdObjectiveKill = 'qd-obj-kill';
const qdObjectiveGive = 'qd-obj-give';
const qdObjectiveOptional = 'qd-obj-optional';
const qdObjectiveCountA = 'qd-obj-count-a';
const qdObjectiveCountB = 'qd-obj-count-b';
const qdObjectiveOverride = 'qd-obj-override';
const qdObjectiveRemoved = 'qd-obj-removed';

const qdRewardItem = 'qd-item-reward';
const qdTurnInItem = 'qd-item-turnin';

const qdRewardItemName = 'Gold chain';
const qdTurnInItemName = 'Salewa first aid kit';

/// One hand-written task plus the objective rows the ingestor would split out.
final class _QuestSpec {
  const _QuestSpec({
    required this.id,
    required this.name,
    this.description,
    this.minPlayerLevel = 1,
    this.experience = 1000,
    this.kappaRequired = false,
    this.wikiLink,
    this.objectives = const [],
    this.taskRequirements = const [],
    this.traderRequirements = const [],
    this.finishRewards = const {},
    this.malformedRequirements = false,
  });

  final String id;
  final String name;
  final String? description;
  final int? minPlayerLevel;
  final int? experience;
  final bool kappaRequired;
  final String? wikiLink;
  final List<Map<String, Object?>> objectives;
  final List<Map<String, Object?>> taskRequirements;
  final List<Map<String, Object?>> traderRequirements;
  final Map<String, Object?> finishRewards;

  /// Writes `taskRequirements` as a string instead of an array.
  final bool malformedRequirements;
}

Map<String, Object?> _objective({
  required String id,
  required String type,
  required String description,
  int? count,
  bool optional = false,
  List<String> mapIds = const [],
  List<String> itemIds = const [],
  String? questItemId,
  List<String> targetNames = const [],
}) => {
  'id': id,
  'type': type,
  'description': description,
  'optional': optional,
  'count': ?count,
  if (mapIds.isNotEmpty) 'mapIds': mapIds,
  if (itemIds.isNotEmpty) 'itemIds': itemIds,
  'questItemId': ?questItemId,
  if (targetNames.isNotEmpty) 'targetNames': targetNames,
};

final _quests = <_QuestSpec>[
  _QuestSpec(
    id: qdMainQuest,
    name: 'Big Customer',
    description: 'A multi-step quest used by the detail screen tests.',
    minPlayerLevel: 10,
    experience: 5000,
    kappaRequired: true,
    wikiLink: 'https://escapefromtarkov.fandom.com/wiki/Big_Customer',
    taskRequirements: [
      {
        'taskId': qdPrereqQuest,
        'status': ['complete'],
      },
    ],
    objectives: [
      _objective(
        id: qdObjectiveKill,
        type: 'shoot',
        description: 'Eliminate Scavs on Customs',
        count: 5,
        mapIds: [qdCustoms],
        targetNames: ['Scav'],
      ),
      _objective(
        id: qdObjectiveGive,
        type: 'giveItem',
        description: 'Hand over a Salewa first aid kit',
        count: 2,
        itemIds: [qdTurnInItem],
      ),
      _objective(
        id: qdObjectiveOptional,
        type: 'visit',
        description: 'Optional: visit the dormitory',
        optional: true,
        mapIds: [qdCustoms],
      ),
    ],
    finishRewards: {
      'items': [
        {'itemId': qdRewardItem, 'count': 2},
      ],
      'traderStanding': [
        {'traderId': qdPrapor, 'standing': 0.1},
      ],
      'skillLevelReward': [
        {'skill': 'Strength', 'level': 1},
      ],
      'achievementIds': <String>[],
      'craftUnlock': <Object?>[],
      'customization': <Object?>[],
      'locationUnlockIds': <String>[],
      'offerUnlock': <Object?>[],
      'traderDialogueUnlockIds': <String>[],
      'traderUnlockIds': <String>[],
    },
  ),
  _QuestSpec(
    id: qdPrereqQuest,
    name: 'First Job',
    objectives: [
      _objective(
        id: 'qd-obj-prereq',
        type: 'visit',
        description: 'Visit Customs',
        mapIds: [qdCustoms],
      ),
    ],
  ),
  _QuestSpec(
    id: qdLevelLockedQuest,
    name: 'High Roller',
    minPlayerLevel: 50,
    experience: 20000,
  ),
  _QuestSpec(
    id: qdCycleAQuest,
    name: 'Cycle A',
    taskRequirements: [
      {
        'taskId': qdCycleBQuest,
        'status': ['complete'],
      },
    ],
  ),
  _QuestSpec(
    id: qdCycleBQuest,
    name: 'Cycle B',
    taskRequirements: [
      {
        'taskId': qdCycleAQuest,
        'status': ['complete'],
      },
    ],
  ),
  _QuestSpec(
    id: qdMalformedQuest,
    name: 'Malformed Data',
    malformedRequirements: true,
  ),
  _QuestSpec(
    id: qdAdvisoryQuest,
    name: 'Loyalty Check',
    traderRequirements: [
      {
        'id': 'qd-req-loyalty',
        'traderId': qdPrapor,
        'requirementType': 'level',
        'compareMethod': '>=',
        'value': 4,
      },
    ],
  ),
  _QuestSpec(id: qdAvailableQuest, name: 'Fresh Start'),
  _QuestSpec(
    id: qdDependentQuest,
    name: 'Follow Up',
    taskRequirements: [
      {
        'taskId': qdAvailableQuest,
        'status': ['complete'],
      },
    ],
  ),
  _QuestSpec(
    id: qdCountQuest,
    name: 'Counting Kills',
    objectives: [
      _objective(
        id: qdObjectiveCountA,
        type: 'shoot',
        description: 'Kill Scavs',
        count: 3,
        targetNames: ['Scav'],
      ),
      _objective(
        id: qdObjectiveCountB,
        type: 'shoot',
        description: 'Kill PMCs',
        count: 2,
        targetNames: ['PMC'],
      ),
    ],
  ),
  _QuestSpec(
    id: qdOverrideQuest,
    name: 'Override Trial',
    objectives: [
      _objective(
        id: qdObjectiveOverride,
        type: 'findItem',
        description: 'Find two gold chains',
        count: 2,
        itemIds: [qdRewardItem],
      ),
    ],
  ),
];

const _regularProgress = <String, String>{qdRemovedQuest: 'in-progress'};

const _pveProgress = <String, String>{
  qdPrereqQuest: 'completed',
  qdCountQuest: 'in-progress',
};

const _pveCounts = <(String, String, int)>[
  (qdCountQuest, qdObjectiveCountA, 1),
];

const _regularCounts = <(String, String, int)>[
  (qdRemovedQuest, qdObjectiveRemoved, 2),
];

/// Opens an in-memory database with two profiles, the detail quests, traders,
/// maps, catalog items and recorded progress.
Future<AppDatabase> openQuestDetailFixtureDatabase() async {
  final database = AppDatabase.memory();
  await database.customSelect('SELECT 1').get(); // Force `beforeOpen`.
  await seedQuestDetailFixture(database);
  return database;
}

/// Inserts the fixture with the same raw SQL shape ingestion writes.
Future<void> seedQuestDetailFixture(AppDatabase database) async {
  final now = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;

  for (final (id, mode, level) in [
    (qdProfileRegular, 'regular', 10),
    (qdProfilePve, 'pve', 15),
  ]) {
    await database.customStatement(
      'INSERT INTO profiles (id, gameMode, playerLevel, createdAt, updatedAt) '
      'VALUES (?, ?, ?, ?, ?)',
      [id, mode, level, now, now],
    );
  }

  await database.customStatement(
    'INSERT INTO traders (id, name, normalizedName, payload) '
    'VALUES (?, ?, ?, ?)',
    [
      qdPrapor,
      'Prapor',
      'prapor',
      jsonEncode({'id': qdPrapor, 'name': 'Prapor'}),
    ],
  );
  await database.customStatement(
    'INSERT INTO maps (id, name, normalizedName, payload) '
    'VALUES (?, ?, ?, ?)',
    [
      qdCustoms,
      'Customs',
      'customs',
      jsonEncode({'id': qdCustoms, 'name': 'Customs'}),
    ],
  );

  for (final item in [
    (qdRewardItem, qdRewardItemName, 'Gold chain'),
    (qdTurnInItem, qdTurnInItemName, 'Salewa'),
  ]) {
    final (id, name, shortName) = item;
    await database.customStatement(
      'INSERT INTO items (id, name, shortName, normalizedName, payload) '
      'VALUES (?, ?, ?, ?, ?)',
      [
        id,
        name,
        shortName,
        name.toLowerCase(),
        jsonEncode({
          'id': id,
          'kind': 'item',
          'name': name,
          'shortName': shortName,
          'types': <String>[],
        }),
      ],
    );
  }

  for (final quest in _quests) {
    final payload = <String, Object?>{
      'id': quest.id,
      'kind': 'task',
      'name': quest.name,
      'normalizedName': quest.name.toLowerCase(),
      'description': ?quest.description,
      'traderId': qdPrapor,
      'mapId': qdCustoms,
      'minPlayerLevel': quest.minPlayerLevel,
      'experience': quest.experience,
      'kappaRequired': quest.kappaRequired,
      'restartable': false,
      'lightkeeperRequired': false,
      'wikiLink': ?quest.wikiLink,
      'objectives': quest.objectives,
      'taskRequirements': quest.malformedRequirements
          ? 'not-an-array'
          : quest.taskRequirements,
      'traderRequirements': quest.traderRequirements,
      'finishRewards': quest.finishRewards,
    };

    await database.customStatement(
      'INSERT INTO tasks ('
      'id, name, traderId, mapId, minPlayerLevel, experience, kappaRequired, '
      'payload'
      ') VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [
        quest.id,
        quest.name,
        qdPrapor,
        qdCustoms,
        quest.minPlayerLevel,
        quest.experience,
        quest.kappaRequired ? 1 : 0,
        jsonEncode(payload),
      ],
    );

    for (final objective in quest.objectives) {
      await database.customStatement(
        'INSERT INTO taskObjectives (id, taskId, type, description, count, '
        'payload) VALUES (?, ?, ?, ?, ?, ?)',
        [
          objective['id'],
          quest.id,
          objective['type'],
          objective['description'],
          objective['count'],
          jsonEncode(objective),
        ],
      );
    }
  }

  for (final entry in _regularProgress.entries) {
    await database.customStatement(
      'INSERT INTO questProgress (profileId, questId, state, updatedAt) '
      'VALUES (?, ?, ?, ?)',
      [qdProfileRegular, entry.key, entry.value, now],
    );
  }
  for (final entry in _pveProgress.entries) {
    await database.customStatement(
      'INSERT INTO questProgress (profileId, questId, state, updatedAt) '
      'VALUES (?, ?, ?, ?)',
      [qdProfilePve, entry.key, entry.value, now],
    );
  }
  for (final (questId, objectiveId, count) in _regularCounts) {
    await database.customStatement(
      'INSERT INTO objectiveProgress ('
      'profileId, questId, objectiveId, count, updatedAt'
      ') VALUES (?, ?, ?, ?, ?)',
      [qdProfileRegular, questId, objectiveId, count, now],
    );
  }
  for (final (questId, objectiveId, count) in _pveCounts) {
    await database.customStatement(
      'INSERT INTO objectiveProgress ('
      'profileId, questId, objectiveId, count, updatedAt'
      ') VALUES (?, ?, ?, ?, ?)',
      [qdProfilePve, questId, objectiveId, count, now],
    );
  }
}
