import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// The result of [exportLogs].
final class LogExportResult {
  /// Creates a result describing a written archive.
  const LogExportResult({
    required this.destination,
    required this.includedFiles,
    required this.exportedAt,
  });

  /// The archive that was written.
  final File destination;

  /// The log files that were readable and included, newest first.
  final List<File> includedFiles;

  /// The UTC time recorded in `metadata.json`.
  final DateTime exportedAt;

  /// Whether the archive contains no log file (only `metadata.json`).
  bool get hasNoLogs => includedFiles.isEmpty;
}

/// Writes a diagnostics ZIP for the log files in [logDir].
///
/// ## Archive layout
///
/// ```
/// logs/app.log
/// logs/app.1.log
/// ...
/// metadata.json
/// ```
///
/// `metadata.json` contains `format` (`tarkov-companion.logs`),
/// `formatVersion` (1), `exportedAt` (UTC ISO-8601), `appVersion` when
/// provided, and `logFiles` with the archive-relative names that were
/// included.
///
/// ## Local only
///
/// This function performs filesystem I/O and nothing else: it never opens a
/// socket, never uploads, and has no telemetry. The caller chooses
/// [destination] (the shell will use a platform file picker later), and the
/// archive is the only copy that leaves the device unless the user shares it.
///
/// A missing [logDir] and a log file that disappears mid-export are treated as
/// "no logs": the archive is still valid and still contains metadata, so a
/// support request can always produce a file.
///
/// [now] exists for deterministic tests; production callers omit it.
Future<LogExportResult> exportLogs({
  required Directory logDir,
  required File destination,
  String? appVersion,
  DateTime? now,
}) async {
  final exportedAt = (now ?? DateTime.now()).toUtc();
  final files = await _logFiles(logDir);

  final archive = Archive();
  final included = <File>[];
  final archiveNames = <String>[];

  for (final file in files) {
    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      // Rotation may have removed the file between listing and reading.
      continue;
    }
    final name = 'logs/${p.basename(file.path)}';
    archive.addFile(ArchiveFile.bytes(name, bytes));
    included.add(file);
    archiveNames.add(name);
  }

  final metadata = <String, Object?>{
    'format': 'tarkov-companion.logs',
    'formatVersion': 1,
    'exportedAt': exportedAt.toIso8601String(),
    'appVersion': ?appVersion,
    'logFiles': archiveNames,
  };
  final encoded = utf8.encode(
    const JsonEncoder.withIndent('  ').convert(metadata),
  );
  archive.addFile(ArchiveFile.bytes('metadata.json', encoded));

  final parent = destination.parent;
  if (!await parent.exists()) {
    await parent.create(recursive: true);
  }
  await destination.writeAsBytes(ZipEncoder().encode(archive), flush: true);

  return LogExportResult(
    destination: destination,
    includedFiles: List<File>.unmodifiable(included),
    exportedAt: exportedAt,
  );
}

/// Matches `app.log` and `app.<n>.log`, capturing the rotation index.
final _logFilePattern = RegExp(r'^app(?:\.(\d+))?\.log$');

/// Log files in [directory], newest first.
///
/// Sorting is by rotation index (`app.log` before `app.1.log`) rather than by
/// modification time, so the archive order is deterministic even when two
/// files share a coarse filesystem timestamp.
Future<List<File>> _logFiles(Directory directory) async {
  if (!await directory.exists()) {
    return const [];
  }

  final indexed = <(int, File)>[];
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    final match = _logFilePattern.firstMatch(p.basename(entity.path));
    if (match == null) {
      continue;
    }
    final rawIndex = match.group(1);
    indexed.add((rawIndex == null ? 0 : int.parse(rawIndex), entity));
  }

  indexed.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final entry in indexed) entry.$2];
}
