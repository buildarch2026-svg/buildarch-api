import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/account_session_service.dart';
import '../services/app_lock_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/avatar_shield.dart';
import '../widgets/dashed_circle.dart';
import '../widgets/unlock_hero_painter.dart';
import 'home_screen.dart';
import 'community_screen.dart';
import 'account_type_selection_screen.dart';
import 'login_screen.dart';

/// Returning-user screen: unlock the app with fingerprint or phone PIN.
class UnlockScreen extends StatefulWidget {
  const UnlockScreen({
    super.key,
    this.userName = 'John Doe',
    this.userRole = 'Project Manager',
    this.autoPrompt = true,
    this.isCommunityOnly = false,
    this.needsAccountType = false,
  });

  /// TODO: replace with the signed-in user's real name and role.
  final String userName;
  final String userRole;

  /// Opens the system fingerprint prompt as soon as the screen appears.
  final bool autoPrompt;
  final bool isCommunityOnly;
  final bool needsAccountType;

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _halo = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 20),
  )..repeat();

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );

  bool _busy = false;
  bool _pressed = false;
  String? _error;
  bool _hasAutoPrompted = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoPrompt) {
      // Register lifecycle observer — we'll trigger biometrics only once the
      // Activity reaches AppLifecycleState.resumed, avoiding the
      // "Called after onSaveInstanceState()" crash that occurs when the prompt
      // fires while the activity is still initialising or momentarily paused.
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        widget.autoPrompt &&
        !_hasAutoPrompted) {
      _hasAutoPrompted = true;
      // Brief delay so the Fragment back-stack is fully settled.
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _unlock(biometricOnly: false, silent: true);
      });
    }
  }

  @override
  void dispose() {
    if (widget.autoPrompt) WidgetsBinding.instance.removeObserver(this);
    _halo.dispose();
    _shake.dispose();
    super.dispose();
  }

  String get _initials {
    final parts = widget.userName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts[1][0]).toUpperCase();
  }

  Future<void> _unlock({
    required bool biometricOnly,
    bool silent = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final result =
        await AppLockService.instance.unlock(biometricOnly: biometricOnly);
    if (!mounted) return;

    switch (result) {
      case UnlockResult.success:
        setState(() => _busy = false);
        _goHome();
        return;
      case UnlockResult.failed:
        if (silent) {
          setState(() => _busy = false);
        } else {
          _fail(biometricOnly
              ? 'Fingerprint not recognized. Try again.'
              : 'Verification failed. Try again.');
        }
        return;
      case UnlockResult.lockedOut:
        _fail('Too many attempts. Use phone PIN instead.');
        return;
      case UnlockResult.unavailable:
        _fail(biometricOnly
            ? 'No fingerprint set up on this phone. Use phone PIN instead.'
            : 'Set up a screen lock (PIN, pattern or fingerprint) in your '
                'phone settings first.');
        return;
    }
  }

  void _fail(String message) {
    setState(() {
      _busy = false;
      _error = message;
    });
    _shake.forward(from: 0);
    HapticFeedback.mediumImpact();
  }

  void _goHome() {
    final destination = widget.isCommunityOnly
        ? const CommunityScreen()
        : widget.needsAccountType
            ? const AccountTypeSelectionScreen()
            : const HomeScreen();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }

  Future<void> _switchAccount() async {
    final serverRevoked = await AccountSessionService.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
    if (!serverRevoked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Signed out on this device, but could not revoke the server session.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    // 32 (hero padding) + 22 (pill) + 24 (gap) + 48 (half of avatar)
    final avatarCenterY = padding.top + 126;

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
                    Positioned.fill(
                      child: CustomPaint(
                        painter:
                            UnlockHeroPainter(avatarCenterY: avatarCenterY),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildHero(padding.top),
                        _buildCard(padding.bottom),
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

  // ------------------------------------------------------------------ hero

  Widget _buildHero(double topInset) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, topInset + 32, 24, 16),
      child: SizedBox(
        width: double.infinity,
        child: Column(
          children: [
            const SizedBox(height: 24),
            AvatarShield(initials: _initials),
            const SizedBox(height: 16),
            Text(
              'WELCOME BACK',
              style: AppTextStyles.labelTechnical.copyWith(
                color: AppColors.creamSand,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.userName,
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle.copyWith(
                fontSize: 24,
                height: 1.25,
                letterSpacing: -0.6,
                color: AppColors.surface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.userRole,
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSm.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.creamSand.withAlpha(230),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ card

  Widget _buildCard(double bottomInset) {
    final hasError = _error != null;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 32 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Color(0x1F4B240F),
            blurRadius: 32,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Grab handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 8),

          // Header
          Text(
            'Unlock Build Arch',
            textAlign: TextAlign.center,
            style: AppTextStyles.cardTitle.copyWith(
              height: 1.375,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Use your fingerprint or phone PIN to continue to your projects.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMd.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // Failed-attempt banner
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: hasError
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _errorBanner(_error!),
                  )
                : const SizedBox(width: double.infinity),
          ),

          // Scanner
          _scanner(hasError),
          const SizedBox(height: 16),

          // Alternative: phone PIN
          _pinButton(),
          const SizedBox(height: 24),

          // Switch account
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Not you?',
                style: AppTextStyles.bodySm
                    .copyWith(color: AppColors.onSurfaceVariant),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: _switchAccount,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                  child: Text('Switch account',
                      style: _labelLg(AppColors.primary)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Encryption seal
          Opacity(
            opacity: 0.8,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.lock_outline,
                    size: 13, color: AppColors.outline),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'SECURED WITH DEVICE-LEVEL ENCRYPTION',
                    style: AppTextStyles.labelTechnical
                        .copyWith(letterSpacing: 1.0),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _labelLg(Color color) => GoogleFonts.inter(
        fontSize: 13,
        height: 18 / 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 13 * 0.04,
        color: color,
      );

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withAlpha(26),
        border: Border.all(color: AppColors.error.withAlpha(77)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.error, size: 20, color: AppColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.bodySm.copyWith(
                fontWeight: FontWeight.w500,
                height: 1.25,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scanner(bool hasError) {
    final haloColor = hasError
        ? AppColors.error.withAlpha(128)
        : AppColors.copper.withAlpha(102);

    final label = _busy
        ? 'Verifying biometric...'
        : hasError
            ? 'Verification Failed'
            : 'Touch to unlock';

    return Column(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Slowly rotating dashed halo
              RotationTransition(
                turns: _halo,
                child: SizedBox(
                  width: 120,
                  height: 120,
                  child: CustomPaint(
                    painter: DashedCirclePainter(
                      color: haloColor,
                      strokeWidth: 1,
                      dash: 3,
                      gap: 3,
                    ),
                  ),
                ),
              ),
              // Solid guide ring
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border),
                ),
              ),
              // Fingerprint button
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final t = _shake.value;
                  final dx = math.sin(t * math.pi * 6) * 6 * (1 - t);
                  return Transform.translate(
                      offset: Offset(dx, 0), child: child);
                },
                child: _fingerprintButton(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          label,
          style: _labelLg(hasError ? AppColors.error : AppColors.primary),
        ),
        const SizedBox(height: 2),
        Text(
          'SENSOR READY',
          style: AppTextStyles.labelTechnical.copyWith(letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _fingerprintButton() {
    return AnimatedScale(
      scale: _pressed ? 0.95 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: 88,
        height: 88,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x598B5200),
              blurRadius: 24,
              spreadRadius: -4,
              offset: Offset(0, 12),
            ),
          ],
        ),
        child: Material(
          color: _pressed ? AppColors.primary : AppColors.primaryContainer,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _unlock(biometricOnly: true),
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Inner bevel highlight
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                    ),
                  ),
                ),
                const Icon(Icons.fingerprint, size: 42, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pinButton() {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _unlock(biometricOnly: false),
        splashColor: AppColors.creamSand.withAlpha(102),
        highlightColor: AppColors.creamSand.withAlpha(102),
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.dialpad, size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 10),
              Text('Use phone PIN instead',
                  style: _labelLg(AppColors.textPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}
