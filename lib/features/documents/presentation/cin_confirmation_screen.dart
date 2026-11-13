import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../domain/local_cin_repository.dart';
import '../domain/national_id_ocr.dart';
import '../domain/vault_document.dart';

sealed class CinConfirmationOutcome {
  const CinConfirmationOutcome();
}

final class CinConfirmationSaved extends CinConfirmationOutcome {
  const CinConfirmationSaved(this.document);

  final VaultDocument document;
}

final class CinConfirmationRetake extends CinConfirmationOutcome {
  const CinConfirmationRetake();
}

class CinConfirmationScreen extends StatefulWidget {
  const CinConfirmationScreen({
    required this.onSaveCin,
    required this.imageBytes,
    this.backImageBytes,
    required this.imageMimeType,
    required this.ocrResult,
    super.key,
  });

  final SaveLocalDocument onSaveCin;
  final Uint8List imageBytes;
  final Uint8List? backImageBytes;
  final String imageMimeType;
  final NationalIdOcrResult ocrResult;

  @override
  State<CinConfirmationScreen> createState() => _CinConfirmationScreenState();
}

class _CinConfirmationScreenState extends State<CinConfirmationScreen> {
  static const _identityCategory = 'Pièce d’identité';

  final _cinNumberController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _placeOfBirthController = TextEditingController();
  final _professionController = TextEditingController();
  final _addressController = TextEditingController();
  final _issueDateController = TextEditingController();

  String _selectedGender = 'Non spécifié';
  late final String _documentId;
  DateTime? _expirationDate;
  bool _isSaving = false;
  String? _saveError;
  int _activePhotoIndex = 0; // 0 = Recto, 1 = Verso
  final _imagePicker = ImagePicker();
  Uint8List? _backImageBytes;
  String? _backImageMimeType;

  @override
  void initState() {
    super.initState();
    _backImageBytes = widget.backImageBytes;
    _backImageMimeType = widget.backImageBytes == null ? null : 'image/jpeg';
    final random = Random.secure();
    _documentId = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    final ocr = widget.ocrResult;
    _cinNumberController.text = ocr.documentNumber ?? '';
    _firstNameController.text = ocr.firstName ?? '';
    _lastNameController.text = ocr.lastName ?? '';
    _fatherNameController.text = ocr.fatherName ?? '';
    _motherNameController.text = ocr.motherName ?? '';
    _dateOfBirthController.text = ocr.dateOfBirth ?? '';
    _placeOfBirthController.text = ocr.placeOfBirth ?? '';
    _professionController.text = ocr.profession ?? '';
    _addressController.text = ocr.address ?? '';
    _issueDateController.text = ocr.issueDate ?? '';
    if (ocr.gender != null) {
      _selectedGender = ocr.gender!;
    }
    _expirationDate = _parseDate(ocr.expirationDate);
  }

  @override
  void dispose() {
    _cinNumberController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _fatherNameController.dispose();
    _motherNameController.dispose();
    _dateOfBirthController.dispose();
    _placeOfBirthController.dispose();
    _professionController.dispose();
    _addressController.dispose();
    _issueDateController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _saveError = null;
    });

    final firstName = _nonEmpty(_firstNameController.text);
    final lastName = _nonEmpty(_lastNameController.text);
    final cinNumber = _nonEmpty(_cinNumberController.text);
    final fullName = [firstName, lastName].whereType<String>().join(' ');
    final now = DateTime.now();

    final document = VaultDocument(
      id: _documentId,
      title: 'Carte nationale d’identité tunisienne',
      category: _identityCategory,
      holderName: fullName.isNotEmpty ? fullName : (cinNumber ?? 'Titulaire CIN'),
      createdAt: now,
      updatedAt: now,
      documentType: 'CIN_TUNISIE',
      fullName: fullName,
      firstName: firstName,
      lastName: lastName,
      cinNumber: cinNumber,
      dateOfBirth: _nonEmpty(_dateOfBirthController.text),
      placeOfBirth: _nonEmpty(_placeOfBirthController.text),
      expirationDate: _expirationDate,
      name: firstName,
      surname: lastName,
      documentNumber: cinNumber,
      expiryDate: _expirationDate,
      status: 'verified_by_user',
    );

    try {
      final savedDocument = await widget.onSaveCin(
        document,
        widget.imageBytes,
        widget.imageMimeType,
        _backImageBytes,
        _backImageMimeType,
      );
      if (mounted) {
        Navigator.of(context).pop(CinConfirmationSaved(savedDocument));
      }
    } on LocalCinException catch (error) {
      if (mounted) {
        setState(() => _saveError = _localSaveFailureMessage(error));
      }
    } on Exception catch (error) {
      if (mounted) {
        setState(() => _saveError = 'Erreur inattendue : $error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _retakePhoto() {
    if (!_isSaving) {
      Navigator.of(context).pop(const CinConfirmationRetake());
    }
  }

  Future<void> _captureBackPhoto() async {
    try {
      final selected = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        imageQuality: 88,
      );
      if (selected == null || !mounted) return;
      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty || bytes.length > 6 * 1024 * 1024) {
        setState(() => _saveError = 'La photo du Verso doit être valide et peser au maximum 6 Mo.');
        return;
      }
      final path = selected.path.toLowerCase();
      final mime = path.endsWith('.png') ? 'image/png' : 'image/jpeg';
      setState(() {
        _backImageBytes = bytes;
        _backImageMimeType = mime;
        _activePhotoIndex = 1;
        _saveError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _saveError = 'Impossible de prendre la photo du Verso : $error');
    }
  }

  Future<void> _chooseExpirationDate() async {
    final today = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _expirationDate ?? today,
      firstDate: DateTime(today.year - 30),
      lastDate: DateTime(today.year + 50),
      helpText: 'Date d’expiration',
      cancelText: 'Annuler',
      confirmText: 'Choisir',
    );
    if (selectedDate != null && mounted) {
      setState(() => _expirationDate = selectedDate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.ocrResult;
    final hasBack = _backImageBytes != null;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Données CIN de Tunisie',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: Color(0xFF172B3A),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF172B3A), size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Aperçu des photos (Recto / Verso) ──────────────────
              if (hasBack) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Face avant (Recto)'),
                      selected: _activePhotoIndex == 0,
                      onSelected: (val) {
                        if (val) setState(() => _activePhotoIndex = 0);
                      },
                    ),
                    const SizedBox(width: 10),
                    ChoiceChip(
                      label: const Text('Face arrière (Verso)'),
                      selected: _activePhotoIndex == 1,
                      onSelected: (val) {
                        if (val) setState(() => _activePhotoIndex = 1);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],

              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(
                  (_activePhotoIndex == 1 && hasBack)
                      ? _backImageBytes!
                      : widget.imageBytes,
                  height: 190,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    height: 190,
                    child: Center(child: Text('Impossible d’afficher cette photo.')),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              if (!hasBack) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _captureBackPhoto,
                  icon: const Icon(Icons.flip_rounded),
                  label: const Text('Ajouter la photo du Verso'),
                ),
                const Text(
                  'Ajoutez le verso pour pouvoir partager les deux faces de votre CIN.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF71808A), fontSize: 11),
                ),
              ] else ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _captureBackPhoto,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Remplacer la photo du Verso'),
                ),
              ],

              // ── Titre de section ────────────────────────────────────
              const Text(
                'Champs de votre CIN tunisienne',
                style: TextStyle(
                  color: Color(0xFF172B3A),
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Les champs ci-dessous ont été remplis automatiquement. '
                'Vérifiez et complétez les informations avant d\'enregistrer.',
                style: TextStyle(
                  color: Color(0xFF71808A),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),

              const SizedBox(height: 16),
              _OcrResultNotice(result: result),

              const SizedBox(height: 14),

              // ── Formulaire structuré CIN Tunisie ────────────────────
              _buildSectionTitle('Identification'),
              _EditableInformationField(
                label: 'Numéro de CIN (8 chiffres) / رقم ب.ت.و',
                controller: _cinNumberController,
                keyboardType: TextInputType.number,
                icon: Icons.numbers_rounded,
                hintText: 'ex: 09876543',
              ),
              Row(
                children: [
                  Expanded(
                    child: _EditableInformationField(
                      label: 'Prénom / الإسم',
                      controller: _firstNameController,
                      keyboardType: TextInputType.name,
                      icon: Icons.person_outline_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EditableInformationField(
                      label: 'Nom / اللقب',
                      controller: _lastNameController,
                      keyboardType: TextInputType.name,
                      icon: Icons.family_restroom_rounded,
                    ),
                  ),
                ],
              ),
              _EditableInformationField(
                label: 'Nom du père & grand-père / إسم الأب والجد',
                controller: _fatherNameController,
                keyboardType: TextInputType.name,
                icon: Icons.person_pin_circle_outlined,
              ),
              _EditableInformationField(
                label: 'Nom et prénom de la mère / إسم الأم ولقبها',
                controller: _motherNameController,
                keyboardType: TextInputType.name,
                icon: Icons.favorite_border_rounded,
              ),

              const SizedBox(height: 16),
              _buildSectionTitle('Naissance & Sexe'),
              Row(
                children: [
                  Expanded(
                    child: _EditableInformationField(
                      label: 'Date de naissance / تاريخ الولادة',
                      controller: _dateOfBirthController,
                      keyboardType: TextInputType.datetime,
                      icon: Icons.cake_outlined,
                      hintText: 'JJ/MM/AAAA',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EditableInformationField(
                      label: 'Lieu de naissance / مكان الولادة',
                      controller: _placeOfBirthController,
                      keyboardType: TextInputType.text,
                      icon: Icons.location_on_outlined,
                      hintText: 'ex: Tunis / تونس',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),
              // Sexe Dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE1E8E8)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.wc_rounded, size: 20, color: Color(0xFF71808A)),
                    const SizedBox(width: 12),
                    const Text(
                      'Sexe / الجنس :',
                      style: TextStyle(fontSize: 13, color: Color(0xFF71808A)),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _selectedGender,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'Non spécifié', child: Text('Non spécifié')),
                        DropdownMenuItem(value: 'Masculin', child: Text('Masculin (ذكر)')),
                        DropdownMenuItem(value: 'Féminin', child: Text('Féminin (أنثى)')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedGender = val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              _buildSectionTitle('Informations du Verso'),
              _EditableInformationField(
                label: 'Profession / المهنة',
                controller: _professionController,
                keyboardType: TextInputType.text,
                icon: Icons.work_outline_rounded,
              ),
              _EditableInformationField(
                label: 'Adresse / العنوان',
                controller: _addressController,
                keyboardType: TextInputType.streetAddress,
                icon: Icons.home_outlined,
              ),
              _EditableInformationField(
                label: 'Date de délivrance / سلمت في',
                controller: _issueDateController,
                keyboardType: TextInputType.datetime,
                icon: Icons.event_available_rounded,
                hintText: 'JJ/MM/AAAA',
              ),

              const SizedBox(height: 16),
              _buildSectionTitle('Date d’expiration (facultatif)'),
              OutlinedButton.icon(
                onPressed: _isSaving ? null : _chooseExpirationDate,
                icon: const Icon(Icons.event_outlined, size: 19),
                label: Text(
                  _expirationDate == null
                      ? 'Choisir une date d’expiration'
                      : _formatDate(_expirationDate!),
                ),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  foregroundColor: const Color(0xFF172B3A),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                  side: const BorderSide(color: Color(0xFFE1E8E8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),

              const SizedBox(height: 24),

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

              // ── Bouton Enregistrer ─────────────────────────────────
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _confirm,
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
                      : const Icon(Icons.check_circle_outline_rounded, size: 21),
                  label: Text(
                    _isSaving ? 'Enregistrement…' : 'Confirmer et Enregistrer la CIN',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              OutlinedButton(
                onPressed: _isSaving ? null : _retakePhoto,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: const Color(0xFF172B3A),
                  side: const BorderSide(color: Color(0xFFE1E8E8)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Reprendre les photos'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF087E78),
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  static String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null) return null;
    final date = DateTime.tryParse(value);
    if (date == null || date.toIso8601String().substring(0, 10) != value) {
      return null;
    }
    return date;
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/'
      '${date.year}';

  static String _localSaveFailureMessage(LocalCinException error) {
    final stage = switch (error.stage) {
      LocalCinSaveStage.imageCopy => 'la copie de la photo sur cet appareil',
      LocalCinSaveStage.databaseWrite =>
        'l’enregistrement des informations dans SQLite',
      LocalCinSaveStage.imageDelete => 'la suppression locale de la photo',
    };
    final message = 'Échec pendant $stage.\n${_exceptionDetails(error.cause)}';
    final rollbackError = error.rollbackError;
    if (rollbackError == null) return message;
    return '$message\nLe nettoyage de la photo a aussi échoué : '
        '${_exceptionDetails(rollbackError)}';
  }

  static String _exceptionDetails(Object error) {
    return '${error.runtimeType}: $error';
  }
}

class _OcrResultNotice extends StatelessWidget {
  const _OcrResultNotice({required this.result});

  final NationalIdOcrResult result;

  @override
  Widget build(BuildContext context) {
    final hasFields = [
      result.firstName,
      result.lastName,
      result.documentNumber,
      result.dateOfBirth,
      result.placeOfBirth,
    ].any((value) => value != null && value.trim().isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasFields ? const Color(0xFFEAF3F2) : const Color(0xFFFFF6EB),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: hasFields ? const Color(0xFFB5DFD9) : const Color(0xFFFFDAB3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasFields ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            color: hasFields ? const Color(0xFF087E78) : const Color(0xFFD97706),
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasFields
                  ? 'Reconnaissance OCR réussie : certains champs ont été détectés automatiquement.'
                  : 'Reconnaissance partielle : vous pouvez renseigner directement les champs manquants.',
              style: TextStyle(
                color: hasFields ? const Color(0xFF087E78) : const Color(0xFFB45309),
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableInformationField extends StatelessWidget {
  const _EditableInformationField({
    required this.label,
    required this.controller,
    required this.keyboardType,
    this.icon,
    this.hintText,
  });

  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final IconData? icon;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: icon != null ? Icon(icon, size: 20) : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 13,
          ),
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
            borderSide: const BorderSide(color: Color(0xFF087E78), width: 1.4),
          ),
        ),
      ),
    );
  }
}
