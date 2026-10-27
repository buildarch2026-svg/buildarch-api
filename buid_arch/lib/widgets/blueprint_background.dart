import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Architectural drafting grid, compass rings and crosshair lines
/// drawn behind the login hero (from the design's SVG overlay).
class BlueprintBackgroundPainter extends CustomPainter {
  const BlueprintBackgroundPainter();

  static const double _cell = 40;

  @override
  void paint(Canvas canvas, Size size) {
    // The whole overlay sits at 20% opacity in the design.
    final gridPaint = Paint()
      ..color = AppColors.copper.withAlpha(51)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;
    final dotPaint = Paint()..color = AppColors.copper.withAlpha(51);

    for (double x = 0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (double x = 0; x <= size.width; x += _cell) {
      for (double y = 0; y <= size.height; y += _cell) {
        canvas.drawCircle(Offset(x, y), 1.5, dotPaint);
      }
    }

    final center = Offset(size.width / 2, size.height * 0.28);

    // Dashed cream ring (r=140)
    final ringDashed = Paint()
      ..color = AppColors.creamSand.withAlpha(31)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;
    _drawDashed(
      canvas,
      Path()..addOval(Rect.fromCircle(center: center, radius: 140)),
      ringDashed,
      dash: 4,
      gap: 6,
    );

    // Solid copper ring (r=185)
    final ringSolid = Paint()
      ..color = AppColors.copper.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    canvas.drawCircle(center, 185, ringSolid);

    // Dashed crosshair lines
    final crossPaint = Paint()
      ..color = AppColors.copper.withAlpha(20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    _drawDashed(
      canvas,
      Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width / 2, size.height),
      crossPaint,
      dash: 2,
      gap: 4,
    );
    _drawDashed(
      canvas,
      Path()
        ..moveTo(0, center.dy)
        ..lineTo(size.width, center.dy),
      crossPaint,
      dash: 2,
      gap: 4,
    );
  }

  static void _drawDashed(Canvas canvas, Path path, Paint paint,
      {required double dash, required double gap}) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
