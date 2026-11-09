import 'package:flutter_test/flutter_test.dart';
import 'package:smartvault_pro/features/documents/domain/document_text_classifier.dart';
import 'package:smartvault_pro/models/document_type.dart';

void main() {
  test('recognizes a Tunisian national identity card', () {
    final result = classifyDocumentText(
      'CARTE NATIONALE D’IDENTITÉ RÉPUBLIQUE TUNISIENNE',
    );

    expect(result.type, DocumentType.cin);
    expect(result.confidence, greaterThan(0));
  });

  test('recognizes a Tunisian passport', () {
    expect(
      classifyDocumentText('REPUBLIQUE TUNISIENNE PASSEPORT').type,
      DocumentType.passport,
    );
  });

  test('recognizes certificates and diplomas', () {
    expect(
      classifyDocumentText('ATTESTATION DE TRAVAIL').type,
      DocumentType.certificate,
    );
    expect(
      classifyDocumentText('DIPLÔME UNIVERSITAIRE').type,
      DocumentType.certificate,
    );
  });

  test('recognizes a driving license', () {
    expect(
      classifyDocumentText('PERMIS DE CONDUIRE').type,
      DocumentType.drivingLicense,
    );
  });

  test('recognizes Arabic identity-card text when available', () {
    expect(
      classifyDocumentText('بطاقة التعريف الوطنية').type,
      DocumentType.cin,
    );
  });

  test('returns OTHER for unclear or ambiguous text', () {
    expect(classifyDocumentText('Texte illisible').type, DocumentType.other);
    expect(
      classifyDocumentText('CARTE NATIONALE D’IDENTITÉ PASSEPORT').type,
      DocumentType.other,
    );
    expect(classifyDocumentText('').confidence, 0);
  });

  test('maps detected types to existing vault names and categories', () {
    expect(DocumentType.cin.suggestedTitle, 'Carte nationale d’identité');
    expect(DocumentType.cin.vaultCategory, 'Pièce d’identité');
    expect(DocumentType.certificate.vaultCategory, 'Diplôme');
    expect(DocumentType.drivingLicense.vaultCategory, 'Permis de conduire');
    expect(DocumentType.other.vaultCategory, 'Autres');
  });
}
