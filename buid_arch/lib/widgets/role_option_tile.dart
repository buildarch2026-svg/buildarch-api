import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Selectable card for one role on the role selection screen.
class RoleOptionTile extends StatelessWidget {
  const RoleOptionTile({
    super.key,
    required this.role,
    required this.selected,
    required this.onTap,
  });

  final AppRole role;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: selected ? AppColors.surface : AppColors.surfaceContainerLowest,
        borderRadius: radius,
        border: Border.all(
          color: selected ? AppColors.primaryContainer : AppColors.border,
          width: 1.5,
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: AppColors.primaryContainer.withAlpha(31),
                  spreadRadius: 3,
                  blurRadius: 0,
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.creamSand,
                  ),
                  child: _RoleIcon(role: role, color: AppColors.copper),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(role.label, style: AppTextStyles.titleMd),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              role.packageName.toUpperCase(),
                              style: AppTextStyles.labelTechnical.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        role.description,
                        style: AppTextStyles.bodySm
                            .copyWith(color: AppColors.outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _Radio(selected: selected),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleIcon extends StatelessWidget {
  const _RoleIcon({required this.role, required this.color});

  final AppRole role;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return switch (role) {
      AppRole.homeOwner => CustomPaint(
          size: const Size(22, 22),
          painter: _CrownPainter(color),
        ),
      AppRole.contractor => Icon(role.icon, size: 22, color: color),
      AppRole.designer => SizedBox(
          width: 22,
          height: 22,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.rotate(
                angle: -0.78,
                child: Icon(Icons.edit_outlined, size: 18, color: color),
              ),
              Transform.rotate(
                angle: 0.78,
                child: Icon(Icons.edit_outlined, size: 18, color: color),
              ),
            ],
          ),
        ),
    };
  }
}

class _CrownPainter extends CustomPainter {
  const _CrownPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final crown = Path()
      ..moveTo(size.width * 0.1, size.height * 0.28)
      ..lineTo(size.width * 0.34, size.height * 0.5)
      ..lineTo(size.width * 0.5, size.height * 0.08)
      ..lineTo(size.width * 0.66, size.height * 0.5)
      ..lineTo(size.width * 0.9, size.height * 0.28)
      ..lineTo(size.width * 0.8, size.height * 0.78)
      ..lineTo(size.width * 0.2, size.height * 0.78)
      ..close();
    canvas.drawPath(crown, paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          size.width * 0.2,
          size.height * 0.78,
          size.width * 0.8,
          size.height * 0.92,
        ),
        Radius.circular(size.width * 0.04),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CrownPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primaryContainer : Colors.transparent,
        border: Border.all(
          color: selected ? AppColors.primaryContainer : AppColors.border,
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check, size: 14, color: Colors.white)
          : null,
    );
  }
}
