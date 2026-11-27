import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

import '../theme/support/load_fonts.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadDesignFonts();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(child: SizedBox(width: 640, child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offline strip shows cached-data copy, age and retry', (
    tester,
  ) async {
    var retries = 0;
    await pump(
      tester,
      AppStatusStrip.upstream(
        key: const Key('strip'),
        status: UpstreamStatus.offline(
          dataUpdatedAt: DateTime.utc(2026, 11, 24, 12),
        ),
        now: DateTime.utc(2026, 11, 27, 12),
        onRetry: () => retries++,
      ),
    );

    expect(find.byKey(const Key('strip')), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.textContaining('Showing saved data'), findsOneWidget);
    expect(find.byKey(const Key('app-status-age')), findsOneWidget);
    expect(find.text('Saved data 3 days ago'), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-status-retry')));
    expect(retries, 1);
  });

  testWidgets('failed strip names the upstream and keeps the retry', (
    tester,
  ) async {
    await pump(
      tester,
      AppStatusStrip.upstream(
        status: const UpstreamStatus.failed(message: 'HTTP 503 response.'),
      ),
    );

    expect(find.text('UPSTREAM UNAVAILABLE'), findsOneWidget);
    expect(find.textContaining('HTTP 503 response.'), findsOneWidget);
    expect(find.byKey(const Key('app-status-retry')), findsNothing);
  });

  testWidgets('stale strip keeps the chart age and omits no-data copy', (
    tester,
  ) async {
    await pump(
      tester,
      AppStatusStrip.upstream(
        status: UpstreamStatus.stale(
          dataUpdatedAt: DateTime.utc(2026, 11, 27, 7),
        ),
        now: DateTime.utc(2026, 11, 27, 12),
      ),
    );

    expect(find.text('SAVED DATA'), findsOneWidget);
    expect(find.text('Saved data 5 h ago'), findsOneWidget);
    expect(find.byKey(const Key('app-status-retry')), findsNothing);
  });

  testWidgets('updating strip never offers a retry', (tester) async {
    await pump(
      tester,
      AppStatusStrip(kind: AppStatusStripKind.updating, onRetry: () {}),
    );

    expect(find.text('CHECKING FOR UPDATES'), findsOneWidget);
    expect(find.byKey(const Key('app-status-retry')), findsNothing);
  });

  test('formatStatusAge is coarse and never negative', () {
    final now = DateTime.utc(2026, 11, 27, 12);
    expect(formatStatusAge(now, now: now), 'just now');
    expect(
      formatStatusAge(now.subtract(const Duration(seconds: 30)), now: now),
      'just now',
    );
    expect(
      formatStatusAge(now.subtract(const Duration(minutes: 7)), now: now),
      '7 min ago',
    );
    expect(
      formatStatusAge(now.subtract(const Duration(hours: 5)), now: now),
      '5 h ago',
    );
    expect(
      formatStatusAge(now.subtract(const Duration(days: 1)), now: now),
      '1 day ago',
    );
    expect(
      formatStatusAge(now.subtract(const Duration(days: 9)), now: now),
      '9 days ago',
    );
    expect(
      formatStatusAge(now.add(const Duration(hours: 2)), now: now),
      'just now',
    );
  });

  test('fromError classifies connectivity separately from other failures', () {
    final offline = UpstreamStatus.fromError(
      const SocketException('no route to host'),
    );
    expect(offline.state, UpstreamState.offline);
    expect(offline.isProblem, isTrue);

    final syncOffline = UpstreamStatus.fromError(
      const SyncOfflineException(
        mode: GameMode.regular,
        message: 'The manifest could not be reached.',
      ),
    );
    expect(syncOffline.state, UpstreamState.offline);
    expect(syncOffline.message, 'The manifest could not be reached.');

    final failed = UpstreamStatus.fromError(StateError('bad local write'));
    expect(failed.state, UpstreamState.failed);
    expect(failed.isProblem, isTrue);

    expect(isUpstreamError(StateError('local')), isFalse);
    expect(
      isUpstreamError(
        const SyncOfflineException(mode: GameMode.regular, message: 'offline'),
      ),
      isTrue,
    );
  });
}
