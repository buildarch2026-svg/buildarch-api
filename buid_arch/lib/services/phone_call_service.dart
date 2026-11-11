import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

enum PhoneCallFailure {
  phoneUnavailable,
  invalidNumber,
  notSupported,
  launchFailed,
}

class PhoneCallException implements Exception {
  const PhoneCallException(this.failure);

  final PhoneCallFailure failure;
}

typedef ExternalUrlLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
});

class PhoneCallService {
  PhoneCallService({ExternalUrlLauncher? launcher})
      : _launcher = launcher ?? _launchExternal;

  final ExternalUrlLauncher _launcher;

  static Future<bool> _launchExternal(
    Uri uri, {
    required LaunchMode mode,
  }) {
    return launchUrl(uri, mode: mode);
  }

  static String? normalizePhoneNumber(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final trimmed = value.trim();
    if (!RegExp(r'^[+0-9().\s-]+$').hasMatch(trimmed)) return null;
    var normalized = trimmed.replaceAll(RegExp(r'[\s().-]'), '');
    if (normalized.startsWith('00')) {
      normalized = '+${normalized.substring(2)}';
    }
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(normalized)) return null;
    return normalized;
  }

  Future<void> call(String? phoneNumber) async {
    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      throw const PhoneCallException(PhoneCallFailure.phoneUnavailable);
    }
    final normalized = normalizePhoneNumber(phoneNumber);
    if (normalized == null) {
      throw const PhoneCallException(PhoneCallFailure.invalidNumber);
    }

    final launched = await _launch(Uri(scheme: 'tel', path: normalized));
    if (!launched) {
      throw const PhoneCallException(PhoneCallFailure.notSupported);
    }
  }

  Future<bool> _launch(Uri uri) async {
    try {
      return await _launcher(uri, mode: LaunchMode.externalApplication);
    } on PlatformException {
      throw const PhoneCallException(PhoneCallFailure.launchFailed);
    } on MissingPluginException {
      throw const PhoneCallException(PhoneCallFailure.notSupported);
    }
  }
}
