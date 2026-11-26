/// Severity of a local diagnostic record.
///
/// The numeric [severity] is part of the on-disk contract: it is what a
/// [Logger] compares against its minimum level, and it is independent of the
/// declaration order so a future level can be inserted without silently
/// changing which records pass the filter.
enum LogLevel {
  debug(10),
  info(20),
  warn(30),
  error(40);

  const LogLevel(this.severity);

  /// Ordered weight used for filtering. Higher is more severe.
  final int severity;

  /// Parses a level name as written by [LogRecord.toJson], returning `null`
  /// for an unknown name instead of throwing.
  static LogLevel? parse(String name) {
    for (final level in values) {
      if (level.name == name) {
        return level;
      }
    }
    return null;
  }
}
