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
      final message = switch (error.code) {
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Google sign-in is not configured correctly. Please contact support.',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'This app is not registered correctly with Google. Please contact support.',
        GoogleSignInExceptionCode.canceled => 'Google sign-in was canceled.',
        _ => 'Google sign-in failed. Please try again.',
      };
      throw AuthApiException(message);
    }
  }
}
