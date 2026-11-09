import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../domain/document_image_classifier.dart';
import '../domain/document_text_classifier.dart';

class MlKitDocumentImageClassifier implements DocumentImageClassifier {
  @override
  Future<DocumentClassification> classify(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final image = InputImage.fromFilePath(imagePath);
      final recognizedText = await recognizer.processImage(image);
      return classifyDocumentText(recognizedText.text);
    } finally {
      await recognizer.close();
    }
  }
}
