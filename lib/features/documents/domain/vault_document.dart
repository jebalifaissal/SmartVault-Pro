import 'document_security_classification.dart';

class VaultDocument {
  const VaultDocument({
    required this.id,
    required this.title,
    required this.category,
    required this.holderName,
    required this.createdAt,
    this.documentNumber,
    this.expiryDate,
    this.name,
    this.surname,
    this.dateOfBirth,
    this.placeOfBirth,
    this.imageStoragePath,
    this.localImagePath,
    this.localBackImagePath,
    this.isLocal = false,
    this.documentType,
    this.fullName,
    this.firstName,
    this.lastName,
    this.cinNumber,
    this.expirationDate,
    this.updatedAt,
    this.status,
    this.securityLevel = DocumentSecurityLevel.pending,
    this.classificationStatus = DocumentClassificationStatus.pending,
    this.classificationSource = DocumentClassificationSource.automatic,
  });

  static const categories = [
    'Pièce d’identité',
    'Passeport',
    'Diplôme',
    'Permis de conduire',
    'Cours',
    'Notes',
    'Informations',
    'Autres',
    'En attente d’analyse',
  ];

  final String id;
  final String title;
  final String category;
  final String holderName;
  final DateTime createdAt;
  final String? documentNumber;
  final DateTime? expiryDate;
  final String? name;
  final String? surname;
  final String? dateOfBirth;
  final String? placeOfBirth;
  final String? imageStoragePath;
  final String? localImagePath;
  final String? localBackImagePath;
  final bool isLocal;
  final String? documentType;
  final String? fullName;
  final String? firstName;
  final String? lastName;
  final String? cinNumber;
  final DateTime? expirationDate;
  final DateTime? updatedAt;
  final String? status;
  final DocumentSecurityLevel securityLevel;
  final DocumentClassificationStatus classificationStatus;
  final DocumentClassificationSource classificationSource;

  VaultDocument copyWith({
    String? title,
    String? category,
    String? holderName,
    String? imageStoragePath,
    String? localImagePath,
    String? localBackImagePath,
    bool? isLocal,
    String? documentType,
    String? fullName,
    String? firstName,
    String? lastName,
    String? cinNumber,
    String? documentNumber,
    String? dateOfBirth,
    String? placeOfBirth,
    DateTime? expirationDate,
    DateTime? expiryDate,
    DateTime? updatedAt,
    String? status,
    DocumentSecurityLevel? securityLevel,
    DocumentClassificationStatus? classificationStatus,
    DocumentClassificationSource? classificationSource,
  }) => VaultDocument(
    id: id,
    title: title ?? this.title,
    category: category ?? this.category,
    holderName: holderName ?? this.holderName,
    createdAt: createdAt,
    documentNumber: documentNumber ?? this.documentNumber,
    expiryDate: expiryDate ?? this.expiryDate,
    name: firstName ?? name,
    surname: lastName ?? surname,
    dateOfBirth: dateOfBirth ?? this.dateOfBirth,
    placeOfBirth: placeOfBirth ?? this.placeOfBirth,
    imageStoragePath: imageStoragePath ?? this.imageStoragePath,
    localImagePath: localImagePath ?? this.localImagePath,
    localBackImagePath: localBackImagePath ?? this.localBackImagePath,
    isLocal: isLocal ?? this.isLocal,
    documentType: documentType ?? this.documentType,
    fullName: fullName ?? this.fullName,
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    cinNumber: cinNumber ?? this.cinNumber,
    expirationDate: expirationDate ?? this.expirationDate,
    updatedAt: updatedAt ?? this.updatedAt,
    status: status ?? this.status,
    securityLevel: securityLevel ?? this.securityLevel,
    classificationStatus: classificationStatus ?? this.classificationStatus,
    classificationSource: classificationSource ?? this.classificationSource,
  );
}
