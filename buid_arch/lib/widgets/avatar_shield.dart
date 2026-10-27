import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import 'dashed_circle.dart';

/// 96px monogram avatar with copper guide rings and CAD tick marks.
class AvatarShield extends StatelessWidget {
  const AvatarShield({super.key, required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Badge with copper glow
          Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.darkBrown,
              boxShadow: [
                BoxShadow(
                  color: Color(0x38B87333),
                  blurRadius: 24,
                  offset: Offset(0, 8),
                ),
              ],
            ),
          ),
          // Outer solid guide ring
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.copper.withAlpha(128),
                  width: 1,
                ),
              ),
            ),
          ),
          // Inner dashed guide ring (4px inset)
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: CustomPaint(
                painter: DashedCirclePainter(
                  color: AppColors.copper.withAlpha(102),
                  strokeWidth: 1,
                  dash: 3,
                  gap: 3,
                ),
              ),
            ),
          ),
          // Monogram
          Padding(
            padding: const EdgeInsets.all(6),
            child: Container(
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF2E1500),
              ),
              child: Text(
                initials,
                style: GoogleFonts.poppins(
                  fontSize: 32,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: AppColors.copper,
                ),
              ),
            ),
          ),
          // CAD tick marks
          const Positioned(top: -4, child: _Tick()),
          const Positioned(bottom: -4, child: _Tick()),
        ],
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 8,
      decoration: BoxDecoration(
        color: AppColors.copper,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
