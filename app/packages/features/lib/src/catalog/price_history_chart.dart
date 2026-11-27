import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:tarkov_companion_data/tarkov_companion_data.dart';

import '../theme/app_tokens.dart';

/// The flea price history chart.
///
/// It is deliberately presentation-only: the caller supplies a
/// [PriceHistorySnapshot] that the data layer produced (network, cache, stale
/// or unavailable). The widget therefore never performs I/O, and the
/// offline-without-cache state is just a snapshot with
/// [PriceHistoryStatus.unavailable].
class PriceHistoryChart extends StatelessWidget {
  const PriceHistoryChart({
    super.key,
    required this.snapshot,
    this.height = 180,
  });

  final PriceHistorySnapshot snapshot;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    if (!snapshot.hasData) {
      return Row(
        key: const Key('price-history-unavailable'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.cloud_off_outlined, size: 18, color: tokens.muted),
          SizedBox(width: tokens.spaceSm),
          Expanded(
            child: Text(
              'Price history unavailable offline. No cached history exists '
              'for this item; it will load on the next online visit.',
              style: tokens.bodyStyle.copyWith(color: tokens.muted),
            ),
          ),
        ],
      );
    }

    final points = snapshot.points;
    final values = [for (final point in points) point.price];
    final min = values.reduce(math.min);
    final max = values.reduce(math.max);
    final first = points.first;
    final last = points.last;
    final delta = last.price - first.price;
    final deltaColor = delta == 0
        ? tokens.muted
        : (delta > 0 ? tokens.success : tokens.danger);

    return Column(
      key: const Key('price-history-chart'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: tokens.spaceLg,
          runSpacing: tokens.spaceXs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Figure(
              tokens: tokens,
              label: 'Latest',
              value: _roubles(last.price),
            ),
            _Figure(tokens: tokens, label: 'Lowest', value: _roubles(min)),
            _Figure(tokens: tokens, label: 'Highest', value: _roubles(max)),
            Text(
              '${delta >= 0 ? '+' : ''}${_roubles(delta)} over '
              '${points.length} observations',
              key: const Key('price-history-delta'),
              style: tokens.dataStyle.copyWith(color: deltaColor),
            ),
          ],
        ),
        SizedBox(height: tokens.spaceMd),
        if (points.length == 1)
          Text(
            'Only one observation is cached; a line needs at least two.',
            key: const Key('price-history-single-point'),
            style: tokens.bodyStyle.copyWith(color: tokens.muted),
          )
        else
          SizedBox(
            height: height,
            child: CustomPaint(
              key: const Key('price-history-plot'),
              painter: _PriceHistoryPainter(
                points: points,
                line: tokens.accent,
                fill: tokens.accent.withValues(alpha: 0.12),
                grid: tokens.borderSoft,
              ),
            ),
          ),
        SizedBox(height: tokens.spaceXs),
        Text(
          '${_stamp(first.observedAt)} → ${_stamp(last.observedAt)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: tokens.labelStyle,
        ),
        if (snapshot.status == PriceHistoryStatus.stale)
          Padding(
            padding: EdgeInsets.only(top: tokens.spaceXs),
            child: Text(
              'Showing cached history; the source could not be refreshed.',
              key: const Key('price-history-stale'),
              style: tokens.labelStyle.copyWith(color: tokens.value),
            ),
          ),
      ],
    );
  }

  static String _roubles(int value) {
    final digits = value.abs().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${value < 0 ? '-' : ''}$grouped ₽';
  }

  static String _stamp(DateTime value) {
    final utc = value.toUtc();
    final month = utc.month.toString().padLeft(2, '0');
    final day = utc.day.toString().padLeft(2, '0');
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    return '${utc.year}-$month-$day $hour:$minute UTC';
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.tokens,
    required this.label,
    required this.value,
  });

  final AppTokens tokens;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: tokens.labelStyle.copyWith(color: tokens.dim),
        ),
        SizedBox(width: tokens.spaceXs),
        Text(value, style: tokens.dataStyle.copyWith(color: tokens.text)),
      ],
    );
  }
}

/// Draws a padded polyline with a soft area fill.
///
/// The painter only knows the points, colours and canvas size; it has no state
/// and no theme lookup, so the widget stays cheap to rebuild.
final class _PriceHistoryPainter extends CustomPainter {
  const _PriceHistoryPainter({
    required this.points,
    required this.line,
    required this.fill,
    required this.grid,
  });

  final List<PriceHistoryPoint> points;
  final Color line;
  final Color fill;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) {
      return;
    }

    const padding = 8.0;
    final plotWidth = size.width - padding * 2;
    final plotHeight = size.height - padding * 2;
    if (plotWidth <= 0 || plotHeight <= 0) {
      return;
    }

    final values = [for (final point in points) point.price];
    var min = values.reduce(math.min).toDouble();
    var max = values.reduce(math.max).toDouble();
    if (min == max) {
      min -= 1;
      max += 1;
    }

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var index = 0; index <= 3; index++) {
      final y = padding + plotHeight * index / 3;
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );
    }

    final path = Path();
    for (var index = 0; index < points.length; index++) {
      final x = padding + plotWidth * index / (points.length - 1);
      final normalized = (points[index].price - min) / (max - min);
      final y = padding + plotHeight * (1 - normalized);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final area = Path.from(path)
      ..lineTo(size.width - padding, size.height - padding)
      ..lineTo(padding, size.height - padding)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    final lastX = size.width - padding;
    final lastNormalized = (points.last.price - min) / (max - min);
    final lastY = padding + plotHeight * (1 - lastNormalized);
    canvas.drawCircle(Offset(lastX, lastY), 3, Paint()..color = line);
  }

  @override
  bool shouldRepaint(_PriceHistoryPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.line != line ||
      oldDelegate.fill != fill ||
      oldDelegate.grid != grid;
}
