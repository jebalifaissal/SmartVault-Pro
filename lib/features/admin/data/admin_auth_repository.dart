import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../auth/domain/auth_exception.dart';
import '../../auth/presentation/auth_error_message.dart';
import '../domain/admin_user.dart';
import '../../../services/cloudflare_api_config.dart';

/// Repository gérant l'authentification de l'administrateur.
///
/// Utilise des routes dédiées (/api/admin/login, /api/admin/me,
/// /api/admin/logout) et une table admin_sessions séparée côté backend.
/// Le token admin n'est JAMAIS interchangeable avec un token utilisateur.
class AdminAuthRepository {
  AdminAuthRepository({
    FlutterSecureStorage? storage,
    http.Client? client,
    String? baseUrl,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? CloudflareApiConfig.baseUrl;

  static const _tokenKey = 'admin_session_token';
  static const _emailKey = 'admin_session_email';

  final FlutterSecureStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  final StreamController<AdminUser?> _authChanges =
      StreamController<AdminUser?>.broadcast();
  Future<AdminUser?>? _initialSession;

  late final Stream<AdminUser?> authStateChanges = _watchAuth();

  Stream<AdminUser?> _watchAuth() async* {
    yield await (_initialSession ??= _restoreSession());
    yield* _authChanges.stream;
  }

  Future<AdminUser?> _restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    final email = await _storage.read(key: _emailKey);
    if (token == null || token.isEmpty || email == null) {
      await _clearStorage();
      return null;
    }
    // Vérifie la session côté serveur
    try {
      final me = await _request('/api/admin/me', token: token);
      return AdminUser.fromApi(me['admin'] as Map<String, dynamic>);
    } catch (_) {
      await _clearStorage();
      return null;
    }
  }

  /// Connexion admin. Lève [AuthException] en cas d'échec.
  Future<AdminUser> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _request(
      '/api/admin/login',
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    final token = response['token'];
    final adminData = response['admin'];
    if (token is! String || token.isEmpty || adminData is! Map<String, dynamic>) {
      throw const FormatException('Réponse de connexion admin invalide.');
    }
    final admin = AdminUser.fromApi(adminData);
    await _storage.write(key: _tokenKey, value: token);
    await _storage.write(key: _emailKey, value: admin.email);
    _authChanges.add(admin);
    return admin;
  }

  /// Déconnexion : révoque la session côté serveur puis efface le stockage.
  Future<void> signOut() async {
    final token = await _storage.read(key: _tokenKey);
    try {
      if (token != null) {
        await _request('/api/admin/logout', method: 'POST', token: token);
      }
    } finally {
      await _clearStorage();
      _authChanges.add(null);
    }
  }

  Future<String?> getAccessToken() => _storage.read(key: _tokenKey);

  Future<void> _clearStorage() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _emailKey),
    ]);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    String? token,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';

    final uri = Uri.parse('$_baseUrl$path');
    final http.Response response;
    try {
      response = await switch (method) {
        'POST' => _client.post(
          uri,
          headers: headers,
          body: jsonEncode(body ?? const {}),
        ),
        _ => _client.get(uri, headers: headers),
      }.timeout(const Duration(seconds: 15));
    } on SocketException {
      throw const AuthException('network-request-failed');
    } on http.ClientException {
      throw const AuthException('network-request-failed');
    } on TimeoutException {
      throw const AuthException('network-request-failed');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const FormatException('Le serveur a retourné une réponse invalide.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Le serveur a retourné une réponse invalide.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('[AdminAuth] ${response.statusCode} $path : ${decoded['error']}');
      final code = decoded['error'] as String? ?? '';
      throw AuthException(switch (code) {
        'Invalid credentials' => 'invalid-credential',
        'Too many login attempts' => 'too-many-requests',
        'Admin authentication required' => 'requires-recent-login',
        _ => 'service-unavailable',
      });
    }
    return decoded;
  }
}
