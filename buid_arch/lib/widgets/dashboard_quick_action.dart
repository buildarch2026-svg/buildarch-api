import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Circular icon button with a one-word label underneath.
class DashboardQuickAction extends StatelessWidget {
  const DashboardQuickAction({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceContainer,
            ),
            child: Icon(
              icon,
              size: 24,
              color: onTap == null ? AppColors.outline : AppColors.secondary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          onTap == null ? '$label · Soon' : label,
          style: AppTextStyles.labelTechnical.copyWith(
            fontSize: 11,
            letterSpacing: 0,
            fontWeight: FontWeight.w600,
            color:
                onTap == null ? AppColors.outline : AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
