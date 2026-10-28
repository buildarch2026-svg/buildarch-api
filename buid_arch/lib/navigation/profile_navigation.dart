import 'package:flutter/material.dart';

import '../services/account_session_service.dart';
import '../services/auth_session_service.dart';
import '../screens/login_screen.dart';
import '../screens/profile_screen.dart';

class ProfileNavigation {
  const ProfileNavigation._();

  static Future<void> open(BuildContext context) async {
    try {
      final user = await AuthSessionService.instance.readUser();
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            user: user ?? const {},
            onLogout: () => logout(context),
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Could not load your profile.')),
        );
    }
  }

  static Future<void> logout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You can sign in again with this or another phone number.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (shouldLogout != true || !context.mounted) return;

    final serverRevoked = await AccountSessionService.instance.signOut();
    if (!context.mounted) return;
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
}
