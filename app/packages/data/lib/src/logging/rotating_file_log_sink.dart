import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'log_record.dart';
import 'log_sink.dart';

/// A [LogSink] writing line-delimited JSON to a rotating file set.
///
/// ## Layout and rotation
///
/// Records are appended to `<directory>/app.log`, one JSON object per line.
/// Rotation happens **before** a write that would push `app.log` past
/// [maxBytes]:
///
/// ```
/// app.log -> app.1.log
/// app.1.log -> app.2.log
/// ...
/// app.<maxFiles-1>.log -> deleted
/// ```
///
/// [maxFiles] counts the current file, so the default of 5 retains
/// `app.log`, `app.1.log` ... `app.4.log`. The oldest file is always the one
/// dropped. A single record larger than [maxBytes] is still written: the file
/// is rotated first, then the oversized line starts the new current file. That
/// keeps the sink making progress instead of looping or dropping the record.
///
/// ## Durability and concurrency
///
/// Every write creates the directory if needed and opens, appends, and closes
/// the file (`flush: true`). No handle is held between writes, so a crashed
/// process cannot leave a locked file on Windows.
///
/// Writes are serialized through an internal queue. Callers may fire many
/// `write` calls without awaiting them; each line is written whole, in call
/// order, and lines never interleave.
///
/// ## Never throws
///
/// I/O failures (missing directory, permission denied, full disk) are
/// swallowed. A diagnostic sink must not crash the app it diagnoses; the
/// [Logger] facade adds the same guarantee around any sink.
final class RotatingFileLogSink implements LogSink {
  /// Creates a sink under [directory].
  ///
  /// [maxBytes] is the maximum size of `app.log` before rotation, and
  /// [maxFiles] is the total number of files kept, including the current one.
  RotatingFileLogSink({
    required this.directory,
    int maxBytes = defaultMaxBytes,
    int maxFiles = defaultMaxFiles,
  }) : maxBytes = _validateMaxBytes(maxBytes),
       maxFiles = _validateMaxFiles(maxFiles);

  /// Default rotation threshold: 1 MiB per file.
  static const int defaultMaxBytes = 1024 * 1024;

  /// Default number of files kept, including the current one (about 5 MiB).
  static const int defaultMaxFiles = 5;

  /// Name of the current log file.
  static const String fileName = 'app.log';

  /// The directory that holds the log files.
  final Directory directory;

  /// Size in bytes at which the current file is rotated.
  final int maxBytes;

  /// Total number of files retained, including the current one.
  final int maxFiles;

  /// Byte length is computed on UTF-8 encoding, so the threshold matches what
  /// lands on disk for non-ASCII messages.
  Future<void> _pending = Future<void>.value();

  /// The current (newest) log file.
  File get currentFile => File(p.join(directory.path, fileName));

  /// Writes [record] after any earlier write has completed.
  ///
  /// The returned future never completes with an error.
  @override
  Future<void> write(LogRecord record) {
    final List<int> bytes;
    try {
      bytes = utf8.encode('${jsonEncode(record.toJson())}\n');
    } catch (_) {
      // A record that cannot be encoded is dropped rather than thrown.
      return Future<void>.value();
    }

    final operation = _pending.then((_) => _append(bytes));
    // The queue must survive a failed operation, otherwise every later write
    // would inherit the error.
    _pending = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  /// Waits for queued writes. The sink holds no open handle, so there is
  /// nothing else to release.
  @override
  Future<void> close() async {
    try {
      await _pending;
    } catch (_) {
      // Best effort.
    }
  }

  Future<void> _append(List<int> bytes) async {
    try {
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }

      final current = currentFile;
      var length = 0;
      if (await current.exists()) {
        length = await current.length();
      }

      if (length > 0 && length + bytes.length > maxBytes) {
        await _rotate();
      }

      await current.writeAsBytes(bytes, mode: FileMode.append, flush: true);
    } catch (_) {
      // Missing directory, permission denied, full disk: the line is lost, the
      // app keeps running.
    }
  }

  Future<void> _rotate() async {
    if (maxFiles <= 1) {
      final current = currentFile;
      if (await current.exists()) {
        await current.delete();
      }
      return;
    }

    final oldest = _fileFor(maxFiles - 1);
    if (await oldest.exists()) {
      await oldest.delete();
    }

    for (var index = maxFiles - 2; index >= 1; index--) {
      final source = _fileFor(index);
      if (await source.exists()) {
        await source.rename(_fileFor(index + 1).path);
      }
    }

    final current = currentFile;
    if (await current.exists()) {
      await current.rename(_fileFor(1).path);
    }
  }

  File _fileFor(int index) =>
      File(p.join(directory.path, index == 0 ? fileName : 'app.$index.log'));

  static int _validateMaxBytes(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'maxBytes', 'Must be positive.');
    }
    return value;
  }

  static int _validateMaxFiles(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'maxFiles', 'Must be positive.');
    }
    return value;
  }
}
