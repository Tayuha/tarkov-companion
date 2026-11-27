import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tarkov_companion/src/app_session.dart';
import 'package:tarkov_companion/src/window_geometry.dart';
import 'package:tarkov_companion/src/window_geometry_binder.dart';
import 'package:tarkov_companion/src/window_platform.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

const _workArea = WindowRect(x: 0, y: 0, width: 1920, height: 1040);

final class _FakeSync implements SyncService {
  @override
  Future<SyncPreparation> prepare(GameMode mode) => throw UnimplementedError();

  @override
  Future<SyncRunResult> run(
    GameMode mode, {
    SyncProgressListener? onProgress,
    DownloadCancellationToken? cancellation,
    SyncPreparation? preparation,
  }) => throw UnimplementedError();
}

final class _FakeWindowPlatform implements WindowPlatform {
  WindowMetrics? metricsValue;
  final List<WindowRect> applied = [];
  final StreamController<WindowRect> changes =
      StreamController<WindowRect>.broadcast();
  Future<void> Function(WindowRect? geometry)? closing;

  @override
  Future<WindowMetrics?> metrics() async => metricsValue;

  @override
  Future<void> setGeometry(WindowRect geometry) async {
    applied.add(geometry);
  }

  @override
  Future<void> focus() async {}

  @override
  Future<void> close() async {}

  @override
  Stream<WindowRect> get geometryChanges => changes.stream;

  @override
  void setClosingHandler(Future<void> Function(WindowRect? geometry)? handler) {
    closing = handler;
  }
}

void main() {
  late AppDatabase database;
  late SettingsRepository settings;
  late _FakeWindowPlatform platform;
  late WindowGeometryBinder binder;

  setUp(() async {
    database = AppDatabase.memory();
    await database.customSelect('SELECT 1').get();
    settings = SettingsRepository(database);
    platform = _FakeWindowPlatform()
      ..metricsValue = const WindowMetrics(
        window: WindowRect(x: 0, y: 0, width: 1280, height: 720),
        workAreas: [_workArea],
      );
    binder = WindowGeometryBinder(platform: platform, saveDelay: Duration.zero);
    await binder.start();
  });

  tearDown(() async {
    await binder.dispose();
    await platform.changes.close();
    await database.close();
  });

  AppSessionReady session() => AppSessionReady(
    sync: _FakeSync(),
    hasAppliedDatasets: true,
    settings: settings,
    close: () async {},
  );

  test('bind restores and clamps a partly off-screen rectangle', () async {
    await settings.setWindowGeometryJson(
      WindowGeometry.encode(
        const WindowRect(x: -100, y: -50, width: 1000, height: 700),
      ),
    );

    await binder.bind(session());

    expect(platform.applied, [
      const WindowRect(x: 0, y: 0, width: 1000, height: 700),
    ]);
  });

  test(
    'bind applies the minimum size to a too-small saved rectangle',
    () async {
      await settings.setWindowGeometryJson(
        WindowGeometry.encode(
          const WindowRect(x: 40, y: 30, width: 300, height: 200),
        ),
      );

      await binder.bind(session());

      final applied = platform.applied.single;
      expect(applied.width, WindowGeometry.minWidth);
      expect(applied.height, WindowGeometry.minHeight);
    },
  );

  test('a first launch applies the centered default geometry', () async {
    await binder.bind(session());

    expect(
      platform.applied.single,
      const WindowRect(x: 320, y: 160, width: 1280, height: 720),
    );
  });

  test('a window move is saved after the debounce', () async {
    await binder.bind(session());
    const moved = WindowRect(x: 220, y: 100, width: 1100, height: 760);

    platform.changes.add(moved);
    await pumpEventQueue();

    expect(
      WindowGeometry.decode(await settings.readWindowGeometryJson()),
      moved,
    );
  });

  test('closing saves the final rectangle', () async {
    await binder.bind(session());
    const finalRect = WindowRect(x: 50, y: 60, width: 900, height: 640);

    await platform.closing!(finalRect);

    expect(
      WindowGeometry.decode(await settings.readWindowGeometryJson()),
      finalRect,
    );
  });

  test('a session without settings leaves the window untouched', () async {
    final noSettings = AppSessionReady(
      sync: _FakeSync(),
      hasAppliedDatasets: true,
      close: () async {},
    );

    await binder.bind(noSettings);

    expect(platform.applied, isEmpty);
  });
}
