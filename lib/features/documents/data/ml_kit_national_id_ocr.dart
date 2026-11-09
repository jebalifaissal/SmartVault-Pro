import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../../models/document_type.dart';
import '../domain/national_id_ocr.dart';
import '../domain/national_id_text_parser.dart';

class MlKitNationalIdOcr implements NationalIdOcr {
  @override
  Future<NationalIdOcrResult> extract(
    String imagePath, {
    DocumentType documentType = DocumentType.cin,
  }) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final recognizedText = await recognizer.processImage(
        InputImage.fromFilePath(imagePath),
      );
      return documentType == DocumentType.passport
          ? parsePassportText(recognizedText.text)
          : parseTunisianNationalIdText(recognizedText.text);
    } finally {
      await recognizer.close();
    }
  }
}
