import 'package:flutter/material.dart';

import '../models/project_type.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// One selectable row in the Project Type list.
class ProjectTypeTile extends StatelessWidget {
  const ProjectTypeTile({
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
    final radius = BorderRadius.circular(8);

    return Material(
      color: selected ? AppColors.secondaryContainer : AppColors.surfaceContainerLowest,
      borderRadius: radius,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.deepBrown.withAlpha(20),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : const [],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primaryContainer
                      : AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  type.icon,
                  size: 20,
                  color: selected ? Colors.white : AppColors.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      type.label,
                      style: AppTextStyles.titleMd.copyWith(
                        color: selected
                            ? const Color(0xFF763F00)
                            : AppColors.onSurface,
                      ),
                    ),
                    Text(
                      type.description,
                      style: AppTextStyles.bodySm
                          .copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: selected ? 24 : 20,
                height: selected ? 24 : 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.primaryContainer : Colors.transparent,
                ),
                child: selected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
