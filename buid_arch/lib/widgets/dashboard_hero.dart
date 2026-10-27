import 'package:flutter/material.dart';

import '../models/project.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Rounded-bottom hero: the project photo when there is one, otherwise a
/// copper gradient with a house icon. Status row sits underneath.
class DashboardHero extends StatelessWidget {
  const DashboardHero({
    super.key,
    required this.project,
    this.statusLabel = 'Active',
    this.updatedLabel = 'Updated 2h ago',
  });

  final Project project;
  final String statusLabel;
  final String updatedLabel;

  @override
  Widget build(BuildContext context) {
    final photo = project.photoUrl;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null)
              Image.network(
                photo,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _gradient(),
              )
            else
              _gradient(),
            if (photo != null)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withAlpha(60),
                      Colors.black.withAlpha(120),
                    ],
                  ),
                ),
              ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (photo == null) ...[
                    const Icon(Icons.home_outlined,
                        size: 80, color: Colors.white),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        statusLabel,
                        style: AppTextStyles.bodyMd.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: AppTextStyles.bodySm
                            .copyWith(color: Colors.white54),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        updatedLabel,
                        style: AppTextStyles.bodySm
                            .copyWith(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradient() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryContainer,
              AppColors.primary,
              AppColors.tertiary,
            ],
          ),
        ),
      );
}
