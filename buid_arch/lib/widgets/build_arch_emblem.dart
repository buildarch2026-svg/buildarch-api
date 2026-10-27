import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Round logo badge. The house mark is drawn in code so it works without
/// network access; swap the CustomPaint for Image.asset('assets/images/logo.png')
/// once you export the real logo from the design.
class BuildArchEmblem extends StatelessWidget {
  const BuildArchEmblem({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft copper glow behind the badge
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.secondaryContainer.withAlpha(77),
                blurRadius: 14,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
        Container(
          width: 96,
          height: 96,
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.darkBrown,
            boxShadow: [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 25,
                spreadRadius: -5,
                offset: Offset(0, 20),
              ),
            ],
          ),
          child: const CustomPaint(
            size: Size(80, 80),
            painter: _EmblemPainter(),
          ),
        ),
      ],
    );
  }
}

class _EmblemPainter extends CustomPainter {
  const _EmblemPainter();

  Path _house(Size s, {double inset = 0}) {
    final w = s.width;
    final h = s.height;
    final i = inset;
    return Path()
      ..moveTo(w / 2, i)
      ..lineTo(w - i, h * 0.30 + i * 0.5)
      ..lineTo(w - i, h - i)
      ..lineTo(i, h - i)
      ..lineTo(i, h * 0.30 + i * 0.5)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const bronze = Color(0xFFC8793A);
    final w = size.width;
    final h = size.height;

    // Outer house outline
    canvas.drawPath(
      _house(Size(w * 0.82, h * 0.78)).shift(Offset(w * 0.09, h * 0.12)),
      Paint()
        ..color = bronze
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );

    // Dotted inner outline
    final dotted = _house(Size(w * 0.70, h * 0.66), inset: 0)
        .shift(Offset(w * 0.15, h * 0.18));
    final dotPaint = Paint()
      ..color = bronze
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final m in dotted.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + 1.5, m.length)), dotPaint);
        d += 4;
      }
    }

    // Small white house in the middle
    final inner = Path()
      ..moveTo(w * 0.5, h * 0.30)
      ..lineTo(w * 0.74, h * 0.46)
      ..lineTo(w * 0.74, h * 0.80)
      ..lineTo(w * 0.26, h * 0.80)
      ..lineTo(w * 0.26, h * 0.46)
      ..close();
    canvas.drawPath(
      inner,
      Paint()
        ..color = AppColors.creamSand
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Center dot
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.50),
      w * 0.06,
      Paint()..color = const Color(0xFFE08A2E),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
