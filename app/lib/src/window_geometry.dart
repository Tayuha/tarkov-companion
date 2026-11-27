import 'dart:convert';
import 'dart:math' as math;

/// A rectangle in logical desktop pixels.
///
/// The coordinate space matches GTK: `x` grows right and `y` grows down, and
/// the origin belongs to the primary monitor's work area. The type is plain
/// Dart so restore/clamp rules can be unit-tested without a Flutter binding.
final class WindowRect {
  const WindowRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// The window's horizontal position.
  final double x;

  /// The window's vertical position.
  final double y;

  /// The window width.
  final double width;

  /// The window height.
  final double height;

  /// The right edge (`x + width`).
  double get right => x + width;

  /// The bottom edge (`y + height`).
  double get bottom => y + height;

  /// Whether every coordinate is finite.
  bool get isFinite =>
      x.isFinite && y.isFinite && width.isFinite && height.isFinite;

  /// Whether the rectangle has a positive width and height.
  bool get hasSize => width > 0 && height > 0;

  /// The area in square pixels, or zero for a degenerate rectangle.
  double get area => hasSize ? width * height : 0;

  /// The overlap with [other], or `null` when they do not intersect.
  WindowRect? intersection(WindowRect other) {
    final left = math.max(x, other.x);
    final top = math.max(y, other.y);
    final rightEdge = math.min(right, other.right);
    final bottomEdge = math.min(bottom, other.bottom);
    if (rightEdge <= left || bottomEdge <= top) {
      return null;
    }
    return WindowRect(
      x: left,
      y: top,
      width: rightEdge - left,
      height: bottomEdge - top,
    );
  }

  /// The JSON shape persisted under `settings.windowGeometry`.
  Map<String, double> toJson() => {
    'x': x,
    'y': y,
    'width': width,
    'height': height,
  };

  /// Parses a stored geometry document, or returns `null` when [value] is not
  /// a finite rectangle with a positive size.
  static WindowRect? tryParse(Object? value) {
    if (value is! Map) {
      return null;
    }
    final x = _number(value['x']);
    final y = _number(value['y']);
    final width = _number(value['width']);
    final height = _number(value['height']);
    if (x == null || y == null || width == null || height == null) {
      return null;
    }
    if (width <= 0 || height <= 0) {
      return null;
    }
    return WindowRect(x: x, y: y, width: width, height: height);
  }

  static double? _number(Object? value) {
    if (value is! num || !value.isFinite) {
      return null;
    }
    return value.toDouble();
  }

  @override
  bool operator ==(Object other) =>
      other is WindowRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() =>
      'WindowRect(x: $x, y: $y, width: $width, height: $height)';
}

/// The window and monitor work areas reported by the desktop runner.
final class WindowMetrics {
  const WindowMetrics({
    required this.window,
    required this.workAreas,
    this.primaryIndex = 0,
  });

  /// The current window rectangle.
  final WindowRect window;

  /// The usable area of every monitor, excluding panels and docks.
  final List<WindowRect> workAreas;

  /// Index of the primary monitor in [workAreas].
  final int primaryIndex;

  /// Decodes the method-channel map sent by the GTK runner.
  static WindowMetrics? fromMap(Object? value) {
    if (value is! Map) {
      return null;
    }
    final window = WindowRect.tryParse(value['window']);
    if (window == null) {
      return null;
    }
    final rawAreas = value['workAreas'];
    final areas = <WindowRect>[];
    if (rawAreas is List) {
      for (final raw in rawAreas) {
        final area = WindowRect.tryParse(raw);
        if (area != null) {
          areas.add(area);
        }
      }
    }
    final primary = value['primaryIndex'];
    return WindowMetrics(
      window: window,
      workAreas: List.unmodifiable(areas),
      primaryIndex: primary is int ? primary : 0,
    );
  }
}

/// Pure restore and clamp rules for the desktop window.
///
/// A saved rectangle is clamped inside the work area it overlaps most, so a
/// window last used on a second monitor reopens there. A rectangle that no
/// longer overlaps any monitor (for example after unplugging the display) is
/// clamped into the primary monitor instead of reopening off-screen.
abstract final class WindowGeometry {
  /// Smallest usable window width, mirrored by the GTK minimum-size hint.
  static const double minWidth = 800;

  /// Smallest usable window height, mirrored by the GTK minimum-size hint.
  static const double minHeight = 560;

  /// Default width for a first launch.
  static const double defaultWidth = 1280;

  /// Default height for a first launch.
  static const double defaultHeight = 720;

  /// Resolves the rectangle to apply at startup.
  ///
  /// [saved] is the previously persisted window rectangle, or `null` for a
  /// first launch. [workAreas] must contain at least one monitor for clamping;
  /// when it is empty the saved rectangle is returned unchanged, or the default
  /// size at the origin.
  static WindowRect restore({
    WindowRect? saved,
    required List<WindowRect> workAreas,
    int primaryIndex = 0,
  }) {
    final areas = workAreas
        .where((area) => area.isFinite && area.hasSize)
        .toList(growable: false);
    if (areas.isEmpty) {
      if (saved != null && saved.isFinite && saved.hasSize) {
        return saved;
      }
      return const WindowRect(
        x: 0,
        y: 0,
        width: defaultWidth,
        height: defaultHeight,
      );
    }

    final primary = areas[primaryIndex.clamp(0, areas.length - 1)];
    if (saved == null || !saved.isFinite || !saved.hasSize) {
      return _centered(primary);
    }

    final target = _largestOverlap(saved, areas) ?? primary;
    final width = _clamp(
      saved.width,
      minWidth,
      math.max(minWidth, target.width),
    );
    final height = _clamp(
      saved.height,
      minHeight,
      math.max(minHeight, target.height),
    );
    final maxX = math.max(target.x, target.right - width);
    final maxY = math.max(target.y, target.bottom - height);
    return WindowRect(
      x: _clamp(saved.x, target.x, maxX),
      y: _clamp(saved.y, target.y, maxY),
      width: width,
      height: height,
    );
  }

  /// Encodes [rect] as the JSON document stored in the settings table.
  static String encode(WindowRect rect) => jsonEncode(rect.toJson());

  /// Decodes a stored geometry document; bad JSON and bad shapes return `null`.
  static WindowRect? decode(String? source) {
    if (source == null || source.isEmpty) {
      return null;
    }
    try {
      return WindowRect.tryParse(jsonDecode(source));
    } on FormatException {
      return null;
    }
  }

  static WindowRect _centered(WindowRect area) {
    final width = _clamp(
      defaultWidth,
      minWidth,
      math.max(minWidth, area.width),
    );
    final height = _clamp(
      defaultHeight,
      minHeight,
      math.max(minHeight, area.height),
    );
    return WindowRect(
      x: area.x + ((area.width - width) / 2),
      y: area.y + ((area.height - height) / 2),
      width: width,
      height: height,
    );
  }

  static WindowRect? _largestOverlap(WindowRect saved, List<WindowRect> areas) {
    WindowRect? best;
    var bestArea = 0.0;
    for (final area in areas) {
      final overlap = saved.intersection(area);
      final overlapArea = overlap?.area ?? 0;
      if (overlapArea > bestArea) {
        bestArea = overlapArea;
        best = area;
      }
    }
    return best;
  }

  static double _clamp(double value, double min, double max) {
    if (value < min) {
      return min;
    }
    if (value > max) {
      return max;
    }
    return value;
  }
}
