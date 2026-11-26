import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../bundle/game_mode.dart';
import '../database/app_database.dart';

/// The cached manifest for one game mode, independent of the drift row class.
///
/// [lastCheckedAt] and [lastChangedAt] are UTC instants; the repository
/// normalizes them on read, because drift stores local-time `DateTime`s.
final class CachedManifest {
  const CachedManifest({
    required this.mode,
    required this.etag,
    required this.lastModified,
    required this.manifestJson,
    required this.manifestGeneratedAt,
    required this.lastCheckedAt,
    required this.lastChangedAt,
    required this.contentHash,
  });

  /// The mode this document belongs to.
  final GameMode mode;

  /// HTTP `ETag` of the last successful fetch, if the response had one.
  final String? etag;

  /// HTTP `Last-Modified` of the last successful fetch, if present.
  final String? lastModified;

  /// The raw manifest body exactly as received.
  final String manifestJson;

  /// The manifest's `generatedAt`, verbatim.
  final String? manifestGeneratedAt;

  /// When this client last asked the server about this manifest.
  final DateTime lastCheckedAt;

  /// When the body last changed; `null` before the first change.
  final DateTime? lastChangedAt;

  /// Lowercase hex SHA-256 of the raw manifest bytes.
  final String contentHash;

  /// Conditional-request headers for the next fetch, in `If-*` form.
  ///
  /// A missing validator is omitted rather than sent empty, so a first fetch is
  /// an ordinary `GET`.
  Map<String, String> get conditionalHeaders => {
    'if-none-match': ?etag,
    'if-modified-since': ?lastModified,
  };

  CachedManifest copyWith({DateTime? lastCheckedAt}) => CachedManifest(
    mode: mode,
    etag: etag,
    lastModified: lastModified,
    manifestJson: manifestJson,
    manifestGeneratedAt: manifestGeneratedAt,
    lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
    lastChangedAt: lastChangedAt,
    contentHash: contentHash,
  );
}

/// What [ManifestRepository.recordCheck] did to the cached row.
enum ManifestRecordOutcome {
  /// No row existed; the first manifest for this mode was cached.
  inserted,

  /// The body was byte-identical; only validators and check time moved.
  unchanged,

  /// The body changed; the cache and [CachedManifest.lastChangedAt] moved.
  changed,
}

/// The row after a [ManifestRepository.recordCheck] write plus its outcome.
final class ManifestRecordResult {
  const ManifestRecordResult({required this.cache, required this.outcome});

  final CachedManifest cache;
  final ManifestRecordOutcome outcome;
}

/// Stores the last manifest fetched for each game mode.
///
/// The table is keyed by mode, so `regular`, `pve` and `pvp-season` never share
/// a document or its validators. [recordCheck] is the only writer; the fetcher
/// calls it after a fully validated `200`.
///
/// Change detection is [CachedManifest.contentHash], the SHA-256 of the raw
/// body, not the `ETag`. A `200` whose body is unchanged but whose `ETag` moved
/// (GitHub's CDN can answer with its own validator) updates the stored
/// validators and [CachedManifest.lastCheckedAt] without moving
/// [CachedManifest.lastChangedAt].
final class ManifestRepository {
  ManifestRepository(this._database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _database;
  final DateTime Function() _clock;

  /// The current time according to the injected clock.
  DateTime now() => _clock();

  /// The cached manifest for [mode], or `null` when none was stored.
  Future<CachedManifest?> read(GameMode mode) async {
    final row = await (_database.select(
      _database.remoteManifests,
    )..where((row) => row.mode.equals(mode.wireValue))).getSingleOrNull();
    return row == null ? null : _toCache(row);
  }

  /// Records a validated `200` response for [mode].
  ///
  /// [manifestJson] is the raw body and [contentHash] its SHA-256. A different
  /// hash means the document changed and moves `lastChangedAt`; the same hash
  /// means only metadata changed. A first insert counts as a change.
  ///
  /// [checkedAt] and [changedAt] default to [now], so tests can pin them.
  Future<ManifestRecordResult> recordCheck(
    GameMode mode, {
    required String manifestJson,
    required String contentHash,
    String? etag,
    String? lastModified,
    String? generatedAt,
    DateTime? checkedAt,
    DateTime? changedAt,
  }) {
    final when = (checkedAt ?? now()).toUtc();
    final changeTime = (changedAt ?? when).toUtc();

    return _database.transaction(() async {
      final existing = await (_database.select(
        _database.remoteManifests,
      )..where((row) => row.mode.equals(mode.wireValue))).getSingleOrNull();

      if (existing == null) {
        await _database
            .into(_database.remoteManifests)
            .insert(
              RemoteManifestsCompanion.insert(
                mode: mode.wireValue,
                etag: Value(etag),
                lastModified: Value(lastModified),
                manifestJson: manifestJson,
                manifestGeneratedAt: Value(generatedAt),
                lastCheckedAt: when,
                lastChangedAt: Value(changeTime),
                contentHash: contentHash,
              ),
            );
        return ManifestRecordResult(
          outcome: ManifestRecordOutcome.inserted,
          cache: CachedManifest(
            mode: mode,
            etag: etag,
            lastModified: lastModified,
            manifestJson: manifestJson,
            manifestGeneratedAt: generatedAt,
            lastCheckedAt: when,
            lastChangedAt: changeTime,
            contentHash: contentHash,
          ),
        );
      }

      final unchanged = existing.contentHash == contentHash;
      final changedAtValue = unchanged
          ? existing.lastChangedAt?.toUtc()
          : changeTime;

      await (_database.update(
        _database.remoteManifests,
      )..where((row) => row.mode.equals(mode.wireValue))).write(
        RemoteManifestsCompanion(
          etag: Value(etag),
          lastModified: Value(lastModified),
          manifestJson: Value(manifestJson),
          manifestGeneratedAt: Value(generatedAt),
          lastCheckedAt: Value(when),
          lastChangedAt: Value(changedAtValue),
          contentHash: Value(contentHash),
        ),
      );

      return ManifestRecordResult(
        outcome: unchanged
            ? ManifestRecordOutcome.unchanged
            : ManifestRecordOutcome.changed,
        cache: CachedManifest(
          mode: mode,
          etag: etag,
          lastModified: lastModified,
          manifestJson: manifestJson,
          manifestGeneratedAt: generatedAt,
          lastCheckedAt: when,
          lastChangedAt: changedAtValue,
          contentHash: contentHash,
        ),
      );
    });
  }

  /// Moves only `lastCheckedAt` for [mode], used after a `304 Not Modified`.
  ///
  /// Returns the updated cache, or `null` when the mode has no cached manifest.
  /// The body, validators and `lastChangedAt` are not touched.
  Future<CachedManifest?> markChecked(GameMode mode, DateTime checkedAt) async {
    final updated =
        await (_database.update(_database.remoteManifests)
              ..where((row) => row.mode.equals(mode.wireValue)))
            .write(RemoteManifestsCompanion(lastCheckedAt: Value(checkedAt)));
    if (updated == 0) {
      return null;
    }
    return read(mode);
  }

  /// SHA-256 of [bytes] as lowercase hex, the value stored in [contentHash].
  static String hashBytes(List<int> bytes) => sha256.convert(bytes).toString();

  CachedManifest _toCache(RemoteManifestRecord row) {
    final mode = GameMode.parse(row.mode).valueOrNull;
    if (mode == null) {
      throw StateError(
        'remoteManifest contains an unknown mode "${row.mode}".',
      );
    }
    return CachedManifest(
      mode: mode,
      etag: row.etag,
      lastModified: row.lastModified,
      manifestJson: row.manifestJson,
      manifestGeneratedAt: row.manifestGeneratedAt,
      lastCheckedAt: row.lastCheckedAt.toUtc(),
      lastChangedAt: row.lastChangedAt?.toUtc(),
      contentHash: row.contentHash,
    );
  }
}
