import '../../../models/document_type.dart';

enum DocumentSecurityLevel {
  high('HIGH'),
  medium('MEDIUM'),
  pending('PENDING');

  const DocumentSecurityLevel(this.databaseValue);

  final String databaseValue;

  static DocumentSecurityLevel fromDatabaseValue(String value) =>
      DocumentSecurityLevel.values.firstWhere(
        (level) => level.databaseValue == value,
        orElse: () => throw FormatException(
          'Niveau de sécurité non pris en charge : $value',
        ),
      );
}

enum DocumentClassificationStatus {
  autoClassified('AUTO_CLASSIFIED'),
  pending('PENDING'),
  adminReviewed('ADMIN_REVIEWED'),
  rejected('REJECTED');

  const DocumentClassificationStatus(this.databaseValue);

  final String databaseValue;

  static DocumentClassificationStatus fromDatabaseValue(String value) =>
      DocumentClassificationStatus.values.firstWhere(
        (status) => status.databaseValue == value,
        orElse: () => throw FormatException(
          'Statut de classification non pris en charge : $value',
        ),
      );
}

enum DocumentClassificationSource {
  automatic('AUTOMATIC'),
  administrator('ADMIN');

  const DocumentClassificationSource(this.databaseValue);

  final String databaseValue;

  static DocumentClassificationSource fromDatabaseValue(String value) =>
      DocumentClassificationSource.values.firstWhere(
        (source) => source.databaseValue == value,
        orElse: () => throw FormatException(
          'Origine de classification non prise en charge : $value',
        ),
      );
}

class DocumentSecurityClassification {
  const DocumentSecurityClassification({
    required this.level,
    required this.status,
    required this.source,
  });

  final DocumentSecurityLevel level;
  final DocumentClassificationStatus status;
  final DocumentClassificationSource source;
}

DocumentSecurityClassification classifyDocumentSecurity(DocumentType type) =>
    switch (type) {
      DocumentType.cin ||
      DocumentType.passport ||
      DocumentType.drivingLicense => const DocumentSecurityClassification(
        level: DocumentSecurityLevel.high,
        status: DocumentClassificationStatus.autoClassified,
        source: DocumentClassificationSource.automatic,
      ),
      DocumentType.certificate => const DocumentSecurityClassification(
        level: DocumentSecurityLevel.medium,
        status: DocumentClassificationStatus.autoClassified,
        source: DocumentClassificationSource.automatic,
      ),
      DocumentType.other => const DocumentSecurityClassification(
        level: DocumentSecurityLevel.pending,
        status: DocumentClassificationStatus.pending,
        source: DocumentClassificationSource.automatic,
      ),
    };
