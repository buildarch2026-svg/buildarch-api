import 'package:flutter/material.dart';

import '../models/project_type.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// One square tile in the 3-across Project Type grid on Create Project.
class ProjectTypeGridTile extends StatelessWidget {
  const ProjectTypeGridTile({
    super.key,
    required this.type,
    required this.selected,
    required this.onTap,
  });

  final ProjectType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 112,
      decoration: BoxDecoration(
        color: selected ? AppColors.primaryContainer : Colors.white,
        borderRadius: radius,
        border: selected ? null : Border.all(color: AppColors.border),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primaryContainer.withAlpha(90),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  type.icon,
                  size: 28,
                  color: selected ? Colors.white : AppColors.outline,
                ),
                const SizedBox(height: 8),
                Text(
                  type.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: AppTextStyles.bodySm.copyWith(
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                    color: selected ? Colors.white : AppColors.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
