/// The client side of the bundle contract documented in
/// `docs/data-bundles.md`.
///
/// These are the only version numbers the app implements. They live in one
/// place so the manifest model, the dataset-state repository and future sync
/// code cannot drift apart:
///
/// * [manifestVersion] — the manifest document shape the parser understands.
/// * [supportedBundleSchemaVersion] — the newest bundle layout the client can
///   consume. A manifest with a newer value is refused (`bundleUnsupported`).
/// * [appDataSchemaVersion] — the newest dataset record schema the client can
///   ingest. A manifest whose `minAppSchemaVersion` is newer is refused
///   (`appUpdateRequired`); so is an individual dataset whose `schemaVersion`
///   is newer.
///
/// Bumping any of these is a client release: the parser and ingestion must
/// understand the new contract before the constant moves.
abstract final class BundleContract {
  /// The manifest document version this client implements.
  static const int manifestVersion = 1;

  /// The newest bundle schema version (layout, compression, JSONL envelope)
  /// this client supports.
  static const int supportedBundleSchemaVersion = 1;

  /// The newest dataset record schema version this client can ingest.
  static const int appDataSchemaVersion = 1;

  /// File name of the manifest inside a mode bundle/release.
  static const String manifestFileName = 'manifest.json';

  /// Suffix of a compressed dataset file.
  static const String datasetFileSuffix = '.jsonl.zst';

  /// Number of lowercase hex characters in a SHA-256.
  static const int sha256HexLength = 64;

  /// Whether this client implements [schemaVersion] for a dataset.
  static bool supportsDatasetSchema(int schemaVersion) =>
      schemaVersion <= appDataSchemaVersion;
}
