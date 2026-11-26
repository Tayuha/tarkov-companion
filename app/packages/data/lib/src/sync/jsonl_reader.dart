import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Why a compressed JSONL dataset could not be read.
enum JsonlReadFailure {
  /// The verified dataset file is not on disk.
  missingFile,

  /// The bytes are not a valid zstd frame (or are truncated).
  decompression,
}

/// A typed read failure before JSON parsing starts.
final class JsonlReadException implements Exception {
  const JsonlReadException(this.failure, this.message, {this.cause});

  final JsonlReadFailure failure;
  final String message;
  final Object? cause;

  @override
  String toString() => 'JsonlReadException(${failure.name}): $message';
}

/// Reads the lines of a zstd-compressed JSONL dataset one at a time.
///
/// The compressed file is decoded lazily from disk with the pure-Dart
/// `ZstdDecoder.decodeLazy`, so neither the compressed frame nor the decoded
/// payload is ever held whole. Memory is bounded by [chunkSize] plus the
/// longest single line; the largest shipped dataset decompresses to roughly
/// 8 MB, and no line comes close to the 64 KiB default chunk.
///
/// The reader is synchronous and single-use. [nextLine] returns the line
/// without its `\n` (and without a preceding `\r`), or `null` at the end of the
/// stream. Byte-level line splitting is UTF-8 safe: `0x0A` never occurs inside
/// a multi-byte sequence.
final class JsonlLineReader {
  JsonlLineReader(File file, {int chunkSize = 64 * 1024})
    : assert(chunkSize > 0),
      _file = file,
      _chunk = Uint8List(chunkSize);

  final File _file;
  final Uint8List _chunk;
  final List<int> _carry = <int>[];
  final Queue<String> _pending = Queue<String>();
  InputFileStream? _source;
  InputStream? _decoded;
  bool _started = false;
  bool _closed = false;

  /// Reads and returns the next line, or `null` when the dataset is exhausted.
  ///
  /// Throws [JsonlReadException] when the file is missing or the frame cannot
  /// be decoded, and [FormatException] when a line is not valid UTF-8.
  String? nextLine() {
    _ensureStarted();
    final decoded = _decoded!;

    while (_pending.isEmpty) {
      if (_guard(() => decoded.isEOS)) {
        if (_carry.isEmpty) {
          return null;
        }
        _pending.add(_decodeLine(_carry));
        _carry.clear();
        return _pending.removeFirst();
      }

      final read = _guard(() => decoded.readInto(_chunk, 0, _chunk.length));
      if (read == 0) {
        // A lazy stream reports end-of-stream through `isEOS`; a zero-length
        // read is only a safety stop so a malformed decoder cannot hang us.
        if (_carry.isEmpty) {
          return null;
        }
        _pending.add(_decodeLine(_carry));
        _carry.clear();
        return _pending.removeFirst();
      }

      var start = 0;
      for (var index = 0; index < read; index++) {
        if (_chunk[index] != 0x0A) {
          continue;
        }
        _carry.addAll(_chunk.sublist(start, index));
        _pending.add(_decodeLine(_carry));
        _carry.clear();
        start = index + 1;
      }
      if (start < read) {
        _carry.addAll(_chunk.sublist(start, read));
      }
    }

    return _pending.removeFirst();
  }

  /// Releases the file handle and the decoder window. Safe to call twice.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    try {
      _decoded?.closeSync();
    } finally {
      _source?.closeSync();
    }
  }

  void _ensureStarted() {
    if (_started) {
      return;
    }
    _started = true;
    if (!_file.existsSync()) {
      throw JsonlReadException(
        JsonlReadFailure.missingFile,
        'Dataset file ${_file.path} does not exist.',
      );
    }
    final source = InputFileStream(_file.path);
    _source = source;
    _decoded = ZstdDecoder().decodeLazy(source);
  }

  String _decodeLine(List<int> bytes) {
    var end = bytes.length;
    if (end > 0 && bytes[end - 1] == 0x0D) {
      end--;
    }
    return utf8.decode(bytes.sublist(0, end), allowMalformed: false);
  }

  T _guard<T>(T Function() action) {
    try {
      return action();
    } on JsonlReadException {
      rethrow;
    } on ArchiveException catch (error) {
      throw JsonlReadException(
        JsonlReadFailure.decompression,
        'The dataset is not a valid zstd frame: ${error.message}',
        cause: error,
      );
    } on FormatException catch (error) {
      throw JsonlReadException(
        JsonlReadFailure.decompression,
        'The zstd frame could not be decoded: ${error.message}',
        cause: error,
      );
    }
  }
}
