import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_role.dart';

/// Stores the chosen role on the phone for now.
/// TODO: save the role on the server (Laravel API) once login is connected.
class UserRoleService {
  UserRoleService._();
  static final UserRoleService instance = UserRoleService._();

  static const _key = 'user_role';

  Future<void> save(AppRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, role.name);
  }

  Future<AppRole?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    for (final role in AppRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }
}
