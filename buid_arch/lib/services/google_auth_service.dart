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
    try {
      await GoogleSignIn.instance.initialize(
        serverClientId: _webClientId.isEmpty ? null : _webClientId,
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
      final details = error.description;
      final message = switch (error.code) {
        GoogleSignInExceptionCode.clientConfigurationError =>
          'Google sign-in client configuration is incomplete. Check the Web '
              'OAuth client ID and Android OAuth setup.'
              '${details == null ? '' : ' Details: $details'}',
        GoogleSignInExceptionCode.providerConfigurationError =>
          'Google Play services rejected this app configuration. Verify the '
              'Android OAuth package name and signing SHA-1.'
              '${details == null ? '' : ' Details: $details'}',
        GoogleSignInExceptionCode.canceled => 'Google sign-in was canceled.',
        _ => 'Google sign-in failed (${error.code.name}).'
            '${details == null ? '' : ' Details: $details'}',
      };
      throw AuthApiException(message);
    }
  }
}
