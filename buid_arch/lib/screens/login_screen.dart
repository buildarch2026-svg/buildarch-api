import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_flow.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../services/google_auth_service.dart';
import '../services/pending_invitation_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_button.dart';
import '../widgets/blueprint_background.dart';
import '../widgets/build_arch_emblem.dart';
import '../widgets/google_logo.dart';
import '../widgets/phase_badge.dart';
import 'home_screen.dart';
import 'mobile_number_screen.dart';
import 'role_selection_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _googleSigningIn = false;
  bool _pendingInvitation = false;

  @override
  void initState() {
    super.initState();
    _checkPendingInvitation();
  }

  Future<void> _checkPendingInvitation() async {
    final token = await PendingInvitationService.instance.read();
    if (mounted && token != null) {
      setState(() => _pendingInvitation = true);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (_googleSigningIn) return;

    setState(() => _googleSigningIn = true);

    try {
      final session = await GoogleAuthService.instance.signIn();
      final token = session['token'] as String;
      final user = session['user'] as Map<String, dynamic>;
      final profileComplete = user['profile_complete'] as bool;
      await AuthSessionService.instance.saveSession(token: token, user: user);

      if (!mounted) return;

      final destination = profileComplete
          ? const HomeScreen()
          : const RoleSelectionScreen(
              authFlow: AuthFlow.googleLogin,
            );

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => destination,
        ),
        (route) => false,
      );
    } on AuthApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
              content: Text('Google sign-in failed. Please try again.')),
        );
    } finally {
      if (mounted) setState(() => _googleSigningIn = false);
    }
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
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: CustomPaint(
                        painter: BlueprintBackgroundPainter(),
                      ),
                    ),
                    Positioned(
                      top: -96,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          width: 320,
                          height: 320,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(
                              colors: [
                                AppColors.secondaryContainer.withAlpha(60),
                                AppColors.secondaryContainer.withAlpha(0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Hero(topInset: padding.top),
                        _AuthCard(
                          bottomInset: padding.bottom,
                          pendingInvitation: _pendingInvitation,
                          onGoogle: _handleGoogleSignIn,
                          onSignIn: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const MobileNumberScreen(
                                authFlow: AuthFlow.mobileLogin,
                              ),
                            ),
                          ),
                          googleSigningIn: _googleSigningIn,
                        ),
                      ],
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, topInset + 32, 16, 24),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            const BuildArchEmblem(),
            const SizedBox(height: 16),
            Text(
              'BUILD ARCH',
              textAlign: TextAlign.center,
              style: AppTextStyles.brandTitle,
            ),
            const SizedBox(height: 4),
            Text(
              'WE ARE HERE FOR YOU',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSm.copyWith(
                color: AppColors.creamSand,
                letterSpacing: 0.45,
              ),
            ),
            const SizedBox(height: 16),
            const PhaseBadge(label: 'Build Better. Live Better.'),
          ],
        ),
      ),
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.bottomInset,
    required this.onGoogle,
    required this.onSignIn,
    this.googleSigningIn = false,
    this.pendingInvitation = false,
  });

  final double bottomInset;
  final VoidCallback onGoogle;
  final VoidCallback onSignIn;
  final bool googleSigningIn;
  final bool pendingInvitation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 24, 16, 32 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: AppShadows.xl2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Grab handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Welcome to Build Arch',
            style: AppTextStyles.cardTitle,
          ),
          const SizedBox(height: 4),
          Text(
            'Manage your construction projects in one place with '
            'architects, engineers & contractors.',
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
              height: 1.625,
            ),
          ),
          if (pendingInvitation) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.group_add_outlined,
                      color: AppColors.secondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your project invitation is saved. Complete sign-in or '
                      'account setup and we will return you to it.',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Auth actions
          AuthButton(
            label: googleSigningIn
                ? 'Connecting to Google...'
                : 'Continue with Google',
            onPressed: googleSigningIn ? () {} : onGoogle,
            backgroundColor: AppColors.surfaceContainerLowest,
            pressedColor: AppColors.surfaceContainerLow,
            textStyle:
                AppTextStyles.titleMd.copyWith(color: AppColors.textPrimary),
            leading: googleSigningIn
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : const GoogleLogo(size: 20),
          ),
          const SizedBox(height: 8),
          AuthButton(
            label: 'Sign In',
            onPressed: onSignIn,
            backgroundColor: AppColors.primaryContainer,
            pressedColor: AppColors.primary.withAlpha(90),
            shadows: AppShadows.md,
            textStyle: AppTextStyles.titleMd.copyWith(
              color: AppColors.surface,
              letterSpacing: 0.4,
            ),
            trailing: const Icon(
              Icons.arrow_forward,
              size: 18,
              color: AppColors.surface,
            ),
          ),
          const SizedBox(height: 24),

          // Legal
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                'BY CONTINUING YOU AGREE TO BUILD ARCH ARCHITECTURAL '
                'SERVICE TERMS & PRIVACY DISCLOSURE POLICY.',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelTechnical.copyWith(height: 1.3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
