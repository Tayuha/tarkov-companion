import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:tarkov_companion_core/tarkov_companion_core.dart';

import '../bundle/canonical_json.dart';
import '../bundle/game_mode.dart';
import '../quests/quest_query.dart';

/// The stable `format` marker of a progress export.
const String progressFormat = 'tarkov-companion-progress';

/// The format version this client writes.
const int progressFormatVersion = 1;

/// The oldest format version this client can still read.
const int progressFormatMinVersion = 1;

/// Upper bound for a recorded player level in a progress file.
const int progressMaxPlayerLevel = 99;

/// Upper bound for one objective count in a progress file.
///
/// Objective counters are bounded by the quest dataset, but the dataset is
/// game data that may be absent on import. This generous ceiling rejects
/// corrupt integers without rejecting any real objective.
const int progressMaxObjectiveCount = 1000000;

/// The three persisted quest states; `not-started` is encoded by absence.
const Set<String> progressQuestStates = {'in-progress', 'completed', 'failed'};

/// A progress file could not be read or validated.
///
/// The import path throws this before writing anything. [code] is stable and
/// [message] is the sentence shown to the user; `docs/progress-format.md`
/// documents both for every code.
final class ProgressFormatException implements Exception {
  const ProgressFormatException(this.code, this.message, {this.path});

  final ProgressFormatErrorCode code;
  final String message;

  /// Dot-separated location inside the document, when one is known.
  final String? path;

  @override
  String toString() =>
      'ProgressFormatException(${code.name})'
      '${path == null ? '' : ' at $path'}: $message';
}

/// Why a progress file was refused.
enum ProgressFormatErrorCode {
  /// The file is not valid JSON, or the top level is not an object.
  malformedJson,

  /// The `format` marker is missing or is not [progressFormat].
  wrongFormat,

  /// `formatVersion` is newer than [progressFormatVersion].
  newerVersion,

  /// `formatVersion` is older than [progressFormatMinVersion] or unusable.
  unsupportedVersion,

  /// The checksum is missing, malformed, or does not match the contents.
  badChecksum,

  /// A field is out of its documented range or has the wrong type.
  invalidValue,
}

/// One recorded quest state in a progress export.
final class ProgressQuestEntry {
  const ProgressQuestEntry({required this.questId, required this.state});

  final String questId;
  final QuestProgressState state;

  Map<String, Object?> toJson() => {
    'questId': questId,
    'state': state.storedValue!,
  };

  @override
  bool operator ==(Object other) =>
      other is ProgressQuestEntry &&
      other.questId == questId &&
      other.state == state;

  @override
  int get hashCode => Object.hash(questId, state);
}

/// One recorded objective count in a progress export.
final class ProgressObjectiveEntry {
  const ProgressObjectiveEntry({
    required this.questId,
    required this.objectiveId,
    required this.count,
  });

  final String questId;
  final String objectiveId;
  final int count;

  Map<String, Object?> toJson() => {
    'questId': questId,
    'objectiveId': objectiveId,
    'count': count,
  };

  @override
  bool operator ==(Object other) =>
      other is ProgressObjectiveEntry &&
      other.questId == questId &&
      other.objectiveId == objectiveId &&
      other.count == count;

  @override
  int get hashCode => Object.hash(questId, objectiveId, count);
}

/// The portable part of one profile.
///
/// Device-local facts — the profile id, timestamps and absolute paths — are
/// deliberately absent, so a file can move between platforms without carrying
/// identifiers. The game mode is the identity an import uses.
final class ProgressProfileRecord {
  const ProgressProfileRecord({
    required this.gameMode,
    required this.playerLevel,
    this.quests = const [],
    this.objectives = const [],
  });

  final GameMode gameMode;
  final int playerLevel;
  final List<ProgressQuestEntry> quests;
  final List<ProgressObjectiveEntry> objectives;

  Map<String, Object?> toJson() => {
    'gameMode': gameMode.wireValue,
    'playerLevel': playerLevel,
    'quests': [for (final quest in quests) quest.toJson()],
    'objectives': [for (final objective in objectives) objective.toJson()],
  };
}

/// A decoded and validated progress export.
///
/// Constructing this type does not validate: [ProgressExportDocument.parse]
/// does. A writer builds one directly from database rows and
/// [ProgressExport.encode] computes the checksum over canonical JSON.
final class ProgressExportDocument {
  const ProgressExportDocument({
    required this.appVersion,
    required this.exportedAt,
    required this.profiles,
    this.format = progressFormat,
    this.formatVersion = progressFormatVersion,
  });

  /// Parse and validate a progress file.
  ///
  /// Validation order is: JSON shape, `format`, `formatVersion`, checksum, then
  /// every value range. Nothing is written by this method.
  factory ProgressExportDocument.parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.malformedJson,
        'The file is not a valid progress export: the JSON could not be '
        'parsed.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.malformedJson,
        'The file is not a valid progress export: the top level must be a '
        'JSON object.',
      );
    }

    final format = decoded['format'];
    if (format != progressFormat) {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.wrongFormat,
        'The file is not a valid progress export: the format marker is '
        'missing or unknown.',
        path: 'format',
      );
    }

    final rawVersion = decoded['formatVersion'];
    if (rawVersion is! int) {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: formatVersion must be an '
        'integer.',
        path: 'formatVersion',
      );
    }
    if (rawVersion > progressFormatVersion) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.newerVersion,
        'This progress file uses format version $rawVersion, but this app '
        'supports up to $progressFormatVersion. Update the app to import it.',
        path: 'formatVersion',
      );
    }
    if (rawVersion < progressFormatMinVersion) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.unsupportedVersion,
        'This progress file uses unsupported format version $rawVersion.',
        path: 'formatVersion',
      );
    }

    final checksum = decoded['checksum'];
    if (checksum is! String || !_checksumPattern.hasMatch(checksum)) {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.badChecksum,
        'The file is not a valid progress export: the checksum is missing or '
        'malformed.',
        path: 'checksum',
      );
    }
    final withoutChecksum = Map<String, Object?>.of(decoded)
      ..remove('checksum');
    final expected = checksumOf(withoutChecksum);
    if (checksum != expected) {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.badChecksum,
        'The file is not a valid progress export: the checksum does not match '
        'its contents.',
        path: 'checksum',
      );
    }

    final appVersion = decoded['appVersion'];
    if (appVersion is! String || appVersion.trim().isEmpty) {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: appVersion must be a '
        'non-empty string.',
        path: 'appVersion',
      );
    }

    final exportedAtRaw = decoded['exportedAt'];
    final exportedAt = exportedAtRaw is String
        ? DateTime.tryParse(exportedAtRaw)
        : null;
    if (exportedAt == null) {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: exportedAt must be an '
        'ISO-8601 timestamp.',
        path: 'exportedAt',
      );
    }

    final rawProfiles = decoded['profiles'];
    if (rawProfiles is! List || rawProfiles.isEmpty) {
      throw const ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: profiles must be a '
        'non-empty array.',
        path: 'profiles',
      );
    }
    if (rawProfiles.length > GameMode.values.length) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: profiles has '
        '${rawProfiles.length} entries, but at most ${GameMode.values.length} '
        'game modes exist.',
        path: 'profiles',
      );
    }

    final records = <ProgressProfileRecord>[];
    final seenModes = <String>{};
    for (var index = 0; index < rawProfiles.length; index++) {
      final record = _parseProfile(rawProfiles[index], index);
      if (!seenModes.add(record.gameMode.wireValue)) {
        throw ProgressFormatException(
          ProgressFormatErrorCode.invalidValue,
          'The file is not a valid progress export: duplicate profile for '
          'game mode "${record.gameMode.wireValue}".',
          path: 'profiles[$index].gameMode',
        );
      }
      records.add(record);
    }

    return ProgressExportDocument(
      appVersion: appVersion,
      exportedAt: exportedAt,
      profiles: List.unmodifiable(records),
    );
  }

  final String format;
  final int formatVersion;
  final String appVersion;
  final DateTime exportedAt;
  final List<ProgressProfileRecord> profiles;

  /// Total quest state rows in the file.
  int get questCount =>
      profiles.fold(0, (total, profile) => total + profile.quests.length);

  /// Total objective count rows in the file.
  int get objectiveCount =>
      profiles.fold(0, (total, profile) => total + profile.objectives.length);

  /// The document without its `checksum` key, in canonical key order.
  Map<String, Object?> toJsonWithoutChecksum() => {
    'format': format,
    'formatVersion': formatVersion,
    'appVersion': appVersion,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'profiles': [for (final profile in profiles) profile.toJson()],
  };

  /// The `sha256:` checksum of [toJsonWithoutChecksum].
  String get checksum => checksumOf(toJsonWithoutChecksum());

  /// The complete JSON document, with `checksum` included.
  Map<String, Object?> toJson() => {
    ...toJsonWithoutChecksum(),
    'checksum': checksum,
  };

  /// Canonical one-line JSON, the form the checksum is computed over.
  String get canonicalJson => canonicalJsonEncode(toJson());

  /// The canonical document without the checksum (what is hashed).
  String get checksumPayload => canonicalJsonEncode(toJsonWithoutChecksum());

  @override
  String toString() =>
      'ProgressExportDocument($format v$formatVersion, '
      '${profiles.length} profile(s), $questCount quest state(s), '
      '$objectiveCount objective count(s))';
}

/// A written export, ready to save or assert against a golden file.
final class ProgressExport {
  const ProgressExport({
    required this.document,
    required this.checksum,
    required this.json,
  });

  final ProgressExportDocument document;

  /// `sha256:` followed by 64 lowercase hex characters.
  final String checksum;

  /// Pretty-printed canonical JSON: stable key order and indentation.
  final String json;

  /// Writes [json] to [path] and returns the file.
  ///
  /// Missing parent directories are created. The write is a single UTF-8 file
  /// write with an explicit flush, so a reader that opens the file after this
  /// future completes sees the complete document.
  Future<File> writeTo(String path) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(json, flush: true);
    return file;
  }
}

/// The checksum string for a decoded JSON map.
///
/// The map's keys are sorted recursively by `canonicalJsonEncode`, so the same
/// data hashes identically regardless of key order in the input. The result is
/// `sha256:` plus lowercase hex.
String checksumOf(Map<String, Object?> withoutChecksum) {
  final digest = sha256.convert(
    utf8.encode(canonicalJsonEncode(withoutChecksum)),
  );
  return 'sha256:$digest';
}

/// Pretty prints a canonical JSON map without changing its key order.
///
/// `JsonEncoder.withIndent` preserves insertion order, and the input came from
/// `canonicalJsonEncode`, so the file is diff-stable.
String prettyCanonicalJson(Map<String, Object?> value) {
  return const JsonEncoder.withIndent('  ').convert(value);
}

final RegExp _checksumPattern = RegExp(r'^sha256:[0-9a-f]{64}$');

ProgressProfileRecord _parseProfile(Object? raw, int index) {
  final path = 'profiles[$index]';
  if (raw is! Map<String, Object?>) {
    throw ProgressFormatException(
      ProgressFormatErrorCode.invalidValue,
      'The file is not a valid progress export: each profile must be an '
      'object.',
      path: path,
    );
  }

  final rawMode = raw['gameMode'];
  final mode = rawMode is String ? GameMode.parse(rawMode) : null;
  if (mode == null || mode is! Ok<GameMode>) {
    throw ProgressFormatException(
      ProgressFormatErrorCode.invalidValue,
      'The file is not a valid progress export: gameMode must be one of '
      '${GameMode.values.map((mode) => mode.wireValue).join(', ')}.',
      path: '$path.gameMode',
    );
  }

  final level = raw['playerLevel'];
  if (level is! int || level < 1 || level > progressMaxPlayerLevel) {
    throw ProgressFormatException(
      ProgressFormatErrorCode.invalidValue,
      'The file is not a valid progress export: playerLevel must be between '
      '1 and $progressMaxPlayerLevel.',
      path: '$path.playerLevel',
    );
  }

  final rawQuests = raw['quests'];
  if (rawQuests is! List) {
    throw ProgressFormatException(
      ProgressFormatErrorCode.invalidValue,
      'The file is not a valid progress export: quests must be an array.',
      path: '$path.quests',
    );
  }
  final quests = <ProgressQuestEntry>[];
  final seenQuests = <String>{};
  for (var questIndex = 0; questIndex < rawQuests.length; questIndex++) {
    final questPath = '$path.quests[$questIndex]';
    final entry = rawQuests[questIndex];
    if (entry is! Map<String, Object?>) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: each quest entry must be '
        'an object.',
        path: questPath,
      );
    }
    final questId = entry['questId'];
    if (questId is! String || questId.trim().isEmpty) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: questId must be a non-empty '
        'string.',
        path: '$questPath.questId',
      );
    }
    final state = entry['state'];
    if (state is! String || !progressQuestStates.contains(state)) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: state must be one of '
        '${progressQuestStates.join(', ')}.',
        path: '$questPath.state',
      );
    }
    if (!seenQuests.add(questId)) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: duplicate quest "$questId".',
        path: '$questPath.questId',
      );
    }
    quests.add(
      ProgressQuestEntry(
        questId: questId,
        state: QuestProgressState.fromStoredValue(state),
      ),
    );
  }

  final rawObjectives = raw['objectives'];
  if (rawObjectives is! List) {
    throw ProgressFormatException(
      ProgressFormatErrorCode.invalidValue,
      'The file is not a valid progress export: objectives must be an array.',
      path: '$path.objectives',
    );
  }
  final objectives = <ProgressObjectiveEntry>[];
  final seenObjectives = <String>{};
  for (
    var objectiveIndex = 0;
    objectiveIndex < rawObjectives.length;
    objectiveIndex++
  ) {
    final objectivePath = '$path.objectives[$objectiveIndex]';
    final entry = rawObjectives[objectiveIndex];
    if (entry is! Map<String, Object?>) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: each objective entry must '
        'be an object.',
        path: objectivePath,
      );
    }
    final questId = entry['questId'];
    if (questId is! String || questId.trim().isEmpty) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: questId must be a non-empty '
        'string.',
        path: '$objectivePath.questId',
      );
    }
    final objectiveId = entry['objectiveId'];
    if (objectiveId is! String || objectiveId.trim().isEmpty) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: objectiveId must be a '
        'non-empty string.',
        path: '$objectivePath.objectiveId',
      );
    }
    final count = entry['count'];
    if (count is! int || count < 0 || count > progressMaxObjectiveCount) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: count must be an integer '
        'between 0 and $progressMaxObjectiveCount.',
        path: '$objectivePath.count',
      );
    }
    final key = '$questId\u0000$objectiveId';
    if (!seenObjectives.add(key)) {
      throw ProgressFormatException(
        ProgressFormatErrorCode.invalidValue,
        'The file is not a valid progress export: duplicate objective '
        '"$objectiveId" for quest "$questId".',
        path: '$objectivePath.objectiveId',
      );
    }
    objectives.add(
      ProgressObjectiveEntry(
        questId: questId,
        objectiveId: objectiveId,
        count: count,
      ),
    );
  }

  return ProgressProfileRecord(
    gameMode: mode.value,
    playerLevel: level,
    quests: List.unmodifiable(quests),
    objectives: List.unmodifiable(objectives),
  );
}
