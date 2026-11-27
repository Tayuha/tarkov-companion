import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart' show Value;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// Inserts a profile row with an explicit level.
Future<void> insertProfileRow(
  AppDatabase database, {
  required String id,
  required String gameMode,
  required DateTime now,
  int playerLevel = 1,
}) async {
  await database
      .into(database.profiles)
      .insert(
        ProfilesCompanion.insert(
          id: id,
          gameMode: gameMode,
          playerLevel: Value(playerLevel),
          createdAt: now,
          updatedAt: now,
        ),
      );
}

/// Inserts a task with only the fields quest availability reads.
Future<void> insertTask(
  AppDatabase database, {
  required String id,
  required String name,
  int? minPlayerLevel = 1,
}) async {
  await database.customStatement(
    'INSERT INTO tasks (id, name, minPlayerLevel, payload) VALUES (?, ?, ?, ?)',
    [
      id,
      name,
      minPlayerLevel,
      jsonEncode({'normalizedName': name.toLowerCase()}),
    ],
  );
}

Future<void> insertQuestState(
  AppDatabase database, {
  required String profileId,
  required String questId,
  required String state,
  required DateTime now,
}) async {
  await database
      .into(database.questProgress)
      .insert(
        QuestProgressCompanion.insert(
          profileId: profileId,
          questId: questId,
          state: state,
          updatedAt: now,
        ),
      );
}

Future<void> insertObjectiveCount(
  AppDatabase database, {
  required String profileId,
  required String questId,
  required String objectiveId,
  required int count,
  required DateTime now,
}) async {
  await database
      .into(database.objectiveProgress)
      .insert(
        ObjectiveProgressCompanion.insert(
          profileId: profileId,
          questId: questId,
          objectiveId: objectiveId,
          count: Value(count),
          updatedAt: now,
        ),
      );
}

/// Resolves a file under `packages/data/test` from the package URI.
Future<File> dataTestFile(String relativePath) async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:tarkov_companion_data/tarkov_companion_data.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Could not resolve the data package URI.');
  }
  return File.fromUri(libraryUri.resolve('../test/$relativePath'));
}

/// Whether the golden files should be rewritten.
bool get updateGoldens => Platform.environment['UPDATE_GOLDENS'] == '1';

/// Recursively reverses object key order, keeping values and array order.
///
/// Used to prove the checksum and parsing do not depend on the order keys
/// appear in the input text.
Object? reversedKeys(Object? value) {
  if (value is List) {
    return [for (final element in value) reversedKeys(element)];
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList().reversed.toList();
    return {for (final key in keys) key: reversedKeys(value[key])};
  }
  return value;
}
