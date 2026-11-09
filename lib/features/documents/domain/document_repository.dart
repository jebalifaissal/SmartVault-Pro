import 'dart:typed_data';

import 'vault_document.dart';

enum DocumentSaveStage { storageUpload, documentApiWrite }

class DocumentSaveException implements Exception {
  const DocumentSaveException({
    required this.stage,
    required this.cause,
    this.rollbackError,
  });

  final DocumentSaveStage stage;
  final Object cause;
  final Object? rollbackError;
}

typedef SaveVaultDocument =
    Future<VaultDocument> Function(
      VaultDocument document,
      Uint8List? imageBytes,
      String? imageMimeType,
    );

abstract interface class DocumentRepository {
  Stream<List<VaultDocument>> watchDocuments(String userId);

  Future<VaultDocument> saveDocument({
    required String userId,
    required VaultDocument document,
    Uint8List? imageBytes,
    String? imageMimeType,
  });
}
