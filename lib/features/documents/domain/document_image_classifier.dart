import 'document_text_classifier.dart';

abstract interface class DocumentImageClassifier {
  Future<DocumentClassification> classify(String imagePath);
}
