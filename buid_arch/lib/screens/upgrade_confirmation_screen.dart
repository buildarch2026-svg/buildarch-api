import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'home_screen.dart';

class UpgradeConfirmationScreen extends StatelessWidget {
  const UpgradeConfirmationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: AppColors.secondary,
                ),
                const SizedBox(height: 20),
                Text(
                  'Your Build Arch account is ready',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'You can now access project management features while '
                  'continuing to use the Community.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute<void>(
                        builder: (_) => const HomeScreen(),
                      ),
                      (route) => false,
                    ),
                    child: const Text('Go to Main App'),
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
