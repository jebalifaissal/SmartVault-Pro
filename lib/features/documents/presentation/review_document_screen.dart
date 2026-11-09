import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/document_repository.dart';
import '../domain/vault_document.dart';

class ReviewDocumentScreen extends StatefulWidget {
  const ReviewDocumentScreen({
    required this.onSave,
    super.key,
    this.initialCategory,
    this.initialTitle,
    this.initialHolderName,
    this.initialDocumentNumber,
    this.initialExpiryDate,
    this.initialName,
    this.initialSurname,
    this.initialDateOfBirth,
    this.initialPlaceOfBirth,
    this.nationalIdFieldsEnabled = false,
    this.imageBytes,
    this.imageMimeType,
    this.classificationConfidence,
  });

  final SaveVaultDocument onSave;
  final String? initialCategory;
  final String? initialTitle;
  final String? initialHolderName;
  final String? initialDocumentNumber;
  final DateTime? initialExpiryDate;
  final String? initialName;
  final String? initialSurname;
  final String? initialDateOfBirth;
  final String? initialPlaceOfBirth;
  final bool nationalIdFieldsEnabled;
  final Uint8List? imageBytes;
  final String? imageMimeType;
  final double? classificationConfidence;

  @override
  State<ReviewDocumentScreen> createState() => _ReviewDocumentScreenState();
}

class _ReviewDocumentScreenState extends State<ReviewDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _holderController = TextEditingController();
  final _numberController = TextEditingController();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _placeOfBirthController = TextEditingController();
  String _category = VaultDocument.categories.first;
  DateTime? _expiryDate;
  bool _isSaving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    final suggestedCategory = widget.initialCategory;
    if (suggestedCategory != null &&
        VaultDocument.categories.contains(suggestedCategory)) {
      _category = suggestedCategory;
    }
    _titleController.text = widget.initialTitle ?? '';
    _holderController.text = widget.initialHolderName ?? '';
    _numberController.text = widget.initialDocumentNumber ?? '';
    _nameController.text = widget.initialName ?? '';
    _surnameController.text = widget.initialSurname ?? '';
    _dateOfBirthController.text = widget.initialDateOfBirth ?? '';
    _placeOfBirthController.text = widget.initialPlaceOfBirth ?? '';
    _expiryDate = widget.initialExpiryDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _holderController.dispose();
    _numberController.dispose();
    _nameController.dispose();
    _surnameController.dispose();
    _dateOfBirthController.dispose();
    _placeOfBirthController.dispose();
    super.dispose();
  }

  Future<void> _chooseExpiryDate() async {
    final today = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? today,
      firstDate: DateTime(today.year - 30),
      lastDate: DateTime(today.year + 50),
      helpText: 'Date d’expiration',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (value != null) setState(() => _expiryDate = value);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Complétez les champs obligatoires signalés en rouge avant '
              'l’enregistrement.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      final document = VaultDocument(
        id: id,
        title: _titleController.text.trim(),
        category: _category,
        holderName: _showNationalIdFields
            ? '${_nameController.text.trim()} ${_surnameController.text.trim()}'
                  .trim()
            : _holderController.text.trim(),
        documentNumber: _numberController.text.trim().isEmpty
            ? null
            : _numberController.text.trim(),
        expiryDate: _expiryDate,
        documentType: _documentTypeForCategory(_category),
        fullName: _showNationalIdFields
            ? '${_nameController.text.trim()} ${_surnameController.text.trim()}'
                  .trim()
            : _holderController.text.trim(),
        firstName: _showNationalIdFields ? _nameController.text.trim() : null,
        lastName: _showNationalIdFields ? _surnameController.text.trim() : null,
        cinNumber: _category == 'Pièce d’identité'
            ? _numberController.text.trim().isEmpty
                  ? null
                  : _numberController.text.trim()
            : null,
        name: _showNationalIdFields ? _nameController.text.trim() : null,
        surname: _showNationalIdFields ? _surnameController.text.trim() : null,
        dateOfBirth:
            _showNationalIdFields &&
                _dateOfBirthController.text.trim().isNotEmpty
            ? _dateOfBirthController.text.trim()
            : null,
        placeOfBirth:
            _showNationalIdFields &&
                _placeOfBirthController.text.trim().isNotEmpty
            ? _placeOfBirthController.text.trim()
            : null,
        createdAt: DateTime.now(),
      );
      final savedDocument = await widget.onSave(
        document,
        widget.imageBytes,
        widget.imageMimeType,
      );
      if (!mounted) return;
      Navigator.of(context).pop(savedDocument);
    } on ArgumentError catch (error) {
      if (mounted) setState(() => _saveError = error.message.toString());
    } on Exception catch (error) {
      if (mounted) {
        setState(
          () => _saveError =
              'Impossible d’enregistrer le document. Vérifiez votre connexion '
              'puis réessayez. ($error)',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7F7),
        title: const Text(
          'Vérifier les informations',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _ReviewPreview(
                      imageBytes: widget.imageBytes,
                      classificationConfidence: widget.classificationConfidence,
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Informations du document',
                      style: TextStyle(
                        color: Color(0xFF172B3A),
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Vérifiez et complétez les champs avant de continuer.',
                      style: TextStyle(color: Color(0xFF71808A), fontSize: 12),
                    ),
                    const SizedBox(height: 19),
                    _ReviewField(
                      label: 'Nom du document',
                      hint: 'Ex. Carte nationale d’identité',
                      controller: _titleController,
                      icon: Icons.description_outlined,
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? 'Saisissez le nom du document.'
                          : null,
                    ),
                    const SizedBox(height: 15),
                    const _ReviewLabel('Catégorie'),
                    const SizedBox(height: 7),
                    DropdownButtonFormField<String>(
                      initialValue: _category,
                      decoration: _fieldDecoration(icon: Icons.folder_outlined),
                      items: [
                        for (final category in VaultDocument.categories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _category = value);
                      },
                    ),
                    const SizedBox(height: 15),
                    if (_showNationalIdFields) ...[
                      _ReviewField(
                        label: 'Prénom(s)',
                        hint: 'Prénom(s) figurant sur la CIN',
                        controller: _nameController,
                        icon: Icons.person_outline_rounded,
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Saisissez le prénom figurant sur la CIN.'
                            : null,
                      ),
                      const SizedBox(height: 15),
                      _ReviewField(
                        label: 'Nom',
                        hint: 'Nom de famille figurant sur la CIN',
                        controller: _surnameController,
                        icon: Icons.person_outline_rounded,
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Saisissez le nom figurant sur la CIN.'
                            : null,
                      ),
                      const SizedBox(height: 15),
                      _ReviewField(
                        label: 'Date de naissance',
                        hint: 'AAAA-MM-JJ',
                        controller: _dateOfBirthController,
                        icon: Icons.event_outlined,
                        validator: _validateBirthDate,
                      ),
                      const SizedBox(height: 15),
                      _ReviewField(
                        label: 'Lieu de naissance',
                        hint: 'Lieu figurant sur la CIN',
                        controller: _placeOfBirthController,
                        icon: Icons.location_on_outlined,
                      ),
                    ] else
                      _ReviewField(
                        label: 'Nom figurant sur le document',
                        hint: 'Nom complet',
                        controller: _holderController,
                        icon: Icons.person_outline_rounded,
                        validator: (value) => (value?.trim().isEmpty ?? true)
                            ? 'Saisissez le nom du titulaire.'
                            : null,
                      ),
                    const SizedBox(height: 15),
                    _ReviewField(
                      label: 'Numéro du document',
                      hint: 'Facultatif',
                      controller: _numberController,
                      icon: Icons.numbers_rounded,
                      validator: (value) {
                        final number = value?.trim() ?? '';
                        if (_category == 'Pièce d’identité' &&
                            number.isNotEmpty &&
                            !RegExp(r'^\d{8}$').hasMatch(number)) {
                          return 'Saisissez les 8 chiffres de la CIN.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 15),
                    const _ReviewLabel('Date d’expiration'),
                    const SizedBox(height: 7),
                    OutlinedButton.icon(
                      onPressed: _chooseExpiryDate,
                      icon: const Icon(Icons.event_outlined, size: 19),
                      label: Text(
                        _expiryDate == null
                            ? 'Ajouter une date (facultatif)'
                            : _formatDate(_expiryDate!),
                      ),
                      style: OutlinedButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        foregroundColor: _expiryDate == null
                            ? const Color(0xFF71808A)
                            : const Color(0xFF172B3A),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 16,
                        ),
                        side: const BorderSide(color: Color(0xFFE1E8E8)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 23),
                    if (_saveError != null) ...[
                      Text(
                        _saveError!,
                        style: const TextStyle(
                          color: Color(0xFFC83D4D),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      height: 53,
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF087E78),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check_rounded, size: 20),
                        label: Text(
                          _isSaving
                              ? 'Enregistrement...'
                              : 'Enregistrer dans le portefeuille',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Les champs reconnus par OCR sont préremplis quand ils '
                      'sont lisibles. Vérifiez chaque information avant de '
                      'l’enregistrer.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF71808A),
                        fontSize: 10,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';

  String? _validateBirthDate(String? value) {
    final date = value?.trim() ?? '';
    if (date.isEmpty) return null;
    final parsed = DateTime.tryParse(date);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != date) {
      return 'Utilisez le format AAAA-MM-JJ.';
    }
    return null;
  }

  bool get _showNationalIdFields =>
      widget.nationalIdFieldsEnabled &&
      (_category == 'Pièce d’identité' || _category == 'Passeport');

  String _documentTypeForCategory(String category) => switch (category) {
    'Pièce d’identité' => 'CIN',
    'Passeport' => 'PASSPORT',
    'Diplôme' => 'CERTIFICATE',
    'Permis de conduire' => 'DRIVING_LICENSE',
    _ => 'OTHER',
  };
}

class _ReviewPreview extends StatelessWidget {
  const _ReviewPreview({this.imageBytes, this.classificationConfidence});

  final Uint8List? imageBytes;
  final double? classificationConfidence;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3F2),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.memory(
                    imageBytes!,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                  ),
                )
              else
                const Icon(
                  Icons.fact_check_outlined,
                  color: Color(0xFF087E78),
                  size: 22,
                ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      classificationConfidence == null
                          ? 'Vérification des données'
                          : 'Informations proposées par l’IA',
                      style: const TextStyle(
                        color: Color(0xFF172B3A),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      classificationConfidence == null
                          ? 'Contrôlez chaque information avant de l’enregistrer.'
                          : classificationConfidence! < 0.65
                          ? 'Aucun texte concluant reconnu. Choisissez la '
                                'catégorie correcte manuellement.'
                          : 'Vérifiez la catégorie suggérée et corrigez-la '
                                'si nécessaire.',
                      style: const TextStyle(
                        color: Color(0xFF526870),
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (classificationConfidence != null) ...[
            const SizedBox(height: 8),
            const Text(
              'Aucun texte n’a pu être reconnu. Vous pouvez choisir la '
              'catégorie et saisir les informations manuellement.',
              style: TextStyle(color: Color(0xFF526870), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewField extends StatelessWidget {
  const _ReviewField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    this.validator,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReviewLabel(label),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          validator: validator,
          textCapitalization: TextCapitalization.sentences,
          decoration: _fieldDecoration(icon: icon, hint: hint),
        ),
      ],
    );
  }
}

class _ReviewLabel extends StatelessWidget {
  const _ReviewLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF263B49),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

InputDecoration _fieldDecoration({required IconData icon, String? hint}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon, size: 19),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE1E8E8)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE1E8E8)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF087E78), width: 1.5),
    ),
  );
}
