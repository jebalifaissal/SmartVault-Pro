import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'package:tesseract_ocr/tesseract_ocr.dart';

import '../../../models/document_type.dart';
import '../domain/document_image_classifier.dart';
import '../domain/document_text_classifier.dart';
import '../domain/national_id_ocr.dart';
import '../domain/national_id_text_parser.dart';

/// Reconnaissance OCR hybride : combine Google ML Kit (très rapide et fiable sur mobile)
/// et Tesseract (pour le support de l'arabe) avec fallback automatique.
class HybridNationalIdOcr implements NationalIdOcr, DocumentImageClassifier {
  @override
  Future<DocumentClassification> classify(String imagePath) async {
    final result = await extract(imagePath);
    return classifyDocumentText(result.rawText);
  }

  @override
  Future<NationalIdOcrResult> extract(
    String imagePath, {
    DocumentType documentType = DocumentType.cin,
  }) async {
    final collectedTexts = <String>[];

    // 1. Moteur principal : Google ML Kit Text Recognition (rapide et robuste)
    try {
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      try {
        final inputImage = InputImage.fromFilePath(imagePath);
        final recognizedText = await recognizer.processImage(inputImage);
        if (recognizedText.text.trim().isNotEmpty) {
          collectedTexts.add(recognizedText.text.trim());
        }
      } finally {
        await recognizer.close();
      }
    } catch (_) {
      // Si ML Kit rencontre une exception, Tesseract prendra le relais
    }

    // 2. Moteur complémentaire : Tesseract (support multilingue fra + ara)
    try {
      final tesseractText = await TesseractOcr.extractText(
        imagePath,
        config: const OCRConfig(language: 'fra+ara', engine: OCREngine.tesseract),
      );
      if (tesseractText.trim().isNotEmpty) {
        collectedTexts.add(tesseractText.trim());
      }
    } catch (_) {
      // Tesseract peut échouer si les fichiers traineddata ne sont pas installés
    }

    final combinedText = collectedTexts.join('\n');

    return documentType == DocumentType.passport
        ? parsePassportText(combinedText)
        : parseTunisianNationalIdText(combinedText);
  }
}
