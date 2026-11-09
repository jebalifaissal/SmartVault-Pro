import '../../../models/document_type.dart';

class DocumentClassification {
  const DocumentClassification({required this.type, required this.confidence});

  final DocumentType type;
  final double confidence;
}

DocumentClassification classifyDocumentText(String text) {
  final normalized = _normalize(text);
  if (normalized.isEmpty) return _uncertain();

  final scores = <DocumentType, int>{
    DocumentType.cin:
        _score(normalized, [
          (RegExp(r'\bcarte nationale d identite\b'), 5),
          (RegExp(r'\bcarte d identite\b'), 4),
          (RegExp(r'\bnational identity card\b'), 5),
          (RegExp(r'\bidentity card\b'), 4),
          (RegExp(r'\bcni\b'), 2),
          (RegExp(r'\brepublique tunisienne\b'), 2),
        ]) +
        _scoreArabic(text, [
          ('بطاقة التعريف الوطنية', 5),
          ('رقم بطاقة التعريف الوطنية', 5),
          ('الجمهورية التونسية', 2),
        ]),
    DocumentType.passport:
        _score(normalized, [
          (RegExp(r'\bpassport\b'), 5),
          (RegExp(r'\bpasseport\b'), 5),
          (RegExp(r'\bpassport no\b'), 2),
        ]) +
        _scoreArabic(text, [('جواز سفر', 5)]),
    DocumentType.certificate: _score(normalized, [
      (RegExp(r'\battestation\b'), 4),
      (RegExp(r'\bcertificat\b'), 4),
      (RegExp(r'\bdiplome\b'), 4),
      (RegExp(r'\bcertificate\b'), 4),
      (RegExp(r'\bdiploma\b'), 4),
      (RegExp(r'\buniversite\b'), 1),
      (RegExp(r'\bdegree\b'), 2),
      (RegExp(r'\bbachelor\b'), 2),
      (RegExp(r'\bmaster\b'), 1),
      (RegExp(r'\bbaccalaureat\b'), 2),
    ]),
    DocumentType.drivingLicense: _score(normalized, [
      (RegExp(r'\bpermis de conduire\b'), 5),
      (RegExp(r'\bdriving licen[cs]e\b'), 5),
      (RegExp(r'\bdriver licen[cs]e\b'), 5),
      (RegExp(r'\bcategory b\b'), 1),
    ]),
    DocumentType.other: 0,
  }..remove(DocumentType.other);

  final ranked = scores.entries.toList()
    ..sort((first, second) => second.value.compareTo(first.value));
  if (ranked.first.value < 4 || ranked.first.value - ranked[1].value < 2) {
    return _uncertain();
  }

  return DocumentClassification(
    type: ranked.first.key,
    confidence: ranked.first.value >= 5 ? 0.9 : 0.7,
  );
}

DocumentClassification _uncertain() =>
    const DocumentClassification(type: DocumentType.other, confidence: 0);

int _score(String text, List<(RegExp, int)> rules) {
  var score = 0;
  for (final (pattern, weight) in rules) {
    if (pattern.hasMatch(text)) score += weight;
  }
  return score;
}

int _scoreArabic(String text, List<(String, int)> rules) {
  final normalized = text
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  var score = 0;
  for (final (phrase, weight) in rules) {
    if (normalized.contains(phrase)) score += weight;
  }
  return score;
}

String _normalize(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[àáâä]'), 'a')
      .replaceAll(RegExp(r'[èéêë]'), 'e')
      .replaceAll(RegExp(r'[ìíîï]'), 'i')
      .replaceAll(RegExp(r'[òóôö]'), 'o')
      .replaceAll(RegExp(r'[ùúûü]'), 'u')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06FF]+'), ' ')
      .trim();
}
