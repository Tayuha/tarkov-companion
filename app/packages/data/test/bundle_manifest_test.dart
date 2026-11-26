import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import 'support/manifest_fixtures.dart';

void main() {
  group('BundleManifest.parse', () {
    test('parses the published regular manifest fixture', () async {
      final manifest = BundleManifest.parse(await readManifestFixture());

      expect(manifest.manifestVersion, 1);
      expect(manifest.bundleSchemaVersion, 1);
      expect(manifest.minAppSchemaVersion, 1);
      expect(manifest.mode, GameMode.regular);
      expect(manifest.generatedAt, DateTime.utc(2026, 11, 26, 10, 32, 14, 883));
      expect(manifest.source.baseUrl, 'https://json.tarkov.dev');
      expect(
        manifest.source.capturedAt,
        DateTime.utc(2026, 11, 26, 10, 30, 9, 640),
      );

      expect(manifest.datasets, hasLength(2));

      final items = manifest.datasets.first;
      expect(items.dataset, DatasetKind.items);
      expect(items.path, 'items-ed751dcd264d.jsonl.zst');
      expect(items.schemaVersion, 1);
      expect(
        items.sha256,
        'ed751dcd264d08fceeea2029ba47b5e03a07e8674a094f3ada562a776a188195',
      );
      expect(items.compressedBytes, 1433154);
      expect(items.uncompressedBytes, 17417643);
      expect(items.records, 6015);
      expect(items.source.url, 'https://json.tarkov.dev/regular/items');
      expect(items.source.etag, 'W/"c1708b692be362f22f764dbbb7603b70"');
      expect(items.source.lastModified, 'Thu, 26 Nov 2026 10:30:24 GMT');
      expect(
        items.source.fetchedAt,
        DateTime.utc(2026, 11, 26, 10, 32, 16, 375),
      );

      final tasks = manifest.datasets.last;
      expect(tasks.dataset, DatasetKind.tasks);
      expect(tasks.path, 'tasks-8fc7c11e0264.jsonl.zst');
      expect(tasks.records, 778);

      expect(manifest.totals.datasets, 2);
      expect(manifest.totals.records, 6793);
      expect(manifest.totals.compressedBytes, 1672554);
      expect(manifest.totals.uncompressedBytes, 19562454);
      expect(manifest.skipped, isEmpty);
      expect(
        manifest.checkCompatibility().status,
        ManifestCompatibility.compatible,
      );
    });

    test('rejects a missing required field', () async {
      final json = await readManifestFixture();
      json.remove('generatedAt');

      _expectPath(json, 'generatedAt');
    });

    test('rejects a missing required dataset field', () async {
      final json = await readManifestFixture();
      _firstDataset(json).remove('path');

      _expectPath(json, 'datasets[0].path');
    });

    test('rejects a non-positive bundle schema version', () async {
      final json = await readManifestFixture();
      json['bundleSchemaVersion'] = 0;

      _expectPath(json, 'bundleSchemaVersion');
    });

    test('rejects a non-positive minimum app schema version', () async {
      final json = await readManifestFixture();
      json['minAppSchemaVersion'] = 0;

      _expectPath(json, 'minAppSchemaVersion');
    });

    test('rejects an unsupported manifest version', () async {
      final json = await readManifestFixture();
      json['manifestVersion'] = 2;

      _expectPath(json, 'manifestVersion');
    });

    test('rejects an unknown game mode', () async {
      final json = await readManifestFixture();
      json['mode'] = 'arena';

      _expectPath(json, 'mode');
    });

    test('rejects a non-ISO generatedAt', () async {
      final json = await readManifestFixture();
      json['generatedAt'] = '2026-11-26';

      _expectPath(json, 'generatedAt');
    });

    test('rejects a non-UTC generatedAt', () async {
      final json = await readManifestFixture();
      json['generatedAt'] = '2026-11-26T10:32:14+01:00';

      _expectPath(json, 'generatedAt');
    });

    test('rejects an empty dataset array', () async {
      final json = await readManifestFixture();
      json['datasets'] = <Object?>[];

      _expectPath(json, 'datasets');
    });

    test('rejects a duplicate dataset', () async {
      final json = await readManifestFixture();
      _datasetAt(json, 1)['dataset'] = 'items';

      _expectPath(json, 'datasets[1].dataset');
    });

    test('rejects an unknown dataset name', () async {
      final json = await readManifestFixture();
      _firstDataset(json)['dataset'] = 'season';

      _expectPath(json, 'datasets[0].dataset');
    });

    test('rejects an absolute dataset path', () async {
      final json = await readManifestFixture();
      _firstDataset(json)['path'] = '/items.jsonl.zst';

      _expectPath(json, 'datasets[0].path');
    });

    test('rejects a parent-directory dataset path', () async {
      final json = await readManifestFixture();
      _firstDataset(json)['path'] = '../items.jsonl.zst';

      _expectPath(json, 'datasets[0].path');
    });

    test('rejects a backslash dataset path', () async {
      final json = await readManifestFixture();
      _firstDataset(json)['path'] = r'..\items.jsonl.zst';

      _expectPath(json, 'datasets[0].path');
    });

    test('rejects a dataset path with the wrong extension', () async {
      final json = await readManifestFixture();
      _firstDataset(json)['path'] = 'items.jsonl';

      _expectPath(json, 'datasets[0].path');
    });

    test('rejects a malformed sha256', () async {
      final json = await readManifestFixture();
      _firstDataset(json)['sha256'] = 'ABC123';

      _expectPath(json, 'datasets[0].sha256');
    });

    test('rejects a negative size', () async {
      final json = await readManifestFixture();
      _firstDataset(json)['compressedBytes'] = -1;

      _expectPath(json, 'datasets[0].compressedBytes');
    });

    test('rejects a non-positive dataset schema version', () async {
      final json = await readManifestFixture();
      _firstDataset(json)['schemaVersion'] = 0;

      _expectPath(json, 'datasets[0].schemaVersion');
    });

    test('rejects a missing dataset source object', () async {
      final json = await readManifestFixture();
      _firstDataset(json).remove('source');

      _expectPath(json, 'datasets[0].source');
    });

    test('rejects an unknown skipped reason', () async {
      final json = await readManifestFixture();
      json['skipped'] = <Object?>[
        <String, Object?>{'dataset': 'maps', 'reason': 'upstream-error'},
      ];

      _expectPath(json, 'skipped[0].reason');
    });
  });

  group('BundleManifest.checkCompatibility', () {
    test('accepts the published bundle versions', () async {
      final manifest = BundleManifest.parse(await readManifestFixture());

      final result = manifest.checkCompatibility();

      expect(result.status, ManifestCompatibility.compatible);
      expect(result.isCompatible, isTrue);
    });

    test('accepts an older bundle version', () async {
      final manifest = BundleManifest.parse(await readManifestFixture());

      final result = manifest.checkCompatibility(
        supportedBundleSchemaVersion: 2,
        appDataSchemaVersion: 2,
      );

      expect(result.status, ManifestCompatibility.compatible);
    });

    test('refuses a newer bundle schema', () async {
      final json = await readManifestFixture();
      json['bundleSchemaVersion'] = 2;
      final manifest = BundleManifest.parse(json);

      final result = manifest.checkCompatibility();

      expect(result.status, ManifestCompatibility.bundleUnsupported);
      expect(result.reason, contains('bundleSchemaVersion 2'));
    });

    test('refuses a bundle schema newer than a custom client', () async {
      final manifest = BundleManifest.parse(await readManifestFixture());

      final result = manifest.checkCompatibility(
        supportedBundleSchemaVersion: 0,
      );

      expect(result.status, ManifestCompatibility.bundleUnsupported);
    });

    test('requires an app update for a newer minAppSchemaVersion', () async {
      final json = await readManifestFixture();
      json['minAppSchemaVersion'] = 2;
      final manifest = BundleManifest.parse(json);

      final result = manifest.checkCompatibility();

      expect(result.status, ManifestCompatibility.appUpdateRequired);
      expect(result.reason, contains('minAppSchemaVersion 2'));
    });

    test('requires an app update for a custom older data schema', () async {
      final manifest = BundleManifest.parse(await readManifestFixture());

      final result = manifest.checkCompatibility(appDataSchemaVersion: 0);

      expect(result.status, ManifestCompatibility.appUpdateRequired);
    });

    test('reports an unsupported bundle before an app update', () async {
      final json = await readManifestFixture();
      json['bundleSchemaVersion'] = 2;
      json['minAppSchemaVersion'] = 2;
      final manifest = BundleManifest.parse(json);

      final result = manifest.checkCompatibility();

      expect(result.status, ManifestCompatibility.bundleUnsupported);
    });
  });
}

void _expectPath(Map<String, Object?> json, String path) {
  expect(
    () => BundleManifest.parse(json),
    throwsA(
      isA<ManifestFormatException>().having(
        (error) => error.path,
        'path',
        path,
      ),
    ),
  );
}

Map<String, Object?> _firstDataset(Map<String, Object?> manifest) =>
    _datasetAt(manifest, 0);

Map<String, Object?> _datasetAt(Map<String, Object?> manifest, int index) {
  final datasets = manifest['datasets'];
  if (datasets is! List<Object?>) {
    throw StateError('Fixture has no datasets array.');
  }
  final entry = datasets[index];
  if (entry is! Map<String, Object?>) {
    throw StateError('Fixture dataset $index is not an object.');
  }
  return entry;
}
