import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/document_type.dart';
import '../services/ai_service.dart';

class DocumentScanScreen extends StatefulWidget {
  const DocumentScanScreen({required this.aiService, super.key});

  final AIService aiService;

  @override
  State<DocumentScanScreen> createState() => _DocumentScanScreenState();
}

class _DocumentScanScreenState extends State<DocumentScanScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  File? _selectedImage;
  DocumentType? _documentType;
  bool _isClassifying = false;
  String? _errorMessage;

  Future<void> _selectImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2400,
        imageQuality: 88,
      );
      if (image == null || !mounted) return;

      setState(() {
        _selectedImage = File(image.path);
        _documentType = null;
        _errorMessage = null;
      });
    } on PlatformException {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Could not open the camera or photo gallery. Check the app permissions and try again.';
      });
    }
  }

  Future<bool> _confirmImageUpload() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Send image for classification?'),
            content: const Text(
              'This image will be sent to Google Gemini through our secure '
              'server for document classification. Personal information is '
              'not requested. Continue only if you agree.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Send image'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _classifyImage() async {
    final image = _selectedImage;
    if (image == null || _isClassifying) return;
    if (!await _confirmImageUpload() || !mounted) return;

    setState(() {
      _isClassifying = true;
      _documentType = null;
      _errorMessage = null;
    });

    try {
      final documentType = await widget.aiService.classifyDocument(image);
      if (!mounted) return;
      setState(() => _documentType = documentType);
    } on AIServiceException catch (error) {
      if (!mounted) return;
      setState(() => _errorMessage = error.message);
    } on Exception {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Classification failed unexpectedly. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _isClassifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a document')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_selectedImage == null)
              Container(
                height: 240,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('Select or take a document photo'),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  _selectedImage!,
                  height: 300,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    height: 240,
                    child: Center(child: Text('Could not preview this image.')),
                  ),
                ),
              ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _isClassifying
                      ? null
                      : () => _selectImage(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Choose from Gallery'),
                ),
                OutlinedButton.icon(
                  onPressed: _isClassifying
                      ? null
                      : () => _selectImage(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Take a Picture'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _selectedImage == null || _isClassifying
                  ? null
                  : _classifyImage,
              child: _isClassifying
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Classify Document'),
            ),
            if (_documentType case final documentType?) ...[
              const SizedBox(height: 20),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Detected document category'),
                  subtitle: Text(
                    '${documentType.apiValue} — ${documentType.displayName}',
                  ),
                ),
              ),
            ],
            if (_errorMessage case final errorMessage?) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  errorMessage,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
