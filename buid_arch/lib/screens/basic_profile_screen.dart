import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/app_role.dart';
import '../models/auth_flow.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';
import '../services/current_location_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_button.dart';
import '../widgets/profile_text_field.dart';
import '../widgets/setup_pill.dart';
import 'app_lock_setup_screen.dart';

/// "Tell Us About Your Project" - name, location and project details,
/// shown after Role selection (Home Owner).
class BasicProfileScreen extends StatefulWidget {
  const BasicProfileScreen({
    super.key,
    this.phoneNumber,
    this.authFlow = AuthFlow.mobileLogin,
    required this.role,
  });

  /// Already-verified number from mobile login, if available.
  final String? phoneNumber;
  final AuthFlow authFlow;
  final AppRole role;

  @override
  State<BasicProfileScreen> createState() => _BasicProfileScreenState();
}

class _BasicProfileScreenState extends State<BasicProfileScreen> {
  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  late final TextEditingController _phoneController =
      TextEditingController(text: widget.phoneNumber ?? '');
  final _phoneOtpController = TextEditingController();

  bool _saving = false;
  bool _phoneVerified = false;
  bool _phoneOtpSent = false;
  bool _sendingPhoneOtp = false;
  bool _verifyingPhone = false;
  bool _gettingLocation = false;
  String? _otpSentTo;

  @override
  void initState() {
    super.initState();
    _phoneVerified = widget.phoneNumber != null;
    for (final c in [_nameController, _locationController]) {
      c.addListener(() => setState(() {}));
    }
    _phoneController.addListener(_onPhoneChanged);
    _phoneOtpController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _phoneController.dispose();
    _phoneOtpController.dispose();
    super.dispose();
  }

  bool get _canContinue =>
      _nameController.text.trim().isNotEmpty &&
      _locationController.text.trim().isNotEmpty &&
      _phoneVerified;

  String? get _phoneNumberForVerification {
    final digits = _phoneController.text.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 10) return null;
    return '+91$digits';
  }

  void _onPhoneChanged() {
    final phoneNumber = _phoneNumberForVerification;
    if (_phoneVerified && phoneNumber == widget.phoneNumber) return;
    if (phoneNumber != _otpSentTo) _phoneOtpController.clear();
    setState(() {
      _phoneVerified = false;
      if (phoneNumber != _otpSentTo) {
        _phoneOtpSent = false;
      }
    });
  }

  Future<void> _sendPhoneOtp() async {
    final phoneNumber = _phoneNumberForVerification;
    if (phoneNumber == null || _sendingPhoneOtp || _verifyingPhone) return;

    setState(() => _sendingPhoneOtp = true);
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
            'Your session expired. Please sign in again.');
      }
      await AuthApiService.instance.requestProfilePhoneOtp(
        token: token,
        phoneNumber: phoneNumber,
      );
      if (!mounted) return;
      setState(() {
        _phoneOtpSent = true;
        _otpSentTo = phoneNumber;
        _phoneVerified = false;
      });
      _showMessage('Verification code sent to +91 ${phoneNumber.substring(3)}');
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _sendingPhoneOtp = false);
    }
  }

  Future<void> _verifyPhone() async {
    final phoneNumber = _phoneNumberForVerification;
    final code = _phoneOtpController.text.trim();
    if (phoneNumber == null ||
        phoneNumber != _otpSentTo ||
        code.length != 6 ||
        _verifyingPhone ||
        _sendingPhoneOtp) {
      return;
    }

    setState(() => _verifyingPhone = true);
    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
            'Your session expired. Please sign in again.');
      }
      await AuthApiService.instance.verifyProfilePhone(
        token: token,
        phoneNumber: phoneNumber,
        code: code,
      );
      if (!mounted) return;
      setState(() {
        _phoneVerified = true;
        _phoneOtpSent = false;
      });
      _showMessage('Mobile number verified');
    } on AuthApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _verifyingPhone = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _useCurrentLocation() async {
    if (_gettingLocation) return;
    setState(() => _gettingLocation = true);
    try {
      final address = await CurrentLocationService.instance.getCurrentAddress();
      if (mounted) setState(() => _locationController.text = address);
    } on CurrentLocationException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _continue() async {
    if (!_canContinue || _saving) return;
    setState(() => _saving = true);

    try {
      final token = await AuthSessionService.instance.readToken();
      if (token == null || token.isEmpty) {
        throw const AuthApiException(
            'Your session expired. Please sign in again.');
      }

      final user = await AuthApiService.instance.updateProfile(
        token: token,
        name: _nameController.text.trim(),
        location: _locationController.text.trim(),
        role: widget.role.name,
      );
      await AuthSessionService.instance.saveSession(token: token, user: user);

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AppLockSetupScreen(
            authFlow: widget.authFlow,
          ),
        ),
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
              content: Text('Could not save your profile. Try again.')),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
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
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildHero(),
                _buildCard(padding.bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHero() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back, color: AppColors.creamSand),
              ),
              Text('R-102.4 // PROFILE', style: _cornerStyle()),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text('SEC // AUTH-04', style: _cornerStyle()),
          ),
          const SizedBox(height: 12),
          const Center(child: SetupPill(label: 'SETUP // 03')),
          const SizedBox(height: 12),
          Center(
            child: Text(
              'Tell Us About Your Project',
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle.copyWith(
                fontSize: 28,
                height: 36 / 28,
                letterSpacing: -0.6,
                color: AppColors.surface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                'A few details to set up your workspace',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMd.copyWith(
                  color: AppColors.surfaceContainerLow,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _cornerStyle() => AppTextStyles.labelTechnical.copyWith(
        color: AppColors.creamSand.withAlpha(140),
        letterSpacing: 1.0,
      );

  Widget _buildCard(double bottomInset) {
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
              margin: const EdgeInsets.only(bottom: 20),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          ProfileTextField(
            label: 'Full Name',
            icon: Icons.person_outline,
            controller: _nameController,
            hintText: 'e.g. Arjun Menon',
          ),
          const SizedBox(height: 18),
          ProfileTextField(
            label: 'Mobile Number (+91)',
            icon: Icons.phone_iphone,
            controller: _phoneController,
            readOnly: widget.phoneNumber != null && _phoneVerified,
            keyboardType: TextInputType.phone,
            hintText: '10-digit mobile number',
            trailing: _phoneVerified
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified,
                          size: 12, color: AppColors.secondary),
                      const SizedBox(width: 2),
                      Text(
                        'VERIFIED',
                        style: AppTextStyles.labelTechnical.copyWith(
                          color: AppColors.secondary,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  )
                : null,
          ),
          if (!_phoneVerified) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _phoneNumberForVerification == null ||
                        _sendingPhoneOtp ||
                        _verifyingPhone
                    ? null
                    : _sendPhoneOtp,
                icon: _sendingPhoneOtp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sms_outlined, size: 18),
                label: Text(
                    _phoneOtpSent ? 'Resend code' : 'Send verification code'),
              ),
            ),
            if (_phoneOtpSent) ...[
              const SizedBox(height: 8),
              ProfileTextField(
                label: 'Verification Code',
                icon: Icons.lock_outline,
                controller: _phoneOtpController,
                keyboardType: TextInputType.number,
                hintText: '6-digit code',
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _phoneOtpController.text.trim().length == 6 &&
                          !_verifyingPhone
                      ? _verifyPhone
                      : null,
                  icon: _verifyingPhone
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('Verify mobile number'),
                ),
              ),
            ],
          ],
          const SizedBox(height: 18),
          ProfileTextField(
            label: 'Location',
            icon: Icons.location_on_outlined,
            controller: _locationController,
            hintText: 'City, State',
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _gettingLocation ? null : _useCurrentLocation,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_gettingLocation)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      const Icon(Icons.my_location,
                          size: 16, color: AppColors.secondary),
                    const SizedBox(width: 4),
                    Text(
                      _gettingLocation
                          ? 'Getting location...'
                          : 'Use current location',
                      style: AppTextStyles.bodyMd.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 13 * 0.04,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Opacity(
            opacity: _canContinue ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !_canContinue,
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
          const SizedBox(height: 10),
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
}
