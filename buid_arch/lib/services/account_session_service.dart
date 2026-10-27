import 'app_lock_service.dart';
import 'auth_api_service.dart';
import 'auth_session_service.dart';
import 'projects_store.dart';

class AccountSessionService {
  AccountSessionService._();

  static final AccountSessionService instance = AccountSessionService._();

  /// Clears local account data even when the server cannot be reached.
  /// Returns false if the server token could not be revoked.
  Future<bool> signOut() async {
    final token = await AuthSessionService.instance.readToken();
    await AuthSessionService.instance.clearSession();
    await AppLockService.instance.reset();
    ProjectsStore.instance.clear();

    if (token == null || token.isEmpty) return true;

    try {
      await AuthApiService.instance.logout(token: token);
      return true;
    } on AuthApiException {
      return false;
    }
  }
}
