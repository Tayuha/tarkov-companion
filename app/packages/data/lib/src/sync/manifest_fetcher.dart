import 'dart:convert';
import 'dart:typed_data';

import '../bundle/bundle_contract.dart';
import '../bundle/game_mode.dart';
import '../bundle/manifest.dart';
import '../net/allowlisted_http_client.dart';
import '../net/http_errors.dart';
import 'manifest_repository.dart';

/// A typed manifest-fetch failure.
///
/// Transport failures that are not about the document's content keep
/// propagating as the allowlisted client's own errors (`HttpStatusException`
/// for `5xx`, `SocketException` for DNS, ...). A `404` and a `304` are expected
/// outcomes of a sync and therefore get their own types.
sealed class ManifestFetchException implements Exception {
  const ManifestFetchException(this.mode, this.uri, this.message);

  /// The mode whose manifest was requested.
  final GameMode mode;

  /// The stable manifest URL for [mode].
  final Uri uri;

  /// Human-readable reason; safe to show in a sync report.
  final String message;

  @override
  String toString() => '$runtimeType ($mode): $message ($uri)';
}

/// The release has no `manifest.json` (HTTP `404`), so no bundle is published
/// for this mode.
///
/// The cache, if any, is left exactly as it was: a manifest disappearing is a
/// publishing problem, not a reason to discard the last known document.
final class ManifestNotFound extends ManifestFetchException {
  const ManifestNotFound(GameMode mode, Uri uri)
    : super(
        mode,
        uri,
        'The release has no manifest for this mode (HTTP 404). No bundle is '
        'published.',
      );
}

/// A conditional request returned `304` but this client has no cached
/// manifest, so there is nothing to serve.
///
/// This is distinct from "unchanged": a first sync must download the document.
final class ManifestNotModifiedWithoutCache extends ManifestFetchException {
  const ManifestNotModifiedWithoutCache(GameMode mode, Uri uri)
    : super(
        mode,
        uri,
        'The server reported the manifest unchanged (HTTP 304), but no '
        'manifest is cached for this mode.',
      );
}

/// The response body is not valid UTF-8, not JSON, or not a manifest this
/// client implements.
///
/// [cause] is the underlying [FormatException] or [ManifestFormatException].
/// The cached row is untouched.
final class ManifestInvalid extends ManifestFetchException {
  const ManifestInvalid(GameMode mode, Uri uri, {required this.cause})
    : super(mode, uri, 'The manifest response is invalid: $cause');

  final Object cause;
}

/// The manifest parsed cleanly but declares a different mode than requested.
///
/// Accepting it would mix datasets between game modes, so it is refused and the
/// cached row is untouched.
final class ManifestModeMismatch extends ManifestFetchException {
  ManifestModeMismatch(GameMode mode, Uri uri, {required this.actualMode})
    : super(
        mode,
        uri,
        'Requested the ${mode.wireValue} manifest but the document declares '
        '"${actualMode.wireValue}".',
      );

  /// The mode the document itself declares.
  final GameMode actualMode;
}

/// The outcome of [ManifestFetcher.fetch].
sealed class ManifestFetchResult {
  const ManifestFetchResult({
    required this.mode,
    required this.checkedAt,
    required this.manifest,
    required this.cache,
  });

  /// The mode the fetch was for.
  final GameMode mode;

  /// When this check completed, from the fetcher's clock.
  final DateTime checkedAt;

  /// The parsed manifest, either freshly fetched or from the cache.
  final BundleManifest manifest;

  /// The cache row after the fetch.
  final CachedManifest cache;

  /// Whether this was a `304 Not Modified` response.
  bool get isNotModified;
}

/// A `200` response was parsed, validated and recorded in the cache.
final class ManifestFetched extends ManifestFetchResult {
  const ManifestFetched({
    required super.mode,
    required super.checkedAt,
    required super.manifest,
    required super.cache,
    required this.rawBytes,
  });

  /// The raw response body, exactly the bytes the hash covers.
  final Uint8List rawBytes;

  @override
  bool get isNotModified => false;
}

/// A `304 Not Modified` response: the cached manifest is still current.
///
/// No dataset was requested or downloaded; only `lastCheckedAt` moved.
final class ManifestNotModified extends ManifestFetchResult {
  const ManifestNotModified({
    required super.mode,
    required super.checkedAt,
    required super.manifest,
    required super.cache,
  });

  @override
  bool get isNotModified => true;
}

/// Fetches and caches the per-mode bundle manifest with conditional requests.
///
/// The only URL this class requests is the stable release asset:
///
/// ```
/// https://github.com/Tayuha/tarkov-companion/releases/download/data-<mode>-latest/manifest.json
/// ```
///
/// It never builds or requests a dataset URL; that is task 4.2. The flow is:
///
/// 1. read the cached document for the mode;
/// 2. `GET` the manifest with `If-None-Match` / `If-Modified-Since` when the
///    cache has them;
/// 3. `304` → move `lastCheckedAt`, parse the cached body, return
///    [ManifestNotModified];
/// 4. `200` → strict UTF-8 + JSON + [BundleManifest.parse] + mode check, then
///    record the raw body, validators, `generatedAt` and SHA-256, and return
///    [ManifestFetched].
///
/// Every failure that concerns the document (`404`, invalid body, wrong mode,
/// `304` without a cache) is a typed [ManifestFetchException]; in all of those
/// cases the cached row is left untouched.
final class ManifestFetcher {
  ManifestFetcher(this._client, this._repository, {DateTime Function()? clock})
    : _clock = clock ?? _repository.now;

  final AllowlistedHttpClient _client;
  final ManifestRepository _repository;
  final DateTime Function() _clock;

  /// The stable manifest URL for [mode].
  static Uri uriFor(GameMode mode) => Uri.parse(
    'https://github.com/Tayuha/tarkov-companion/releases/download/'
    'data-${mode.wireValue}-latest/${BundleContract.manifestFileName}',
  );

  /// The last time this client checked [mode], or `null` when never checked.
  Future<DateTime?> lastCheckedAt(GameMode mode) async =>
      (await _repository.read(mode))?.lastCheckedAt;

  /// Performs one conditional manifest fetch for [mode].
  Future<ManifestFetchResult> fetch(GameMode mode) async {
    final uri = uriFor(mode);
    final cached = await _repository.read(mode);
    final headers = cached?.conditionalHeaders;

    final AllowlistedHttpResponse response;
    try {
      response = await _client.get(
        uri,
        headers: headers == null || headers.isEmpty ? null : headers,
      );
    } on HttpStatusException catch (error) {
      if (error.isNotModified) {
        return _handleNotModified(mode, uri, cached);
      }
      if (error.isNotFound) {
        throw ManifestNotFound(mode, uri);
      }
      rethrow;
    }

    return _handleFetched(mode, uri, response.bodyBytes, response.headers);
  }

  Future<ManifestFetchResult> _handleNotModified(
    GameMode mode,
    Uri uri,
    CachedManifest? cached,
  ) async {
    if (cached == null) {
      throw ManifestNotModifiedWithoutCache(mode, uri);
    }

    final checkedAt = _clock();
    final BundleManifest manifest;
    try {
      manifest = BundleManifest.parse(jsonDecode(cached.manifestJson));
    } on FormatException catch (error) {
      // The body was validated before it was written, so this is local
      // corruption; report it as an invalid document instead of crashing.
      throw ManifestInvalid(mode, uri, cause: error);
    } on ManifestFormatException catch (error) {
      throw ManifestInvalid(mode, uri, cause: error);
    }

    final updated = await _repository.markChecked(mode, checkedAt);
    if (updated == null) {
      // The row disappeared between the read and the update; treat it exactly
      // like a 304 without a cache rather than returning a stale document.
      throw ManifestNotModifiedWithoutCache(mode, uri);
    }

    return ManifestNotModified(
      mode: mode,
      checkedAt: checkedAt,
      manifest: manifest,
      cache: updated,
    );
  }

  Future<ManifestFetchResult> _handleFetched(
    GameMode mode,
    Uri uri,
    Uint8List bodyBytes,
    Map<String, String> headers,
  ) async {
    final String body;
    try {
      body = utf8.decode(bodyBytes);
    } on FormatException catch (error) {
      throw ManifestInvalid(mode, uri, cause: error);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (error) {
      throw ManifestInvalid(mode, uri, cause: error);
    }

    final BundleManifest manifest;
    try {
      manifest = BundleManifest.parse(decoded);
    } on ManifestFormatException catch (error) {
      throw ManifestInvalid(mode, uri, cause: error);
    }

    if (manifest.mode != mode) {
      throw ManifestModeMismatch(mode, uri, actualMode: manifest.mode);
    }

    final checkedAt = _clock();
    final record = await _repository.recordCheck(
      mode,
      manifestJson: body,
      contentHash: ManifestRepository.hashBytes(bodyBytes),
      etag: headers['etag'],
      lastModified: headers['last-modified'],
      generatedAt: (decoded as Map<String, Object?>)['generatedAt'] as String?,
      checkedAt: checkedAt,
      changedAt: checkedAt,
    );

    return ManifestFetched(
      mode: mode,
      checkedAt: checkedAt,
      manifest: manifest,
      cache: record.cache,
      rawBytes: bodyBytes,
    );
  }
}
