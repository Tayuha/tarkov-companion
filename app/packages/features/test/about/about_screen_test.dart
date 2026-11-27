import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../theme/support/load_fonts.dart';

final _now = DateTime.utc(2026, 11, 27, 12);

DataBundleStatus _data() {
  return DataBundleStatus(
    mode: GameMode.regular,
    appliedDatasets: 7,
    expectedDatasets: 7,
    oldestAppliedAt: DateTime.utc(2026, 11, 25, 12),
    newestAppliedAt: DateTime.utc(2026, 11, 25, 18),
    newestSourceUpdatedAt: DateTime.utc(2026, 11, 24, 10),
    manifestVersion: 1,
    bundleSchemaVersion: 1,
    manifestGeneratedAt: DateTime.utc(2026, 11, 24, 10, 32),
    manifestCheckedAt: DateTime.utc(2026, 11, 27, 9),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadDesignFonts();
  });

  Future<void> pumpAbout(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.view.reset();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: AboutScreen(appVersion: '0.1.0', data: _data(), now: () => _now),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows version, data provenance, licence and attribution', (
    tester,
  ) async {
    await pumpAbout(tester);

    expect(tester.widget<Text>(find.byKey(AboutKeys.appVersion)).data, '0.1.0');
    expect(
      tester.widget<Text>(find.byKey(AboutKeys.bundleVersion)).data,
      'manifest 1 · schema 1',
    );
    expect(
      tester.widget<Text>(find.byKey(AboutKeys.datasetAge)).data,
      '2 days old',
    );
    expect(find.text('7 of 7'), findsOneWidget);
    expect(find.textContaining('tarkov.dev'), findsWidgets);
    expect(find.textContaining('Battlestate Games'), findsOneWidget);
    expect(find.textContaining('No game art'), findsOneWidget);
    expect(find.byKey(AboutKeys.licence), findsOneWidget);
    expect(find.textContaining('MIT LICENCE'), findsOneWidget);
  });

  testWidgets('handles a session with no applied data', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const AboutScreen(appVersion: '0.1.0'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(AboutKeys.bundleVersion)).data,
      'Not inspected',
    );
    expect(
      tester.widget<Text>(find.byKey(AboutKeys.datasetAge)).data,
      'Not inspected',
    );
  });

  testWidgets('golden at a fixed desktop size', (tester) async {
    await pumpAbout(tester);

    await expectLater(
      find.byKey(AboutKeys.screen),
      matchesGoldenFile('goldens/about_900.png'),
    );
  });
}
