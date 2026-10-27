import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Pill with a pulsing status dot, e.g. "PHASE: FOUNDATION V2.4".
class PhaseBadge extends StatefulWidget {
  const PhaseBadge({super.key, required this.label});

  final String label;

  @override
  State<PhaseBadge> createState() => _PhaseBadgeState();
}

class _PhaseBadgeState extends State<PhaseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 1),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.darkBrown,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PingDot(animation: _controller),
          const SizedBox(width: 8),
          Text(
            widget.label.toUpperCase(),
            style: AppTextStyles.labelTechnical.copyWith(
              color: AppColors.primaryFixed,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PingDot extends StatelessWidget {
  const _PingDot({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      height: 8,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: animation,
            builder: (context, _) {
              final t = Curves.easeOut.transform(animation.value);
              return Opacity(
                opacity: 0.75 * (1 - t),
                child: Transform.scale(
                  scale: 1 + t,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.secondaryFixed,
                    ),
                    child: SizedBox(width: 8, height: 8),
                  ),
                ),
              );
            },
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.secondaryContainer,
            ),
            child: SizedBox(width: 8, height: 8),
          ),
        ],
      ),
    );
  }
}
