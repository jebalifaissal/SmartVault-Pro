import 'dart:typed_data';

import 'document_security_classification.dart';
import 'vault_document.dart';

enum LocalCinSaveStage { imageCopy, databaseWrite, imageDelete }

class LocalCinException implements Exception {
  const LocalCinException({
    required this.stage,
    required this.cause,
    this.rollbackError,
  });

  final LocalCinSaveStage stage;
  final Object cause;
  final Object? rollbackError;
}

typedef SaveLocalDocument =
    Future<VaultDocument> Function(
      VaultDocument document,
      Uint8List? imageBytes,
      String? imageMimeType,
      [Uint8List? backImageBytes, String? backImageMimeType]
    );

typedef UpdateLocalDocument =
    Future<VaultDocument> Function(VaultDocument document);

typedef SubmitClassificationRequest =
    Future<bool> Function(
      VaultDocument document,
      Uint8List imageBytes,
      String imageMimeType,
      String message,
      [Uint8List? backImageBytes, String? backImageMimeType],
    );

class PendingLocalClassification {
  const PendingLocalClassification({
    required this.id,
    required this.title,
    required this.message,
    required this.documentType,
    required this.imagePath,
    required this.imageMimeType,
    required this.isSubmitted,
    this.backImagePath,
    this.backImageMimeType,
  });

  final String id;
  final String title;
  final String message;
  final String documentType;
  final String imagePath;
  final String imageMimeType;
  final bool isSubmitted;
  final String? backImagePath;
  final String? backImageMimeType;
}

abstract interface class LocalDocumentRepository {
  Stream<List<VaultDocument>> watchDocuments(String userId);

  Future<VaultDocument> saveDocument({
    required String userId,
    required VaultDocument document,
    Uint8List? imageBytes,
    String? imageMimeType,
    Uint8List? backImageBytes,
    String? backImageMimeType,
  });

  Future<VaultDocument> updateDocument({
    required String userId,
    required VaultDocument document,
  });

  Future<void> stageClassificationRequest({
    required String userId,
    required String id,
    required String title,
    required String message,
    required String documentType,
    required Uint8List imageBytes,
    required String imageMimeType,
    Uint8List? backImageBytes,
    String? backImageMimeType,
  });

  Future<List<PendingLocalClassification>> pendingClassificationRequests(
    String userId,
  );

  Future<void> markClassificationRequestSubmitted({
    required String userId,
    required String id,
  });

  Future<VaultDocument> completeClassificationRequest({
    required String userId,
    required String id,
    required String category,
    required DocumentSecurityLevel securityLevel,
    String? firstName,
    String? lastName,
    String? documentNumber,
    String? dateOfBirth,
    String? placeOfBirth,
    DateTime? expirationDate,
  });

  Future<void> removeClassificationRequest({
    required String userId,
    required String id,
  });

  Future<void> deleteDocument({
    required String userId,
    required String documentId,
  });
}
