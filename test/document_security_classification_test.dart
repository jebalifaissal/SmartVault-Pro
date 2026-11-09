import 'package:flutter_test/flutter_test.dart';
import 'package:smartvault_pro/features/documents/domain/document_security_classification.dart';
import 'package:smartvault_pro/models/document_type.dart';

void main() {
  test(
    'classifies identity, passport and driving license as high security',
    () {
      for (final type in [
        DocumentType.cin,
        DocumentType.passport,
        DocumentType.drivingLicense,
      ]) {
        final classification = classifyDocumentSecurity(type);

        expect(classification.level, DocumentSecurityLevel.high);
        expect(
          classification.status,
          DocumentClassificationStatus.autoClassified,
        );
        expect(classification.source, DocumentClassificationSource.automatic);
      }
    },
  );

  test('classifies certificates as medium security', () {
    final classification = classifyDocumentSecurity(DocumentType.certificate);

    expect(classification.level, DocumentSecurityLevel.medium);
    expect(classification.status, DocumentClassificationStatus.autoClassified);
  });

  test('keeps unknown document types pending', () {
    final classification = classifyDocumentSecurity(DocumentType.other);

    expect(classification.level, DocumentSecurityLevel.pending);
    expect(classification.status, DocumentClassificationStatus.pending);
    expect(classification.source, DocumentClassificationSource.automatic);
  });
}
