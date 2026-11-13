import 'dart:typed_data';

import '../../../services/document_api_service.dart';

class DocumentShareService {
  const DocumentShareService({required DocumentApiService api}) : _api = api;

  final DocumentApiService _api;

  Future<DocumentShareSession> createShare({
    required String documentId,
    required Map<String, String> fields,
    required int durationMinutes,
    required Uint8List frontImageBytes,
    required String frontImageMimeType,
    Uint8List? backImageBytes,
    String? backImageMimeType,
  }) async {
    final response = await _api.createShare(
      documentId: documentId,
      fields: fields,
      durationMinutes: durationMinutes,
      frontImageBytes: frontImageBytes,
      frontImageMimeType: frontImageMimeType,
      backImageBytes: backImageBytes,
      backImageMimeType: backImageMimeType,
    );
    return _parseShare(response);
  }

  Future<List<DocumentShareSession>> listShares({
    required String documentId,
  }) async {
    final response = await _api.getShares(documentId: documentId);
    return response.map(_parseShare).toList(growable: false);
  }

  Future<void> revokeShare(String shareId) => _api.revokeShare(shareId);

  DocumentShareSession _parseShare(Map<String, dynamic> data) {
    final id = data['id'];
    final url = data['url'];
    final expiresAt = _date(data['expires_at'], 'expires_at');
    final createdAtValue = data['created_at'];
    final status = data['status'];
    if (id is! String ||
        id.isEmpty ||
        (url != null && url is! String) ||
        status is! String) {
      throw const FormatException('Réponse de partage invalide.');
    }
    return DocumentShareSession(
      id: id,
      url: url as String? ?? '',
      expiresAt: expiresAt,
      createdAt: createdAtValue == null
          ? null
          : _date(createdAtValue, 'created_at'),
      status: status,
    );
  }

  DateTime _date(Object? value, String field) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt());
    }
    throw FormatException('Date de partage invalide : $field.');
  }
}

class DocumentShareSession {
  const DocumentShareSession({
    required this.id,
    required this.url,
    required this.expiresAt,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String url;
  final DateTime expiresAt;
  final DateTime? createdAt;
  final String status;

  bool get isExpired => !expiresAt.isAfter(DateTime.now());
}
