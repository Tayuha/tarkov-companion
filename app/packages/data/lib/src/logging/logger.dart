import 'log_level.dart';
import 'log_record.dart';
import 'log_sink.dart';

/// Level-filtered facade over a [LogSink].
///
/// ## Never throws
///
/// Every write goes through `try`/`catch`. If the sink is missing, unwritable,
/// or throws synchronously, the returned future still completes normally. This
/// is deliberate: diagnostics are best effort, and a broken log must never
/// take down the app it is supposed to help debug.
///
/// ## Filtering
///
/// Records below [minimumLevel] are dropped before touching the sink. The
/// default is [LogLevel.info]; a debug build of the shell can pass
/// [LogLevel.debug].
final class Logger {
  /// Creates a logger writing to [sink].
  Logger({required this.sink, this.minimumLevel = LogLevel.info});

  /// The destination for records that pass the filter.
  final LogSink sink;

  /// Lowest severity that is written.
  final LogLevel minimumLevel;

  /// Whether a record at [level] would be written.
  bool isEnabled(LogLevel level) => level.severity >= minimumLevel.severity;

  /// Writes a record at [level] unless it is filtered out.
  ///
  /// [timestamp] exists for deterministic tests; production callers omit it.
  /// The future never completes with an error.
  Future<void> log(
    LogLevel level,
    String message, {
    Map<String, Object?>? context,
    DateTime? timestamp,
  }) async {
    if (!isEnabled(level)) {
      return;
    }
    try {
      await sink.write(
        LogRecord(
          timestamp: timestamp ?? DateTime.now(),
          level: level,
          message: message,
          context: context,
        ),
      );
    } catch (_) {
      // Diagnostics are best effort. Swallowing here is the contract: callers
      // must not need to guard every log call, and an unhandled async error
      // from a background write would be worse than a lost line.
    }
  }

  /// Writes a [LogLevel.debug] record.
  Future<void> debug(
    String message, {
    Map<String, Object?>? context,
    DateTime? timestamp,
  }) => log(LogLevel.debug, message, context: context, timestamp: timestamp);

  /// Writes a [LogLevel.info] record.
  Future<void> info(
    String message, {
    Map<String, Object?>? context,
    DateTime? timestamp,
  }) => log(LogLevel.info, message, context: context, timestamp: timestamp);

  /// Writes a [LogLevel.warn] record.
  Future<void> warn(
    String message, {
    Map<String, Object?>? context,
    DateTime? timestamp,
  }) => log(LogLevel.warn, message, context: context, timestamp: timestamp);

  /// Writes a [LogLevel.error] record.
  Future<void> error(
    String message, {
    Map<String, Object?>? context,
    DateTime? timestamp,
  }) => log(LogLevel.error, message, context: context, timestamp: timestamp);

  /// Flushes and closes the sink, ignoring failures for the same reason
  /// [log] does.
  Future<void> close() async {
    try {
      await sink.close();
    } catch (_) {
      // Best effort.
    }
  }
}
