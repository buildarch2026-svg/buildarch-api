import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_flow.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_button.dart';
import '../widgets/otp_box_row.dart';
import 'home_screen.dart';
import 'role_selection_screen.dart';

/// "Verify Your Number" - 6-digit OTP entry after the mobile number screen.
class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phoneNumber,
    this.authFlow = AuthFlow.mobileLogin,
    this.authApiService,
  });

  /// E.g. "+91 98765 43210" - shown under the heading.
  final String phoneNumber;
  final AuthFlow authFlow;
  final AuthApiService? authApiService;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  static const _otpLength = 6;
  static const _resendSeconds = 60;
  static const _otpRequestRateLimitSeconds = 600;

  final _rowKey = GlobalKey<OtpBoxRowState>();

  String _code = '';
  bool _hasError = false;
  bool _verifying = false;
  bool _resending = false;
  String? _errorMessage;
  int _secondsLeft = _resendSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer([int seconds = _resendSeconds]) {
    _secondsLeft = seconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  String get _timerLabel {
    final m = (_secondsLeft ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsLeft % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() => _resending = true);
    try {
      await (widget.authApiService ?? AuthApiService.instance)
          .requestOtp(widget.phoneNumber);
      if (!mounted) return;
      _rowKey.currentState?.clear();
      setState(() {
        _code = '';
        _hasError = false;
        _errorMessage = null;
      });
      _startTimer();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('A new code was sent')));
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = error.message;
      });
      if (error.statusCode == 429) {
        final retryAfter = error.retryAfterSeconds;
        _startTimer(
          retryAfter != null && retryAfter > 0
              ? retryAfter
              : _otpRequestRateLimitSeconds,
        );
      }
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  Future<void> _verify() async {
    if (_code.length != _otpLength || _verifying) return;

    var profileComplete = false;
    setState(() {
      _verifying = true;
      _hasError = false;
    });

    try {
      final session =
          await (widget.authApiService ?? AuthApiService.instance).verifyOtp(
        phoneNumber: widget.phoneNumber,
        code: _code,
      );

      final token = session['token'] as String;
      final user = session['user'] as Map<String, dynamic>;
      profileComplete = user['profile_complete'] as bool;
      await AuthSessionService.instance.saveSession(token: token, user: user);
    } on AuthApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _hasError = true;
        _errorMessage = error.message;
      });
      HapticFeedback.mediumImpact();
      return;
    }
    if (!mounted) return;
    setState(() => _verifying = false);

    final destination = profileComplete
        ? const HomeScreen()
        : RoleSelectionScreen(
            phoneNumber: widget.phoneNumber,
            authFlow: widget.authFlow,
          );

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => destination,
      ),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;
    final canVerify = _code.length == _otpLength && !_verifying;

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
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildHero(padding.top),
                _buildCard(padding.bottom, canVerify),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero(double topInset) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.creamSand),
              ),
              const Spacer(),
              const SizedBox(
                width: 48,
                child: Icon(Icons.verified_user_outlined,
                    size: 18, color: AppColors.border),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Verify Your Number',
              style: AppTextStyles.cardTitle.copyWith(
                fontSize: 28,
                height: 36 / 28,
                letterSpacing: -0.6,
                color: AppColors.surface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: RichText(
              text: TextSpan(
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.surfaceContainerLow,
                ),
                children: [
                  const TextSpan(
                      text: 'Enter the 6-digit code sent via WhatsApp to '),
                  TextSpan(
                    text: widget.phoneNumber,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.surface,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: Text(
                'Edit',
                style: AppTextStyles.bodyMd.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryContainer,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(double bottomInset, bool canVerify) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: AppShadows.xl2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enter Verification Code',
                style: AppTextStyles.bodyMd.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 13 * 0.04,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                'WHATSAPP TIMEOUT 60S',
                style:
                    AppTextStyles.labelTechnical.copyWith(letterSpacing: 1.0),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OtpBoxRow(
            key: _rowKey,
            length: _otpLength,
            hasError: _hasError,
            onChanged: (value) {
              setState(() {
                _code = value;
                if (_hasError) {
                  _hasError = false;
                  _errorMessage = null;
                }
              });
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            alignment: Alignment.topCenter,
            child: _hasError
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _errorBanner(),
                  )
                : const SizedBox(width: double.infinity, height: 0),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule,
                        size: 16, color: AppColors.primaryContainer),
                    const SizedBox(width: 6),
                    Text(
                      _secondsLeft > 0 ? 'Resend code in' : 'Didn\'t get it?',
                      style: AppTextStyles.bodySm.copyWith(
                        color: AppColors.outline,
                      ),
                    ),
                    if (_secondsLeft > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        _timerLabel,
                        style: AppTextStyles.bodySm.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryContainer,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ],
                ),
                InkWell(
                  onTap: _secondsLeft > 0 || _resending ? null : _resend,
                  child: Text(
                    _resending ? 'Sending...' : 'Resend Code',
                    style: AppTextStyles.bodySm.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 11 * 0.06,
                      color: _secondsLeft > 0 || _resending
                          ? AppColors.primaryContainer.withAlpha(102)
                          : AppColors.primaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.lock_outline,
                      size: 18, color: AppColors.primaryContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              'Encrypted Dispatch Protocol',
                              style: AppTextStyles.bodySm.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.onSurface,
                              ),
                            ),
                          ),
                          Text(
                            'ISO-19650',
                            style: AppTextStyles.labelTechnical.copyWith(
                              color: AppColors.primaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Secure 6-digit cryptographic verification backed by '
                        'enterprise architectural workspace permissions.',
                        style: AppTextStyles.bodySm.copyWith(
                          color: AppColors.onSurfaceVariant,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Opacity(
            opacity: canVerify ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !canVerify,
              child: AuthButton(
                label: _verifying ? 'Verifying...' : 'Verify & Proceed',
                onPressed: _verify,
                backgroundColor: AppColors.primary,
                pressedColor: AppColors.primaryContainer,
                shadows: AppShadows.md,
                textStyle: AppTextStyles.titleMd.copyWith(color: Colors.white),
                trailing: _verifying
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
          const SizedBox(height: 16),
          Center(
            child: Text(
              'BUILD ARCH V2.4 // TELEMETRY GATEWAY - ISO-19650 COMPLIANT',
              textAlign: TextAlign.center,
              style: AppTextStyles.labelTechnical.copyWith(letterSpacing: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
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
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _errorMessage ?? 'Incorrect code. Please try again.',
              style: AppTextStyles.bodySm.copyWith(
                fontWeight: FontWeight.w500,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
