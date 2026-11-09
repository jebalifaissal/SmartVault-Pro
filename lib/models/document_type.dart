enum DocumentType {
  cin(
    'CIN',
    'Carte nationale d’identité (CIN)',
    'Carte nationale d’identité',
    'Pièce d’identité',
  ),
  passport('PASSPORT', 'Passeport', 'Passeport', 'Passeport'),
  certificate('CERTIFICATE', 'Certificat ou diplôme', 'Certificat', 'Diplôme'),
  drivingLicense(
    'DRIVING_LICENSE',
    'Permis de conduire',
    'Permis de conduire',
    'Permis de conduire',
  ),
  other('OTHER', 'Autre document', 'Autre document', 'Autres');

  const DocumentType(
    this.apiValue,
    this.displayName,
    this.suggestedTitle,
    this.vaultCategory,
  );

  final String apiValue;
  final String displayName;
  final String suggestedTitle;
  final String vaultCategory;

  static DocumentType fromApiValue(String value) {
    return DocumentType.values.firstWhere(
      (type) => type.apiValue == value,
      orElse: () => throw FormatException(
        'Catégorie de document non prise en charge : $value',
      ),
    );
  }
}
