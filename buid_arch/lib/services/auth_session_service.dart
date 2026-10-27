import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'auth_api_service.dart';

enum SavedSessionStatus {
  signedOut,
  authenticated,
  temporarilyUnavailable,
}

class AuthSessionService {
  AuthSessionService._();

  static final AuthSessionService instance = AuthSessionService._();

  static const _tokenKey = 'auth_token';
  static const _userKey = 'auth_user';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> saveSession({
    required String token,
    required Map<String, dynamic> user,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _userKey, value: jsonEncode(user));
  }

  Future<String?> readToken() async => _storage.read(key: _tokenKey);

  Future<Map<String, dynamic>?> readUser() async {
    final raw = await _storage.read(key: _userKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<void> clearSession() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }

  Future<SavedSessionStatus> validateSavedSession() async {
    final token = await readToken();
    if (token == null || token.isEmpty) return SavedSessionStatus.signedOut;

    try {
      final user = await AuthApiService.instance.getCurrentUser(token: token);
      await saveSession(token: token, user: user);
      return SavedSessionStatus.authenticated;
    } on AuthApiException catch (error) {
      if (error.isUnauthorized) {
        await clearSession();
        return SavedSessionStatus.signedOut;
      }
      return SavedSessionStatus.temporarilyUnavailable;
    }
  }
}
