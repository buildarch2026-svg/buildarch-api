import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../screens/project_chats_screen.dart';
import '../screens/job_portal_job_detail_screen.dart';
import '../screens/community_contacts_screen.dart';
import 'auth_api_service.dart';
import 'auth_session_service.dart';

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();
  static final navigatorKey = GlobalKey<NavigatorState>();
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  FirebaseMessaging? _messaging;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  Future<void>? _initializing;
  bool _initialized = false;
  bool _pendingChatNavigation = false;
  bool _pendingCommunityContactsNavigation = false;

  Future<void> initialize() async {
    if (_initialized) return;
    final activeInitialization = _initializing;
    if (activeInitialization != null) {
      await activeInitialization;
      return;
    }

    final initialization = _initialize();
    _initializing = initialization;
    try {
      await initialization;
    } finally {
      _initializing = null;
    }
  }

  Future<void> registerDevice() async {
    try {
      await initialize();
      final messaging = _messaging;
      if (messaging == null) return;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _registerToken(token);
      _listenForTokenRefresh(messaging);
      if (_pendingChatNavigation) _openChatInbox();
      if (_pendingCommunityContactsNavigation) {
        unawaited(_openCommunityContactRequests());
      }
    } on AuthApiException catch (error) {
      debugPrint('Push notification registration failed: ${error.message}');
    } on FirebaseException catch (error) {
      debugPrint('Firebase notification setup failed: ${error.code}');
    } catch (error) {
      debugPrint('Push notification setup failed: $error');
    }
  }

  Future<bool> unregisterDevice({required String sessionToken}) async {
    try {
      await initialize();
      final messaging = _messaging;
      if (messaging == null) return true;
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return true;

      await AuthApiService.instance.removePushToken(
        token: sessionToken,
        firebaseToken: token,
      );
      return true;
    } on AuthApiException catch (error) {
      debugPrint('Push token could not be revoked: ${error.message}');
      return false;
    } on FirebaseException catch (error) {
      debugPrint('Push token could not be read for sign-out: ${error.code}');
      return false;
    } catch (error) {
      debugPrint('Push token could not be revoked: $error');
      return false;
    }
  }

  Future<void> _initialize() async {
    final options = _firebaseOptions;
    if (options == null) return;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
    final messaging = FirebaseMessaging.instance;
    _messaging = messaging;
    _foregroundSubscription ??= FirebaseMessaging.onMessage.listen(
      _showForegroundNotification,
      onError: (Object error) {
        debugPrint(
            'A foreground push notification could not be handled: $error');
      },
    );
    _openedSubscription ??= FirebaseMessaging.onMessageOpenedApp.listen(
      _handleNotificationTap,
      onError: (Object error) {
        debugPrint('A push notification tap could not be handled: $error');
      },
    );
    _initialized = true;

    if (await messaging.getInitialMessage() case final initialMessage?) {
      _handleNotificationTap(initialMessage);
    }
  }

  FirebaseOptions? get _firebaseOptions {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return null;
    }

    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const messagingSenderId =
        String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
    const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    const iosAppId = String.fromEnvironment('FIREBASE_IOS_APP_ID');
    const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
    const iosBundleId = String.fromEnvironment(
      'FIREBASE_IOS_BUNDLE_ID',
      defaultValue: 'com.buidarch.buidArch',
    );

    final appId = defaultTargetPlatform == TargetPlatform.android
        ? androidAppId
        : iosAppId;
    if (apiKey.isEmpty ||
        projectId.isEmpty ||
        messagingSenderId.isEmpty ||
        appId.isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
      iosBundleId:
          defaultTargetPlatform == TargetPlatform.iOS ? iosBundleId : null,
    );
  }

  void _listenForTokenRefresh(FirebaseMessaging messaging) {
    _tokenRefreshSubscription ??= messaging.onTokenRefresh.listen(
      (token) => unawaited(_registerToken(token)),
      onError: (Object error) {
        debugPrint('Firebase push token refresh failed: $error');
      },
    );
  }

  Future<void> _registerToken(String firebaseToken) async {
    final sessionToken = await AuthSessionService.instance.readToken();
    final platform = switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => null,
    };
    if (sessionToken == null || sessionToken.isEmpty || platform == null) {
      return;
    }

    await AuthApiService.instance.registerPushToken(
      token: sessionToken,
      firebaseToken: firebaseToken,
      platform: platform,
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    if ((message.data['notification_type'] as String?)
            ?.startsWith('community_contact_') ==
        true) {
      unawaited(_openCommunityContactRequests());
      return;
    }
    if (message.data['event'] == 'chat_message') {
      unawaited(_openChatInboxIfSignedIn());
      return;
    }
    if (message.data['job_id'] case final String id
        when int.tryParse(id) != null) {
      unawaited(_openJobFromNotification(int.parse(id)));
    }
  }

  Future<void> _openJobFromNotification(int jobId) async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) return;
    try {
      final job = await AuthApiService.instance.getConstructionJob(
        token: token,
        jobId: jobId,
      );
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => JobPortalJobDetailScreen(
            token: token,
            initialJob: job,
          ),
        ),
      );
    } on AuthApiException catch (error) {
      messengerKey.currentState?.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }

  Future<void> _openCommunityContactRequests() async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      _pendingCommunityContactsNavigation = true;
      return;
    }
    _pendingCommunityContactsNavigation = false;
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityContactsScreen(
          token: token,
          initialTab: 1,
        ),
      ),
    );
  }

  Future<void> _openChatInboxIfSignedIn() async {
    final token = await AuthSessionService.instance.readToken();
    if (token == null || token.isEmpty) {
      _pendingChatNavigation = true;
      return;
    }
    _openChatInbox();
  }

  void _openChatInbox() {
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _pendingChatNavigation = true;
      return;
    }
    _pendingChatNavigation = false;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const ProjectChatsScreen(),
      ),
    );
  }

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    final title = notification.title;
    final body = notification.body;
    final messenger = messengerKey.currentState;
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            title == null || title.isEmpty
                ? body ?? 'You have a new project message.'
                : body == null || body.isEmpty
                    ? title
                    : '$title: $body',
          ),
          action: SnackBarAction(
            label: 'OPEN',
            onPressed: () {
              final jobId = int.tryParse(message.data['job_id'] ?? '');
              if ((message.data['notification_type'] as String?)
                      ?.startsWith('community_contact_') ==
                  true) {
                unawaited(_openCommunityContactRequests());
              } else if (jobId != null) {
                unawaited(_openJobFromNotification(jobId));
              } else {
                _openChatInbox();
              }
            },
          ),
        ),
      );
  }
}
