import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../../../services/cloudflare_api_config.dart';
import '../domain/auth_exception.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'cloudflare_session_store.dart';

class CloudflareAuthRepository implements AuthRepository {
  CloudflareAuthRepository({
    required CloudflareSessionStore sessionStore,
    http.Client? client,
    String? baseUrl,
  }) : _sessionStore = sessionStore,
       _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? CloudflareApiConfig.baseUrl;

  final CloudflareSessionStore _sessionStore;
  final http.Client _client;
  final String _baseUrl;
  final StreamController<AuthUser?> _authChanges =
      StreamController<AuthUser?>.broadcast();
  Future<AuthUser?>? _initialSession;

  @override
  late final Stream<AuthUser?> authStateChanges = _watchAuthChanges();

  Stream<AuthUser?> _watchAuthChanges() async* {
    yield await (_initialSession ??= _restoreSession());
    yield* _authChanges.stream;
  }

  Future<AuthUser?> _restoreSession() async {
    final token = await _sessionStore.readToken();
    final user = await _sessionStore.readUser();
    if (token == null || token.isEmpty || user == null) {
      await _sessionStore.clear();
      return null;
    }
    return user;
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _request(
      '/api/auth/login',
      method: 'POST',
      body: {'email': email.trim(), 'password': password},
    );
    final token = response['token'];
    final userData = response['user'];
    final isAdmin = response['isAdmin'];
    if (token is! String ||
        token.isEmpty ||
        userData is! Map<String, dynamic> ||
        isAdmin is! bool) {
      throw const FormatException('Invalid Cloudflare login response.');
    }
    final user = _parseUser(userData);
    await _sessionStore.writeSession(
      token: token,
      user: user,
      isAdministrator: isAdmin,
    );
    _authChanges.add(user);
    return user;
  }

  @override
  Future<AuthUser> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    final response = await _request(
      '/api/auth/register',
      method: 'POST',
      body: {
        'name': name.trim(),
        'email': email.trim().toLowerCase(),
        'password': password,
      },
    );
    final token = response['token'];
    final userData = response['user'];
    final isAdmin = response['isAdmin'];
    if (token is! String ||
        token.isEmpty ||
        userData is! Map<String, dynamic> ||
        isAdmin is! bool) {
      throw const FormatException('Invalid Cloudflare registration response.');
    }
    final user = _parseUser(userData);
    await _sessionStore.writeSession(
      token: token,
      user: user,
      isAdministrator: isAdmin,
    );
    _authChanges.add(user);
    return user;
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async {
    await _request(
      '/api/auth/password-reset',
      method: 'POST',
      body: {'email': email.trim().toLowerCase()},
    );
  }

  @override
  Future<void> reauthenticate({required String password}) async {
    final token = await getAccessToken();
    if (token == null) throw const AuthException('requires-recent-login');
    await _request(
      '/api/auth/reauthenticate',
      method: 'POST',
      body: {'password': password},
      accessToken: token,
    );
  }

  @override
  Future<void> signOut() async {
    final token = await getAccessToken();
    try {
      if (token != null) {
        await _request(
          '/api/auth/session',
          method: 'DELETE',
          accessToken: token,
        );
      }
    } finally {
      await _sessionStore.clear();
      _authChanges.add(null);
    }
  }

  Future<String?> getAccessToken() => _sessionStore.readToken();

  Future<bool?> getCachedAdministrator() => _sessionStore.readAdministrator();

  AuthUser _parseUser(Map<String, dynamic> data) {
    final id = data['id'];
    final email = data['email'];
    final displayName = data['display_name'];
    if (id is! String ||
        id.isEmpty ||
        email is! String ||
        email.isEmpty ||
        (displayName != null && displayName is! String)) {
      throw const FormatException('Invalid Cloudflare user response.');
    }
    return AuthUser(id: id, email: email, displayName: displayName as String?);
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? body,
    String? accessToken,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (accessToken != null) {
      headers['Authorization'] = 'Bearer $accessToken';
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
        'DELETE' => _client.delete(uri, headers: headers),
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
      throw const FormatException('Cloudflare returned an invalid response.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Cloudflare returned an invalid response.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('AUTH URL: $uri');
  debugPrint('AUTH STATUS: ${response.statusCode}');
  debugPrint('AUTH ERROR: ${decoded['error']}');
      final code = decoded['error'];
      throw AuthException(switch (code) {
        'Invalid email or password' => 'invalid-credential',
        'Invalid credentials' => 'invalid-credential',
        'Too many login attempts' => 'too-many-requests',
        'Email already in use' ||
        'Email already registered' =>
          'email-already-in-use',
        'Invalid email' || 'Invalid email address' => 'invalid-email',
        'Password must be at least 8 characters' ||
        'Password too short' =>
          'weak-password',
        'Invalid name' => 'invalid-name',
        'Account registration is disabled until email verification is configured.' =>
          'registration-disabled',
        'Password reset is unavailable until email delivery is configured.' =>
          'password-reset-disabled',
        'Authentication required' => 'requires-recent-login',
        _ => 'service-unavailable',
      });
    }
    return decoded;
  }
}
