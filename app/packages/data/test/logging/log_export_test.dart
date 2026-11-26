import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/logging_helpers.dart';

void main() {
  group('exportLogs', () {
    test('writes every log file plus metadata to a readable ZIP', () async {
      final root = createLogTempDir(addTearDown);
      final logDir = Directory(p.join(root.path, 'logs'));
      final sink = RotatingFileLogSink(
        directory: logDir,
        maxBytes: 512,
        maxFiles: 3,
      );
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      await logger.info(paddedMessage('older'));
      await logger.info(paddedMessage('newer'));

      // Not part of the diagnostics format and must not be exported.
      File(p.join(logDir.path, 'notes.txt')).writeAsStringSync('ignore me');

      final destination = File(
        p.join(root.path, 'export', 'tarkov-diagnostics.zip'),
      );
      final exportedAt = DateTime.utc(2026, 11, 26, 15);
      final result = await exportLogs(
        logDir: logDir,
        destination: destination,
        appVersion: '0.1.0',
        now: exportedAt,
      );

      expect(destination.existsSync(), isTrue);
      expect(result.destination.path, destination.path);
      expect(result.exportedAt, exportedAt);
      expect(result.hasNoLogs, isFalse);
      expect(result.includedFiles.map((file) => p.basename(file.path)), [
        'app.log',
        'app.1.log',
      ]);

      final archive = ZipDecoder().decodeBytes(
        destination.readAsBytesSync(),
        verify: true,
      );
      final names = archive.files.map((file) => file.name).toList()..sort();
      expect(names, ['logs/app.1.log', 'logs/app.log', 'metadata.json']);

      expect(
        _entry(archive, 'logs/app.log').content,
        File(p.join(logDir.path, 'app.log')).readAsBytesSync(),
      );
      expect(
        _entry(archive, 'logs/app.1.log').content,
        File(p.join(logDir.path, 'app.1.log')).readAsBytesSync(),
      );

      final metadata = jsonDecode(
        utf8.decode(_entry(archive, 'metadata.json').content),
      ) as Map<String, Object?>;
      expect(metadata['format'], 'tarkov-companion.logs');
      expect(metadata['formatVersion'], 1);
      expect(metadata['exportedAt'], '2026-11-26T15:00:00.000Z');
      expect(metadata['appVersion'], '0.1.0');
      expect(metadata['logFiles'], ['logs/app.log', 'logs/app.1.log']);
    });

    test('exports a valid archive when there are no logs', () async {
      final root = createLogTempDir(addTearDown);
      final logDir = Directory(p.join(root.path, 'missing', 'logs'));
      final destination = File(p.join(root.path, 'empty.zip'));

      final result = await exportLogs(
        logDir: logDir,
        destination: destination,
        now: DateTime.utc(2026, 11, 26, 16),
      );

      expect(destination.existsSync(), isTrue);
      expect(result.hasNoLogs, isTrue);
      expect(result.includedFiles, isEmpty);

      final archive = ZipDecoder().decodeBytes(
        destination.readAsBytesSync(),
        verify: true,
      );
      expect(archive.files, hasLength(1));

      final metadata = jsonDecode(
        utf8.decode(_entry(archive, 'metadata.json').content),
      ) as Map<String, Object?>;
      expect(metadata['format'], 'tarkov-companion.logs');
      expect(metadata['formatVersion'], 1);
      expect(metadata['exportedAt'], '2026-11-26T16:00:00.000Z');
      expect(metadata['logFiles'], isEmpty);
      expect(metadata.containsKey('appVersion'), isFalse);
    });

    test('a single current file exports without rotation files', () async {
      final root = createLogTempDir(addTearDown);
      final logDir = Directory(p.join(root.path, 'logs'));
      final sink = RotatingFileLogSink(directory: logDir);
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      await logger.warn('only one line', context: const {'dataset': 'items'});

      final destination = File(p.join(root.path, 'one.zip'));
      await exportLogs(
        logDir: logDir,
        destination: destination,
        appVersion: '0.1.0',
        now: DateTime.utc(2026, 11, 26, 17),
      );

      final archive = ZipDecoder().decodeBytes(
        destination.readAsBytesSync(),
        verify: true,
      );
      expect(
        archive.files.map((file) => file.name),
        unorderedEquals(['logs/app.log', 'metadata.json']),
      );

      final line = jsonDecode(
        utf8.decode(_entry(archive, 'logs/app.log').content),
      ) as Map<String, Object?>;
      expect(line['message'], 'only one line');
      expect(line['level'], 'warn');
      expect(line['context'], {'dataset': 'items'});
    });
  });
}

ArchiveFile _entry(Archive archive, String name) =>
    archive.files.firstWhere((file) => file.name == name);
