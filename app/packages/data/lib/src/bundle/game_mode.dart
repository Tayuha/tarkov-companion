import 'package:tarkov_companion_core/tarkov_companion_core.dart';

/// A game mode with its own bundle, manifest and `datasetState` rows.
///
/// [wireValue] is the exact string used by the manifest and the release tag
/// (`data-<mode>-latest`). The enum name and the wire value differ only for
/// [pvpSeason], whose wire value is `pvp-season`.
enum GameMode {
  regular('regular'),
  pve('pve'),
  pvpSeason('pvp-season');

  const GameMode(this.wireValue);

  /// The manifest and storage value.
  final String wireValue;

  /// Parses a manifest mode.
  ///
  /// Returns [Err] instead of throwing so a caller can report an unsupported
  /// mode without guessing; `BundleManifest.parse` turns the [Err] into a
  /// `ManifestFormatException` carrying the field path.
  static Result<GameMode> parse(String wireValue) {
    for (final mode in values) {
      if (mode.wireValue == wireValue) {
        return Ok(mode);
      }
    }
    return Err(ArgumentError.value(wireValue, 'mode', 'Unknown bundle mode'));
  }
}
