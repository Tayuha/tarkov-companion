import 'dart:convert';
import 'dart:io';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

/// Creates a temporary directory removed when the test finishes.
Directory createLogTempDir(void Function(void Function()) addTearDown) {
  final directory = Directory.systemTemp.createTempSync('tarkov_logs_');
  addTearDown(() {
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  });
  return directory;
}

/// Parses every non-empty line of [file] as a JSON object.
List<Map<String, Object?>> readJsonLines(File file) {
  final text = file.readAsStringSync();
  return [
    for (final line in const LineSplitter().convert(text))
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, Object?>,
  ];
}

/// A [LogSink] that records every write in memory.
class MemoryLogSink implements LogSink {
  final List<LogRecord> records = [];
  var closed = false;

  @override
  Future<void> write(LogRecord record) async {
    records.add(record);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

/// A [LogSink] that fails every write, optionally after an async gap.
final class FailingLogSink implements LogSink {
  FailingLogSink({this.async = false});

  /// When true, the failure surfaces as a rejected future instead of a throw.
  final bool async;

  var attempts = 0;

  @override
  Future<void> write(LogRecord record) {
    attempts++;
    if (async) {
      return Future<void>.error(StateError('sink is broken'));
    }
    throw StateError('sink is broken');
  }

  @override
  Future<void> close() async {}
}

/// A message padded to a predictable UTF-8 size for rotation tests.
String paddedMessage(String label, {int padding = 280}) =>
    '$label ${'x' * padding}';
