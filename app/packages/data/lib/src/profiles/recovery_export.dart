import 'dart:convert';
import 'dart:io';

import 'package:tarkov_companion_core/tarkov_companion_core.dart';

import '../bundle/game_mode.dart';
import '../database/migration_runner.dart';
import '../quests/quest_query.dart';
import 'progress_format.dart';

/// Recovery found no profile row it could turn into a progress export.
///
/// The progress format requires at least one profile, so this is a typed
/// outcome rather than an empty document: the caller can explain what was
/// unreadable without writing a file that would fail its own parser.
final class NoRecoveryProfilesError implements Exception {
  const NoRecoveryProfilesError(this.reasons);

  /// One sentence per reason the profile set was empty or unreadable.
  final List<String> reasons;

  @override
  String toString() =>
      'NoRecoveryProfilesError: '
      '${reasons.isEmpty ? 'there is no profile to export' : reasons.join(' ')}';
}

/// How faithfully a recovery export represents the on-disk rows.
///
/// [skippedRows] counts rows that were dropped because they could not be
/// represented (an unknown quest state, a blank id, an unknown game mode or a
/// duplicate). [normalizedRows] counts rows that were kept after clamping a
/// level or count into the format's documented range. [warnings] holds one
/// human-readable sentence per condition, for the screen and the log.
final class RecoveryExportDiagnostics {
  const RecoveryExportDiagnostics({
    this.skippedRows = 0,
    this.normalizedRows = 0,
    this.warnings = const [],
  });

  final int skippedRows;
  final int normalizedRows;
  final List<String> warnings;

  /// Whether the export is an exact copy of every readable row.
  bool get isExact => skippedRows == 0 && normalizedRows == 0;
}

/// A recovery export in memory, before it is written anywhere.
final class RecoveryProgressExport {
  const RecoveryProgressExport({
    required this.export,
    required this.diagnostics,
  });

  final ProgressExport export;
  final RecoveryExportDiagnostics diagnostics;
}

/// A recovery export written to a file.
final class RecoveryProgressFile {
  const RecoveryProgressFile({
    required this.export,
    required this.diagnostics,
    required this.file,
  });

  final ProgressExport export;
  final RecoveryExportDiagnostics diagnostics;
  final File file;
}

/// Builds the same [ProgressExport] as [ProgressExportWriter] from a
/// read-only [RecoveryDatabase].
///
/// Nothing on this path writes to SQLite: every read goes through
/// [RecoveryDatabase.select], which runs on the existing `OpenMode.readOnly`
/// handle. The caller must not open the database a second time.
///
/// Rows are sorted (game mode wire value, then ids) so repeated exports of the
/// same file are byte-identical for a fixed clock. Facts that cannot be
/// represented are handled instead of aborting the export: an unknown quest
/// state, a blank id, an unknown mode or a duplicate profile/quest/objective is
/// skipped and counted; a player level or objective count outside the format's
/// range is clamped and counted. Tables that cannot be read are treated as
/// empty and reported in [RecoveryExportDiagnostics.warnings].
final class RecoveryProgressExporter {
  RecoveryProgressExporter(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final RecoveryDatabase _database;
  final DateTime Function() _clock;

  /// Builds the document and its canonical, pretty JSON without writing.
  ///
  /// [exportedAt] defaults to the injected clock and is always stored in UTC.
  RecoveryProgressExport build({
    required String appVersion,
    DateTime? exportedAt,
  }) {
    final diagnostics = _Diagnostics();
    final profileRows = _readTable(
      'profiles',
      'SELECT id, gameMode, playerLevel FROM profiles',
      diagnostics,
    );

    final profiles = <_ProfileRows>[];
    final seenModes = <String>{};
    for (final row in _sortedProfiles(profileRows)) {
      final id = _nonEmptyString(row['id']);
      if (id == null) {
        diagnostics.skip('profiles: a row has no readable id');
        continue;
      }
      final rawMode = row['gameMode'];
      final parsedMode = rawMode is String ? GameMode.parse(rawMode) : null;
      if (parsedMode is! Ok<GameMode>) {
        diagnostics.skip('profiles: "$id" has an unknown game mode');
        continue;
      }
      final mode = parsedMode.value;
      if (!seenModes.add(mode.wireValue)) {
        diagnostics.skip(
          'profiles: duplicate profile for game mode "${mode.wireValue}"',
        );
        continue;
      }
      final rawLevel = row['playerLevel'];
      var level = rawLevel is int ? rawLevel : 1;
      if (level < 1 || level > progressMaxPlayerLevel) {
        level = level.clamp(1, progressMaxPlayerLevel);
        diagnostics.normalize('profiles: "$id" player level clamped to $level');
      }
      profiles.add(_ProfileRows(id: id, mode: mode, playerLevel: level));
    }

    if (profiles.isEmpty) {
      throw NoRecoveryProfilesError(
        diagnostics.warnings.isEmpty
            ? const ['No profile rows were found in the database.']
            : diagnostics.warnings,
      );
    }

    final byId = {for (final profile in profiles) profile.id: profile};

    _readQuests(byId, diagnostics);
    _readObjectives(byId, diagnostics);

    final records = <ProgressProfileRecord>[
      for (final profile in profiles)
        ProgressProfileRecord(
          gameMode: profile.mode,
          playerLevel: profile.playerLevel,
          quests: List.unmodifiable(profile.quests),
          objectives: List.unmodifiable(profile.objectives),
        ),
    ];

    final document = ProgressExportDocument(
      appVersion: appVersion,
      exportedAt: (exportedAt ?? _clock()).toUtc(),
      profiles: List.unmodifiable(records),
    );
    final canonical =
        jsonDecode(document.canonicalJson) as Map<String, Object?>;

    return RecoveryProgressExport(
      export: ProgressExport(
        document: document,
        checksum: document.checksum,
        json: '${prettyCanonicalJson(canonical)}\n',
      ),
      diagnostics: diagnostics.snapshot(),
    );
  }

  /// Builds the export and writes it into [directory].
  ///
  /// The file is named `progress-recovery-<UTC timestamp>.json`. Missing
  /// directories are created; a name collision gets a `-1`, `-2`, ... suffix
  /// rather than overwriting an earlier export.
  Future<RecoveryProgressFile> writeTo({
    required String appVersion,
    required Directory directory,
    DateTime? exportedAt,
  }) async {
    final built = build(appVersion: appVersion, exportedAt: exportedAt);
    final timestamp = built.export.document.exportedAt;
    final file = await _writeUnique(directory, timestamp, built.export.json);
    return RecoveryProgressFile(
      export: built.export,
      diagnostics: built.diagnostics,
      file: file,
    );
  }

  List<Map<String, Object?>> _readTable(
    String name,
    String sql,
    _Diagnostics diagnostics,
  ) {
    try {
      return _database.select(sql);
    } on Object catch (error) {
      diagnostics.warn('The $name table could not be read: $error');
      return const [];
    }
  }

  void _readQuests(Map<String, _ProfileRows> byId, _Diagnostics diagnostics) {
    final rows = _readTable(
      'questProgress',
      'SELECT profileId, questId, state FROM questProgress',
      diagnostics,
    );
    for (final row in rows) {
      final profile = _profileOf(row, byId, diagnostics, 'questProgress');
      if (profile == null) continue;
      final questId = _nonEmptyString(row['questId']);
      if (questId == null) {
        diagnostics.skip('questProgress: a row has no readable quest id');
        continue;
      }
      final state = _stateOf(row['state']);
      if (state == null) {
        diagnostics.skip(
          'questProgress: "$questId" has an unknown state '
          '"${row['state']}"',
        );
        continue;
      }
      if (!profile.questIds.add(questId)) {
        diagnostics.skip('questProgress: duplicate quest "$questId"');
        continue;
      }
      profile.quests.add(ProgressQuestEntry(questId: questId, state: state));
    }
    for (final profile in byId.values) {
      profile.quests.sort(
        (left, right) => left.questId.compareTo(right.questId),
      );
    }
  }

  void _readObjectives(
    Map<String, _ProfileRows> byId,
    _Diagnostics diagnostics,
  ) {
    final rows = _readTable(
      'objectiveProgress',
      'SELECT profileId, questId, objectiveId, count FROM objectiveProgress',
      diagnostics,
    );
    for (final row in rows) {
      final profile = _profileOf(row, byId, diagnostics, 'objectiveProgress');
      if (profile == null) continue;
      final questId = _nonEmptyString(row['questId']);
      final objectiveId = _nonEmptyString(row['objectiveId']);
      if (questId == null || objectiveId == null) {
        diagnostics.skip(
          'objectiveProgress: a row has no readable quest or objective id',
        );
        continue;
      }
      final rawCount = row['count'];
      if (rawCount is! int) {
        diagnostics.skip(
          'objectiveProgress: "$objectiveId" has a non-integer count',
        );
        continue;
      }
      var count = rawCount;
      if (count < 0 || count > progressMaxObjectiveCount) {
        count = count.clamp(0, progressMaxObjectiveCount);
        diagnostics.normalize(
          'objectiveProgress: "$objectiveId" count clamped to $count',
        );
      }
      if (!profile.objectiveKeys.add('$questId\u0000$objectiveId')) {
        diagnostics.skip(
          'objectiveProgress: duplicate objective "$objectiveId" for quest '
          '"$questId"',
        );
        continue;
      }
      profile.objectives.add(
        ProgressObjectiveEntry(
          questId: questId,
          objectiveId: objectiveId,
          count: count,
        ),
      );
    }
    for (final profile in byId.values) {
      profile.objectives.sort((left, right) {
        final byQuest = left.questId.compareTo(right.questId);
        return byQuest != 0
            ? byQuest
            : left.objectiveId.compareTo(right.objectiveId);
      });
    }
  }

  _ProfileRows? _profileOf(
    Map<String, Object?> row,
    Map<String, _ProfileRows> byId,
    _Diagnostics diagnostics,
    String table,
  ) {
    final profileId = row['profileId'];
    final profile = profileId is String ? byId[profileId] : null;
    if (profile == null) {
      diagnostics.skip(
        '$table: a row refers to a profile that was not readable',
      );
    }
    return profile;
  }
}

/// The first copied diagnostics file and every log file that was copied.
final class RecoveryDiagnosticsCopy {
  const RecoveryDiagnosticsCopy({
    required this.directory,
    required this.backup,
    required this.logFiles,
  });

  /// The directory the files were copied into.
  final Directory directory;

  /// The copied pre-migration backup, or `null` when none was available.
  final File? backup;

  /// The copied log files, sorted by rotation index.
  final List<File> logFiles;

  /// Whether there was nothing to copy.
  bool get isEmpty => backup == null && logFiles.isEmpty;

  /// Number of files that were copied.
  int get copiedFileCount => (backup == null ? 0 : 1) + logFiles.length;
}

/// Copies the pre-migration backup and the current log files into [directory].
///
/// This uses only the filesystem: it does not read or write the database and
/// does not open a socket. The [backup] file is optional because a failure can
/// happen before a backup was taken. Missing or unreadable files are skipped;
/// an empty result means there was nothing to collect.
Future<RecoveryDiagnosticsCopy> exportRecoveryDiagnostics({
  required Directory directory,
  required Directory logsDirectory,
  File? backup,
}) async {
  await directory.create(recursive: true);

  File? copiedBackup;
  if (backup != null && await backup.exists()) {
    try {
      copiedBackup = await _copyInto(directory, backup);
    } on FileSystemException {
      copiedBackup = null;
    }
  }

  final logFiles = <File>[];
  if (await logsDirectory.exists()) {
    final candidates = <File>[];
    await for (final entity in logsDirectory.list(followLinks: false)) {
      if (entity is File && _logFilePattern.hasMatch(_baseName(entity.path))) {
        candidates.add(entity);
      }
    }
    candidates.sort((left, right) {
      final leftIndex = _rotationIndex(_baseName(left.path));
      final rightIndex = _rotationIndex(_baseName(right.path));
      return leftIndex.compareTo(rightIndex);
    });
    for (final file in candidates) {
      try {
        logFiles.add(await _copyInto(directory, file));
      } on FileSystemException {
        // Rotation can remove a file between listing and copying.
        continue;
      }
    }
  }

  return RecoveryDiagnosticsCopy(
    directory: directory,
    backup: copiedBackup,
    logFiles: List.unmodifiable(logFiles),
  );
}

/// `progress-recovery-20261127T120000.123456Z.json`
String recoveryProgressFileName(DateTime exportedAt) =>
    'progress-recovery-${_compactTimestamp(exportedAt)}.json';

Future<File> _writeUnique(
  Directory directory,
  DateTime timestamp,
  String contents,
) async {
  await directory.create(recursive: true);
  var target = File(
    '${directory.path}${Platform.pathSeparator}'
    '${recoveryProgressFileName(timestamp)}',
  );
  var suffix = 1;
  while (await target.exists()) {
    final name = recoveryProgressFileName(timestamp);
    final dot = name.lastIndexOf('.');
    target = File(
      '${directory.path}${Platform.pathSeparator}'
      '${name.substring(0, dot)}-$suffix${name.substring(dot)}',
    );
    suffix++;
  }
  await target.writeAsString(contents, flush: true);
  return target;
}

Future<File> _copyInto(Directory directory, File source) async {
  final name = _baseName(source.path);
  var target = File('${directory.path}${Platform.pathSeparator}$name');
  final dot = name.lastIndexOf('.');
  var suffix = 1;
  while (await target.exists()) {
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    target = File(
      '${directory.path}${Platform.pathSeparator}$stem-$suffix$extension',
    );
    suffix++;
  }
  return source.copy(target.path);
}

List<Map<String, Object?>> _sortedProfiles(List<Map<String, Object?>> rows) {
  final sorted = List<Map<String, Object?>>.of(rows);
  sorted.sort((left, right) {
    final byMode = '${left['gameMode']}'.compareTo('${right['gameMode']}');
    return byMode != 0 ? byMode : '${left['id']}'.compareTo('${right['id']}');
  });
  return sorted;
}

String? _nonEmptyString(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return value;
}

QuestProgressState? _stateOf(Object? stored) => switch (stored) {
  'in-progress' => QuestProgressState.inProgress,
  'completed' => QuestProgressState.completed,
  'failed' => QuestProgressState.failed,
  _ => null,
};

String _baseName(String path) => path.split(Platform.pathSeparator).last;

final RegExp _logFilePattern = RegExp(r'^app(?:\.(\d+))?\.log$');

int _rotationIndex(String name) {
  final match = _logFilePattern.firstMatch(name);
  final raw = match?.group(1);
  return raw == null ? 0 : int.parse(raw);
}

String _compactTimestamp(DateTime time) {
  final utc = time.toUtc();
  String two(int value) => value.toString().padLeft(2, '0');
  final micros = utc.millisecond * 1000 + utc.microsecond;
  return '${utc.year.toString().padLeft(4, '0')}'
      '${two(utc.month)}${two(utc.day)}T'
      '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}.'
      '${micros.toString().padLeft(6, '0')}Z';
}

final class _ProfileRows {
  _ProfileRows({
    required this.id,
    required this.mode,
    required this.playerLevel,
  });

  final String id;
  final GameMode mode;
  final int playerLevel;
  final List<ProgressQuestEntry> quests = [];
  final List<ProgressObjectiveEntry> objectives = [];
  final Set<String> questIds = {};
  final Set<String> objectiveKeys = {};
}

final class _Diagnostics {
  var _skipped = 0;
  var _normalized = 0;
  final List<String> _warnings = [];

  void skip(String reason) {
    _skipped++;
    warn(reason);
  }

  void normalize(String reason) {
    _normalized++;
    warn(reason);
  }

  void warn(String reason) {
    _warnings.add(reason);
  }

  List<String> get warnings => List.unmodifiable(_warnings);

  RecoveryExportDiagnostics snapshot() => RecoveryExportDiagnostics(
    skippedRows: _skipped,
    normalizedRows: _normalized,
    warnings: List.unmodifiable(_warnings),
  );
}
