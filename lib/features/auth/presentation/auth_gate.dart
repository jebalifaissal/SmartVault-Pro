
import 'package:flutter/material.dart';

import '../../../services/document_api_service.dart';

import '../../admin/data/admin_auth_repository.dart';
import '../../admin/domain/admin_user.dart';
import '../../admin/presentation/admin_inbox_screen.dart';
import '../../admin/presentation/admin_login_screen.dart';

import '../../documents/data/document_share_service.dart';
import '../../documents/domain/document_repository.dart';
import '../../documents/domain/local_cin_repository.dart';
import '../../documents/presentation/public_documents_screen.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

import 'welcome_screen.dart';
import 'document_category_selection_screen.dart';
import 'home_screen.dart';
import 'idle_session_gate.dart';
import 'login_screen.dart';
import 'register_screen.dart';

enum _Step {
  welcome,
  categoryChoice,
  login,
  register,
  publicDocs,
  adminLogin,
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.authRepository,
    required this.adminAuthRepository,
    required this.adminApi,
    required this.documentsRepository,
    this.localCinRepository,
    this.classificationApi,
    this.documentShareService,
    this.idleTimeout = const Duration(minutes: 1),
    super.key,
  });

  // Authentification utilisateur
  final AuthRepository authRepository;

  // Authentification Admin indépendante
  final AdminAuthRepository adminAuthRepository;

  // API utilisant exclusivement le token Admin
  final DocumentApiService adminApi;

  // Documents utilisateur
  final DocumentRepository documentsRepository;
  final LocalDocumentRepository? localCinRepository;

  // API utilisateur
  final DocumentApiService? classificationApi;
  final DocumentShareService? documentShareService;

  final Duration idleTimeout;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _Step _step = _Step.welcome;

  bool _wasLoggedIn = false;

  @override
  Widget build(BuildContext context) {
    // Vérification indépendante de la session Admin
    return StreamBuilder<AdminUser?>(
      stream: widget.adminAuthRepository.authStateChanges,
      builder: (context, adminSnapshot) {
        if (adminSnapshot.hasError) {
          return _errorScreen(
            'Impossible de vérifier la session Admin : '
            '${adminSnapshot.error}',
          );
        }

        if (adminSnapshot.connectionState == ConnectionState.waiting) {
          return _loadingScreen();
        }

        final admin = adminSnapshot.data;

        // Admin connecté → ouverture directe de la boîte de réception
        if (admin != null) {
          return _adminScreen(admin);
        }

        // Pas de session Admin → vérification utilisateur normal
        return _buildUserAuthentication();
      },
    );
  }

  Widget _buildUserAuthentication() {
    return StreamBuilder<AuthUser?>(
      stream: widget.authRepository.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _errorScreen(
            'Impossible de vérifier la session : ${snapshot.error}',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingScreen();
        }

        final user = snapshot.data;

        if (user != null) {
          _wasLoggedIn = true;
          return _authenticatedScreen(user);
        }

        if (_wasLoggedIn) {
          _wasLoggedIn = false;
          _step = _Step.welcome;
        }

        return _buildNavigationSteps();
      },
    );
  }

  Widget _buildNavigationSteps() {
    return switch (_step) {
      _Step.welcome => WelcomeScreen(
          onCommencer: () {
            setState(() {
              _step = _Step.categoryChoice;
            });
          },
          onAdminLogin: () {
            setState(() {
              _step = _Step.adminLogin;
            });
          },
        ),

      _Step.categoryChoice => DocumentCategorySelectionScreen(
          onSelectSensitive: () {
            setState(() {
              _step = _Step.login;
            });
          },
          onSelectModerate: () {
            setState(() {
              _step = _Step.publicDocs;
            });
          },
        ),

      _Step.login => LoginScreen(
          authRepository: widget.authRepository,
          onBack: () {
            setState(() {
              _step = _Step.categoryChoice;
            });
          },
          onRegister: () {
            setState(() {
              _step = _Step.register;
            });
          },
        ),

      _Step.register => RegisterScreen(
          authRepository: widget.authRepository,
          onBack: () {
            setState(() {
              _step = _Step.login;
            });
          },
        ),

      _Step.publicDocs => PublicDocumentsScreen(
          onBack: () {
            setState(() {
              _step = _Step.categoryChoice;
            });
          },
        ),

      _Step.adminLogin => AdminLoginScreen(
          repository: widget.adminAuthRepository,
          onBack: () {
            setState(() {
              _step = _Step.welcome;
            });
          },
        ),
    };
  }

  // Espace Admin : utilise uniquement AdminUser et adminApi
  Widget _adminScreen(AdminUser admin) {
    return AdminInboxScreen(
      api: widget.adminApi,
      user: admin,
      onSignOut: widget.adminAuthRepository.signOut,
    );
  }

  // Espace utilisateur normal
  Widget _authenticatedScreen(AuthUser user) {
    return IdleSessionGate(
      key: ValueKey(user.id),
      authRepository: widget.authRepository,
      user: user,
      idleTimeout: widget.idleTimeout,
      child: HomeScreen(
        authRepository: widget.authRepository,
        documentsRepository: widget.documentsRepository,
        localCinRepository: widget.localCinRepository,
        classificationApi: widget.classificationApi,
        documentShareService: widget.documentShareService,
        user: user,
      ),
    );
  }

  Widget _loadingScreen() {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF087E78),
        ),
      ),
    );
  }

  Widget _errorScreen(String message) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
