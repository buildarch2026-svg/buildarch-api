import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'fingerprint_icon.dart';

/// 96px round badge with copper rings and a fingerprint icon.
class BiometricBadge extends StatelessWidget {
  const BiometricBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      height: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ambient glow
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.copper.withAlpha(46),
                  blurRadius: 24,
                  spreadRadius: 6,
                ),
              ],
            ),
          ),
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.darkBrown,
              boxShadow: [
                BoxShadow(
                  color: Color(0x40000000),
                  blurRadius: 50,
                  spreadRadius: -12,
                  offset: Offset(0, 25),
                ),
              ],
            ),
            child: const Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _BadgeRingsPainter()),
                ),
                FingerprintIcon(
                  color: AppColors.copper,
                  size: 48,
                  strokeWidth: 1.6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeRingsPainter extends CustomPainter {
  const _BadgeRingsPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Outer solid ring
    canvas.drawCircle(
      center,
      46.5,
      Paint()
        ..color = AppColors.copper.withAlpha(217)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Inner dashed ring
    final dashed = Paint()
      ..color = AppColors.copper.withAlpha(153)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: 43));
    for (final metric in path.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + 2, metric.length)),
          dashed,
        );
        d += 5;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
