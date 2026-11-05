import 'app_lock_service.dart';
import 'auth_api_service.dart';
import 'auth_session_service.dart';
import 'projects_store.dart';
import 'push_notification_service.dart';

class AccountSessionService {
  AccountSessionService._();

  static final AccountSessionService instance = AccountSessionService._();

  /// Clears local account data even when the server cannot be reached.
  /// Returns false if the server token could not be revoked.
  Future<bool> signOut() async {
    final token = await AuthSessionService.instance.readToken();
    var pushTokenRevoked = true;
    if (token != null && token.isNotEmpty) {
      pushTokenRevoked = await PushNotificationService.instance
          .unregisterDevice(sessionToken: token);
    }
    await AuthSessionService.instance.clearSession();
    await AppLockService.instance.reset();
    ProjectsStore.instance.clear();

    if (token == null || token.isEmpty) return pushTokenRevoked;

    try {
      await AuthApiService.instance.logout(token: token);
      return pushTokenRevoked;
    } on AuthApiException {
      return false;
    }
  }
}
