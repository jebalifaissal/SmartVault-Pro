import 'dart:io';

import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

import '../../../models/document_type.dart';
import '../domain/document_image_classifier.dart';
import '../domain/document_text_classifier.dart';
import '../domain/national_id_ocr.dart';
import '../domain/national_id_text_parser.dart';

class TesseractNationalIdOcr implements NationalIdOcr, DocumentImageClassifier {
  final Map<String, Future<String>> _pendingRecognitions = {};

  @override
  Future<DocumentClassification> classify(String imagePath) async {
    final text = await _recognize(imagePath);
    return classifyDocumentText(text);
  }

  @override
  Future<NationalIdOcrResult> extract(
    String imagePath, {
    DocumentType documentType = DocumentType.cin,
  }) async {
    final recognition =
        _pendingRecognitions[imagePath] ?? _recognize(imagePath);
    try {
      final text = await recognition;
      return documentType == DocumentType.passport
          ? parsePassportText(text)
          : parseTunisianNationalIdText(text);
    } finally {
      if (identical(_pendingRecognitions[imagePath], recognition)) {
        _pendingRecognitions.remove(imagePath);
      }
    }
  }

  Future<String> _recognize(String imagePath) {
    if (imagePath.trim().isEmpty) {
      throw ArgumentError.value(imagePath, 'imagePath', 'Le chemin est vide.');
    }
    final pending = _pendingRecognitions[imagePath];
    if (pending != null) return pending;

    final recognition = _runTesseract(imagePath);
    _pendingRecognitions[imagePath] = recognition;
    if (_pendingRecognitions.length > 4) {
      _pendingRecognitions.remove(_pendingRecognitions.keys.first);
    }
    return recognition;
  }

  Future<String> _runTesseract(String imagePath) async {
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw FileSystemException(
        'La photo à analyser est introuvable.',
        imagePath,
      );
    }
    if (await imageFile.length() == 0) {
      throw FileSystemException('La photo à analyser est vide.', imagePath);
    }
    final text = await TesseractOcr.extractText(
      imagePath,
      config: const OCRConfig(language: 'fra+ara', engine: OCREngine.tesseract),
    );
    return text;
  }
}
