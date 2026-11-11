import 'package:flutter/material.dart';

import '../screens/login_screen.dart';
import '../services/auth_api_service.dart';
import '../services/auth_session_service.dart';

class AuthSessionNavigation {
  const AuthSessionNavigation._();

  static Future<void> handleUnauthorized(
    BuildContext context,
    AuthApiException error,
  ) async {
    final status = await AuthSessionService.instance.validateSavedSession();
    if (!context.mounted) return;
    if (status == SavedSessionStatus.signedOut) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
        (_) => false,
      );
      return;
    }

    final message = status == SavedSessionStatus.authenticated
        ? error.message
        : 'Could not verify your sign-in. Your session was kept; please retry.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
