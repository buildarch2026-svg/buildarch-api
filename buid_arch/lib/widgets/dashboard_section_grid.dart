import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class DashboardTileSpec {
  const DashboardTileSpec({
    required this.icon,
    required this.label,
    this.iconColor = AppColors.primaryContainer,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color iconColor;
  final VoidCallback? onTap;
}

/// Titled section with a 3-across grid of icon-and-label tiles.
class DashboardSectionGrid extends StatelessWidget {
  const DashboardSectionGrid({
    super.key,
    required this.title,
    required this.tiles,
    this.onTileTap,
    this.onViewAll,
  });

  final String title;
  final List<DashboardTileSpec> tiles;
  final ValueChanged<String>? onTileTap;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: AppTextStyles.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (onViewAll != null)
              InkWell(
                onTap: onViewAll,
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'View all',
                      style: AppTextStyles.labelTechnical.copyWith(
                        fontSize: 11,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary,
                      ),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 16, color: AppColors.secondary),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final tile in tiles)
              _DashboardTile(
                spec: tile,
                onTap: tile.onTap ??
                    (onTileTap == null ? null : () => onTileTap!(tile.label)),
              ),
          ],
        ),
      ],
    );
  }
}

class _DashboardTile extends StatelessWidget {
  const _DashboardTile({required this.spec, required this.onTap});

  final DashboardTileSpec spec;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Material(
      color: AppColors.surfaceContainerLowest,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                spec.icon,
                size: 26,
                color: onTap == null ? AppColors.outline : spec.iconColor,
              ),
              const SizedBox(height: 8),
              Text(
                spec.label,
                textAlign: TextAlign.center,
                style: AppTextStyles.labelTechnical.copyWith(
                  fontSize: 11,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w600,
                  color: onTap == null
                      ? AppColors.outline
                      : AppColors.onSurfaceVariant,
                ),
              ),
              if (onTap == null) ...[
                const SizedBox(height: 3),
                Text(
                  'Coming soon',
                  style: AppTextStyles.labelTechnical.copyWith(
                    fontSize: 9,
                    letterSpacing: 0,
                    color: AppColors.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
