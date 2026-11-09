import 'package:flutter/material.dart';

/// Ecran intermediaire affiche apres la video d'intro.
/// L'utilisateur choisit entre :
///  - Documents tres sensibles  -> vers Login / compte securise
///  - Documents moyennement sensibles -> vers espace ouvert (cours, notes...)
class DocumentCategorySelectionScreen extends StatelessWidget {
  const DocumentCategorySelectionScreen({
    required this.onSelectSensitive,
    required this.onSelectModerate,
    super.key,
  });

  /// Appele quand l'utilisateur choisit "Tres sensible"
  final VoidCallback onSelectSensitive;

  /// Appele quand l'utilisateur choisit "Moyennement sensible"
  final VoidCallback onSelectModerate;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07151B),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── En-tête ─────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF18B6A5).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: const Color(0xFF18B6A5).withValues(alpha: 0.5),
                      ),
                    ),
                    child: const Icon(
                      Icons.shield_rounded,
                      color: Color(0xFF18B6A5),
                      size: 25,
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
              ),

              const SizedBox(height: 48),

              // ── Titre ───────────────────────────────────────────────
              const Text(
                'Quel type de\ndocument ?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "Choisissez la cat\u00e9gorie correspondant \u00e0 votre document "
                "pour acc\u00e9der \u00e0 l'espace s\u00e9curis\u00e9 appropri\u00e9.",
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 14,
                  height: 1.55,
                ),
              ),

              const SizedBox(height: 40),

              // ── Carte « Très sensible » ──────────────────────────────
              _DocumentCategoryCard(
                onTap: onSelectSensitive,
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A3A6B), Color(0xFF0D2247)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderColor: const Color(0xFF3A6CC2),
                badgeColor: const Color(0xFF3A6CC2),
                badgeLabel: 'ACC\u00c8S S\u00c9CURIS\u00c9',
                icon: Icons.verified_user_rounded,
                iconBg: const Color(0xFF1E4494),
                iconColor: const Color(0xFF7AADFF),
                title: 'Documents tr\u00e8s sensibles',
                subtitle:
                    "Pi\u00e8ces d'identit\u00e9 officielles qui n\u00e9cessitent une "
                    "authentification s\u00e9curis\u00e9e.",
                examples: const [
                  _ExampleChip(
                    icon: Icons.badge_outlined,
                    label: 'CIN',
                    color: Color(0xFF7AADFF),
                  ),
                  _ExampleChip(
                    icon: Icons.book_outlined,
                    label: 'Passeport',
                    color: Color(0xFF7AADFF),
                  ),
                  _ExampleChip(
                    icon: Icons.directions_car_outlined,
                    label: 'Permis',
                    color: Color(0xFF7AADFF),
                  ),
                ],
                actionLabel: 'Acc\u00e9der \u00e0 mon compte',
                actionIcon: Icons.lock_open_rounded,
                actionBg: const Color(0xFF3A6CC2),
                securityNote:
                    'Ces documents sont analys\u00e9s et class\u00e9s '
                    'par un administrateur.',
              ),

              const SizedBox(height: 20),

              // ── Carte « Moyennement sensible » ──────────────────────
              _DocumentCategoryCard(
                onTap: onSelectModerate,
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F3028), Color(0xFF072019)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderColor: const Color(0xFF18B6A5),
                badgeColor: const Color(0xFF18B6A5),
                badgeLabel: 'ACC\u00c8S SIMPLIFI\u00c9',
                icon: Icons.folder_special_rounded,
                iconBg: const Color(0xFF134E42),
                iconColor: const Color(0xFF4CD9C8),
                title: 'Documents moyennement sensibles',
                subtitle:
                    "Cours, notes, fiches d'information et tout autre "
                    "document sans donn\u00e9es personnelles critiques.",
                examples: const [
                  _ExampleChip(
                    icon: Icons.menu_book_outlined,
                    label: 'Cours',
                    color: Color(0xFF4CD9C8),
                  ),
                  _ExampleChip(
                    icon: Icons.note_outlined,
                    label: 'Notes',
                    color: Color(0xFF4CD9C8),
                  ),
                  _ExampleChip(
                    icon: Icons.info_outline_rounded,
                    label: 'Infos',
                    color: Color(0xFF4CD9C8),
                  ),
                ],
                actionLabel: 'Parcourir les documents',
                actionIcon: Icons.folder_open_rounded,
                actionBg: const Color(0xFF18B6A5),
                securityNote:
                    "L'admin peut d\u00e9placer un document vers "
                    "la section s\u00e9curis\u00e9e si n\u00e9cessaire.",
              ),

              const SizedBox(height: 32),

              // ── Note de bas de page ─────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 13,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      "L'administrateur analyse et classe les documents "
                      "selon leur niveau de sensibilit\u00e9.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.35),
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte de categorie reutilisable
// ─────────────────────────────────────────────────────────────────────────────

class _DocumentCategoryCard extends StatefulWidget {
  const _DocumentCategoryCard({
    required this.onTap,
    required this.gradient,
    required this.borderColor,
    required this.badgeColor,
    required this.badgeLabel,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.examples,
    required this.actionLabel,
    required this.actionIcon,
    required this.actionBg,
    required this.securityNote,
  });

  final VoidCallback onTap;
  final Gradient gradient;
  final Color borderColor;
  final Color badgeColor;
  final String badgeLabel;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final List<_ExampleChip> examples;
  final String actionLabel;
  final IconData actionIcon;
  final Color actionBg;
  final String securityNote;

  @override
  State<_DocumentCategoryCard> createState() => _DocumentCategoryCardState();
}

class _DocumentCategoryCardState extends State<_DocumentCategoryCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            gradient: widget.gradient,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: widget.borderColor.withValues(alpha: _pressed ? 1.0 : 0.6),
              width: _pressed ? 1.5 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.borderColor
                    .withValues(alpha: _pressed ? 0.3 : 0.12),
                blurRadius: _pressed ? 20 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Badge + Icone ───────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: widget.badgeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: widget.badgeColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        widget.badgeLabel,
                        style: TextStyle(
                          color: widget.badgeColor,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.9,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: widget.iconBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        widget.icon,
                        color: widget.iconColor,
                        size: 24,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 18),

                // ── Titre ───────────────────────────────────────────
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.65),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 16),

                // ── Exemples ────────────────────────────────────────
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.examples,
                ),

                const SizedBox(height: 20),

                // ── Bouton d'action ─────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: widget.onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: widget.actionBg,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: Icon(widget.actionIcon, size: 18),
                    label: Text(
                      widget.actionLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Note securite ───────────────────────────────────
                Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      size: 12,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        widget.securityNote,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 11,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chip d'exemple de document
// ─────────────────────────────────────────────────────────────────────────────

class _ExampleChip extends StatelessWidget {
  const _ExampleChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
