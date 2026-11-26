import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

/// Reads `test/fixtures/manifest-regular.json` without touching the network.
///
/// The path is resolved from the package URI so the test works both from
/// `app/` (`dart test packages/data`) and from the package directory.
Future<Map<String, Object?>> readManifestFixture() async {
  final libraryUri = await Isolate.resolvePackageUri(
    Uri.parse('package:tarkov_companion_data/tarkov_companion_data.dart'),
  );
  if (libraryUri == null) {
    throw StateError('Could not resolve the data package URI.');
  }
  final file = File.fromUri(
    libraryUri.resolve('../test/fixtures/manifest-regular.json'),
  );
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map<String, Object?>) {
    throw StateError('Manifest fixture is not a JSON object.');
  }
  return decoded;
}
