import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppLockResult { enabled, cancelled, notAvailable, failed }

enum UnlockResult { success, failed, lockedOut, unavailable }

/// Handles fingerprint / face / phone PIN authentication for the app lock.
/// Uses the phone's own lock, so the app never stores a PIN itself.
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _enabledKey = 'app_lock_enabled';
  static const _promptedKey = 'app_lock_prompted';

  final LocalAuthentication _auth = LocalAuthentication();

  Future<bool> isEnabled() async {
    if (kIsWeb) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  /// True once the user has either enabled or skipped the setup screen.
  Future<bool> wasPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_promptedKey) ?? false;
  }

  /// Used by the "Secure Your Account" screen.
  Future<AppLockResult> enable() async {
    if (kIsWeb) return AppLockResult.notAvailable;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return AppLockResult.notAvailable;

      final ok = await _auth.authenticate(
        localizedReason: 'Confirm it is you to turn on app lock for Build Arch',
        options: const AuthenticationOptions(stickyAuth: true),
      );
      if (!ok) return AppLockResult.cancelled;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, true);
      await prefs.setBool(_promptedKey, true);
      return AppLockResult.enabled;
    } on PlatformException catch (e) {
      if (_isUnavailableCode(e.code)) return AppLockResult.notAvailable;
      return AppLockResult.failed;
    }
  }

  /// Used by the returning-user "Unlock Build Arch" screen.
  /// [biometricOnly] true  -> fingerprint / face only.
  /// [biometricOnly] false -> allows the phone PIN / pattern as well.
  Future<UnlockResult> unlock({required bool biometricOnly}) async {
    if (kIsWeb) return UnlockResult.unavailable;
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Build Arch',
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
        ),
      );
      return ok ? UnlockResult.success : UnlockResult.failed;
    } on PlatformException catch (e) {
      final code = e.code.toLowerCase();
      if (_isUnavailableCode(code)) return UnlockResult.unavailable;
      if (code == 'lockedout' || code == 'permanentlylockedout') {
        return UnlockResult.lockedOut;
      }
      return UnlockResult.failed;
    }
  }

  Future<void> skip() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_promptedKey, true);
  }

  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
  }

  /// Clears the lock settings (used by "Switch account").
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, false);
    await prefs.setBool(_promptedKey, false);
  }

  bool _isUnavailableCode(String code) {
    final c = code.toLowerCase();
    return c == 'notavailable' || c == 'notenrolled' || c == 'passcodenotset';
  }
}
