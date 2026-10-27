import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/auth_flow.dart';
import '../services/auth_api_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_button.dart';
import '../widgets/india_flag.dart';
import '../widgets/phone_number_formatter.dart';
import '../widgets/setup_hero_painter.dart';
import 'otp_screen.dart';

/// "Enter Your Number" - mobile entry before OTP, shown after the user
/// taps "Continue with Mobile" on the login screen.
class MobileNumberScreen extends StatefulWidget {
  const MobileNumberScreen({
    super.key,
    this.authFlow = AuthFlow.mobileLogin,
    this.authApiService,
  });

  final AuthFlow authFlow;
  final AuthApiService? authApiService;

  @override
  State<MobileNumberScreen> createState() => _MobileNumberScreenState();
}

class _MobileNumberScreenState extends State<MobileNumberScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _focused = false;
  bool _sendingOtp = false;
  String? _requestError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _focusNode
        .addListener(() => setState(() => _focused = _focusNode.hasFocus));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool get _isValid => _controller.text.replaceAll(' ', '').length == 10;

  String get _heading => switch (widget.authFlow) {
        AuthFlow.signUp => 'Create Your Account',
        AuthFlow.mobileLogin => 'Enter Your Number',
        AuthFlow.googleLogin => 'Finish with Google',
      };

  String get _subtitle => switch (widget.authFlow) {
        AuthFlow.signUp =>
          'We will send you a one-time code to create your account',
        AuthFlow.mobileLogin => 'We will send you a one-time code to verify',
        AuthFlow.googleLogin =>
          'Secure your sign-in with a quick mobile verification',
      };

  String get _ctaLabel => switch (widget.authFlow) {
        AuthFlow.signUp => 'Send OTP',
        AuthFlow.mobileLogin => 'Send OTP',
        AuthFlow.googleLogin => 'Continue',
      };

  Future<void> _sendOtp() async {
    if (!_isValid || _sendingOtp) return;
    setState(() {
      _sendingOtp = true;
      _requestError = null;
    });

    final phoneNumber = '+91 ${_controller.text}';
    try {
      final authApiService = widget.authApiService ?? AuthApiService.instance;
      await authApiService.requestOtp(phoneNumber);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => OtpScreen(
            phoneNumber: phoneNumber,
            authFlow: widget.authFlow,
            authApiService: authApiService,
          ),
        ),
      );
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _requestError = error.message);
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what - coming soon')));
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
        Padding(
          padding: EdgeInsets.fromLTRB(16, topInset + 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back,
                        color: AppColors.creamSand),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                _heading,
                textAlign: TextAlign.center,
                style: AppTextStyles.cardTitle.copyWith(
                  fontSize: 24,
                  height: 30 / 24,
                  letterSpacing: -0.6,
                  color: AppColors.surface,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  _subtitle,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.headlineSm.copyWith(
                    fontSize: 14,
                    height: 20 / 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.creamSand.withAlpha(230),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard(double bottomInset) {
    final canSend = _isValid && !_sendingOtp;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: AppShadows.xl2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
          Text(
            'Mobile Number',
            style: AppTextStyles.bodyMd.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _phoneField(),
          if (_requestError != null) ...[
            const SizedBox(height: 8),
            Text(
              _requestError!,
              style: AppTextStyles.bodySm.copyWith(color: AppColors.error),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'By continuing, you agree to receive a WhatsApp message with '
            'a verification code.',
            style: AppTextStyles.bodySm.copyWith(
              color: AppColors.outline,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          _trustBadge(),
          const SizedBox(height: 16),
          AuthButton(
            label: _sendingOtp ? 'Sending...' : _ctaLabel,
            onPressed: canSend ? _sendOtp : () {},
            backgroundColor: AppColors.primaryContainer,
            pressedColor: AppColors.primary.withAlpha(90),
            shadows: _isValid ? AppShadows.sm : const [],
            textStyle: AppTextStyles.titleMd.copyWith(
              fontSize: 15,
              color: Colors.white,
            ),
            trailing: _sendingOtp
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
          ).let((btn) => Opacity(
                opacity: canSend || _sendingOtp ? 1 : 0.4,
                child: IgnorePointer(ignoring: !canSend, child: btn),
              )),
        ],
      ),
    );
  }

  Widget _phoneField() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _focused ? AppColors.primaryContainer : AppColors.border,
          width: _focused ? 1.5 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: AppColors.primaryContainer.withAlpha(31),
                  blurRadius: 8,
                  spreadRadius: 3,
                ),
              ]
            : const [],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => _comingSoon('Country selection'),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const IndiaFlag(),
                  const SizedBox(width: 6),
                  Text(
                    '+91',
                    style: AppTextStyles.bodyMd.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down,
                      size: 16,
                      color: AppColors.onSurfaceVariant.withAlpha(178)),
                ],
              ),
            ),
          ),
          Container(
            width: 1,
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: AppColors.border,
          ),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              keyboardType: TextInputType.phone,
              maxLength: 11, // 10 digits + 1 space
              inputFormatters: [PhoneNumberFormatter()],
              style: AppTextStyles.bodyMd.copyWith(
                fontSize: 16,
                color: AppColors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: '98765 43210',
                hintStyle: AppTextStyles.bodyMd.copyWith(
                  fontSize: 16,
                  color: AppColors.outline,
                ),
                counterText: '',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            InkWell(
              onTap: () => _controller.clear(),
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.cancel,
                    size: 18, color: AppColors.outline.withAlpha(153)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _trustBadge() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.copper.withAlpha(46)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.copper.withAlpha(31),
            ),
            child: const Icon(Icons.lock_outline,
                size: 16, color: AppColors.copper),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Encrypted Dispatch Protocol',
                  style: AppTextStyles.bodySm.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.deepBrown,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Secure 6-digit OTP delivered via WhatsApp, with SMS as backup.',
                  style: AppTextStyles.bodySm.copyWith(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.onSurfaceVariant,
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

extension _Let<T> on T {
  R let<R>(R Function(T it) block) => block(this);
}
