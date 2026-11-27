import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

/// First-render budget from task 5.9.
const int firstRenderBudgetMilliseconds = 1500;

/// Finds the committed full items fixture by walking up from the working
/// directory, so the test runs from `app/`, the workspace root or the package
/// directory.
Directory _benchmarkDirectory() {
  var directory = Directory.current;
  while (true) {
    for (final relative in const [
      'packages/data/test/fixtures/benchmark',
      'app/packages/data/test/fixtures/benchmark',
      'test/fixtures/benchmark',
    ]) {
      final candidate = Directory('${directory.path}/$relative');
      if (File('${candidate.path}/manifest.json').existsSync()) {
        return candidate;
      }
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate the benchmark items fixture.');
    }
    directory = parent;
  }
}

void main() {
  late AppDatabase database;
  late CatalogRepository repository;
  late Directory temporary;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    temporary = Directory.systemTemp.createTempSync(
      'catalog_render_benchmark_',
    );
    database = AppDatabase.memory();
    await database.customSelect('SELECT 1').get();

    final directory = _benchmarkDirectory();
    final manifest = BundleManifest.parse(
      jsonDecode(await File('${directory.path}/manifest.json').readAsString()),
    );
    final entry = manifest.datasets
        .where((dataset) => dataset.dataset == DatasetKind.items)
        .single;
    await DatasetIngestor(database).ingest(
      mode: GameMode.regular,
      dataset: entry,
      compressedFile: File('${directory.path}/${entry.path}'),
    );
    repository = CatalogRepository(database);
  });

  tearDownAll(() async {
    await database.close();
    if (temporary.existsSync()) {
      temporary.deleteSync(recursive: true);
    }
  });

  testWidgets('the full catalog renders its first page under 1.5 s', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final stopwatch = Stopwatch()..start();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: CatalogScreen(repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    stopwatch.stop();

    expect(find.byKey(const Key('catalog-list')), findsOneWidget);
    expect(find.byType(CatalogTableRow), findsWidgets);
    expect(find.text('Showing 50 of 5498 items'), findsOneWidget);

    // ignore: avoid_print
    print('catalog first render: ${stopwatch.elapsedMilliseconds} ms');
    expect(
      stopwatch.elapsedMilliseconds,
      lessThan(firstRenderBudgetMilliseconds),
      reason:
          'first catalog render took ${stopwatch.elapsedMilliseconds} ms; '
          'budget is $firstRenderBudgetMilliseconds ms',
    );
  });
}
