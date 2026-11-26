import 'dart:convert';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/logging_helpers.dart';

void main() {
  group('LogLevel', () {
    test('orders severity and parses names', () {
      expect(LogLevel.debug.severity, lessThan(LogLevel.info.severity));
      expect(LogLevel.info.severity, lessThan(LogLevel.warn.severity));
      expect(LogLevel.warn.severity, lessThan(LogLevel.error.severity));

      expect(LogLevel.parse('warn'), LogLevel.warn);
      expect(LogLevel.parse('WARN'), isNull);
      expect(LogLevel.parse('trace'), isNull);
    });
  });

  group('LogRecord', () {
    test('normalizes the timestamp to UTC and serializes the line shape', () {
      final local = DateTime(2026, 11, 26, 12, 30, 15);
      final record = LogRecord(
        timestamp: local,
        level: LogLevel.info,
        message: 'started',
        context: const {'mode': 'regular'},
      );

      expect(record.timestamp.isUtc, isTrue);
      expect(record.timestamp, local.toUtc());

      final json = record.toJson();
      expect(json['timestamp'], endsWith('Z'));
      expect(DateTime.parse(json['timestamp']! as String), local.toUtc());
      expect(json['level'], 'info');
      expect(json['message'], 'started');
      expect(json['context'], {'mode': 'regular'});
    });

    test('flattens non-primitive context so JSON encoding cannot fail', () {
      final record = LogRecord(
        timestamp: DateTime.utc(2026, 11, 26),
        level: LogLevel.warn,
        message: 'odd context',
        context: {
          'when': DateTime.utc(2026, 1, 2),
          'nested': {
            'list': [1, true, null, Object()],
          },
        },
      );

      final encoded = jsonEncode(record.toJson());
      final decoded = jsonDecode(encoded) as Map<String, Object?>;
      expect(decoded['context'], {
        'when': DateTime.utc(2026, 1, 2).toString(),
        'nested': {
          'list': [1, true, null, 'Instance of \'Object\''],
        },
      });
    });

    test('omits empty context', () {
      final record = LogRecord(
        timestamp: DateTime.utc(2026, 11, 26),
        level: LogLevel.error,
        message: 'boom',
        context: const {},
      );

      expect(record.toJson().containsKey('context'), isFalse);
    });
  });

  group('Logger', () {
    test('drops records below the minimum level', () async {
      final sink = MemoryLogSink();
      final logger = Logger(sink: sink, minimumLevel: LogLevel.warn);

      await logger.debug('ignored');
      await logger.info('ignored');
      await logger.warn('kept warn');
      await logger.error('kept error');

      expect(logger.isEnabled(LogLevel.info), isFalse);
      expect(logger.isEnabled(LogLevel.warn), isTrue);
      expect(sink.records.map((record) => record.level), [
        LogLevel.warn,
        LogLevel.error,
      ]);
    });

    test('does not touch the sink when filtered', () async {
      final sink = FailingLogSink();
      final logger = Logger(sink: sink, minimumLevel: LogLevel.info);

      await logger.debug('ignored');

      expect(sink.attempts, 0);
    });

    test('passes context and explicit timestamps through', () async {
      final sink = MemoryLogSink();
      final logger = Logger(sink: sink);
      final timestamp = DateTime(2026, 11, 26, 9);

      await logger.info(
        'manifest checked',
        context: const {'status': 304},
        timestamp: timestamp,
      );

      final record = sink.records.single;
      expect(record.timestamp, timestamp.toUtc());
      expect(record.level, LogLevel.info);
      expect(record.message, 'manifest checked');
      expect(record.context, {'status': 304});
    });

    test('never throws when the sink throws synchronously', () async {
      final sink = FailingLogSink();
      final logger = Logger(sink: sink);

      await expectLater(logger.info('still safe'), completes);
      expect(sink.attempts, 1);
    });

    test('never throws when the sink fails asynchronously', () async {
      final sink = FailingLogSink(async: true);
      final logger = Logger(sink: sink);

      await expectLater(logger.error('still safe'), completes);
      expect(sink.attempts, 1);
    });

    test('close drains the sink and swallows failures', () async {
      final sink = MemoryLogSink();
      final logger = Logger(sink: sink);
      await logger.close();
      expect(sink.closed, isTrue);

      final broken = _BrokenCloseSink();
      await expectLater(Logger(sink: broken).close(), completes);
    });
  });
}

final class _BrokenCloseSink extends MemoryLogSink {
  @override
  Future<void> close() async {
    throw StateError('close failed');
  }
}
