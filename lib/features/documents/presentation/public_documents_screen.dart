import 'package:flutter/material.dart';

/// Espace dédié aux documents moyennement sensibles :
/// cours, notes, fiches d'information, etc.
/// Accessible sans authentification forte.
class PublicDocumentsScreen extends StatefulWidget {
  const PublicDocumentsScreen({this.onBack, super.key});

  /// Callback optionnel pour revenir en arrière (vers l'écran de choix).
  final VoidCallback? onBack;

  @override
  State<PublicDocumentsScreen> createState() => _PublicDocumentsScreenState();
}

class _PublicDocumentsScreenState extends State<PublicDocumentsScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'Tous';

  static const _teal = Color(0xFF18B6A5);
  static const _ink = Color(0xFF172B3A);
  static const _muted = Color(0xFF71808A);
  static const _canvas = Color(0xFFF4F7F7);
  static const _line = Color(0xFFE5EBEB);

  static const _categories = [
    'Tous',
    'Cours',
    'Notes',
    'Fiches',
    'Informations',
    'Autres',
  ];

  // Données de démonstration – à remplacer par un vrai repository
  static const _demoDocuments = <_PublicDoc>[
    _PublicDoc(
      title: 'Cours de Mathématiques – Algèbre',
      category: 'Cours',
      description: 'Chapitre 3 : Équations du second degré et discriminant.',
      icon: Icons.calculate_outlined,
      color: Color(0xFF5B8DEF),
      date: '12 Oct 2026',
    ),
    _PublicDoc(
      title: 'Notes de réunion – Projet Alpha',
      category: 'Notes',
      description: 'Compte rendu de la réunion du 05/10/2026.',
      icon: Icons.notes_outlined,
      color: Color(0xFFB06DD4),
      date: '05 Oct 2026',
    ),
    _PublicDoc(
      title: 'Fiche de révision – Histoire',
      category: 'Fiches',
      description: 'Résumé du chapitre sur la Révolution française.',
      icon: Icons.history_edu_outlined,
      color: Color(0xFFE0953A),
      date: '28 Sep 2026',
    ),
    _PublicDoc(
      title: 'Informations pratiques – Campus',
      category: 'Informations',
      description: 'Horaires, plans et services disponibles sur le campus.',
      icon: Icons.info_outline_rounded,
      color: Color(0xFF18B6A5),
      date: '20 Sep 2026',
    ),
    _PublicDoc(
      title: 'Cours de Physique – Optique',
      category: 'Cours',
      description: 'Lois de la réfraction et applications pratiques.',
      icon: Icons.science_outlined,
      color: Color(0xFF5B8DEF),
      date: '15 Sep 2026',
    ),
    _PublicDoc(
      title: 'Recueil de bonnes pratiques',
      category: 'Autres',
      description: 'Guide interne pour la gestion documentaire.',
      icon: Icons.checklist_rounded,
      color: Color(0xFF5DAF7A),
      date: '10 Sep 2026',
    ),
  ];

  List<_PublicDoc> get _visibleDocs {
    final query = _searchController.text.trim().toLowerCase();
    return _demoDocuments.where((doc) {
      final matchesCat =
          _selectedCategory == 'Tous' || doc.category == _selectedCategory;
      final matchesQuery =
          query.isEmpty ||
          doc.title.toLowerCase().contains(query) ||
          doc.description.toLowerCase().contains(query) ||
          doc.category.toLowerCase().contains(query);
      return matchesCat && matchesQuery;
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            _buildSearchBar(),
            _buildCategoryFilter(),
            Expanded(child: _buildDocumentList()),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUploadSheet(context),
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text(
          'Déposer un document',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  // ── En-tête ──────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 20, 18, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onBack ?? () => Navigator.of(context).pop(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 18,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Documents partagés',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  'Cours, notes & informations générales',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          // Badge « Accès simplifié »
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _teal.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_open_rounded, size: 11, color: _teal),
                SizedBox(width: 4),
                Text(
                  'SIMPLIFIÉ',
                  style: TextStyle(
                    color: _teal,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Barre de recherche ────────────────────────────────────────────────────

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: TextField(
        controller: _searchController,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: 'Rechercher un document…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                  },
                )
              : null,
        ),
      ),
    );
  }

  // ── Filtre par catégorie ──────────────────────────────────────────────────

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        itemCount: _categories.length,
        separatorBuilder: (context, idx) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = _categories[index];
          final isSelected = cat == _selectedCategory;
          return GestureDetector(
            onTap: () => setState(() => _selectedCategory = cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? _teal : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? _teal : _line,
                ),
              ),
              child: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? Colors.white : _muted,
                  fontSize: 12.5,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Liste de documents ────────────────────────────────────────────────────

  Widget _buildDocumentList() {
    final docs = _visibleDocs;
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F4F2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.search_off_rounded, color: _teal, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              'Aucun document trouvé',
              style: TextStyle(
                color: _ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Essayez une autre recherche ou catégorie.',
              style: TextStyle(color: _muted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 100),
      itemCount: docs.length,
      separatorBuilder: (context, idx) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _PublicDocumentTile(doc: docs[index]),
    );
  }

  // ── Feuille de dépôt ──────────────────────────────────────────────────────

  void _showUploadSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Déposer un document',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Le document sera examiné par un administrateur avant d\'être '
              'classé dans la section appropriée.',
              style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 20),
            // Boutons de dépôt
            _UploadOption(
              icon: Icons.photo_camera_outlined,
              label: 'Prendre une photo',
              color: _teal,
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Fonctionnalité disponible prochainement.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            _UploadOption(
              icon: Icons.upload_file_outlined,
              label: 'Choisir depuis les fichiers',
              color: const Color(0xFF5B8DEF),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Fonctionnalité disponible prochainement.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tuile de document public
// ─────────────────────────────────────────────────────────────────────────────

class _PublicDocumentTile extends StatelessWidget {
  const _PublicDocumentTile({required this.doc});

  final _PublicDoc doc;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5EBEB)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08172B3A),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: doc.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(doc.icon, color: doc.color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF172B3A),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  doc.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF71808A),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: doc.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        doc.category,
                        style: TextStyle(
                          color: doc.color,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      doc.date,
                      style: const TextStyle(
                        color: Color(0xFF9BAAB2),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.arrow_forward_ios_rounded,
            size: 14,
            color: Colors.grey.shade400,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bouton d'option de dépôt
// ─────────────────────────────────────────────────────────────────────────────

class _UploadOption extends StatelessWidget {
  const _UploadOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 14),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_rounded,
              color: color.withValues(alpha: 0.6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modèle de données (démo)
// ─────────────────────────────────────────────────────────────────────────────

class _PublicDoc {
  const _PublicDoc({
    required this.title,
    required this.category,
    required this.description,
    required this.icon,
    required this.color,
    required this.date,
  });

  final String title;
  final String category;
  final String description;
  final IconData icon;
  final Color color;
  final String date;
}
