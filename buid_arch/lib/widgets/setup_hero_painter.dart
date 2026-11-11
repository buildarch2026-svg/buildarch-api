import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Dashed blueprint grid, compass rings, and crosshairs behind the
/// "Secure Your Account" hero.
class SetupHeroPainter extends CustomPainter {
  const SetupHeroPainter();

  static const double _cell = 36;

  @override
  void paint(Canvas canvas, Size size) {
    // Whole overlay is at 25% opacity in the design.
    final copper25 = AppColors.copper.withAlpha(64);

    // Dashed grid (2px dash, 3px gap)
    final gridPath = Path();
    for (double y = 0; y <= size.height; y += _cell) {
      for (double x = 0; x < size.width; x += 5) {
        gridPath
          ..moveTo(x, y)
          ..lineTo(math.min(x + 2, size.width), y);
      }
    }
    for (double x = 0; x <= size.width; x += _cell) {
      for (double y = 0; y < size.height; y += 5) {
        gridPath
          ..moveTo(x, y)
          ..lineTo(x, math.min(y + 2, size.height));
      }
    }
    canvas.drawPath(
      gridPath,
      Paint()
        ..color = copper25
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );

    final center = Offset(size.width / 2, size.height * 0.48);

    // Rings
    _dashedCircle(canvas, center, 68, copper25, 1, dash: 4, gap: 4);
    canvas.drawCircle(
      center,
      102,
      Paint()
        ..color = AppColors.copper.withAlpha(38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );
    _dashedCircle(canvas, center, 138, copper25, 0.5, dash: 1, gap: 6);

    // Crosshairs
    final cross = Paint()
      ..color = AppColors.copper.withAlpha(26)
      ..strokeWidth = 0.75;
    canvas.drawLine(
      Offset(center.dx, 12),
      Offset(center.dx, math.min(240, size.height - 12)),
      cross,
    );
    canvas.drawLine(
      Offset(20, center.dy),
      Offset(size.width - 20, center.dy),
      cross,
    );
    canvas.drawCircle(center, 3, Paint()..color = copper25);
  }

  void _dashedCircle(
      Canvas canvas, Offset center, double radius, Color color, double width,
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
