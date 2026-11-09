import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../models/document_type.dart';
import '../domain/document_image_classifier.dart';
import '../domain/document_text_classifier.dart';
import '../domain/local_cin_repository.dart';
import '../domain/national_id_ocr.dart';
import '../domain/document_repository.dart';
import '../domain/vault_document.dart';
import '../../auth/presentation/session_lock_activity.dart';
import 'cin_capture_screen.dart';
import 'cin_confirmation_screen.dart';
import 'review_document_screen.dart';

class AddDocumentScreen extends StatefulWidget {
  const AddDocumentScreen({
    required this.onSave,
    required this.onSaveCin,
    required this.onSubmitCinForReview,
    required this.classifier,
    required this.nationalIdOcr,
    super.key,
  });

  final SaveVaultDocument onSave;
  final SaveLocalDocument onSaveCin;
  final SubmitClassificationRequest onSubmitCinForReview;
  final DocumentImageClassifier classifier;
  final NationalIdOcr nationalIdOcr;

  @override
  State<AddDocumentScreen> createState() => _AddDocumentScreenState();
}

class _AddDocumentScreenState extends State<AddDocumentScreen> {
  static const _maxImageBytes = 6 * 1024 * 1024;
  final _picker = ImagePicker();
  bool _isClassifying = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_recoverLostCameraCapture());
      });
    }
  }

  Future<void> _recoverLostCameraCapture() async {
    if (!mounted || _isClassifying) return;
    setState(() => _isClassifying = true);
    try {
      final response = await _picker.retrieveLostData();
      final exception = response.exception;
      if (exception != null) {
        _showMessage(
          'Android n’a pas pu récupérer la photo prise. '
          '(${exception.code}) ${exception.message ?? ''}',
        );
        return;
      }

      final files = response.files;
      if (files == null || files.isEmpty) return;
      await _processCinPhoto(files.first);
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          'Impossible de récupérer la photo Android '
          '(${error.code}) : ${error.message ?? 'erreur sans détail'}.',
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        _showMessage('Impossible de récupérer la photo Android : $error');
      }
    } finally {
      if (mounted) setState(() => _isClassifying = false);
    }
  }

  Future<void> _captureCin() async {
    final document = await Navigator.of(context).push<VaultDocument>(
      MaterialPageRoute<VaultDocument>(
        builder: (_) => CinCaptureScreen(
          onSubmit: widget.onSubmitCinForReview,
          nationalIdOcr: widget.nationalIdOcr,
        ),
      ),
    );
    if (!mounted || document == null) return;
    Navigator.of(context).pop(document);
  }

  Future<bool> _processCinPhoto(XFile selected) async {
    final path = selected.path.trim();
    if (path.isEmpty) {
      _showMessage('La caméra a renvoyé un chemin de photo vide.');
      return false;
    }

    final photo = File(path);
    if (!await photo.exists()) {
      _showMessage('La photo renvoyée par la caméra est introuvable.');
      return false;
    }

    late final Uint8List bytes;
    try {
      bytes = await photo.readAsBytes();
    } on FileSystemException {
      _showMessage('Impossible de lire la photo renvoyée par la caméra.');
      return false;
    }
    if (bytes.isEmpty) {
      _showMessage('La photo renvoyée par la caméra est vide.');
      return false;
    }

    final mimeType = _imageMimeType(selected) ?? _imageMimeTypeFromBytes(bytes);
    if (mimeType == null) {
      _showMessage(
        'Le fichier de la caméra n’est pas une image JPEG ou PNG reconnue.',
      );
      return false;
    }

    late final NationalIdOcrResult nationalId;
    try {
      nationalId = await widget.nationalIdOcr.extract(path);
    } on PlatformException catch (error) {
      _showMessage(
        'Tesseract n’a pas pu analyser la photo '
        '(${error.code}) : ${error.message ?? 'erreur sans détail'}.',
      );
      return false;
    } on Exception catch (error) {
      _showMessage('L’analyse OCR de la CIN a échoué : $error');
      return false;
    } finally {
      await _removeTemporaryPhoto(path);
    }

    if (!mounted) return false;
    final outcome = await Navigator.of(context).push<CinConfirmationOutcome>(
      MaterialPageRoute<CinConfirmationOutcome>(
        builder: (_) => CinConfirmationScreen(
          onSaveCin: widget.onSaveCin,
          imageBytes: bytes,
          imageMimeType: mimeType,
          ocrResult: nationalId,
        ),
      ),
    );
    if (!mounted || outcome == null) return false;
    if (outcome is CinConfirmationSaved) {
      Navigator.of(context).pop(outcome.document);
      return false;
    }
    return outcome is CinConfirmationRetake;
  }

  Future<void> _removeTemporaryPhoto(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      if (mounted) {
        _showMessage(
          'La copie temporaire n’a pas pu être supprimée automatiquement.',
        );
      }
    }
  }

  Future<void> _openManualEntry(BuildContext context) async {
    final document = await Navigator.of(context).push<VaultDocument>(
      MaterialPageRoute<VaultDocument>(
        builder: (_) => ReviewDocumentScreen(onSave: widget.onSave),
      ),
    );
    if (context.mounted && document != null) {
      Navigator.of(context).pop(document);
    }
  }

  Future<void> _selectAndClassify(ImageSource source) async {
    if (_isClassifying) return;
    setState(() => _isClassifying = true);
    try {
      final selected = await SessionLockActivityScope.run(
        context,
        () =>
            _picker.pickImage(source: source, maxWidth: 2400, imageQuality: 88),
      );
      if (selected == null || !mounted) return;

      final mimeType = _imageMimeType(selected);
      if (mimeType == null) {
        _showMessage('Choisissez une image au format JPEG ou PNG.');
        return;
      }

      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty) {
        _showMessage('La photo est vide. Prenez une nouvelle photo.');
        return;
      }
      if (bytes.length > _maxImageBytes) {
        _showMessage('La photo doit peser au maximum 6 Mo.');
        return;
      }

      DocumentType? selectedType;
      try {
        final classification = await widget.classifier.classify(selected.path);
        if (!mounted) return;
        final confirmed = await _confirmClassification(classification);
        if (!mounted || confirmed == null) return;
        selectedType = confirmed
            ? classification.type
            : await _chooseDocumentType();
      } on PlatformException {
        if (!mounted) return;
        _showMessage(
          'La reconnaissance du texte a échoué. Choisissez le type '
          'manuellement pour continuer.',
        );
        selectedType = await _chooseDocumentType();
      } on Exception {
        if (!mounted) return;
        _showMessage(
          'La reconnaissance du texte est indisponible. Choisissez le type '
          'manuellement pour continuer.',
        );
        selectedType = await _chooseDocumentType();
      }

      final documentType = selectedType;
      if (!mounted || documentType == null) return;
      final nationalId =
          documentType == DocumentType.cin ||
              documentType == DocumentType.passport
          ? await _extractNationalId(selected.path, documentType)
          : const NationalIdOcrResult();
      if (!mounted) return;
      final initialExpiryDate = DateTime.tryParse(
        nationalId.expirationDate ?? '',
      );
      final document = await Navigator.of(context).push<VaultDocument>(
        MaterialPageRoute<VaultDocument>(
          builder: (_) => ReviewDocumentScreen(
            onSave: widget.onSave,
            initialCategory: documentType.vaultCategory,
            initialTitle: documentType.suggestedTitle,
            nationalIdFieldsEnabled:
                documentType == DocumentType.cin ||
                documentType == DocumentType.passport,
            initialName: nationalId.firstName,
            initialSurname: nationalId.lastName,
            initialDateOfBirth: nationalId.dateOfBirth,
            initialPlaceOfBirth: nationalId.placeOfBirth,
            initialDocumentNumber: nationalId.documentNumber,
            initialExpiryDate: initialExpiryDate,
            imageBytes: bytes,
            imageMimeType: mimeType,
          ),
        ),
      );
      if (mounted && document != null) {
        Navigator.of(context).pop(document);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(
          error.message ??
              'Impossible d’ouvrir la caméra ou de sélectionner cette photo '
                  '(erreur ${error.code}).',
        );
      }
    } on FileSystemException {
      if (mounted) {
        _showMessage(
          'La photo sélectionnée est illisible. Choisissez-en une autre.',
        );
      }
    } on Exception catch (error) {
      if (mounted) {
        _showMessage('Impossible de préparer cette photo. ($error)');
      }
    } finally {
      if (mounted) setState(() => _isClassifying = false);
    }
  }

  Future<NationalIdOcrResult> _extractNationalId(
    String imagePath,
    DocumentType documentType,
  ) async {
    try {
      return await widget.nationalIdOcr.extract(
        imagePath,
        documentType: documentType,
      );
    } on PlatformException {
      if (mounted) {
        _showMessage(
          'La lecture de la CIN a échoué. Les champs non reconnus resteront '
          'vides ; vous pourrez les saisir manuellement.',
        );
      }
      return const NationalIdOcrResult();
    } on Exception {
      if (mounted) {
        _showMessage(
          'La lecture de la CIN est indisponible. Les champs non reconnus '
          'resteront vides ; vous pourrez les saisir manuellement.',
        );
      }
      return const NationalIdOcrResult();
    }
  }

  Future<bool?> _confirmClassification(DocumentClassification classification) {
    final message = classification.type == DocumentType.other
        ? 'Le texte reconnu ne permet pas d’identifier clairement ce document. '
              'Nous vous proposons « Autre document ». Est-ce correct ?'
        : 'Notre analyse du texte estime qu’il s’agit de '
              '${classification.type.displayName}. '
              'La reconnaissance peut se tromper. Est-ce correct ?';

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Document détecté !'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non, modifier'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Oui, c’est correct'),
          ),
        ],
      ),
    );
  }

  Future<DocumentType?> _chooseDocumentType() {
    return showDialog<DocumentType>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Choisir un type de document'),
        children: [
          for (final type in DocumentType.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, type),
              child: Text(type.displayName),
            ),
        ],
      ),
    );
  }

  String? _imageMimeType(XFile file) {
    final mimeType = file.mimeType?.toLowerCase();
    if (mimeType == 'image/jpeg' || mimeType == 'image/png') return mimeType;

    final name = file.name.toLowerCase();
    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) return 'image/jpeg';
    if (name.endsWith('.png')) return 'image/png';
    return null;
  }

  String? _imageMimeTypeFromBytes(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F7F7),
        title: const Text(
          'Ajouter un document',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Comment souhaitez-vous\najouter votre document ?',
                    style: TextStyle(
                      color: Color(0xFF172B3A),
                      fontSize: 25,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 9),
                  const Text(
                    'Choisissez une méthode pour commencer.',
                    style: TextStyle(color: Color(0xFF71808A), fontSize: 14),
                  ),
                  const SizedBox(height: 25),
                  _AddMethodCard(
                    icon: Icons.camera_enhance_rounded,
                    title: 'Photographier un papier pour l\'Admin',
                    subtitle:
                        'Prenez la photo (Recto/Verso), l\'admin l\'analyse et la classe dans le bon container',
                    badge: 'POUR ADMIN',
                    color: const Color(0xFFE3F2F0),
                    iconColor: const Color(0xFF087E78),
                    onTap: _captureCin,
                  ),
                  if (_isClassifying) ...[
                    const SizedBox(height: 10),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 9),
                        Text(
                          'En attente de la photo ou analyse OCR…',
                          style: TextStyle(
                            color: Color(0xFF526870),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 13),
                  _AddMethodCard(
                    icon: Icons.photo_camera_outlined,
                    title: 'Photographier un document',
                    subtitle:
                        'Classification locale par reconnaissance de texte',
                    badge: _isClassifying ? 'ANALYSE' : 'CAMÉRA',
                    color: const Color(0xFFE3F2F0),
                    iconColor: const Color(0xFF087E78),
                    onTap: _isClassifying
                        ? null
                        : () => _selectAndClassify(ImageSource.camera),
                  ),
                  const SizedBox(height: 13),
                  _AddMethodCard(
                    icon: Icons.image_outlined,
                    title: 'Importer une photo',
                    subtitle:
                        'JPEG ou PNG · 6 Mo · traitement sur cet appareil',
                    badge: _isClassifying ? 'ANALYSE' : 'IMAGE',
                    color: const Color(0xFFEAF0FB),
                    iconColor: const Color(0xFF537AB2),
                    onTap: _isClassifying
                        ? null
                        : () => _selectAndClassify(ImageSource.gallery),
                  ),
                  const SizedBox(height: 13),
                  _AddMethodCard(
                    icon: Icons.edit_note_rounded,
                    title: 'Saisie manuelle',
                    subtitle: 'Remplissez vous-même les informations',
                    badge: 'DISPONIBLE',
                    color: const Color(0xFFF5ECFF),
                    iconColor: const Color(0xFF7957A9),
                    onTap: () => _openManualEntry(context),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3F2),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: Color(0xFF087E78),
                          size: 19,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'La reconnaissance de texte s’effectue sur cet '
                            'appareil. Pour la CIN, vérifiez les informations '
                            'lues avant confirmation; elles ne constituent pas '
                            'une vérification officielle de votre identité.',
                            style: TextStyle(
                              color: Color(0xFF526870),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddMethodCard extends StatelessWidget {
  const _AddMethodCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String badge;
  final Color color;
  final Color iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3EAEA)),
          ),
          child: Row(
            children: [
              Container(
                width: 49,
                height: 49,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF172B3A),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF71808A),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 7),
              Column(
                children: [
                  if (onTap == null && badge == 'ANALYSE')
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: iconColor,
                      ),
                    )
                  else
                    Icon(
                      Icons.chevron_right_rounded,
                      color: iconColor,
                      size: 20,
                    ),
                  const SizedBox(height: 3),
                  Text(
                    badge,
                    style: TextStyle(
                      color: iconColor,
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
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
