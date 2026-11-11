import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_flow.dart';
import '../services/app_lock_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_button.dart';
import '../widgets/benefit_tile.dart';
import '../widgets/biometric_badge.dart';
import '../widgets/fingerprint_icon.dart';
import '../widgets/setup_hero_painter.dart';
import 'home_screen.dart';

/// "Secure Your Account" - optional fingerprint / PIN app lock setup.
class AppLockSetupScreen extends StatefulWidget {
  const AppLockSetupScreen({
    super.key,
    this.authFlow = AuthFlow.mobileLogin,
  });

  final AuthFlow authFlow;

  @override
  State<AppLockSetupScreen> createState() => _AppLockSetupScreenState();
}

class _AppLockSetupScreenState extends State<AppLockSetupScreen> {
  bool _busy = false;

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await AppLockService.instance.enable();
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result) {
      case AppLockResult.enabled:
        _showToast('App lock enabled', 'Build Arch workspace unlocked');
        _goHome();
        break;
      case AppLockResult.cancelled:
        break; // user closed the prompt - stay on this screen
      case AppLockResult.notAvailable:
        _showMessage(
          'Set up a screen lock (PIN, pattern or fingerprint) in your phone '
          'settings first, then try again.',
        );
        break;
      case AppLockResult.failed:
        _showMessage("Couldn't turn on app lock. Please try again.");
        break;
    }
  }

  Future<void> _skip() async {
    if (_busy) return;
    await AppLockService.instance.skip();
    if (!mounted) return;
    _goHome();
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _showToast(String title, String subtitle) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.darkBrown,
          elevation: 8,
          margin: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          padding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(milliseconds: 2400),
          content: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer,
                ),
                child: const Icon(Icons.check, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.titleMd.copyWith(
                        fontSize: 13,
                        height: 16 / 13,
                        color: AppColors.surface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppTextStyles.bodySm.copyWith(
                        fontSize: 11,
                        height: 12 / 11,
                        color: AppColors.creamSand,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.deepBrown,
        body: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Hero(topInset: padding.top),
                    _ActionCard(
                      bottomInset: padding.bottom,
                      busy: _busy,
                      onEnable: _enable,
                      onSkip: _skip,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: SetupHeroPainter()),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, topInset + 32, 24, 24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BiometricBadge(),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    children: [
                      Text(
                        'Secure Your Account',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.cardTitle.copyWith(
                          fontSize: 24,
                          height: 30 / 24,
                          letterSpacing: -0.6,
                          color: AppColors.surface,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Protect your projects with fingerprint or PIN',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.headlineSm.copyWith(
                          fontSize: 14,
                          height: 20 / 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.creamSand.withAlpha(230),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.bottomInset,
    required this.busy,
    required this.onEnable,
    required this.onSkip,
  });

  final double bottomInset;
  final bool busy;
  final VoidCallback onEnable;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 32 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: AppShadows.xl2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grab handle
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 20),
            child: Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),

          // Headline + body
          Text(
            'Enable App Lock',
            style: AppTextStyles.cardTitle.copyWith(
              height: 28 / 22,
              letterSpacing: -0.55,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Use your fingerprint, face, or phone PIN to open Build Arch '
            'quickly and keep your project data private.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.625,
            ),
          ),
          const SizedBox(height: 20),

          // Benefits
          const BenefitTile(
            icon: Icons.bolt,
            title: 'Fast, one-touch access',
            description:
                'Bypass credentials securely on active construction sites',
          ),
          const SizedBox(height: 12),
          const BenefitTile(
            icon: Icons.shield,
            title: 'Device-level encryption',
            description:
                'Your data stays protected if your phone is lost or misplaced',
          ),
          const SizedBox(height: 24),

          // Primary action
          AuthButton(
            label: 'Enable Fingerprint / PIN',
            onPressed: onEnable,
            backgroundColor: AppColors.primaryContainer,
            pressedColor: AppColors.primary.withAlpha(90),
            shadows: AppShadows.md,
            textStyle: AppTextStyles.titleMd.copyWith(color: Colors.white),
            leading: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const FingerprintIcon(
                    color: Colors.white,
                    size: 20,
                    strokeWidth: 2,
                    compact: true,
                  ),
          ),
          const SizedBox(height: 12),

          // Skip
          SizedBox(
            height: 40,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
              child: Text(
                'Skip for now',
                style: AppTextStyles.titleMd.copyWith(
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'YOU CAN CHANGE THIS ANYTIME IN SETTINGS',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelTechnical.copyWith(letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
