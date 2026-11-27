/// An item deep link extracted from the process launch arguments.
///
/// Two forms are accepted, both by game item identifier (the Tarkov item id,
/// for example `5447a9cd4bdc2dbd208b4567`):
///
/// ```
/// tarkov_companion --item-id=<id>
/// tarkov_companion --item-id <id>
/// tarkov_companion tarkov-companion://item/<id>
/// ```
///
/// A second launch forwards the request to the running instance over its
/// runtime socket; see `SingleInstance`.
final class LaunchRequest {
  const LaunchRequest({this.itemId});

  /// The requested item id, or `null` when the launch has no deep link.
  final String? itemId;

  /// Whether this launch asks for an item.
  bool get hasItem => itemId != null;

  /// Parses the arguments the Flutter engine received from the runner.
  ///
  /// Unknown arguments are ignored. The first well-formed item request wins.
  static LaunchRequest parse(Iterable<String> arguments) {
    final args = arguments.toList(growable: false);
    for (var index = 0; index < args.length; index++) {
      final argument = args[index];
      if (argument.startsWith('--item-id=')) {
        final id = _clean(argument.substring('--item-id='.length));
        if (id != null) {
          return LaunchRequest(itemId: id);
        }
      } else if (argument == '--item-id' && index + 1 < args.length) {
        final id = _clean(args[index + 1]);
        if (id != null) {
          return LaunchRequest(itemId: id);
        }
        index++;
      } else {
        final id = _fromUri(argument);
        if (id != null) {
          return LaunchRequest(itemId: id);
        }
      }
    }
    return const LaunchRequest();
  }

  static String? _fromUri(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || uri.scheme != 'tarkov-companion') {
      return null;
    }
    final segments = uri.pathSegments;
    if (uri.host == 'item') {
      return segments.isEmpty ? null : _clean(segments.first);
    }
    if (segments.length >= 2 && segments.first == 'item') {
      return _clean(segments[1]);
    }
    return null;
  }

  static String? _clean(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
