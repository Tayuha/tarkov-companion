import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../bundle/manifest.dart';
import '../dataset_kind.dart';
import '../net/allowlisted_http_client.dart';
import '../net/http_errors.dart';

/// Progress of one dataset download.
///
/// [downloadedBytes] only grows: each chunk that reaches the local file is
/// reported once. [totalBytes] is the manifest's `compressedBytes`, so
/// [fraction] can drive a determinate progress bar.
final class DownloadProgress {
  const DownloadProgress({
    required this.downloadedBytes,
    required this.totalBytes,
  });

  /// Bytes written to the partial file so far.
  final int downloadedBytes;

  /// Expected byte count from the manifest.
  final int totalBytes;

  /// Progress in `0.0..1.0`; a zero-byte dataset is complete immediately.
  double get fraction {
    if (totalBytes <= 0) {
      return 1;
    }
    final value = downloadedBytes / totalBytes;
    return value.clamp(0.0, 1.0).toDouble();
  }

  @override
  String toString() =>
      'DownloadProgress($downloadedBytes/$totalBytes, '
      '${(fraction * 100).toStringAsFixed(1)}%)';
}

/// Cooperative cancellation for [DatasetDownloader.download].
///
/// [cancel] is safe to call from any callback, including an `onProgress`
/// handler. A cancelled download throws [DownloadCancelled] and leaves no file
/// behind.
final class DownloadCancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  /// Whether [cancel] has been called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Completes when [cancel] is called; never completes otherwise.
  Future<void> get whenCancelled => _cancelled.future;

  /// Requests cancellation. Later calls are no-ops.
  void cancel() {
    if (!_cancelled.isCompleted) {
      _cancelled.complete();
    }
  }
}

/// A dataset download that did not produce a verified file.
///
/// Every subtype means the same thing to the caller: the destination is
/// exactly what it was before the call (absent for a first download, the
/// previous verified file for an update) and no partial file remains.
sealed class DatasetDownloadException implements Exception {
  const DatasetDownloadException(this.dataset, this.uri, this.message);

  /// Dataset that was being downloaded.
  final DatasetKind dataset;

  /// Resolved URL that was requested.
  final Uri uri;

  /// Human-readable reason; safe to log or show in a sync report.
  final String message;

  @override
  String toString() => '$runtimeType (${dataset.id}): $message ($uri)';
}

/// The caller cancelled the download, or the token was already cancelled when
/// it started.
///
/// The partial file was deleted and the response body subscription was
/// cancelled, which releases the connection.
final class DownloadCancelled extends DatasetDownloadException {
  const DownloadCancelled(
    DatasetKind dataset,
    Uri uri, {
    this.downloadedBytes = 0,
  }) : super(dataset, uri, 'The download was cancelled.');

  /// Bytes received before cancellation.
  final int downloadedBytes;
}

/// The response body did not have exactly `compressedBytes` bytes.
final class DownloadSizeMismatchException extends DatasetDownloadException {
  const DownloadSizeMismatchException(
    DatasetKind dataset,
    Uri uri, {
    required this.expectedBytes,
    required this.actualBytes,
  }) : super(
         dataset,
         uri,
         'Expected $expectedBytes bytes but received $actualBytes.',
       );

  /// `compressedBytes` from the manifest.
  final int expectedBytes;

  /// Bytes actually received.
  final int actualBytes;
}

/// The body length matched but its SHA-256 differs from the manifest.
final class DownloadChecksumMismatchException extends DatasetDownloadException {
  const DownloadChecksumMismatchException(
    DatasetKind dataset,
    Uri uri, {
    required this.expectedSha256,
    required this.actualSha256,
  }) : super(
         dataset,
         uri,
         'Expected SHA-256 $expectedSha256 but computed $actualSha256.',
       );

  /// `sha256` from the manifest, lowercase hex.
  final String expectedSha256;

  /// SHA-256 of the received bytes, lowercase hex.
  final String actualSha256;
}

/// The verified download could not be moved onto the destination path.
///
/// This is a local storage failure (permissions, a locked file, a full volume),
/// not a network or integrity failure. The partial file is removed; on Windows
/// the previous destination may already have been deleted to make room.
final class DownloadReplaceException extends DatasetDownloadException {
  const DownloadReplaceException(
    DatasetKind dataset,
    Uri uri, {
    required this.cause,
  }) : super(
         dataset,
         uri,
         'Could not move the verified file into place: $cause',
       );

  /// The underlying filesystem error.
  final FileSystemException cause;
}

/// Downloads one dataset to a verified file, atomically replacing the old one.
///
/// The flow implements step 4 and step 5 of the client resolution algorithm in
/// `docs/data-bundles.md`:
///
/// 1. resolve `dataset.path` against the manifest URL with [Uri.resolve];
/// 2. `GET` it through [AllowlistedHttpClient.send], so the allowlist, HTTPS
///    and redirect rules apply to the asset exactly as they do to the manifest
///    (a `404` reaches the caller as [HttpStatusException]);
/// 3. stream the body into `<destination>.part`, hashing and reporting progress
///    per chunk;
/// 4. verify the byte count against `dataset.compressedBytes` and the digest
///    against `dataset.sha256`;
/// 5. rename the verified temp file over [destination].
///
/// ## Guarantees
///
/// * **Nothing partial is visible.** The destination is only written by the
///   final rename, which is atomic on POSIX. On Windows, where a rename cannot
///   replace an existing file, the destination is deleted immediately before
///   the rename; this is the smallest unavoidable window.
/// * **A failed update keeps the old file.** Verification happens before the
///   old destination is touched, so a corrupted download leaves the previously
///   verified dataset in place. On a first download, a failure leaves no
///   destination at all.
/// * **No `.part` survives any outcome.** Cancellation, transport errors, size
///   and checksum mismatches all delete the partial file.
/// * **Bounded memory.** Chunks are written and flushed as they arrive; the
///   compressed body is never buffered as a whole.
final class DatasetDownloader {
  DatasetDownloader(this._client);

  final AllowlistedHttpClient _client;

  /// Downloads [dataset] from the bundle [manifestUri] points at.
  ///
  /// [destination] is the final path, for example
  /// `<data>/regular/items.jsonl.zst`. Parent directories are created. When
  /// [cancellation] is already cancelled, nothing is requested.
  ///
  /// [onProgress] is called once per non-empty chunk, in order, and is never
  /// called after the future completes.
  ///
  /// Throws [DownloadCancelled], [DownloadSizeMismatchException],
  /// [DownloadChecksumMismatchException], or any error from the HTTP client
  /// ([HttpStatusException], [HttpTimeoutException], policy errors, or the
  /// underlying `dart:io` transport error).
  Future<void> download({
    required Uri manifestUri,
    required ManifestDataset dataset,
    required File destination,
    DownloadCancellationToken? cancellation,
    void Function(DownloadProgress)? onProgress,
  }) async {
    final token = cancellation;
    if (token != null && token.isCancelled) {
      throw DownloadCancelled(
        dataset.dataset,
        manifestUri.resolve(dataset.path),
      );
    }

    final uri = manifestUri.resolve(dataset.path);
    final response = await _client.send(uri);

    if (token != null && token.isCancelled) {
      await response.body.listen(null).cancel();
      throw DownloadCancelled(dataset.dataset, uri);
    }

    await destination.parent.create(recursive: true);
    final part = File('${destination.path}.part');

    final totalBytes = dataset.compressedBytes;
    var downloadedBytes = 0;
    final digestSink = _SingleDigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    final sink = part.openWrite();
    final iterator = StreamIterator<List<int>>(
      response.body.timeout(_client.timeout),
    );

    var verified = false;
    try {
      while (true) {
        if (token != null && token.isCancelled) {
          throw DownloadCancelled(
            dataset.dataset,
            uri,
            downloadedBytes: downloadedBytes,
          );
        }
        if (!await iterator.moveNext()) {
          break;
        }

        final chunk = iterator.current;
        if (chunk.isEmpty) {
          continue;
        }

        sink.add(chunk);
        hasher.add(chunk);
        downloadedBytes += chunk.length;
        onProgress?.call(
          DownloadProgress(
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
          ),
        );
        // Flush per chunk: the stream stays paused while the disk catches up,
        // so memory does not grow with the dataset size.
        await sink.flush();

        if (token != null && token.isCancelled) {
          throw DownloadCancelled(
            dataset.dataset,
            uri,
            downloadedBytes: downloadedBytes,
          );
        }
      }
      hasher.close();

      if (downloadedBytes != totalBytes) {
        throw DownloadSizeMismatchException(
          dataset.dataset,
          uri,
          expectedBytes: totalBytes,
          actualBytes: downloadedBytes,
        );
      }

      final actualSha256 = digestSink.digest?.toString();
      if (actualSha256 == null || actualSha256 != dataset.sha256) {
        throw DownloadChecksumMismatchException(
          dataset.dataset,
          uri,
          expectedSha256: dataset.sha256,
          actualSha256: actualSha256 ?? '(none)',
        );
      }

      verified = true;
    } on TimeoutException {
      throw HttpTimeoutException(uri, _client.timeout);
    } finally {
      // Cancelling the iterator closes the response body subscription.
      await iterator.cancel();
      try {
        await sink.close();
      } on FileSystemException {
        if (verified) {
          // The bytes were verified but cannot be durably closed, so they must
          // not be renamed onto the destination.
          await _deleteQuietly(part);
          rethrow;
        }
        // Otherwise the transfer already failed; keep the original error and
        // let the cleanup below discard the partial file.
      }
      if (!verified) {
        await _deleteQuietly(part);
      }
    }

    await _replaceAtomically(part, destination, dataset, uri);
  }

  /// Renames [part] over [destination], deleting the old file first on Windows.
  ///
  /// The delete happens only after the new bytes are verified, so on every
  /// platform a failure before this point leaves the previous dataset intact.
  Future<void> _replaceAtomically(
    File part,
    File destination,
    ManifestDataset dataset,
    Uri uri,
  ) async {
    try {
      if (Platform.isWindows && await destination.exists()) {
        // Windows `rename` refuses to overwrite. The old file has already
        // served its purpose: the new one is verified and ready to move in.
        await destination.delete();
      }
      await part.rename(destination.path);
    } on FileSystemException catch (error) {
      await _deleteQuietly(part);
      throw DownloadReplaceException(dataset.dataset, uri, cause: error);
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best effort. A leftover `.part` from a crash is truncated by the next
      // `openWrite`, so it cannot be mistaken for a finished dataset.
    }
  }
}

/// Collects the single [Digest] produced by a chunked hash conversion.
final class _SingleDigestSink implements Sink<Digest> {
  Digest? digest;

  @override
  void add(Digest data) => digest = data;

  @override
  void close() {}
}
