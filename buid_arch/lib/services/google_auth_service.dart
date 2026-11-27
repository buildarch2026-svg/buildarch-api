import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_api_service.dart';

class GoogleAuthService {
  GoogleAuthService._();

  static final GoogleAuthService instance = GoogleAuthService._();

  final String _webClientId = const String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '',
  );

  Future<Map<String, dynamic>> signIn() async {
    if (_webClientId.trim().isEmpty) {
      throw const AuthApiException(
        'Google sign-in is not configured for this build. Please contact support.',
      );
    }

    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: _webClientId.trim(),
      );

      final account = await GoogleSignIn.instance.authenticate();
      final auth = account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.trim().isEmpty) {
        throw const AuthApiException(
          'Google did not return an ID token. Check the Web OAuth client ID '
          'configuration and try again.',
        );
      }

      final response = await AuthApiService.instance.signInWithGoogle(
        idToken: idToken,
      );

      if (response['verified'] != true) {
        throw const AuthApiException('Google sign-in was not accepted.');
      }

      return response;
    } on GoogleSignInException catch (error) {
      if (kDebugMode) {
        final message = _safeDiagnosticMessage(error.description);
        debugPrint(
          'Google Sign-In exception type=${error.runtimeType}; '
          'code=${error.code.name}; message=$message',
        );
      }

      final isAccountReauthenticationFailure = error.description
              ?.toLowerCase()
              .contains('account reauth failed') ??
          false;
      final message = switch (error.code) {
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Google sign-in is not configured correctly. Please contact support.',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'This app is not registered correctly with Google. Please contact support.',
        GoogleSignInExceptionCode.canceled when
          isAccountReauthenticationFailure =>
          'Google could not reauthenticate this account. Reauthenticate the '
              'Google account on your phone or choose another account, then retry.',
        GoogleSignInExceptionCode.canceled => 'Google sign-in was canceled.',
        _ => 'Google sign-in failed. Please try again.',
      };
      throw AuthApiException(message);
    }
  }

  String _safeDiagnosticMessage(String? message) {
    if (message == null || message.trim().isEmpty) {
      return 'not provided';
    }

    return message
        .replaceAll(
          RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b'),
          '[redacted email]',
        )
        .replaceAll(
          RegExp(r'\b\d{6,}-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com\b'),
          '[redacted client ID]',
        )
        .replaceAll(
          RegExp(
            r'\b[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\b',
          ),
          '[redacted token]',
        )
        .replaceAll(
          RegExp(r'\bBearer\s+\S+', caseSensitive: false),
          'Bearer [redacted]',
        );
  }
}
