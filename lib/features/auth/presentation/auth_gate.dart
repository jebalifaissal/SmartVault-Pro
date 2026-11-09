import 'package:flutter/material.dart';
import '../../../services/document_api_service.dart';
import '../../admin/presentation/admin_inbox_screen.dart';
import '../../documents/data/document_share_service.dart';
import 'welcome_screen.dart';
import 'document_category_selection_screen.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import '../../documents/domain/document_repository.dart';
import '../../documents/domain/local_cin_repository.dart';
import '../../documents/presentation/public_documents_screen.dart';
import 'home_screen.dart';
import 'idle_session_gate.dart';
import 'login_screen.dart';
import 'register_screen.dart';

/// Étapes de navigation pré-authentification.
enum _Step {
  welcome, // Vidéo d'intro
  categoryChoice, // Choix Sensible / Modéré
  login, // Connexion (documents sensibles)
  register, // Création de compte
  publicDocs, // Espace ouvert (documents modérés)
}

class AuthGate extends StatefulWidget {
  const AuthGate({
    required this.authRepository,
    required this.documentsRepository,
    this.localCinRepository,
    this.classificationApi,
    this.documentShareService,
    this.idleTimeout = const Duration(minutes: 1),
    super.key,
  });

  final AuthRepository authRepository;
  final DocumentRepository documentsRepository;
  final LocalDocumentRepository? localCinRepository;
  final DocumentApiService? classificationApi;
  final DocumentShareService? documentShareService;

  /// Durée d'inactivité avant verrouillage, réglée à une minute par défaut.
  final Duration idleTimeout;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _Step _step = _Step.welcome;
  bool _wasLoggedIn = false;
  String? _roleCheckUserId;
  Future<bool>? _administratorCheck;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthUser?>(
      stream: widget.authRepository.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Impossible de vérifier la session : ${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF087E78)),
            ),
          );
        }

        final user = snapshot.data;

        // ── Utilisateur authentifié → tableau de bord ─────────────────────
        if (user != null) {
          _wasLoggedIn = true;
          final classificationApi = widget.classificationApi;
          if (classificationApi != null) {
            if (_roleCheckUserId != user.id) {
              _roleCheckUserId = user.id;
              _administratorCheck = classificationApi
                  .isCurrentUserAdministrator();
            }
            return FutureBuilder<bool>(
              future: _administratorCheck,
              builder: (context, roleSnapshot) {
                if (roleSnapshot.hasError) {
                  return Scaffold(
                    body: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Impossible de vérifier les autorisations : '
                          '${roleSnapshot.error}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }
                if (!roleSnapshot.hasData) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF087E78),
                      ),
                    ),
                  );
                }
                return _authenticatedScreen(
                  user,
                  isAdministrator: roleSnapshot.data!,
                );
              },
            );
          }
          return _authenticatedScreen(user, isAdministrator: false);
        }

        _roleCheckUserId = null;
        _administratorCheck = null;

        // Si l'utilisateur était connecté et vient de se déconnecter,
        // on retourne obligatoirement à la première page (vidéo d'intro).
        if (_wasLoggedIn) {
          _wasLoggedIn = false;
          _step = _Step.welcome;
        }

        // ── Non authentifié → flux de navigation en étapes ───────────────
        return switch (_step) {
          _Step.welcome => WelcomeScreen(
            onCommencer: () => setState(() => _step = _Step.categoryChoice),
          ),

          _Step.categoryChoice => DocumentCategorySelectionScreen(
            // Très sensible → connexion sécurisée
            onSelectSensitive: () => setState(() => _step = _Step.login),
            // Moyennement sensible → espace ouvert
            onSelectModerate: () => setState(() => _step = _Step.publicDocs),
          ),

          _Step.login => LoginScreen(
            authRepository: widget.authRepository,
            onBack: () => setState(() => _step = _Step.categoryChoice),
            onRegister: () => setState(() => _step = _Step.register),
          ),

          _Step.register => RegisterScreen(
            authRepository: widget.authRepository,
            onBack: () => setState(() => _step = _Step.login),
          ),

          _Step.publicDocs => PublicDocumentsScreen(
            onBack: () => setState(() => _step = _Step.categoryChoice),
          ),
        };
      },
    );
  }

  Widget _authenticatedScreen(AuthUser user, {required bool isAdministrator}) =>
      IdleSessionGate(
        key: ValueKey(user.id),
        authRepository: widget.authRepository,
        user: user,
        idleTimeout: widget.idleTimeout,
        child: isAdministrator
            ? AdminInboxScreen(
                api: widget.classificationApi!,
                user: user,
                onSignOut: widget.authRepository.signOut,
              )
            : HomeScreen(
                authRepository: widget.authRepository,
                documentsRepository: widget.documentsRepository,
                localCinRepository: widget.localCinRepository,
                classificationApi: widget.classificationApi,
                documentShareService: widget.documentShareService,
                user: user,
              ),
      );
}
