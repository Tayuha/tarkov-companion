import 'package:tarkov_companion_core/tarkov_companion_core.dart';

/// A dataset name used in a game-mode bundle.
///
/// Mirrors the file rules in `docs/data-bundles.md`: one `<dataset>.jsonl.zst`
/// per name, scoped to a mode.
enum DatasetKind {
  items('items'),
  tasks('tasks'),
  traders('traders'),
  hideout('hideout'),
  crafts('crafts'),
  barters('barters'),
  maps('maps');

  const DatasetKind(this.id);

  /// The name used in bundle file names and manifests.
  final String id;

  /// Parses a manifest dataset name.
  ///
  /// Returns [Err] instead of throwing so ingestion can report an unsupported
  /// dataset without losing the rest of the manifest.
  static Result<DatasetKind> parse(String id) {
    for (final kind in values) {
      if (kind.id == id) {
        return Ok(kind);
      }
    }
    return Err(ArgumentError.value(id, 'id', 'Unknown bundle dataset'));
  }
}
