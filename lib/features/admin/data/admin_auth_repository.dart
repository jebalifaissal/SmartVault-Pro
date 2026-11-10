
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../auth/domain/auth_exception.dart';
import '../domain/admin_user.dart';
import '../../../services/cloudflare_api_config.dart';

/// Repository gérant l'authentification de l'administrateur.
class AdminAuthRepository {
  AdminAuthRepository({
    FlutterSecureStorage? storage,
    http.Client? client,
    String? baseUrl,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? CloudflareApiConfig.baseUrl {
    unawaited(_initializeAuthState());
  }

  static const String _tokenKey = 'admin_session_token';
  static const String _emailKey = 'admin_session_email';

  final FlutterSecureStorage _storage;
  final http.Client _client;
  final String _baseUrl;

  // Stream broadcast stable : accepte plusieurs abonnements.
  late final StreamController<AdminUser?> _authChanges =
      StreamController<AdminUser?>.broadcast(
    onListen: () {
      if (_hasInitialState) {
        _authChanges.add(_currentAdmin);
      }
    },
  );

  // Stream fixe pendant toute la durée de vie du Repository.
  late final Stream<AdminUser?> _authStateChanges =
      _authChanges.stream;

  Stream<AdminUser?> get authStateChanges => _authStateChanges;

  // Dernier état connu de la session Admin.
  AdminUser? _currentAdmin;
  bool _hasInitialState = false;

  // Permet d'éviter qu'une ancienne restauration
  // écrase une connexion ou une déconnexion récente.
  int _authOperationVersion = 0;

  /// Met à jour l'état Admin et notifie les abonnés.
  void _publishAuthState(AdminUser? admin) {
    _currentAdmin = admin;
    _hasInitialState = true;

    if (!_authChanges.isClosed) {
      _authChanges.add(admin);
    }
  }

  /// Initialise et restaure la session Admin.
  Future<void> _initializeAuthState() async {
    final operationVersion = _authOperationVersion;

    try {
      final admin = await _restoreSession();

      // Ne pas écraser une opération plus récente.
      if (operationVersion != _authOperationVersion) {
        return;
      }

      _publishAuthState(admin);
    } catch (error, stackTrace) {
      debugPrint(
        '[AdminAuth] Session initialization error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);

      if (operationVersion == _authOperationVersion) {
        _publishAuthState(null);
      }
    }
  }

  /// Vérifie et restaure la session Admin sauvegardée.
  Future<AdminUser?> _restoreSession() async {
    final token = await _storage.read(key: _tokenKey);
    final email = await _storage.read(key: _emailKey);

    if (token == null ||
        token.isEmpty ||
        email == null ||
        email.isEmpty) {
      await _clearStorage();
      return null;
    }

    try {
      final response = await _request(
        '/api/admin/me',
        token: token,
      );

      final adminData = response['admin'];

      if (adminData is! Map<String, dynamic>) {
        await _clearStorage();
        return null;
      }

      return AdminUser.fromApi(adminData);
    } catch (error) {
      debugPrint(
        '[AdminAuth] Session restoration failed: $error',
      );

      await _clearStorage();
      return null;
    }
  }

  /// Connexion Admin.
  Future<AdminUser> signIn({
    required String email,
    required String password,
  }) async {
    final operationVersion = ++_authOperationVersion;

    final response = await _request(
      '/api/admin/login',
      method: 'POST',
      body: {
        'email': email.trim(),
        'password': password,
      },
    );

    final token = response['token'];
    final adminData = response['admin'];

    if (token is! String ||
        token.isEmpty ||
        adminData is! Map<String, dynamic>) {
      throw const FormatException(
        'Réponse de connexion admin invalide.',
      );
    }

    final admin = AdminUser.fromApi(adminData);

    await _storage.write(
      key: _tokenKey,
      value: token,
    );

    await _storage.write(
      key: _emailKey,
      value: admin.email,
    );

    if (operationVersion == _authOperationVersion) {
      _publishAuthState(admin);
    }

    return admin;
  }

  /// Déconnexion Admin.
  Future<void> signOut() async {
    ++_authOperationVersion;

    final token = await _storage.read(key: _tokenKey);

    try {
      if (token != null && token.isNotEmpty) {
        await _request(
          '/api/admin/logout',
          method: 'POST',
          token: token,
        );
      }
    } catch (error) {
      debugPrint(
        '[AdminAuth] Logout server error: $error',
      );
    } finally {
      await _clearStorage();

      // Retour à l'état non connecté.
      _publishAuthState(null);
    }
  }

  /// Retourne le token Admin.
  Future<String?> getAccessToken() {
    return _storage.read(key: _tokenKey);
  }

  /// Supprime les informations de session locales.
  Future<void> _clearStorage() async {
    await Future.wait([
      _storage.delete(key: _tokenKey),
      _storage.delete(key: _emailKey),
    ]);
  }

  /// Requête HTTP vers Cloudflare Workers.
  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    String? token,
  }) async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    final uri = Uri.parse('$_baseUrl$path');

    final http.Response response;

    try {
      response = await switch (method) {
        'POST' => _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? const {}),
          ),
        _ => _client.get(
            uri,
            headers: headers,
          ),
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
      throw const FormatException(
        'Le serveur a retourné une réponse invalide.',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Le serveur a retourné une réponse invalide.',
      );
    }

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      debugPrint(
        '[AdminAuth] ${response.statusCode} '
        '$path : ${decoded['error']}',
      );

      final code = decoded['error'] as String? ?? '';

      throw AuthException(
        switch (code) {
          'Invalid credentials' => 'invalid-credential',
          'Too many login attempts' => 'too-many-requests',
          'Admin authentication required' =>
            'requires-recent-login',
          _ => 'service-unavailable',
        },
      );
    }

    return decoded;
  }

  /// Libération des ressources.
  Future<void> dispose() async {
    await _authChanges.close();
    _client.close();
  }
}
