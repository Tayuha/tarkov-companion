import 'dart:async';

import 'package:flutter/services.dart';

import 'window_geometry.dart';

/// The method channel implemented by the Linux GTK runner.
///
/// Dart calls `getMetrics`, `setGeometry`, `focus` and `close`; the runner
/// calls back with `windowGeometryChanged` and `windowClosing`.
const String windowChannelName = 'dev.tarkovcompanion/window';

/// Window operations the app shell needs from the desktop runner.
///
/// An interface instead of a direct [MethodChannel] so the geometry binder can
/// be unit-tested with a fake platform.
abstract interface class WindowPlatform {
  /// The current window rectangle and monitor work areas, or `null` when the
  /// platform integration is unavailable.
  Future<WindowMetrics?> metrics();

  /// Moves and resizes the window.
  Future<void> setGeometry(WindowRect geometry);

  /// Brings the existing window to the front and gives it focus.
  Future<void> focus();

  /// Closes the window.
  Future<void> close();

  /// Emits the window rectangle after the user moves or resizes the window.
  Stream<WindowRect> get geometryChanges;

  /// Registers the handler run before the window is destroyed.
  ///
  /// The handler receives the last known rectangle; the platform closes the
  /// window after the handler future completes, even when it throws.
  void setClosingHandler(Future<void> Function(WindowRect? geometry)? handler);
}

/// The production Linux implementation over [windowChannelName].
final class LinuxWindowPlatform implements WindowPlatform {
  LinuxWindowPlatform({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(windowChannelName) {
    _channel.setMethodCallHandler(_handleCall);
  }

  final MethodChannel _channel;
  final StreamController<WindowRect> _changes =
      StreamController<WindowRect>.broadcast();
  Future<void> Function(WindowRect? geometry)? _onClosing;

  @override
  Stream<WindowRect> get geometryChanges => _changes.stream;

  @override
  void setClosingHandler(Future<void> Function(WindowRect? geometry)? handler) {
    _onClosing = handler;
  }

  @override
  Future<WindowMetrics?> metrics() async {
    final value = await _channel.invokeMethod<Object?>('getMetrics');
    return WindowMetrics.fromMap(value);
  }

  @override
  Future<void> setGeometry(WindowRect geometry) {
    return _channel.invokeMethod<void>('setGeometry', geometry.toJson());
  }

  @override
  Future<void> focus() => _channel.invokeMethod<void>('focus');

  @override
  Future<void> close() => _channel.invokeMethod<void>('close');

  Future<Object?> _handleCall(MethodCall call) async {
    if (call.method == 'windowGeometryChanged') {
      final rect = WindowRect.tryParse(call.arguments);
      if (rect != null) {
        _changes.add(rect);
      }
    } else if (call.method == 'windowClosing') {
      final rect = WindowRect.tryParse(call.arguments);
      try {
        await _onClosing?.call(rect);
      } finally {
        // The runner blocks its own close until this call lands. Closing here
        // guarantees the window still disappears when saving failed.
        await close();
      }
    }
    return null;
  }

  /// Releases the change stream. The runner owns the window itself.
  Future<void> dispose() => _changes.close();
}
