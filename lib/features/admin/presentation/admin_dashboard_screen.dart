import 'dart:io';

import 'package:flutter/material.dart';

import '../../documents/domain/vault_document.dart';
import 'admin_classify_document_screen.dart';

/// Tableau de bord administrateur : consultation et traitement des documents en attente.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    required this.documents,
    required this.onUpdateDocument,
    required this.onDeleteDocument,
    super.key,
  });

  final List<VaultDocument> documents;
  final Future<VaultDocument> Function(VaultDocument updatedDocument) onUpdateDocument;
  final Future<void> Function(VaultDocument document) onDeleteDocument;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTabIndex = 0; // 0 = En attente, 1 = Déjà classés

  static const _teal = Color(0xFF087E78);
  static const _ink = Color(0xFF172B3A);
  static const _canvas = Color(0xFFF4F7F7);
  static const _line = Color(0xFFE2E8EB);

  List<VaultDocument> get _pendingDocuments => widget.documents.where((doc) {
        return doc.status == 'pending_admin' || doc.category == 'En attente d’analyse';
      }).toList();

  List<VaultDocument> get _classifiedDocuments => widget.documents.where((doc) {
        return doc.status != 'pending_admin' && doc.category != 'En attente d’analyse';
      }).toList();

  Future<void> _openClassifyScreen(VaultDocument doc) async {
    final result = await Navigator.of(context).push<VaultDocument>(
      MaterialPageRoute<VaultDocument>(
        builder: (_) => AdminClassifyDocumentScreen(
          document: doc,
          onUpdateDocument: widget.onUpdateDocument,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _pendingDocuments;
    final classified = _classifiedDocuments;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.admin_panel_settings_rounded, color: _teal, size: 22),
            SizedBox(width: 8),
            Text(
              'Espace Administrateur',
              style: TextStyle(
                color: _ink,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── En-tête statistiques ─────────────────────────────────
            Container(
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1A3A6B), Color(0xFF0D2247)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x221A3A6B),
                    blurRadius: 12,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _StatBadge(
                      label: 'À analyser',
                      count: pending.length.toString(),
                      icon: Icons.hourglass_top_rounded,
                      color: const Color(0xFFFFB347),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white.withValues(alpha: 0.15),
                  ),
                  Expanded(
                    child: _StatBadge(
                      label: 'Déjà classés',
                      count: classified.length.toString(),
                      icon: Icons.task_alt_rounded,
                      color: const Color(0xFF4CD9C8),
                    ),
                  ),
                ],
              ),
            ),

            // ── Onglets de bascule ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Expanded(
                    child: _FilterTab(
                      label: 'En attente (${pending.length})',
                      isSelected: _selectedTabIndex == 0,
                      badgeColor: const Color(0xFFD97706),
                      onTap: () => setState(() => _selectedTabIndex = 0),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _FilterTab(
                      label: 'Classés (${classified.length})',
                      isSelected: _selectedTabIndex == 1,
                      badgeColor: _teal,
                      onTap: () => setState(() => _selectedTabIndex = 1),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // ── Liste des documents ──────────────────────────────────
            Expanded(
              child: _selectedTabIndex == 0
                  ? _buildPendingList(pending)
                  : _buildClassifiedList(classified),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingList(List<VaultDocument> docs) {
    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFE4F2F0),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle_outline_rounded, color: _teal, size: 32),
            ),
            const SizedBox(height: 14),
            const Text(
              'Aucun papier en attente !',
              style: TextStyle(
                color: _ink,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tous les papiers soumis ont été analysés et classés.',
              style: TextStyle(color: Color(0xFF71808A), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      itemCount: docs.length,
    separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final imagePath = doc.localImagePath;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFFFD59E)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 10,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Aperçu miniature
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64,
                  height: 64,
                  color: const Color(0xFFF2F4F5),
                  child: imagePath != null && File(imagePath).existsSync()
                      ? Image.file(File(imagePath), fit: BoxFit.cover)
                      : const Icon(Icons.description_outlined, color: _teal),
                ),
              ),
              const SizedBox(width: 14),

              // Détails
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3E0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '⏳ EN ATTENTE D\'ANALYSE',
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (doc.holderName.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        doc.holderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF71808A),
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Soumis le ${_formatDate(doc.createdAt)}',
                      style: const TextStyle(
                        color: Color(0xFF9BAAB2),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Bouton Analyser & Classer
              FilledButton(
                onPressed: () => _openClassifyScreen(doc),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Classer',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClassifiedList(List<VaultDocument> docs) {
    if (docs.isEmpty) {
      return const Center(
        child: Text(
          'Aucun document classé pour l\'instant.',
          style: TextStyle(color: Color(0xFF71808A), fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
      itemCount: docs.length,
   separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final doc = docs[index];
        final imagePath = doc.localImagePath;
        final isRejected = doc.status == 'rejected_by_admin';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 52,
                  height: 52,
                  color: const Color(0xFFF2F4F5),
                  child: imagePath != null && File(imagePath).existsSync()
                      ? Image.file(File(imagePath), fit: BoxFit.cover)
                      : const Icon(Icons.folder_outlined, color: _teal),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: isRejected
                                ? const Color(0xFFFFECEC)
                                : const Color(0xFFE4F2F0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isRejected ? 'REJETÉ' : doc.category,
                            style: TextStyle(
                              color: isRejected ? const Color(0xFFC83D4D) : _teal,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (!isRejected)
                          const Text(
                            '✓ Validé Admin',
                            style: TextStyle(color: Color(0xFF087E78), fontSize: 10.5),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      doc.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      doc.holderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFF71808A), fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_note_rounded, color: _teal),
                tooltip: 'Modifier le classement',
                onPressed: () => _openClassifyScreen(doc),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} à ${date.hour}h${date.minute.toString().padLeft(2, '0')}';
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  final String label;
  final String count;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(
              count,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.isSelected,
    required this.badgeColor,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final Color badgeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : const Color(0xFFE9EEEE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? badgeColor : const Color(0xFFE2E8EB),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? const Color(0xFF172B3A) : const Color(0xFF71808A),
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
