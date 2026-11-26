import 'dart:convert';

/// Encodes [value] as canonical JSON: object keys sorted recursively, arrays
/// kept in order, no insignificant whitespace.
///
/// The bundle writer already emits canonical JSON (`docs/data-bundles.md`), so
/// a normal ingest could store the line verbatim. Doing it in the client keeps
/// the `payload` column identical even for a hand-built bundle or a fixture
/// whose keys are not sorted, and makes payload equality a useful test signal.
///
/// Throws [ArgumentError] for a value `jsonEncode` cannot represent, which can
/// only happen for a caller-supplied object that was not decoded from JSON.
String canonicalJsonEncode(Object? value) {
  return jsonEncode(_canonicalize(value));
}

Object? _canonicalize(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List<Object?>) {
    return value.map(_canonicalize).toList(growable: false);
  }
  if (value is Map<Object?, Object?>) {
    final keys = value.keys.toList(growable: false);
    for (final key in keys) {
      if (key is! String) {
        throw ArgumentError.value(
          key,
          'value',
          'JSON object keys must be string',
        );
      }
    }
    keys.sort();
    final ordered = <String, Object?>{};
    for (final key in keys.cast<String>()) {
      ordered[key] = _canonicalize(value[key]);
    }
    return ordered;
  }
  throw ArgumentError.value(value, 'value', 'Not representable as JSON');
}
