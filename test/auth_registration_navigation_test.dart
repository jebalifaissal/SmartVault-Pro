import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartvault_pro/features/auth/domain/auth_exception.dart';
import 'package:smartvault_pro/features/auth/domain/auth_repository.dart';
import 'package:smartvault_pro/features/auth/domain/auth_user.dart';
import 'package:smartvault_pro/features/auth/presentation/login_screen.dart';
import 'package:smartvault_pro/features/auth/presentation/register_screen.dart';

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({
    this.createAccountHandler,
  });

  final Future<AuthUser> Function(String name, String email, String password)?
      createAccountHandler;
  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async => throw UnimplementedError();

  @override
  Future<AuthUser> createAccount({
    required String name,
    required String email,
    required String password,
  }) async {
    if (createAccountHandler != null) {
      final user = await createAccountHandler!(name, email, password);
      _controller.add(user);
      return user;
    }
    throw UnimplementedError();
  }

  @override
  Future<void> sendPasswordResetEmail(String email) async =>
      throw UnimplementedError();

  @override
  Future<void> reauthenticate({required String password}) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {
    _controller.add(null);
  }
}

void main() {
  testWidgets('registration button opens the registration flow', (
    tester,
  ) async {
    var registrationRequested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authRepository: _FakeAuthRepository(),
          onRegister: () => registrationRequested = true,
        ),
      ),
    );

    final registerButton = find.text('Créer un compte');
    await tester.ensureVisible(registerButton);
    await tester.tap(registerButton);

    expect(registrationRequested, isTrue);
  });

  testWidgets('successful registration does not trigger onBack', (
    tester,
  ) async {
    var onBackCalled = false;
    String? createdName;
    String? createdEmail;
    String? createdPassword;

    final fakeRepo = _FakeAuthRepository(
      createAccountHandler: (name, email, password) async {
        createdName = name;
        createdEmail = email;
        createdPassword = password;
        return AuthUser(id: 'new-id', email: email, displayName: name);
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RegisterScreen(
          authRepository: fakeRepo,
          onBack: () => onBackCalled = true,
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Votre nom'),
      'John Doe',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'nom@exemple.com'),
      'john.doe@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '8 caractères minimum'),
      'password123',
    );

    final submitButton = find.widgetWithText(FilledButton, 'Créer mon compte');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(createdName, 'John Doe');
    expect(createdEmail, 'john.doe@example.com');
    expect(createdPassword, 'password123');
    // Crucial: onBack must NOT be called on success!
    expect(onBackCalled, isFalse);
  });

  testWidgets('registration displays French error on duplicate email', (
    tester,
  ) async {
    final fakeRepo = _FakeAuthRepository(
      createAccountHandler: (name, email, password) async {
        throw const AuthException('email-already-in-use');
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RegisterScreen(
          authRepository: fakeRepo,
          onBack: () {},
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Votre nom'),
      'Jane Doe',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'nom@exemple.com'),
      'duplicate@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, '8 caractères minimum'),
      'password123',
    );

    final submitButton = find.widgetWithText(FilledButton, 'Créer mon compte');
    await tester.ensureVisible(submitButton);
    await tester.tap(submitButton);
    await tester.pumpAndSettle();

    expect(find.text('Cette adresse e-mail est déjà utilisée.'), findsOneWidget);
  });

  testWidgets('back buttons in RegisterScreen call onBack', (
    tester,
  ) async {
    var onBackCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: RegisterScreen(
          authRepository: _FakeAuthRepository(),
          onBack: () => onBackCount++,
        ),
      ),
    );

    // Tap top-left back icon button
    await tester.tap(find.byTooltip('Retour à la connexion'));
    await tester.pump();
    expect(onBackCount, 1);

    // Tap "J'ai déjà un compte" button
    final alreadyAccountButton = find.text('J’ai déjà un compte');
    await tester.ensureVisible(alreadyAccountButton);
    await tester.tap(alreadyAccountButton);
    await tester.pump();
    expect(onBackCount, 2);
  });
}
