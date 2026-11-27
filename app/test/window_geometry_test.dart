import 'package:flutter_test/flutter_test.dart';
import 'package:tarkov_companion/src/window_geometry.dart';

const _primary = WindowRect(x: 0, y: 0, width: 1920, height: 1040);
const _secondary = WindowRect(x: 1920, y: 0, width: 2560, height: 1400);

void main() {
  group('WindowGeometry.restore', () {
    test(
      'a first launch centers the default size in the primary work area',
      () {
        final resolved = WindowGeometry.restore(workAreas: const [_primary]);

        expect(
          resolved,
          const WindowRect(x: 320, y: 160, width: 1280, height: 720),
        );
      },
    );

    test('a saved rectangle inside the work area is restored unchanged', () {
      const saved = WindowRect(x: 100, y: 80, width: 1000, height: 700);

      final resolved = WindowGeometry.restore(
        saved: saved,
        workAreas: const [_primary],
      );

      expect(resolved, saved);
    });

    test('a partially off-screen rectangle is clamped to the visible area', () {
      final resolved = WindowGeometry.restore(
        saved: const WindowRect(x: -100, y: -50, width: 1000, height: 700),
        workAreas: const [_primary],
      );

      expect(resolved, const WindowRect(x: 0, y: 0, width: 1000, height: 700));
    });

    test('a rectangle hanging off the right and bottom edge moves inside', () {
      final resolved = WindowGeometry.restore(
        saved: const WindowRect(x: 1800, y: 900, width: 1000, height: 700),
        workAreas: const [_primary],
      );

      expect(
        resolved,
        const WindowRect(x: 920, y: 340, width: 1000, height: 700),
      );
    });

    test(
      'a completely off-screen rectangle falls back to the primary area',
      () {
        final resolved = WindowGeometry.restore(
          saved: const WindowRect(x: 4000, y: 3000, width: 1000, height: 700),
          workAreas: const [_primary],
        );

        expect(
          resolved,
          const WindowRect(x: 920, y: 340, width: 1000, height: 700),
        );
      },
    );

    test('a rectangle on a second monitor keeps its position', () {
      final resolved = WindowGeometry.restore(
        saved: const WindowRect(x: 2100, y: 120, width: 1000, height: 700),
        workAreas: const [_primary, _secondary],
      );

      expect(
        resolved,
        const WindowRect(x: 2100, y: 120, width: 1000, height: 700),
      );
    });

    test(
      'a saved rectangle on an unplugged monitor clamps into the primary',
      () {
        final resolved = WindowGeometry.restore(
          saved: const WindowRect(x: 5000, y: 2000, width: 1000, height: 700),
          workAreas: const [_primary, _secondary],
          primaryIndex: 1,
        );

        expect(
          resolved,
          const WindowRect(x: 3480, y: 700, width: 1000, height: 700),
        );
      },
    );

    test('the minimum size grows a saved rectangle that is too small', () {
      final resolved = WindowGeometry.restore(
        saved: const WindowRect(x: 100, y: 50, width: 400, height: 300),
        workAreas: const [_primary],
      );

      expect(resolved.width, WindowGeometry.minWidth);
      expect(resolved.height, WindowGeometry.minHeight);
      expect(resolved.x, 100);
      expect(resolved.y, 50);
    });

    test('a saved rectangle larger than the display is shrunk to fit', () {
      final resolved = WindowGeometry.restore(
        saved: const WindowRect(x: 10, y: 10, width: 3000, height: 3000),
        workAreas: const [_primary],
      );

      expect(resolved, _primary);
    });

    test('an invalid saved rectangle falls back to the centered default', () {
      final resolved = WindowGeometry.restore(
        saved: const WindowRect(x: 0, y: 0, width: 0, height: 0),
        workAreas: const [_primary],
      );

      expect(
        resolved,
        const WindowRect(x: 320, y: 160, width: 1280, height: 720),
      );
    });

    test('an empty monitor list keeps the saved rectangle', () {
      const saved = WindowRect(x: 40, y: 50, width: 900, height: 600);

      expect(WindowGeometry.restore(saved: saved, workAreas: const []), saved);
      expect(
        WindowGeometry.restore(workAreas: const []),
        const WindowRect(x: 0, y: 0, width: 1280, height: 720),
      );
    });
  });

  group('WindowGeometry persistence format', () {
    test('a rectangle round-trips through JSON', () {
      const rect = WindowRect(x: 12.5, y: -4, width: 900, height: 600);

      expect(WindowGeometry.decode(WindowGeometry.encode(rect)), rect);
    });

    test('bad and missing documents read as no saved geometry', () {
      expect(WindowGeometry.decode(null), isNull);
      expect(WindowGeometry.decode(''), isNull);
      expect(WindowGeometry.decode('{'), isNull);
      expect(WindowGeometry.decode('{"x":0}'), isNull);
      expect(
        WindowGeometry.decode('{"x":0,"y":0,"width":-1,"height":10}'),
        isNull,
      );
      expect(
        WindowGeometry.decode('{"x":0,"y":0,"width":"1","height":10}'),
        isNull,
      );
    });
  });

  group('WindowMetrics', () {
    test('decodes the runner map and ignores malformed work areas', () {
      final metrics = WindowMetrics.fromMap({
        'window': {'x': 1, 'y': 2, 'width': 3, 'height': 4},
        'workAreas': [
          {'x': 0, 'y': 0, 'width': 1920, 'height': 1040},
          {'x': 0, 'y': 0, 'width': 0, 'height': 0},
          'not a rect',
        ],
        'primaryIndex': 0,
      });

      expect(metrics, isNotNull);
      expect(
        metrics!.window,
        const WindowRect(x: 1, y: 2, width: 3, height: 4),
      );
      expect(metrics.workAreas, const [_primary]);
    });

    test('a map without a usable window is rejected', () {
      expect(WindowMetrics.fromMap(null), isNull);
      expect(WindowMetrics.fromMap({'workAreas': const []}), isNull);
    });
  });
}
