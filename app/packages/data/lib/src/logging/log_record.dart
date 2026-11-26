import 'log_level.dart';

/// One diagnostic event, ready to be serialized as a single log line.
///
/// Records carry only what a maintainer needs to reproduce a problem: a UTC
/// timestamp, a level, a short message, and optional structured context. The
/// caller decides what context is appropriate; see `docs/logging.md` for the
/// values that must never be included (tokens, progress, personal data).
final class LogRecord {
  /// Creates a record, normalizing [timestamp] to UTC.
  LogRecord({
    required DateTime timestamp,
    required this.level,
    required this.message,
    Map<String, Object?>? context,
  }) : timestamp = timestamp.toUtc(),
       context = context == null
           ? null
           : Map<String, Object?>.unmodifiable(context);

  /// The event time, always UTC. Serialized as ISO-8601 with a `Z` suffix.
  final DateTime timestamp;

  /// Severity of the event.
  final LogLevel level;

  /// Short, single-line human description. Newlines are escaped by JSON.
  final String message;

  /// Optional structured fields. Values are flattened to JSON primitives when
  /// serialized, so a caller cannot make logging throw by passing an object
  /// that `jsonEncode` does not understand.
  final Map<String, Object?>? context;

  /// The line payload. The line-delimited file sink appends `\n`.
  ///
  /// The key names are a compatibility surface: support tooling reads
  /// `timestamp`, `level`, `message`, and `context`. Renaming a key is a
  /// breaking change to the diagnostics format.
  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.name,
    'message': message,
    if (context != null && context!.isNotEmpty)
      'context': {
        for (final entry in context!.entries) entry.key: _jsonSafe(entry.value),
      },
  };

  @override
  String toString() => '${timestamp.toIso8601String()} ${level.name} $message';
}

/// Converts [value] into something `jsonEncode` accepts.
///
/// Primitives pass through; lists and maps are converted recursively; anything
/// else is rendered with `toString()`. The goal is best effort: a diagnostic
/// record must never be lost because a context value is not JSON-encodable.
Object? _jsonSafe(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return [for (final item in value) _jsonSafe(item)];
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        entry.key.toString(): _jsonSafe(entry.value),
    };
  }
  return value.toString();
}
