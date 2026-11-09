import '../../../models/document_type.dart';

class NationalIdOcrResult {
  const NationalIdOcrResult({
    this.firstName,
    this.lastName,
    this.dateOfBirth,
    this.expirationDate,
    this.placeOfBirth,
    this.documentNumber,
    this.motherName,
    this.fatherName,
    this.gender,
    this.profession,
    this.address,
    this.issueDate,
    this.rawText = '',
  });

  final String? firstName;
  final String? lastName;
  final String? dateOfBirth;
  final String? expirationDate;
  final String? placeOfBirth;
  final String? documentNumber;
  final String? motherName;
  final String? fatherName;
  final String? gender;
  final String? profession;
  final String? address;
  final String? issueDate;
  final String rawText;
}

abstract interface class NationalIdOcr {
  Future<NationalIdOcrResult> extract(
    String imagePath, {
    DocumentType documentType = DocumentType.cin,
  });
}
