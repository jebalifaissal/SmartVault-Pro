import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/auth_user.dart';

class CloudflareSessionStore {
  CloudflareSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'cloudflare_session_token';
  static const _userKey = 'cloudflare_session_user';
  static const _adminKey = 'cloudflare_session_is_admin';

  final FlutterSecureStorage _storage;

  Future<String?> readToken() => _storage.read(key: _tokenKey);

  Future<AuthUser?> readUser() async {
    final value = await _storage.read(key: _userKey);
    if (value == null) return null;
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic> ||
        decoded['id'] is! String ||
        decoded['email'] is! String ||
        (decoded['display_name'] != null &&
            decoded['display_name'] is! String)) {
      throw const FormatException('Stored Cloudflare session is invalid.');
    }
    return AuthUser(
      id: decoded['id'] as String,
      email: decoded['email'] as String,
      displayName: decoded['display_name'] as String?,
    );
  }

  Future<bool?> readAdministrator() async {
    final value = await _storage.read(key: _adminKey);
    if (value == null) return null;
    if (value != 'true' && value != 'false') {
      throw const FormatException('Stored Cloudflare role is invalid.');
    }
    return value == 'true';
  }

  Future<void> writeSession({
    required String token,
    required AuthUser user,
    required bool isAdministrator,
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(
      key: _userKey,
      value: jsonEncode({
        'id': user.id,
        'email': user.email,
        'display_name': user.displayName,
      }),
    );
    await _storage.write(key: _adminKey, value: isAdministrator.toString());
  }

  Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _userKey),
      _storage.delete(key: _adminKey),
    ]);
  }
}
