import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../screens/login_screen.dart';
import '../screens/unlock_screen.dart';
import 'app_lock_service.dart';
import 'auth_session_service.dart';
import 'pending_invitation_service.dart';

class InvitationLinkService {
  InvitationLinkService._();

  static final instance = InvitationLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  GlobalKey<NavigatorState>? _navigatorKey;
  String? _lastHandledToken;
  DateTime? _lastHandledAt;

  Future<void> start(GlobalKey<NavigatorState> navigatorKey) async {
    if (_subscription != null) return;
    _navigatorKey = navigatorKey;
    _subscription = _appLinks.uriLinkStream.listen(
      (uri) => unawaited(_handleLink(uri)),
      onError: (Object error) {
        debugPrint('Could not receive an invitation app link: $error');
      },
    );
    final initialLink = await _appLinks.getInitialLink();
    if (initialLink != null) await _handleLink(initialLink);
  }

  Future<void> _handleLink(Uri uri) async {
    if (uri.scheme != 'buildarch' ||
        uri.host != 'invite' ||
        uri.pathSegments.length != 1) {
      return;
    }

    final token = uri.pathSegments.single;
    final now = DateTime.now();
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        (token == _lastHandledToken &&
            _lastHandledAt != null &&
            now.difference(_lastHandledAt!) < const Duration(seconds: 2))) {
      return;
    }
    _lastHandledToken = token;
    _lastHandledAt = now;
    await PendingInvitationService.instance.save(token);

    final navigator = _navigatorKey?.currentState;
    if (navigator == null) return;

    final authToken = await AuthSessionService.instance.readToken();
    final Widget destination;
    if (authToken == null || authToken.isEmpty) {
      destination = const LoginScreen();
    } else if (await AppLockService.instance.isEnabled()) {
      final user = await AuthSessionService.instance.readUser();
      destination = UnlockScreen(
        userName: user?['name'] is String
            ? user!['name'] as String
            : 'Build Arch User',
        userRole: user?['role'] is String
            ? user!['role'] as String
            : 'Build Arch Member',
      );
    } else {
      destination = const HomeScreen();
    }

    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => destination),
      (route) => false,
    );
  }
}
