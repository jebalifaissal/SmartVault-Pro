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
    );

typedef UpdateLocalDocument =
    Future<VaultDocument> Function(VaultDocument document);

typedef SubmitClassificationRequest =
    Future<bool> Function(
      VaultDocument document,
      Uint8List imageBytes,
      String imageMimeType,
      String message,
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
  });

  final String id;
  final String title;
  final String message;
  final String documentType;
  final String imagePath;
  final String imageMimeType;
  final bool isSubmitted;
}

abstract interface class LocalDocumentRepository {
  Stream<List<VaultDocument>> watchDocuments(String userId);

  Future<VaultDocument> saveDocument({
    required String userId,
    required VaultDocument document,
    Uint8List? imageBytes,
    String? imageMimeType,
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
