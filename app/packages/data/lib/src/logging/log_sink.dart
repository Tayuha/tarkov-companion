import 'log_record.dart';

/// Destination for [LogRecord]s.
///
/// A sink is allowed to fail — a full disk, a revoked permission, or a removed
/// directory must not become an application crash. [Logger] catches anything a
/// sink throws or returns, so implementations may surface I/O errors and still
/// be safe to use.
abstract class LogSink {
  /// Writes [record]. The returned future completes when the record has been
  /// handed to the underlying resource.
  Future<void> write(LogRecord record);

  /// Releases resources and drains queued writes. The default implementation
  /// is a no-op for sinks that hold no handle between writes.
  Future<void> close() async {}
}
