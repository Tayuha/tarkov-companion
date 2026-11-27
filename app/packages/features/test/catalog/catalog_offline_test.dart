import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../support/catalog_screen_fixture.dart';

/// Catalog network-state tests.
///
/// The local database is real and fully populated (or explicitly empty); only
/// the upstream check is a failing seam. That is the point of the task: saved
/// rows must survive a failed network check, and retry must re-run the check.
void main() {
  late AppDatabase database;
  late CatalogRepository repository;

  setUp(() async {
    database = await openCatalogFixtureDatabase();
    repository = CatalogRepository(database);
  });

  tearDown(() => database.close());

  Future<void> pumpCatalog(
    WidgetTester tester, {
    required UpstreamCheck? upstreamCheck,
    Size size = const Size(1440, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: CatalogScreen(
          repository: repository,
          categories: fixtureCategories,
          types: fixtureTypes,
          upstreamCheck: upstreamCheck,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('cached rows stay visible when the upstream is offline', (
    tester,
  ) async {
    var checks = 0;
    Future<UpstreamStatus> failing() async {
      checks++;
      throw const SyncOfflineException(
        mode: GameMode.regular,
        message: 'The manifest could not be reached.',
      );
    }

    await pumpCatalog(tester, upstreamCheck: failing);

    expect(checks, 1);
    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);
    expect(find.byKey(const Key('catalog-upstream-status')), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.textContaining('Showing saved data'), findsOneWidget);
    expect(find.byKey(const Key('app-status-retry')), findsOneWidget);
    expect(find.byKey(const Key('catalog-error-banner')), findsNothing);
  });

  testWidgets('retry re-runs the upstream check without clearing rows', (
    tester,
  ) async {
    var checks = 0;
    Future<UpstreamStatus> failing() async {
      checks++;
      return const UpstreamStatus.offline();
    }

    await pumpCatalog(tester, upstreamCheck: failing);
    expect(checks, 1);

    await tester.tap(find.byKey(const Key('app-status-retry')));
    await tester.pumpAndSettle();

    expect(checks, 2);
    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);
    expect(find.byKey(const Key('catalog-upstream-status')), findsOneWidget);
  });

  testWidgets('a retry in flight is announced without hiding rows', (
    tester,
  ) async {
    final second = Completer<UpstreamStatus>();
    var checks = 0;
    Future<UpstreamStatus> check() async {
      checks++;
      if (checks == 1) {
        return const UpstreamStatus.offline();
      }
      return second.future;
    }

    await pumpCatalog(tester, upstreamCheck: check);
    await tester.tap(find.byKey(const Key('app-status-retry')));
    await tester.pump();

    expect(find.text('CHECKING FOR UPDATES'), findsOneWidget);
    expect(find.text('Colt M4A1 5.56x45 assault rifle'), findsOneWidget);

    second.complete(const UpstreamStatus.current());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('catalog-upstream-status')), findsNothing);
    expect(find.text('Showing 12 of 12 items'), findsOneWidget);
  });

  testWidgets('empty local data shows the explicit offline state with retry', (
    tester,
  ) async {
    final empty = AppDatabase.memory();
    await database.close();
    await empty.customSelect('SELECT 1').get(); // Force `beforeOpen`.
    database = empty;
    repository = CatalogRepository(empty);

    var checks = 0;
    Future<UpstreamStatus> failing() async {
      checks++;
      return const UpstreamStatus.offline();
    }

    await pumpCatalog(tester, upstreamCheck: failing);

    expect(checks, 1);
    expect(
      find.byKey(const Key('catalog-offline-empty-title')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('catalog-offline-empty-detail')),
      findsOneWidget,
    );
    expect(
      find.textContaining('reads from the local dataset first'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('catalog-offline-retry')), findsOneWidget);
    expect(find.byKey(const Key('catalog-list')), findsNothing);
    expect(find.byKey(const Key('catalog-upstream-status')), findsNothing);

    await tester.tap(find.byKey(const Key('catalog-offline-retry')));
    await tester.pumpAndSettle();
    expect(checks, 2);
  });
}
