import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A labeled 56px text field with a leading icon, used on the
/// Basic Profile screen. Supports a read-only "verified" variant.
class ProfileTextField extends StatelessWidget {
  const ProfileTextField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.hintText,
    this.readOnly = false,
    this.keyboardType,
    this.trailing,
    this.badge,
    this.onChanged,
  });

  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String? hintText;
  final bool readOnly;
  final TextInputType? keyboardType;
  final Widget? trailing;
  final Widget? badge;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: AppTextStyles.bodySm.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            if (badge != null) badge!,
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: readOnly
                ? AppColors.surfaceContainerLow
                : AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            boxShadow: readOnly ? const [] : AppShadowsRef.sm,
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: readOnly ? AppColors.outline : AppColors.secondary),
              const SizedBox(width: 12),
              Expanded(
                child: readOnly
                    ? Text(
                        controller.text,
                        style: AppTextStyles.bodyMd.copyWith(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      )
                    : TextField(
                        controller: controller,
                        readOnly: readOnly,
                        keyboardType: keyboardType,
                        onChanged: onChanged,
                        style: AppTextStyles.bodyMd.copyWith(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: hintText,
                          hintStyle: AppTextStyles.bodyMd.copyWith(
                            fontSize: 16,
                            color: AppColors.outline,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ],
    );
  }
}

/// Small indirection so this file doesn't need to import app_theme.dart
/// just for the shadow constant.
class AppShadowsRef {
  static const sm = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 2, offset: Offset(0, 1)),
  ];
}
