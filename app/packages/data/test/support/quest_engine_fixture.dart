import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import 'bundle_fixture.dart';

/// Builds one synthetic `task` record with the fields the quest engine reads.
///
/// The record is written in the same canonical shape the pipeline publishes, so
/// the production [DatasetIngestor] splits objectives out exactly as it does for
/// a real bundle.
Map<String, Object?> questRecord({
  required String id,
  required String name,
  int? minPlayerLevel = 0,
  String? traderId = 'trader-1',
  String? mapId,
  int? experience = 1000,
  bool kappaRequired = false,
  bool restartable = false,
  String? description,
  String? wikiLink,
  List<String>? gameMode,
  List<Map<String, Object?>> objectives = const [],
  List<Map<String, Object?>> taskRequirements = const [],
  List<Map<String, Object?>> traderRequirements = const [],
  Map<String, Object?>? finishRewards,
}) {
  return {
    'id': id,
    'kind': 'task',
    'name': name,
    'normalizedName': name.toLowerCase(),
    'description': ?description,
    'traderId': traderId,
    'mapId': mapId,
    'minPlayerLevel': minPlayerLevel,
    'experience': experience,
    'kappaRequired': kappaRequired,
    'restartable': restartable,
    'gameMode': ?gameMode,
    'wikiLink': ?wikiLink,
    'objectives': objectives,
    'taskRequirements': taskRequirements,
    'traderRequirements': traderRequirements,
    'finishRewards': finishRewards ?? emptyRewards,
  };
}

/// A `finishRewards` block with every collection empty.
const Map<String, Object?> emptyRewards = {
  'achievementIds': <Object?>[],
  'craftUnlock': <Object?>[],
  'customization': <Object?>[],
  'items': <Object?>[],
  'locationUnlockIds': <Object?>[],
  'offerUnlock': <Object?>[],
  'skillLevelReward': <Object?>[],
  'traderDialogueUnlockIds': <Object?>[],
  'traderStanding': <Object?>[],
  'traderUnlockIds': <Object?>[],
};

/// Builds one objective record.
///
/// [count] is omitted for a binary objective, matching the bundle. [level] is
/// used by skill/trader-level objectives that have no count.
Map<String, Object?> objectiveRecord({
  required String id,
  required String type,
  String description = 'Objective',
  int? count,
  int? level,
  bool optional = false,
  List<String> mapIds = const [],
  List<String> itemIds = const [],
  String? questItemId,
  List<String> traderIds = const [],
  String? taskId,
  String? stationId,
  String? skill,
  List<String> targetNames = const [],
  List<String> requiredKeyItemIds = const [],
}) {
  return {
    'id': id,
    'type': type,
    'description': description,
    'optional': optional,
    'count': ?count,
    'level': ?level,
    if (mapIds.isNotEmpty) 'mapIds': mapIds,
    if (itemIds.isNotEmpty) 'itemIds': itemIds,
    'questItemId': ?questItemId,
    if (traderIds.isNotEmpty) 'traderIds': traderIds,
    'taskId': ?taskId,
    'stationId': ?stationId,
    'skill': ?skill,
    if (targetNames.isNotEmpty) 'targetNames': targetNames,
    if (requiredKeyItemIds.isNotEmpty) 'requiredKeyItemIds': requiredKeyItemIds,
  };
}

/// A `taskRequirements` entry.
Map<String, Object?> requiresQuest(
  String taskId, {
  List<String> statuses = const ['complete'],
}) => {'taskId': taskId, 'status': statuses};

/// A `traderRequirements` entry.
Map<String, Object?> traderRequirement({
  String traderId = 'trader-1',
  String type = 'level',
  String compareMethod = '>=',
  num value = 4,
}) => {
  'id': 'requirement-$traderId-$type',
  'traderId': traderId,
  'requirementType': type,
  'compareMethod': compareMethod,
  'value': value,
};

/// Ingest [tasks] as the whole `tasks` dataset for the regular mode.
///
/// Ingestion replaces the previous task rows, so a test can remove a quest by
/// ingesting a smaller list and prove that player progress survives.
Future<void> ingestTasks(
  AppDatabase database,
  Directory directory,
  List<Map<String, Object?>> tasks,
) async {
  final dataset = writeSyntheticDataset(directory, DatasetKind.tasks, [
    for (final task in tasks) jsonEncode(task),
  ]);
  await DatasetIngestor(database).ingest(
    mode: GameMode.regular,
    dataset: dataset.dataset,
    compressedFile: dataset.file,
  );
}

/// Updates the player level recorded for [profileId].
Future<void> setPlayerLevel(
  AppDatabase database,
  String profileId,
  int level,
) async {
  await (database.update(database.profiles)
        ..where((row) => row.id.equals(profileId)))
      .write(ProfilesCompanion(playerLevel: Value(level)));
}
