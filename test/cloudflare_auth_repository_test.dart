import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartvault_pro/features/auth/data/cloudflare_auth_repository.dart';
import 'package:smartvault_pro/features/auth/data/cloudflare_session_store.dart';
import 'package:smartvault_pro/features/auth/domain/auth_exception.dart';
import 'package:smartvault_pro/features/auth/domain/auth_user.dart';

class _MemorySessionStore extends CloudflareSessionStore {
  String? token;
  AuthUser? user;
  bool? administrator;

  @override
  Future<String?> readToken() async => token;

  @override
  Future<AuthUser?> readUser() async => user;

  @override
  Future<bool?> readAdministrator() async => administrator;

  @override
  Future<void> writeSession({
    required String token,
    required AuthUser user,
    required bool isAdministrator,
  }) async {
    this.token = token;
    this.user = user;
    administrator = isAdministrator;
  }

  @override
  Future<void> clear() async {
    token = null;
    user = null;
    administrator = null;
  }
}

void main() {
  test('reports transport failures as a network error', () async {
    final repository = CloudflareAuthRepository(
      sessionStore: _MemorySessionStore(),
      client: MockClient((_) async => throw const SocketException('offline')),
    );

    await expectLater(
      repository.signIn(email: 'user@example.com', password: 'password'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.code,
          'code',
          'network-request-failed',
        ),
      ),
    );
  });

  test('reports login rate limiting separately from network failures', () async {
    final repository = CloudflareAuthRepository(
      sessionStore: _MemorySessionStore(),
      client: MockClient(
        (_) async => http.Response(
          '{"success":false,"error":"Too many login attempts"}',
          429,
        ),
      ),
    );

    await expectLater(
      repository.signIn(email: 'user@example.com', password: 'password'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.code,
          'code',
          'too-many-requests',
        ),
      ),
    );
  });

  test('createAccount registers user, saves session, and emits auth change', () async {
    final sessionStore = _MemorySessionStore();
    final repository = CloudflareAuthRepository(
      sessionStore: sessionStore,
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/auth/register');
        return http.Response(
          '{"success":true,"token":"sample-jwt-bearer-token","expires_at":1900000000000,"user":{"id":"user-123","email":"new@example.com","display_name":"New User"},"isAdmin":false}',
          201,
        );
      }),
    );

    final emittedUsers = <AuthUser?>[];
    final subscription = repository.authStateChanges.listen(emittedUsers.add);

    final user = await repository.createAccount(
      name: 'New User',
      email: 'New@Example.COM',
      password: 'SecurePassword123!',
    );

    expect(user.id, 'user-123');
    expect(user.email, 'new@example.com');
    expect(user.displayName, 'New User');

    expect(sessionStore.token, 'sample-jwt-bearer-token');
    expect(sessionStore.user?.id, 'user-123');
    expect(sessionStore.administrator, isFalse);

    await Future<void>.delayed(Duration.zero);
    expect(emittedUsers.any((u) => u?.id == 'user-123'), isTrue);
    await subscription.cancel();
  });

  test('createAccount handles duplicate email conflict', () async {
    final repository = CloudflareAuthRepository(
      sessionStore: _MemorySessionStore(),
      client: MockClient(
        (_) async => http.Response(
          '{"success":false,"error":"Email already in use"}',
          409,
        ),
      ),
    );

    await expectLater(
      repository.createAccount(
        name: 'User',
        email: 'used@example.com',
        password: 'Password123',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.code,
          'code',
          'email-already-in-use',
        ),
      ),
    );
  });

  test('createAccount handles weak password rejection', () async {
    final repository = CloudflareAuthRepository(
      sessionStore: _MemorySessionStore(),
      client: MockClient(
        (_) async => http.Response(
          '{"success":false,"error":"Password must be at least 8 characters"}',
          400,
        ),
      ),
    );

    await expectLater(
      repository.createAccount(
        name: 'User',
        email: 'user@example.com',
        password: 'short',
      ),
      throwsA(
        isA<AuthException>().having(
          (error) => error.code,
          'code',
          'weak-password',
        ),
      ),
    );
  });

  test('sendPasswordResetEmail handles disabled reset endpoint', () async {
    final repository = CloudflareAuthRepository(
      sessionStore: _MemorySessionStore(),
      client: MockClient(
        (_) async => http.Response(
          '{"success":false,"error":"Password reset is unavailable until email delivery is configured."}',
          503,
        ),
      ),
    );

    await expectLater(
      repository.sendPasswordResetEmail('user@example.com'),
      throwsA(
        isA<AuthException>().having(
          (error) => error.code,
          'code',
          'password-reset-disabled',
        ),
      ),
    );
  });
}
