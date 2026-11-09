import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../auth/presentation/session_lock_activity.dart';
import '../domain/local_cin_repository.dart';
import '../domain/national_id_ocr.dart';
import '../domain/vault_document.dart';

/// Écran de capture de papier / document pour transmission directe à l'administrateur.
/// L'utilisateur prend la photo et l'envoie à l'admin qui se charge de l'analyser et de le classer.
class CinCaptureScreen extends StatefulWidget {
  const CinCaptureScreen({
    required this.onSubmit,
    this.nationalIdOcr,
    super.key,
  });

  final SubmitClassificationRequest onSubmit;
  final NationalIdOcr? nationalIdOcr;

  @override
  State<CinCaptureScreen> createState() => _CinCaptureScreenState();
}

class _CinCaptureScreenState extends State<CinCaptureScreen> {
  final _picker = ImagePicker();
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();

  Uint8List? _frontBytes;
  Uint8List? _backBytes;

  bool _isSaving = false;

  static const _teal = Color(0xFF087E78);
  static const _ink = Color(0xFF172B3A);
  static const _canvas = Color(0xFFF4F7F7);
  static const _line = Color(0xFFE2E8EB);

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({
    required bool isFront,
    required ImageSource source,
  }) async {
    try {
      final file = await SessionLockActivityScope.run(
        context,
        () =>
            _picker.pickImage(source: source, imageQuality: 92, maxWidth: 1920),
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;

      setState(() {
        if (isFront) {
          _frontBytes = bytes;
        } else {
          _backBytes = bytes;
        }
      });
    } on PlatformException catch (error) {
      if (!mounted) return;
      _showSnackBar('Erreur caméra (${error.code}) : ${error.message}');
    } catch (error) {
      if (!mounted) return;
      _showSnackBar('Impossible de charger l\'image : $error');
    }
  }

  void _showImageSourceSheet({required bool isFront}) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isFront
                    ? 'Photo principale / Face avant (Recto)'
                    : 'Photo complémentaire / Face arrière (Verso)',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Prenez une photo claire du papier à transmettre à l\'administrateur.',
                style: TextStyle(color: Color(0xFF71808A), fontSize: 13),
              ),
              const SizedBox(height: 18),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.photo_camera_rounded, color: _teal),
                ),
                title: const Text(
                  'Prendre une photo (Caméra)',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(isFront: isFront, source: ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEAF0FB),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: Color(0xFF3976B8),
                  ),
                ),
                title: const Text(
                  'Sélectionner depuis la galerie',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickImage(isFront: isFront, source: ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitToAdmin() async {
    if (_frontBytes == null && _backBytes == null) {
      _showSnackBar('Veuillez prendre au moins une photo du papier.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final random = Random.secure();
      final documentId = List<int>.generate(
        16,
        (_) => random.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

      final now = DateTime.now();
      final userTitle = _titleController.text.trim();
      final note = _noteController.text.trim();

      final mainBytes = _frontBytes ?? _backBytes!;
      const mimeType = 'image/jpeg';

      final document = VaultDocument(
        id: documentId,
        title: userTitle.isNotEmpty ? userTitle : 'Papier soumis pour analyse',
        category: 'En attente d’analyse',
        holderName: note.isNotEmpty
            ? note
            : 'À déterminer par l\'administrateur',
        createdAt: now,
        updatedAt: now,
        documentType: 'SOUMIS_ADMIN',
        status: 'pending_admin',
      );

      final submitted = await widget.onSubmit(
        document,
        mainBytes,
        mimeType,
        note,
      );

      if (!mounted) return;

      // Dialogue explicatif confirmant la transmission à l'administrateur
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: Color(0xFFE4F2F0),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: _teal,
              size: 34,
            ),
          ),
          title: Text(
            submitted
                ? 'Demande envoyée à l\'administrateur'
                : 'Demande enregistrée en attente d’envoi',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          content: Text(
            submitted
                ? 'Votre photo reste en attente. L’administrateur va la classer '
                      'dans le container très sensible ou moyennement sensible. '
                      'Le document ne sera ajouté à votre coffre qu’après sa décision.'
                : 'Votre photo reste sur cet appareil et la demande sera envoyée '
                      'dès que la connexion sera disponible. Le document ne sera '
                      'ajouté à votre coffre qu’après le classement par l’administrateur.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF526870),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Compris'),
              ),
            ),
          ],
        ),
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        _showSnackBar('Erreur lors de l\'envoi : $error');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final hasFront = _frontBytes != null;

    return Scaffold(
      backgroundColor: _canvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Dépôt de papier pour l\'admin',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: _ink,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Bannière explicative ────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0B827B), Color(0xFF075B61)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Analyse & Classement Admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'Prenez en photo votre papier. L\'administrateur va l\'examiner et le classer dans le container approprié.',
                            style: TextStyle(
                              color: Color(0xFFD2ECE8),
                              fontSize: 12,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Photo Principale (Recto / Papier) ───────────────────
              _buildSideCard(
                title: '1. Photo du papier (Face principale / Recto)',
                subtitle: 'Photo nette du document',
                isFront: true,
                imageBytes: _frontBytes,
                onCapture: () => _showImageSourceSheet(isFront: true),
                onRetake: () => _showImageSourceSheet(isFront: true),
              ),

              const SizedBox(height: 18),

              // ── Photo Optionnelle (Verso) ───────────────────────────
              _buildSideCard(
                title: '2. Face arrière (Verso / Page 2 - optionnel)',
                subtitle:
                    'Si votre document comporte un verso ou une 2ème page',
                isFront: false,
                imageBytes: _backBytes,
                onCapture: () => _showImageSourceSheet(isFront: false),
                onRetake: () => _showImageSourceSheet(isFront: false),
              ),

              const SizedBox(height: 22),

              // ── Informations optionnelles pour l'admin ─────────────
              const Text(
                'Informations complémentaires (facultatif)',
                style: TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),

              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'Titre ou type du document',
                  hintText: 'Ex: Carte CIN, Passeport, Cours de Maths...',
                  prefixIcon: const Icon(Icons.description_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _line),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              TextField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Remarque pour l\'administrateur',
                  hintText:
                      'Ex: Papier urgent, ou précision sur le document...',
                  prefixIcon: const Icon(Icons.comment_outlined),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _line),
                  ),
                ),
              ),

              const SizedBox(height: 26),

              // ── Bouton d'envoi vers l'Admin ─────────────────────────
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: (_isSaving || !hasFront) ? null : _submitToAdmin,
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFC7D3D5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
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
                      : const Icon(Icons.send_rounded, size: 20),
                  label: Text(
                    _isSaving
                        ? 'Envoi en cours…'
                        : hasFront
                        ? 'Enregistrer & Transmettre à l\'Admin'
                        : 'Prenez une photo pour continuer',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.shield_outlined,
                      size: 14,
                      color: Color(0xFF71808A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Transmission sécurisée · Traitement par l\'administrateur',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideCard({
    required String title,
    required String subtitle,
    required bool isFront,
    required Uint8List? imageBytes,
    required VoidCallback onCapture,
    required VoidCallback onRetake,
  }) {
    final hasImage = imageBytes != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasImage ? _teal : _line,
          width: hasImage ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: _ink,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      const SizedBox(height: 2),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hasImage
                        ? const Color(0xFFE3F4F1)
                        : const Color(0xFFF2F4F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    hasImage
                        ? 'PHOTO PRÊTE ✓'
                        : (isFront ? 'REQUIS' : 'OPTIONNEL'),
                    style: TextStyle(
                      color: hasImage ? _teal : const Color(0xFF8B99A2),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          if (hasImage)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      imageBytes,
                      height: 170,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: onRetake,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text(
                          'Changer cette photo',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: TextButton.styleFrom(foregroundColor: _teal),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            InkWell(
              onTap: onCapture,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(18),
              ),
              child: Container(
                height: 120,
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7FBFB),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFC7DEE0)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE4F2F0),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_a_photo_outlined,
                        color: _teal,
                        size: 22,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isFront
                          ? 'Prendre la photo du papier'
                          : 'Prendre le verso (si présent)',
                      style: const TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
