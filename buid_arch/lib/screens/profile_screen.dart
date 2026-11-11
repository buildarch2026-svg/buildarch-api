import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({
    super.key,
    required this.user,
    required this.onLogout,
    this.onUpgrade,
  });

  final Map<String, dynamic> user;
  final VoidCallback onLogout;
  final VoidCallback? onUpgrade;

  String _value(String key, String fallback) {
    final value = user[key];
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  String _roleLabel(String role) {
    for (final appRole in AppRole.values) {
      if (appRole.name == role) return appRole.label;
    }
    return switch (role) {
      'architect' || 'engineer' || 'interiorDesigner' => 'Designer',
      _ => 'Not set',
    };
  }

  @override
  Widget build(BuildContext context) {
    final name = _value('name', 'Build Arch User');
    final role = _roleLabel(_value('role', ''));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        surfaceTintColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'Profile',
          style: AppTextStyles.cardTitle.copyWith(
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryContainer,
              ),
              child: const Icon(Icons.person, size: 48, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            textAlign: TextAlign.center,
            style: AppTextStyles.cardTitle.copyWith(
              fontSize: 22,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            role,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 32),
          _ProfileDetail(
            icon: Icons.email_outlined,
            label: 'Email',
            value: _value('email', 'Not provided'),
          ),
          _ProfileDetail(
            icon: Icons.phone_outlined,
            label: 'Mobile number',
            value: _value('phone_number', 'Not provided'),
          ),
          _ProfileDetail(
            icon: Icons.location_on_outlined,
            label: 'Location',
            value: _value('location', 'Not provided'),
          ),
          _ProfileDetail(
            icon: Icons.work_outline,
            label: 'Role',
            value: role,
          ),
          if (onUpgrade != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onUpgrade,
              icon: const Icon(Icons.apartment_outlined),
              label: const Text('Switch to Main App'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.error,
              side: const BorderSide(color: AppColors.error),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileDetail extends StatelessWidget {
  const _ProfileDetail({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.secondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.bodySm.copyWith(
                    color: AppColors.outline,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: AppTextStyles.bodyMd.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
