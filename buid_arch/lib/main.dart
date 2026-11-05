import 'dart:async';

import 'package:flutter/material.dart';

import 'models/app_role.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/unlock_screen.dart';
import 'services/app_lock_service.dart';
import 'services/auth_session_service.dart';
import 'services/invitation_link_service.dart';
import 'services/push_notification_service.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const BuidArchApp());
}

class BuidArchApp extends StatelessWidget {
  const BuidArchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: PushNotificationService.navigatorKey,
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      title: 'Build Arch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const _StartupGate(),
    );
  }
}

/// Resolves a saved session and presents an offline retry state when needed.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<_StartupState> _startup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        InvitationLinkService.instance.start(
          PushNotificationService.navigatorKey,
        ),
      );
    });
    _startup = _loadStartupState();
  }

  Future<_StartupState> _loadStartupState() async {
    final lockEnabled = await AppLockService.instance.isEnabled();
    final sessionStatus =
        await AuthSessionService.instance.validateSavedSession();
    final user = sessionStatus == SavedSessionStatus.signedOut
        ? null
        : await AuthSessionService.instance.readUser();
    return _StartupState(
      lockEnabled: lockEnabled,
      sessionStatus: sessionStatus,
      userName: _userName(user?['name']),
      userRole: _userRole(user?['role']),
    );
  }

  void _retryStartup() {
    setState(() => _startup = _loadStartupState());
  }

  String _userName(Object? name) {
    if (name is String && name.trim().isNotEmpty) return name.trim();
    return 'Build Arch User';
  }

  String _userRole(Object? role) {
    if (role is String) {
      for (final appRole in AppRole.values) {
        if (appRole.name == role) return appRole.label;
      }
      if (role == 'architect' ||
          role == 'engineer' ||
          role == 'interiorDesigner') {
        return AppRole.designer.label;
      }
    }
    return 'Build Arch Member';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_StartupState>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StartupUnavailableScreen(
            title: 'Session check unavailable',
            message:
                'We couldn’t check your saved session. Your login data has not '
                'been cleared. Please retry when the app is ready.',
            onRetry: _retryStartup,
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: AppColors.deepBrown,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.creamSand),
            ),
          );
        }

        final state = snapshot.data!;
        if (state.sessionStatus == SavedSessionStatus.temporarilyUnavailable) {
          return _StartupUnavailableScreen(
            title: 'You’re still signed in',
            message: 'We couldn’t reach the server. Your saved login is safe. '
                'Check your connection and retry, or continue offline.',
            onRetry: _retryStartup,
            onContinueOffline: () => _continueOffline(
              lockEnabled: state.lockEnabled,
              userName: state.userName,
              userRole: state.userRole,
            ),
          );
        }

        if (state.sessionStatus == SavedSessionStatus.authenticated &&
            state.lockEnabled) {
          return UnlockScreen(
            userName: state.userName,
            userRole: state.userRole,
          );
        }

        return state.sessionStatus == SavedSessionStatus.authenticated
            ? const HomeScreen()
            : const LoginScreen();
      },
    );
  }

  Widget _continueOffline({
    required bool lockEnabled,
    required String? userName,
    required String? userRole,
  }) {
    if (lockEnabled) {
      return UnlockScreen(
        userName: userName ?? 'Build Arch User',
        userRole: userRole ?? 'Build Arch Member',
      );
    }
    return const HomeScreen();
  }
}

class _StartupState {
  const _StartupState({
    required this.lockEnabled,
    required this.sessionStatus,
    required this.userName,
    required this.userRole,
  });

  final bool lockEnabled;
  final SavedSessionStatus sessionStatus;
  final String userName;
  final String userRole;
}

class _StartupUnavailableScreen extends StatelessWidget {
  const _StartupUnavailableScreen({
    required this.onRetry,
    required this.title,
    required this.message,
    this.onContinueOffline,
  });

  final VoidCallback onRetry;
  final String title;
  final String message;
  final Widget Function()? onContinueOffline;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deepBrown,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 48,
                  color: AppColors.creamSand,
                ),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: AppColors.creamSand),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: AppColors.creamSand),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Retry connection'),
                ),
                if (onContinueOffline != null)
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => onContinueOffline!()),
                    ),
                    child: const Text(
                      'Continue offline',
                      style: TextStyle(color: AppColors.creamSand),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
