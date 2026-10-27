import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PendingInvitationService {
  PendingInvitationService._();

  static final instance = PendingInvitationService._();

  static const _tokenKey = 'pending_project_invitation_token';
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<void> save(String token) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) return;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> read() async {
    final token = await _storage.read(key: _tokenKey);
    if (token == null || !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      return null;
    }
    return token;
  }

  Future<void> clear() async => _storage.delete(key: _tokenKey);
}
