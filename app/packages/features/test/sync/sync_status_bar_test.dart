import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';
import 'package:tarkov_companion_features/tarkov_companion_features.dart';

final _now = DateTime.utc(2026, 11, 27, 12);

void main() {
  Future<void> pumpBar(
    WidgetTester tester,
    FakeUpdateControl control, {
    VoidCallback? onAbout,
    Size size = const Size(1100, 260),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() {
      tester.binding.setSurfaceSize(null);
      tester.view.reset();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SyncStatusBar(
              control: control,
              onAbout: onAbout,
              now: () => _now,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the never-checked state offers a manual check', (tester) async {
    final control = FakeUpdateControl(
      status: const UpdateCheckStatus(schedule: UpdateSchedule.daily),
    );

    await pumpBar(tester, control);

    expect(find.text('Not checked yet'), findsOneWidget);
    expect(find.text('DAILY'), findsOneWidget);
    expect(find.byKey(SyncStatusKeys.checkNow), findsOneWidget);
  });

  final outcomeCases = <(UpdateOutcome, String, String?)>[
    (UpdateOutcome.succeeded, 'Game data is up to date', '2 h ago'),
    (UpdateOutcome.failed, 'Last update check failed', 'manifest unreachable'),
    (UpdateOutcome.skippedOffline, 'Offline', '1 day ago'),
    (UpdateOutcome.skipped, 'Last update check was skipped', '1 day ago'),
  ];

  for (final (outcome, label, detail) in outcomeCases) {
    testWidgets('renders the ${outcome.wireValue} outcome without a dialog', (
      tester,
    ) async {
      final control = FakeUpdateControl(
        status: UpdateCheckStatus(
          schedule: UpdateSchedule.daily,
          lastCheckAt: _now.subtract(
            outcome == UpdateOutcome.succeeded
                ? const Duration(hours: 2)
                : const Duration(days: 1),
          ),
          outcome: outcome,
          errorMessage: outcome == UpdateOutcome.failed
              ? 'manifest unreachable'
              : null,
        ),
      );

      await pumpBar(tester, control);

      expect(tester.widget<Text>(find.byKey(SyncStatusKeys.label)).data, label);
      if (detail != null) {
        expect(
          tester
              .widget<Text>(find.byKey(SyncStatusKeys.detail))
              .data!
              .contains(detail),
          isTrue,
        );
      }
      expect(find.byType(Dialog), findsNothing);
    });
  }

  testWidgets('a running check shows progress and disables Check now', (
    tester,
  ) async {
    final control = FakeUpdateControl(
      status: const UpdateCheckStatus(
        schedule: UpdateSchedule.weekly,
        phase: UpdateCheckPhase.checking,
        progress: 0.4,
      ),
    );

    await pumpBar(tester, control);

    expect(find.text('Downloading updates…'), findsOneWidget);
    expect(find.byKey(SyncStatusKeys.progress), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byKey(SyncStatusKeys.checkNow)).onPressed,
      isNull,
    );
  });

  testWidgets('the off schedule is visible and Check now stays usable', (
    tester,
  ) async {
    final control = FakeUpdateControl(
      status: const UpdateCheckStatus(schedule: UpdateSchedule.off),
    );

    await pumpBar(tester, control);

    expect(find.text('Automatic updates off'), findsOneWidget);
    expect(find.text('OFF'), findsOneWidget);
    expect(
      tester.widget<AppButton>(find.byKey(SyncStatusKeys.checkNow)).onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<Text>(find.byKey(SyncStatusKeys.detail))
          .data!
          .contains('Press Check now'),
      isTrue,
    );
  });

  testWidgets('choosing a schedule updates the controller', (tester) async {
    final control = FakeUpdateControl(
      status: const UpdateCheckStatus(schedule: UpdateSchedule.daily),
    );
    await pumpBar(tester, control);

    await tester.tap(find.byKey(SyncStatusKeys.schedule));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WEEKLY').last);
    await tester.pumpAndSettle();

    expect(control.schedules, [UpdateSchedule.weekly]);
  });

  testWidgets('Check now calls the controller', (tester) async {
    final control = FakeUpdateControl(
      status: const UpdateCheckStatus(schedule: UpdateSchedule.daily),
    );
    await pumpBar(tester, control);

    await tester.tap(find.byKey(SyncStatusKeys.checkNow));
    await tester.pump();

    expect(control.checkNowCalls, 1);
  });

  testWidgets('the About control is wired to the shell', (tester) async {
    var taps = 0;
    final control = FakeUpdateControl(
      status: const UpdateCheckStatus(schedule: UpdateSchedule.daily),
    );
    await pumpBar(tester, control, onAbout: () => taps++);

    await tester.tap(find.byKey(SyncStatusKeys.about));
    await tester.pump();

    expect(taps, 1);
  });
}

final class FakeUpdateControl implements UpdateCheckControl {
  FakeUpdateControl({required this.status});

  @override
  UpdateCheckStatus status;

  final _controller = StreamController<UpdateCheckStatus>.broadcast();
  final List<UpdateSchedule> schedules = [];
  int checkNowCalls = 0;

  @override
  Stream<UpdateCheckStatus> get changes => _controller.stream;

  void emit(UpdateCheckStatus next) {
    status = next;
    _controller.add(next);
  }

  @override
  Future<void> start() async {}

  @override
  Future<UpdateCheckStatus> checkNow() async {
    checkNowCalls++;
    return status;
  }

  @override
  Future<void> setSchedule(UpdateSchedule schedule) async {
    schedules.add(schedule);
    emit(UpdateCheckStatus(schedule: schedule));
  }

  @override
  Future<void> dispose() => _controller.close();
}
