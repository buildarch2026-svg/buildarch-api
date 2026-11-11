import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_role.dart';
import '../models/auth_flow.dart';
import '../services/user_role_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_button.dart';
import '../widgets/role_option_tile.dart';
import '../widgets/setup_hero_painter.dart';
import 'basic_profile_screen.dart';

/// "Who are you?" - the user picks a role, then continues to app lock setup.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    super.key,
    this.phoneNumber,
    this.authFlow = AuthFlow.mobileLogin,
    this.isUpgrade = false,
  });

  /// Already-verified number for mobile login, if this flow has one.
  final String? phoneNumber;
  final AuthFlow authFlow;
  final bool isUpgrade;

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  AppRole? _selected;
  bool _saving = false;

  Future<void> _continue() async {
    final role = _selected;
    if (role == null || _saving) return;

    setState(() => _saving = true);
    await UserRoleService.instance.save(role);
    if (!mounted) return;
    setState(() => _saving = false);

    // Next step in the flow: basic profile.
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BasicProfileScreen(
          phoneNumber: widget.phoneNumber,
          authFlow: widget.authFlow,
          role: role,
          isUpgrade: widget.isUpgrade,
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
                    _buildHero(padding.top),
                    _buildCard(padding.bottom),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHero(double topInset) {
    return Stack(
      children: [
        const Positioned.fill(
          child: CustomPaint(painter: SetupHeroPainter()),
        ),
        Positioned(
          top: topInset + 4,
          left: 8,
          child: IconButton(
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back),
            color: AppColors.surface,
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(24, topInset + 32, 24, 24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.isUpgrade
                      ? 'Choose Your Main App Role'
                      : 'Choose Your Role',
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
                  'Tell us how you will use Build Arch',
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
        ),
      ],
    );
  }

  Widget _buildCard(double bottomInset) {
    final canContinue = _selected != null;

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
          Text(
            widget.isUpgrade
                ? 'How would you like to use Build Arch?'
                : 'Who are you?',
            style: AppTextStyles.cardTitle.copyWith(
              height: 28 / 22,
              letterSpacing: -0.55,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Categories',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.625,
            ),
          ),
          const SizedBox(height: 20),

          for (final role in AppRole.values) ...[
            RoleOptionTile(
              role: role,
              selected: _selected == role,
              onTap: () => setState(() => _selected = role),
            ),
            const SizedBox(height: 12),
          ],

          const SizedBox(height: 12),
          Opacity(
            opacity: canContinue ? 1 : 0.5,
            child: IgnorePointer(
              ignoring: !canContinue,
              child: AuthButton(
                label: 'Continue',
                onPressed: _continue,
                backgroundColor: AppColors.primaryContainer,
                pressedColor: AppColors.primary.withAlpha(90),
                shadows: AppShadows.md,
                textStyle: AppTextStyles.titleMd.copyWith(color: Colors.white),
                trailing: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.arrow_forward,
                        size: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
