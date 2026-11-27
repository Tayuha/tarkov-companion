import 'dart:convert';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:test/test.dart';

import '../support/database_helpers.dart';
import '../support/manifest_fixtures.dart';

void main() {
  late AppDatabase db;
  late DatasetStateRepository states;
  late ManifestRepository manifests;

  setUp(() async {
    db = await openMemoryDatabase();
    states = DatasetStateRepository(db);
    manifests = ManifestRepository(db);
  });

  tearDown(() => db.close());

  test('summarises applied datasets and the cached manifest', () async {
    final fixture = await readManifestFixture();
    final raw = jsonEncode(fixture);
    await manifests.recordCheck(
      GameMode.regular,
      manifestJson: raw,
      contentHash: ManifestRepository.hashBytes(utf8.encode(raw)),
      checkedAt: DateTime.utc(2026, 11, 27, 9),
    );

    final manifest = BundleManifest.parse(fixture);
    await states.recordApplied(
      manifest.datasets.first,
      mode: GameMode.regular,
      appliedAt: DateTime.utc(2026, 11, 26, 12),
    );

    final status = await DataBundleStatus.read(
      mode: GameMode.regular,
      stateRepository: states,
      manifestRepository: manifests,
    );

    expect(status.appliedDatasets, 1);
    expect(status.expectedDatasets, DatasetKind.values.length);
    expect(status.isComplete, isFalse);
    expect(status.manifestVersion, 1);
    expect(status.bundleSchemaVersion, 1);
    expect(
      status.manifestGeneratedAt,
      DateTime.utc(2026, 11, 26, 10, 32, 14, 883),
    );
    expect(status.manifestCheckedAt, DateTime.utc(2026, 11, 27, 9));
    expect(status.oldestAppliedAt, DateTime.utc(2026, 11, 26, 12));
    expect(
      status.datasetAgeAt(DateTime.utc(2026, 11, 27, 12)),
      const Duration(days: 1),
    );
  });

  test('an empty database reports no applied data and no manifest', () async {
    final status = await DataBundleStatus.read(
      mode: GameMode.regular,
      stateRepository: states,
      manifestRepository: manifests,
    );

    expect(status.appliedDatasets, 0);
    expect(status.isComplete, isFalse);
    expect(status.manifestVersion, isNull);
    expect(status.datasetAgeAt(DateTime.utc(2026, 11, 27)), isNull);
  });

  test('a corrupt cached manifest keeps the dataset summary', () async {
    await manifests.recordCheck(
      GameMode.regular,
      manifestJson: '{not json',
      contentHash: ManifestRepository.hashBytes(utf8.encode('{not json')),
      checkedAt: DateTime.utc(2026, 11, 27, 9),
    );

    final status = await DataBundleStatus.read(
      mode: GameMode.regular,
      stateRepository: states,
      manifestRepository: manifests,
    );

    expect(status.manifestVersion, isNull);
    expect(status.manifestCheckedAt, DateTime.utc(2026, 11, 27, 9));
    expect(status.appliedDatasets, 0);
  });
}
