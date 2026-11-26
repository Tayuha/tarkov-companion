import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/logging_helpers.dart';

void main() {
  group('RotatingFileLogSink', () {
    test('below the threshold writes one parseable file in order', () async {
      final directory = createLogTempDir(addTearDown);
      final sink = RotatingFileLogSink(
        directory: directory,
        maxBytes: 4096,
        maxFiles: 5,
      );
      final logger = Logger(sink: sink, minimumLevel: LogLevel.debug);
      addTearDown(logger.close);

      final start = DateTime.utc(2026, 11, 26, 10);
      await logger.log(
        LogLevel.debug,
        'boot',
        timestamp: start,
        context: const {'mode': 'regular'},
      );
      await logger.log(
        LogLevel.info,
        'sync checked',
        timestamp: start.add(const Duration(seconds: 1)),
        context: const {'status': 304},
      );
      await logger.log(
        LogLevel.error,
        'image failed',
        timestamp: start.add(const Duration(seconds: 2)),
        context: const {'status': 500},
      );

      expect(_logFileNames(directory), ['app.log']);

      final lines = readJsonLines(sink.currentFile);
      expect(lines, hasLength(3));
      expect(lines.map((line) => line['level']), ['debug', 'info', 'error']);
      expect(lines.map((line) => line['message']), [
        'boot',
        'sync checked',
        'image failed',
      ]);
      expect(
        lines.map((line) => DateTime.parse(line['timestamp']! as String)),
        [
          start,
          start.add(const Duration(seconds: 1)),
          start.add(const Duration(seconds: 2)),
        ],
      );
      expect(lines.first['context'], {'mode': 'regular'});
    });

    test('rotates before a write that would exceed maxBytes', () async {
      final directory = createLogTempDir(addTearDown);
      final sink = RotatingFileLogSink(
        directory: directory,
        maxBytes: 512,
        maxFiles: 5,
      );
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      await logger.info(paddedMessage('first'));
      await logger.info(paddedMessage('second'));

      expect(_logFileNames(directory), ['app.1.log', 'app.log']);
      final current = readJsonLines(File(p.join(directory.path, 'app.log')));
      final rotated = readJsonLines(File(p.join(directory.path, 'app.1.log')));

      expect(current.map((line) => line['message']), [paddedMessage('second')]);
      expect(rotated.map((line) => line['message']), [paddedMessage('first')]);
      expect(sink.currentFile.lengthSync(), lessThanOrEqualTo(512));
    });

    test('prunes the oldest file and never exceeds maxFiles', () async {
      final directory = createLogTempDir(addTearDown);
      final sink = RotatingFileLogSink(
        directory: directory,
        maxBytes: 512,
        maxFiles: 3,
      );
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      for (var index = 0; index < 6; index++) {
        await logger.info(paddedMessage('record-$index'));
      }

      expect(_logFileNames(directory), ['app.1.log', 'app.2.log', 'app.log']);
      expect(File(p.join(directory.path, 'app.3.log')).existsSync(), isFalse);

      final retained = <String>[];
      for (final name in _logFileNames(directory)) {
        retained.addAll(
          readJsonLines(File(p.join(directory.path, name)))
              .map((line) => line['message']! as String),
        );
      }

      expect(
        retained.map((message) => message.split(' ').first),
        unorderedEquals(['record-3', 'record-4', 'record-5']),
      );
      for (final dropped in ['record-0', 'record-1', 'record-2']) {
        expect(retained.any((message) => message.startsWith(dropped)), isFalse);
      }
    });

    test('maxFiles of one keeps only the current file', () async {
      final directory = createLogTempDir(addTearDown);
      final sink = RotatingFileLogSink(
        directory: directory,
        maxBytes: 512,
        maxFiles: 1,
      );
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      for (var index = 0; index < 3; index++) {
        await logger.info(paddedMessage('single-$index'));
      }

      expect(_logFileNames(directory), ['app.log']);
      final lines = readJsonLines(sink.currentFile);
      expect(lines.single['message'], paddedMessage('single-2'));
    });

    test('writes one oversized record instead of looping', () async {
      final directory = createLogTempDir(addTearDown);
      final sink = RotatingFileLogSink(
        directory: directory,
        maxBytes: 64,
        maxFiles: 2,
      );
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      await logger.info(paddedMessage('huge', padding: 200));
      await logger.info('small');

      expect(_logFileNames(directory), ['app.1.log', 'app.log']);
      expect(
        readJsonLines(File(p.join(directory.path, 'app.1.log')))
            .single['message'],
        paddedMessage('huge', padding: 200),
      );
      expect(
        readJsonLines(File(p.join(directory.path, 'app.log')))
            .single['message'],
        'small',
      );
    });

    test('serializes concurrent writes so lines never interleave', () async {
      final directory = createLogTempDir(addTearDown);
      final sink = RotatingFileLogSink(
        directory: directory,
        maxBytes: 100000,
        maxFiles: 2,
      );
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      final start = DateTime.utc(2026, 11, 26, 12);
      final writes = <Future<void>>[
        for (var index = 0; index < 50; index++)
          logger.info(
            'line-$index',
            timestamp: start.add(Duration(milliseconds: index)),
          ),
      ];
      await Future.wait(writes);

      final lines = readJsonLines(sink.currentFile);
      expect(lines, hasLength(50));
      expect(lines.map((line) => line['message']), [
        for (var index = 0; index < 50; index++) 'line-$index',
      ]);
      expect(lines.every((line) => line['timestamp'] is String), isTrue);
    });

    test('creates nested directories on first write', () async {
      final root = createLogTempDir(addTearDown);
      final directory = Directory(p.join(root.path, 'nested', 'logs'));
      final sink = RotatingFileLogSink(directory: directory);
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      expect(directory.existsSync(), isFalse);
      await logger.info('hello');

      expect(directory.existsSync(), isTrue);
      expect(sink.currentFile.existsSync(), isTrue);
    });

    test('a broken directory does not throw out of the logger', () async {
      final root = createLogTempDir(addTearDown);
      final notADirectory = File(p.join(root.path, 'not-a-directory'))
        ..writeAsStringSync('occupied');
      final sink = RotatingFileLogSink(
        directory: Directory(notADirectory.path),
      );
      final logger = Logger(sink: sink);
      addTearDown(logger.close);

      await expectLater(logger.info('nowhere to go'), completes);
      expect(notADirectory.readAsStringSync(), 'occupied');
    });

    test('rejects non-positive limits', () {
      final directory = createLogTempDir(addTearDown);

      expect(
        () => RotatingFileLogSink(directory: directory, maxBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => RotatingFileLogSink(directory: directory, maxFiles: 0),
        throwsArgumentError,
      );
    });
  });
}

List<String> _logFileNames(Directory directory) {
  return [
    for (final entity in directory.listSync().whereType<File>())
      if (RegExp(r'^app(?:\.\d+)?\.log$').hasMatch(p.basename(entity.path)))
        p.basename(entity.path),
  ]..sort();
}
