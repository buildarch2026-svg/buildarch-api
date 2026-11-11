import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

enum AppTab { projects, chat, files, community, profile }

/// Minimal bottom navigation bar shared by the main app screens.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.current,
    required this.onTap,
    this.communityOnly = false,
  });

  final AppTab current;
  final ValueChanged<AppTab> onTap;
  final bool communityOnly;

  static const _items = [
    (tab: AppTab.projects, icon: Icons.apartment, label: 'Projects'),
    (tab: AppTab.chat, icon: Icons.chat_bubble_outline, label: 'Chat'),
    (tab: AppTab.files, icon: Icons.folder_open, label: 'Files'),
    (tab: AppTab.community, icon: Icons.groups_outlined, label: 'Community'),
    (
      tab: AppTab.profile,
      icon: Icons.account_circle_outlined,
      label: 'Profile'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.deepBrown.withAlpha(15),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final item in _items.where(
                (item) =>
                    !communityOnly ||
                    item.tab == AppTab.community ||
                    item.tab == AppTab.profile,
              ))
                Expanded(
                  child: _NavItem(
                    icon: item.icon,
                    label: item.label,
                    active: item.tab == current,
                    onTap: () => onTap(item.tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primaryContainer : AppColors.outline;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 2),
            Text(
              label.toUpperCase(),
              style: AppTextStyles.labelTechnical.copyWith(
                fontSize: 9,
                color: color,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
