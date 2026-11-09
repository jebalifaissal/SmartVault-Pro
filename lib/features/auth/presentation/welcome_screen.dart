import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    required this.onCommencer,
    required this.onAdminLogin,
  });

  final VoidCallback onCommencer;
  final VoidCallback onAdminLogin;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final VideoPlayerController _controller;
  Object? _videoError;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.asset(
      'assets/videos/smartvault_intro.mp4',
    );
    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    try {
      await _controller.initialize();
      await _controller.setLooping(true);
      await _controller.setVolume(0);
      await _controller.play();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _videoError = error);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF18B6A5);

    return Scaffold(
      backgroundColor: const Color(0xFF07151B),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(teal),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x99071319),
                  Color(0x22071319),
                  Color(0x55071319),
                  Color(0xF2071319),
                ],
                stops: [0, 0.3, 0.55, 1],
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 26,
                    vertical: 22,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 44,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBrand(teal),
                        _buildWelcomeContent(teal),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground(Color accent) {
    if (_controller.value.isInitialized) {
      final size = _controller.value.size;
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(_controller),
          ),
        ),
      );
    }

    return ColoredBox(
      color: const Color(0xFF10252D),
      child: Center(
        child: _videoError == null
            ? const CircularProgressIndicator(
                color: Color(0xFF18B6A5),
              )
            : Icon(
                Icons.movie_outlined,
                color: accent.withValues(alpha: 0.7),
                size: 88,
              ),
      ),
    );
  }

  Widget _buildBrand(Color accent) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: accent.withValues(alpha: 0.55),
            ),
          ),
          child: Icon(
            Icons.shield_rounded,
            color: accent,
            size: 27,
          ),
        ),
        const SizedBox(width: 12),
        const Text(
          'SmartVault Pro',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeContent(Color accent) {
    return Padding(
      padding: const EdgeInsets.only(top: 100, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: accent.withValues(alpha: 0.6),
              ),
            ),
            child: const Text(
              'VOTRE COFFRE-FORT NUMÉRIQUE',
              style: TextStyle(
                color: Color(0xFFB8F4EA),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Vos documents.\nToujours protégés.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 38,
              height: 1.08,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Gardez vos documents importants au même endroit, '
            'retrouvez-les facilement et partagez-les en toute sécurité.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontSize: 15,
              height: 1.55,
            ),
          ),
          if (_videoError != null) ...[
            const SizedBox(height: 12),
            Text(
              'La vidéo ne peut pas être lue. Vérifiez le fichier '
              'assets/videos/smartvault_intro.mp4.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 28),

          // Bouton utilisateur
          SizedBox(
            width: double.infinity,
            height: 58,
            child: FilledButton(
              onPressed: widget.onCommencer,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: const Color(0xFF06211F),
                elevation: 8,
                shadowColor: accent.withValues(alpha: 0.38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Commencer',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 21,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Bouton Administrateur
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: widget.onAdminLogin,
              icon: const Icon(
                Icons.admin_panel_settings_outlined,
                size: 21,
              ),
              label: const Text(
                'Accès Administrateur',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(
                  color: accent.withValues(alpha: 0.65),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
          ),

          const SizedBox(height: 18),

          Center(
            child: Text(
              'Simple • Pratique • Sécurisé',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.65),
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}