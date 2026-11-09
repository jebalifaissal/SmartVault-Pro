import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_error_message.dart';
import 'session_lock_activity.dart';

/// Surveille l'inactivité autour des écrans privés et affiche le verrou
/// après un délai d'inactivité (par défaut 1 minute) ou mise en arrière-plan.
class IdleSessionGate extends StatefulWidget {
  const IdleSessionGate({
    required this.authRepository,
    required this.user,
    required this.child,
    this.idleTimeout = const Duration(minutes: 1),
    super.key,
  });

  final AuthRepository authRepository;
  final AuthUser user;
  final Widget child;

  /// Durée d'inactivité avant verrouillage.
  final Duration idleTimeout;

  @override
  State<IdleSessionGate> createState() => _IdleSessionGateState();
}

class _IdleSessionGateState extends State<IdleSessionGate>
    with WidgetsBindingObserver {
  Timer? _idleTimer;

  // L'utilisateur accède directement à l'espace privé dès sa connexion réussie.
  bool _isLocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Démarre le compte à rebours d'inactivité dès la connexion
    _restartIdleTimer();
  }

  @override
  void didUpdateWidget(covariant IdleSessionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.idleTimeout != widget.idleTimeout) {
      _restartIdleTimer();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    super.dispose();
  }

  // Chaque interaction tactile ou clavier remet à zéro le compte à rebours.
  void _recordActivity() {
    if (!_isLocked) {
      _restartIdleTimer();
    }
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    if (_isLocked || !mounted) return;

    _idleTimer = Timer(widget.idleTimeout, _lockSession);
  }

  // Verrouille la session après 1 minute d'inactivité ou passage en arrière-plan.
  void _lockSession() {
    _idleTimer?.cancel();
    if (!mounted || _isLocked) return;
    setState(() => _isLocked = true);
  }

  Future<T> _runWhileExternalActivity<T>(Future<T> Function() action) =>
      action();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Reprise d'activité (retour de la caméra, etc.) : on réarme le minuteur d'inactivité
      _recordActivity();
    }
  }

  Future<void> _unlock() async {
    if (_isLocked && mounted) {
      setState(() => _isLocked = false);
    }
    _restartIdleTimer();
  }

  @override
  Widget build(BuildContext context) {
    return SessionLockActivityScope(
      runWhileExternalActivity: _runWhileExternalActivity,
      child: Focus(
        // Les frappes clavier comptent aussi comme activité, pas seulement les taps.
        onKeyEvent: (node, event) {
          _recordActivity();
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _recordActivity(),
          onPointerMove: (_) => _recordActivity(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Le tableau de bord et les écrans enfants restent ouverts sous le verrou.
              Offstage(
                offstage: _isLocked,
                child: Navigator(
                  onGenerateInitialRoutes: (navigator, initialRoute) => [
                    MaterialPageRoute<void>(
                      builder: (_) => widget.child,
                      settings: RouteSettings(name: initialRoute),
                    ),
                  ],
                  onGenerateRoute: (_) =>
                      MaterialPageRoute<void>(builder: (_) => widget.child),
                ),
              ),
              if (_isLocked)
                _SessionLockScreen(
                  user: widget.user,
                  authRepository: widget.authRepository,
                  idleTimeout: widget.idleTimeout,
                  onUnlocked: _unlock,
                  onSignOut: widget.authRepository.signOut,
                  initializationError: null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionLockScreen extends StatefulWidget {
  const _SessionLockScreen({
    required this.user,
    required this.authRepository,
    required this.idleTimeout,
    required this.onUnlocked,
    required this.onSignOut,
    required this.initializationError,
  });

  final AuthUser user;
  final AuthRepository authRepository;
  final Duration idleTimeout;
  final VoidCallback onUnlocked;
  final Future<void> Function() onSignOut;
  final String? initializationError;

  @override
  State<_SessionLockScreen> createState() => _SessionLockScreenState();
}

class _SessionLockScreenState extends State<_SessionLockScreen> {
  final LocalAuthentication _auth = LocalAuthentication();

  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _verifyBiometrics() async {
    if (_isSubmitting) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final authenticated = await _auth.authenticate(
        localizedReason:
            'Confirmez votre identit\u00e9 pour d\u00e9verrouiller SmartVault Pro.',
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );

      if (!mounted) return;

      if (authenticated) {
        widget.onUnlocked();
      } else {
        setState(() {
          _errorMessage = 'Visage non reconnu. R\u00e9essayez.';
        });
      }
    } on LocalAuthException catch (error) {
      if (!mounted) return;

      setState(() {
        _errorMessage = switch (error.code) {
          LocalAuthExceptionCode.noBiometricsEnrolled =>
            'Aucune biom\u00e9trie utilisable par les applications n\u2019est '
                'configur\u00e9e. Android peut proposer le code ou le sch\u00e9ma '
                'de verrouillage de votre t\u00e9l\u00e9phone.',
          LocalAuthExceptionCode.noBiometricHardware =>
            'Aucune m\u00e9thode biom\u00e9trique utilisable par les applications '
                'n\u2019est disponible sur ce t\u00e9l\u00e9phone.',
          LocalAuthExceptionCode.biometricLockout =>
            'La biom\u00e9trie est temporairement bloqu\u00e9e. D\u00e9verrouillez d\u2019abord '
                'le t\u00e9l\u00e9phone avec son code ou son sch\u00e9ma, puis r\u00e9essayez.',
          LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
            'Le capteur facial est momentan\u00e9ment indisponible. R\u00e9essayez.',
          LocalAuthExceptionCode.userCanceled ||
          LocalAuthExceptionCode.systemCanceled => 'Authentification annul\u00e9e.',
          _ => '\u00c9chec de l\u2019authentification biom\u00e9trique. R\u00e9essayez.',
        };
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _signOut() async {
    setState(() => _isSubmitting = true);

    try {
      await widget.onSignOut();
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = authErrorMessage(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE4F2F0),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.face_retouching_natural,
                    size: 48,
                    color: Color(0xFF087E78),
                  ),
                ),

                const SizedBox(height: 25),

                const Text(
                  'Session verrouill\u00e9e',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF172B3A),
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'Votre session SmartVault Pro est verrouill\u00e9e. '
                  'Confirmez votre identit\u00e9 avec la biom\u00e9trie ou le code '
                  'de verrouillage du t\u00e9l\u00e9phone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF71808A),
                    height: 1.5,
                  ),
                ),

                if (widget.initializationError != null) ...[
                  const SizedBox(height: 15),
                  Text(
                    widget.initializationError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFC83D4D),
                      fontSize: 12,
                    ),
                  ),
                ],

                const SizedBox(height: 35),

                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton.icon(
                    onPressed: _isSubmitting ? null : _verifyBiometrics,
                    icon: const Icon(Icons.face),
                    label: Text(
                      _isSubmitting
                          ? 'V\u00e9rification...'
                          : 'D\u00e9verrouiller avec biom\u00e9trie ou code',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF087E78),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),

                if (_errorMessage != null) ...[
                  const SizedBox(height: 15),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFC83D4D),
                      fontSize: 12,
                    ),
                  ),
                ],

                const SizedBox(height: 15),

                TextButton(
                  onPressed: _isSubmitting ? null : _signOut,
                  child: const Text('Se d\u00e9connecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
