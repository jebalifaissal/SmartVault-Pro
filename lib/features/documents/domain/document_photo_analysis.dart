class DocumentPhotoAnalysis {
  const DocumentPhotoAnalysis({
    required this.category,
    required this.confidence,
    this.holderName,
    this.documentNumber,
    this.expiryDate,
  });

  final String category;
  final double confidence;
  final String? holderName;
  final String? documentNumber;
  final DateTime? expiryDate;
}

abstract interface class DocumentPhotoAnalyzer {
  Future<DocumentPhotoAnalysis> analyze({
    required String imageBase64,
    required String mimeType,
  });
}
