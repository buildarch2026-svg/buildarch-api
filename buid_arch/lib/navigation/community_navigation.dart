import 'package:flutter/material.dart';

import 'auth_session_navigation.dart';
import '../screens/community_screen.dart';
import '../screens/role_selection_screen.dart';
import '../services/auth_api_service.dart';

class CommunityNavigation {
  const CommunityNavigation._();

  static Future<void> open(BuildContext context, {bool replace = false}) {
    final route = MaterialPageRoute<void>(
      builder: (_) => const CommunityScreen(),
    );
    return replace
        ? Navigator.of(context).pushReplacement(route)
        : Navigator.of(context).push(route);
  }

  static void startUpgrade(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RoleSelectionScreen(isUpgrade: true),
      ),
    );
  }

  static Future<void> handleUnauthorized(
    BuildContext context,
    AuthApiException error,
  ) =>
      AuthSessionNavigation.handleUnauthorized(context, error);
}
