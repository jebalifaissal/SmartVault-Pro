import 'dart:io';

import 'package:flutter/material.dart';

import '../../documents/domain/vault_document.dart';

/// Interface où l'administrateur inspecte le papier et le classe dans le container correspondant.
class AdminClassifyDocumentScreen extends StatefulWidget {
  const AdminClassifyDocumentScreen({
    required this.document,
    required this.onUpdateDocument,
    super.key,
  });

  final VaultDocument document;
  final Future<VaultDocument> Function(VaultDocument updatedDocument) onUpdateDocument;

  @override
  State<AdminClassifyDocumentScreen> createState() => _AdminClassifyDocumentScreenState();
}

class _AdminClassifyDocumentScreenState extends State<AdminClassifyDocumentScreen> {
  // 'sensitive', 'moderate', 'other'
  String _sensitivity = 'sensitive';
  String _selectedContainer = 'Pièce d’identité';

  late final TextEditingController _titleController;
  late final TextEditingController _holderController;
  late final TextEditingController _numberController;
  late final TextEditingController _adminNoteController;

  DateTime? _expirationDate;
  bool _isSaving = false;

  static const _teal = Color(0xFF087E78);
  static const _ink = Color(0xFF172B3A);
  static const _canvas = Color(0xFFF4F7F7);
  static const _line = Color(0xFFE2E8EB);

  @override
  void initState() {
    super.initState();
    final doc = widget.document;

    // Détermine la sensibilité par défaut
    if (doc.category == 'Cours' || doc.category == 'Notes' || doc.category == 'Informations') {
      _sensitivity = 'moderate';
      _selectedContainer = doc.category;
    } else if (doc.category == 'Diplôme' || doc.category == 'Autres') {
      _sensitivity = 'other';
      _selectedContainer = doc.category;
    } else {
      _sensitivity = 'sensitive';
      _selectedContainer = doc.category == 'En attente d’analyse' ? 'Pièce d’identité' : doc.category;
    }

    _titleController = TextEditingController(text: doc.title);
    _holderController = TextEditingController(
      text: doc.holderName == 'À déterminer par l\'administrateur' ? '' : doc.holderName,
    );
    _numberController = TextEditingController(text: doc.documentNumber ?? doc.cinNumber ?? '');
    _adminNoteController = TextEditingController();
    _expirationDate = doc.expirationDate ?? doc.expiryDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _holderController.dispose();
    _numberController.dispose();
    _adminNoteController.dispose();
    super.dispose();
  }

  void _onSensitivityChanged(String newSensitivity) {
    setState(() {
      _sensitivity = newSensitivity;
      if (_sensitivity == 'sensitive') {
        _selectedContainer = 'Pièce d’identité';
      } else if (_sensitivity == 'moderate') {
        _selectedContainer = 'Cours';
      } else {
        _selectedContainer = 'Diplôme';
      }
    });
  }

  List<String> get _availableContainers {
    if (_sensitivity == 'sensitive') {
      return ['Pièce d’identité', 'Passeport', 'Permis de conduire'];
    } else if (_sensitivity == 'moderate') {
      return ['Cours', 'Notes', 'Informations'];
    } else {
      return ['Diplôme', 'Autres'];
    }
  }

  Future<void> _chooseExpirationDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expirationDate ?? today,
      firstDate: DateTime(today.year - 20),
      lastDate: DateTime(today.year + 40),
      helpText: 'Date d’expiration du document',
    );
    if (picked != null) {
      setState(() => _expirationDate = picked);
    }
  }

  Future<void> _confirmClassification() async {
    setState(() => _isSaving = true);
    try {
      final now = DateTime.now();
      final updated = widget.document.copyWith(
        title: _titleController.text.trim().isNotEmpty
            ? _titleController.text.trim()
            : 'Document classé - $_selectedContainer',
        category: _selectedContainer,
        holderName: _holderController.text.trim().isNotEmpty
            ? _holderController.text.trim()
            : 'Titulaire vérifié',
        documentNumber: _numberController.text.trim().isNotEmpty
            ? _numberController.text.trim()
            : null,
        cinNumber: _selectedContainer == 'Pièce d’identité'
            ? _numberController.text.trim()
            : widget.document.cinNumber,
        expirationDate: _expirationDate,
        expiryDate: _expirationDate,
        status: 'verified_by_admin',
        updatedAt: now,
      );

      await widget.onUpdateDocument(updated);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✓ Papier validé et placé dans le container « $_selectedContainer » !',
          ),
          backgroundColor: const Color(0xFF087E78),
          behavior: SnackBarBehavior.floating,
        ),
      );

      Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors du classement : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _rejectDocument() async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rejeter ce document ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Indiquez la raison du rejet (ex: photo floue, document non reconnu...) :',
              style: TextStyle(fontSize: 13, color: Color(0xFF526870)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: 'Motif du rejet...',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC83D4D)),
            child: const Text('Confirmer le rejet'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _isSaving = true);
      try {
        final reason = reasonController.text.trim().isNotEmpty
            ? reasonController.text.trim()
            : 'Non conforme ou illisible';

        final updated = widget.document.copyWith(
          status: 'rejected_by_admin',
          holderName: 'Rejeté : $reason',
          updatedAt: DateTime.now(),
        );

        await widget.onUpdateDocument(updated);

        if (!mounted) return;
        Navigator.of(context).pop(updated);
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.document.localImagePath;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Analyse & Classement Admin',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _ink, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Aperçu du papier ───────────────────────────────────
              const Text(
                'Papier soumis par l\'utilisateur',
                style: TextStyle(
                  color: _ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),

              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  height: 220,
                  width: double.infinity,
                  color: Colors.black87,
                  child: imagePath != null && File(imagePath).existsSync()
                      ? InteractiveViewer(
                          maxScale: 4.0,
                          child: Image.file(
                            File(imagePath),
                            fit: BoxFit.contain,
                          ),
                        )
                      : const Center(
                          child: Text(
                            'Image non disponible ou sur le cloud',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 6),
              const Center(
                child: Text(
                  '💡 Pincez pour zoomer et lire les informations sur le papier',
                  style: TextStyle(fontSize: 11, color: Color(0xFF71808A)),
                ),
              ),

              const SizedBox(height: 24),

              // ── Étape 1 : Degré de Sensibilité ─────────────────────
              const Text(
                '1. Analyser le niveau de sensibilité',
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'L\'administrateur décide si le papier est sensible (authentification requise) ou moyennement sensible (cours, notes...).',
                style: TextStyle(color: Color(0xFF71808A), fontSize: 12),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _SensitivityCard(
                      title: 'Très Sensible',
                      subtitle: 'CIN, Passeport, Permis',
                      icon: Icons.shield_rounded,
                      color: const Color(0xFF3976B8),
                      bgColor: const Color(0xFFEAF2FF),
                      isSelected: _sensitivity == 'sensitive',
                      onTap: () => _onSensitivityChanged('sensitive'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SensitivityCard(
                      title: 'Moyennement',
                      subtitle: 'Cours, Notes, Infos',
                      icon: Icons.menu_book_rounded,
                      color: const Color(0xFF18B6A5),
                      bgColor: const Color(0xFFE8F6F4),
                      isSelected: _sensitivity == 'moderate',
                      onTap: () => _onSensitivityChanged('moderate'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SensitivityCard(
                      title: 'Standard',
                      subtitle: 'Diplômes, Autres',
                      icon: Icons.folder_rounded,
                      color: const Color(0xFF7A60B7),
                      bgColor: const Color(0xFFF3EEFF),
                      isSelected: _sensitivity == 'other',
                      onTap: () => _onSensitivityChanged('other'),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Étape 2 : Container de destination ─────────────────
              const Text(
                '2. Choisir le container correspondant',
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Le papier sera automatiquement classé dans ce container du coffre-fort.',
                style: TextStyle(color: Color(0xFF71808A), fontSize: 12),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _availableContainers.map((container) {
                  final isChosen = _selectedContainer == container;
                  return ChoiceChip(
                    label: Text(
                      container,
                      style: TextStyle(
                        fontWeight: isChosen ? FontWeight.w700 : FontWeight.w500,
                        color: isChosen ? Colors.white : _ink,
                      ),
                    ),
                    selected: isChosen,
                    selectedColor: _teal,
                    backgroundColor: Colors.white,
                    side: BorderSide(color: isChosen ? _teal : _line),
                    onSelected: (val) {
                      if (val) setState(() => _selectedContainer = container);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 24),

              // ── Étape 3 : Renseignement des données ────────────────
              const Text(
                '3. Informations validées par l\'Admin',
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _line),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Titre officiel du document',
                        hintText: 'Ex: Carte Nationale d\'Identité - Mohamed',
                        prefixIcon: Icon(Icons.title_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _holderController,
                      decoration: const InputDecoration(
                        labelText: 'Nom du titulaire / Auteur',
                        hintText: 'Ex: Mohamed Ben Salah',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _numberController,
                      decoration: const InputDecoration(
                        labelText: 'Numéro du document (si applicable)',
                        hintText: 'Ex: Numéro CIN (8 chiffres), etc.',
                        prefixIcon: Icon(Icons.numbers_rounded),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _chooseExpirationDate,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _expirationDate == null
                            ? 'Définir une date d\'expiration (facultatif)'
                            : 'Expiration : ${_expirationDate!.day}/${_expirationDate!.month}/${_expirationDate!.year}',
                      ),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Actions de validation ──────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _confirmClassification,
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_rounded, size: 22),
                  label: Text(
                    _isSaving
                        ? 'Classement en cours…'
                        : 'Valider et Classer dans « $_selectedContainer »',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _isSaving ? null : _rejectDocument,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: const Color(0xFFC83D4D),
                  side: const BorderSide(color: Color(0xFFC83D4D)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.close_rounded),
                label: const Text('Rejeter ce papier (non conforme / flou)'),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _SensitivityCard extends StatelessWidget {
  const _SensitivityCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.bgColor,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? bgColor : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFE2E8EB),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 6),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF172B3A),
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? color : const Color(0xFF71808A),
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
