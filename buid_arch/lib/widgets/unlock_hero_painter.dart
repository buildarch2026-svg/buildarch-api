import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Dashed CAD grid, compass rings and crosshair lines behind the
/// returning-user hero. Everything sits at 20% opacity in the design.
class UnlockHeroPainter extends CustomPainter {
  const UnlockHeroPainter({required this.avatarCenterY});

  /// Y position of the avatar centre; the compass rings are centred on it.
  final double avatarCenterY;

  static const double _cell = 32;

  @override
  void paint(Canvas canvas, Size size) {
    final color = AppColors.copper.withAlpha(51);

    // Dashed grid (2px dash, 2px gap)
    final grid = Path();
    for (double y = 0; y <= size.height; y += _cell) {
      for (double x = 0; x < size.width; x += 4) {
        grid
          ..moveTo(x, y)
          ..lineTo(math.min(x + 2, size.width), y);
      }
    }
    for (double x = 0; x <= size.width; x += _cell) {
      for (double y = 0; y < size.height; y += 4) {
        grid
          ..moveTo(x, y)
          ..lineTo(x, math.min(y + 2, size.height));
      }
    }
    canvas.drawPath(
      grid,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );

    final center = Offset(size.width / 2, avatarCenterY);

    _dashedCircle(canvas, center, 80, color, 0.75, dash: 4, gap: 4);
    _dashedCircle(canvas, center, 115, color, 0.5, dash: 1, gap: 5);

    // Dashed crosshairs (3px dash, 3px gap)
    _dashedLine(
      canvas,
      Offset(size.width * 0.1, center.dy),
      Offset(size.width * 0.9, center.dy),
      color,
    );
    _dashedLine(
      canvas,
      Offset(center.dx, center.dy - 100),
      Offset(center.dx, center.dy + 100),
      color,
    );
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Color color) {
    final path = Path();
    final horizontal = a.dy == b.dy;
    final length = horizontal ? (b.dx - a.dx) : (b.dy - a.dy);
    for (double d = 0; d < length; d += 6) {
      final end = math.min(d + 3, length);
      if (horizontal) {
        path
          ..moveTo(a.dx + d, a.dy)
          ..lineTo(a.dx + end, a.dy);
      } else {
        path
          ..moveTo(a.dx, a.dy + d)
          ..lineTo(a.dx, a.dy + end);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5,
    );
  }

  void _dashedCircle(Canvas canvas, Offset center, double radius, Color color,
      double width,
      {required double dash, required double gap}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + dash, metric.length)),
          paint,
        );
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant UnlockHeroPainter old) =>
      old.avatarCenterY != avatarCenterY;
}
