import 'dart:async';

import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import 'app_session.dart';
import 'window_geometry.dart';
import 'window_platform.dart';

/// Restores, applies and persists the desktop window geometry.
///
/// Restoring is best effort: a platform channel that is missing (for example
/// in a headless test) leaves the normal Flutter window untouched and never
/// fails the session. Saves are debounced because GTK emits a configure event
/// for every pixel of a drag.
final class WindowGeometryBinder {
  WindowGeometryBinder({
    required this.platform,
    this.saveDelay = const Duration(milliseconds: 500),
  });

  final WindowPlatform platform;

  /// Quiet period after the last move/resize before writing to the database.
  final Duration saveDelay;

  SettingsRepository? _settings;
  WindowRect? _lastKnown;
  Timer? _saveTimer;
  StreamSubscription<WindowRect>? _changes;
  bool _started = false;

  /// Subscribes to window changes and the close handshake.
  ///
  /// Call once before the window can be closed, even if the session never
  /// opens: [LinuxWindowPlatform] answers the runner's close request either
  /// way.
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    platform.setClosingHandler(_handleClosing);
    _changes = platform.geometryChanges.listen(_onGeometryChanged);
  }

  /// Reads the saved geometry, clamps it to the current monitors and applies
  /// it. Safe to call once per opened session.
  Future<void> bind(AppSession session) async {
    if (session is! AppSessionReady) {
      return;
    }
    final settings = session.settings;
    if (settings == null) {
      return;
    }
    _settings = settings;

    try {
      final metrics = await platform.metrics();
      if (metrics == null) {
        return;
      }
      final saved = WindowGeometry.decode(
        await settings.readWindowGeometryJson(),
      );
      final resolved = WindowGeometry.restore(
        saved: saved,
        workAreas: metrics.workAreas,
        primaryIndex: metrics.primaryIndex,
      );
      _lastKnown = resolved;
      await platform.setGeometry(resolved);
    } on Object {
      // A missing channel or a window manager that ignores moves is not a
      // startup failure: the app keeps its default geometry.
    }
  }

  Future<void> _handleClosing(WindowRect? geometry) async {
    if (geometry != null) {
      _lastKnown = geometry;
    }
    _saveTimer?.cancel();
    await _save();
  }

  void _onGeometryChanged(WindowRect geometry) {
    _lastKnown = geometry;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(_save()));
  }

  Future<void> _save() async {
    final settings = _settings;
    final geometry = _lastKnown;
    if (settings == null || geometry == null) {
      return;
    }
    try {
      await settings.setWindowGeometryJson(WindowGeometry.encode(geometry));
    } on Object {
      // Settings are best effort during shutdown; the next relaunch simply
      // starts from the previous saved rectangle.
    }
  }

  /// Stops timers and releases the change subscription.
  Future<void> dispose() async {
    _saveTimer?.cancel();
    await _changes?.cancel();
    _changes = null;
  }
}
