import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Small dark pill with a pulsing copper dot, e.g. "SETUP // 01".
class SetupPill extends StatefulWidget {
  const SetupPill({super.key, required this.label});

  final String label;

  @override
  State<SetupPill> createState() => _SetupPillState();
}

class _SetupPillState extends State<SetupPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.darkBrown.withAlpha(204),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.4).animate(_controller),
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.copper,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            widget.label.toUpperCase(),
            softWrap: false,
            style: AppTextStyles.labelTechnical.copyWith(
              color: AppColors.tertiaryFixedDim,
              letterSpacing: 2.0,
            ),
          ),
        ],
      ),
    );
  }
}
