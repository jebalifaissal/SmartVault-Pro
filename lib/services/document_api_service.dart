import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../features/documents/domain/classification_request.dart';
import '../features/documents/domain/user_notification.dart';
import 'cloudflare_api_config.dart';

class DocumentApiService {
  DocumentApiService({
    required Future<String?> Function() getAccessToken,
    Future<bool?> Function()? getCachedAdministrator,
    http.Client? client,
    String? baseUrl,
  }) : _getAccessToken = getAccessToken,
       _getCachedAdministrator = getCachedAdministrator,
       _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? CloudflareApiConfig.baseUrl;

  final Future<String?> Function() _getAccessToken;
  final Future<bool?> Function()? _getCachedAdministrator;
  final http.Client _client;
  final String _baseUrl;

  Future<List<Map<String, dynamic>>> getDocuments() async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/api/documents'),
      headers: await _authenticatedHeaders(),
    );
    final data = _decodeResponse(response, expectedStatusCode: 200);
    final documents = data['documents'];
    if (documents is! List) {
      throw const FormatException('Invalid documents response');
    }
    return documents
        .map((document) {
          if (document is! Map<String, dynamic>) {
            throw const FormatException('Invalid document response');
          }
          return document;
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> addDocument(
    Map<String, Object?> document,
  ) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/documents'),
      headers: await _authenticatedHeaders(),
      body: jsonEncode(document),
    );
    final result = _decodeResponse(
      response,
      expectedStatusCode: 201,
    )['document'];
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved document response');
    }
    return result;
  }

  Future<void> deleteDocument(String id) async {
    final response = await _client.delete(
      Uri.parse('$_baseUrl/api/documents/${Uri.encodeComponent(id)}'),
      headers: await _authenticatedHeaders(),
    );
    _decodeResponse(response, expectedStatusCode: 200);
  }

  Future<bool> isCurrentUserAdministrator() async {
    try {
      final data = _decodeResponse(
        await _client.get(
          Uri.parse('$_baseUrl/api/session'),
          headers: await _authenticatedHeaders(),
        ),
        expectedStatusCode: 200,
      );
      final isAdmin = data['isAdmin'];
      if (isAdmin is! bool) {
        throw const FormatException('Invalid user role response');
      }
      return isAdmin;
    } on SocketException {
      return await _getCachedAdministrator?.call() ??
          (throw StateError(
            'Le rôle de la session hors connexion est inconnu.',
          ));
    } on http.ClientException {
      return await _getCachedAdministrator?.call() ??
          (throw StateError(
            'Le rôle de la session hors connexion est inconnu.',
          ));
    } on TimeoutException {
      return await _getCachedAdministrator?.call() ??
          (throw StateError(
            'Le rôle de la session hors connexion est inconnu.',
          ));
    }
  }


Future<void> submitClassificationRequest({
  required String id,
  required String title,
  required String message,
  required String documentType,
  required Uint8List imageBytes,
  required String imageMimeType,
}) async {
  final response = await _client.post(
    Uri.parse('$_baseUrl/api/classification-requests'),
    headers: await _authenticatedHeaders(),
    body: jsonEncode({
      'id': id,
      'title': title,
      'message': message,
      'document_type': documentType,
      'image_base64': base64Encode(imageBytes),
      'image_mime_type': imageMimeType,
    }),
  );

  if (response.statusCode != 200 && response.statusCode != 201) {
    _decodeResponse(response, expectedStatusCode: 200);
    throw StateError('La demande de classification a échoué.');
  }

  final data = _decodeResponse(
    response,
    expectedStatusCode: response.statusCode,
  );

  if (data['success'] != true) {
    throw const FormatException('Invalid classification request response');
  }
}


  Future<List<ClassificationRequest>> getPendingClassificationRequests() async {
    final data = _decodeResponse(
      await _client.get(
        Uri.parse('$_baseUrl/api/admin/classification-requests'),
        headers: await _authenticatedHeaders(),
      ),
      expectedStatusCode: 200,
    );
    return _parseRequests(data['requests']);
  }

  Future<Uint8List> getClassificationRequestPhoto(String id) async {
    final response = await _client.get(
      Uri.parse(
        '$_baseUrl/api/admin/classification-requests/'
        '${Uri.encodeComponent(id)}/photo',
      ),
      headers: await _authenticatedHeaders(),
    );
    if (response.statusCode != 200) {
      _decodeResponse(response, expectedStatusCode: 200);
      throw StateError('La photo de la demande est indisponible.');
    }
    return response.bodyBytes;
  }

  Future<ClassificationDecision> decideClassificationRequest({
    required String id,
    required String decision,
    String? securityLevel,
    String? category,
    String? rejectionReason,
    String? firstName,
    String? lastName,
    String? documentNumber,
    String? dateOfBirth,
    String? placeOfBirth,
    String? expirationDate,
  }) async {
    final requestBody = <String, String>{'decision': decision};
    if (securityLevel != null) requestBody['security_level'] = securityLevel;
    if (category != null) requestBody['category'] = category;
    if (rejectionReason != null) {
      requestBody['rejection_reason'] = rejectionReason;
    }
    if (firstName?.trim().isNotEmpty == true) {
      requestBody['first_name'] = firstName!.trim();
    }
    if (lastName?.trim().isNotEmpty == true) {
      requestBody['last_name'] = lastName!.trim();
    }
    if (documentNumber?.trim().isNotEmpty == true) {
      requestBody['document_number'] = documentNumber!.trim();
    }
    if (dateOfBirth?.trim().isNotEmpty == true) {
      requestBody['date_of_birth'] = dateOfBirth!.trim();
    }
    if (placeOfBirth?.trim().isNotEmpty == true) {
      requestBody['place_of_birth'] = placeOfBirth!.trim();
    }
    if (expirationDate?.trim().isNotEmpty == true) {
      requestBody['expiration_date'] = expirationDate!.trim();
    }

    final response = _decodeResponse(
      await _client.post(
        Uri.parse(
          '$_baseUrl/api/admin/classification-requests/'
          '${Uri.encodeComponent(id)}/decision',
        ),
        headers: await _authenticatedHeaders(),
        body: jsonEncode(requestBody),
      ),
      expectedStatusCode: 200,
    );
    return ClassificationDecision(
      id: id,
      status: _requiredString(response, 'status'),
      securityLevel: response['security_level'] as String?,
      category: response['category'] as String?,
    );
  }

  Future<List<Map<String, dynamic>>> getMyClassificationRequests() async {
    final data = _decodeResponse(
      await _client.get(
        Uri.parse('$_baseUrl/api/classification-requests/mine'),
        headers: await _authenticatedHeaders(),
      ),
      expectedStatusCode: 200,
    );
    final requests = data['requests'];
    if (requests is! List) {
      throw const FormatException('Invalid classification requests response');
    }
    return requests
        .map((request) {
          if (request is! Map<String, dynamic>) {
            throw const FormatException('Invalid classification request');
          }
          return request;
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createShare({
    required String documentId,
    required Map<String, String> fields,
    required int durationMinutes,
    required Uint8List frontImageBytes,
    required String frontImageMimeType,
    Uint8List? backImageBytes,
    String? backImageMimeType,
  }) async {
    final response = _decodeResponse(
      await _client.post(
        Uri.parse('$_baseUrl/api/shares'),
        headers: await _authenticatedHeaders(),
        body: jsonEncode({
          'document_id': documentId,
          'fields': fields,
          'duration_minutes': durationMinutes,
          'front_image_base64': base64Encode(frontImageBytes),
          'front_image_mime_type': frontImageMimeType,
          if (backImageBytes != null && backImageMimeType != null) ...{
            'back_image_base64': base64Encode(backImageBytes),
            'back_image_mime_type': backImageMimeType,
          },
        }),
      ),
      expectedStatusCode: 201,
    );
    final share = response['share'];
    if (share is! Map<String, dynamic>) {
      throw const FormatException('Invalid document share response');
    }
    return share;
  }

  Future<List<Map<String, dynamic>>> getShares({
    required String documentId,
  }) async {
    final response = _decodeResponse(
      await _client.get(
        Uri.parse(
          '$_baseUrl/api/shares',
        ).replace(queryParameters: {'document_id': documentId}),
        headers: await _authenticatedHeaders(),
      ),
      expectedStatusCode: 200,
    );
    final shares = response['shares'];
    if (shares is! List) {
      throw const FormatException('Invalid document shares response');
    }
    return shares
        .map((share) {
          if (share is! Map<String, dynamic>) {
            throw const FormatException('Invalid document share');
          }
          return share;
        })
        .toList(growable: false);
  }

  Future<void> revokeShare(String id) async {
    _decodeResponse(
      await _client.delete(
        Uri.parse('$_baseUrl/api/shares/${Uri.encodeComponent(id)}'),
        headers: await _authenticatedHeaders(),
      ),
      expectedStatusCode: 200,
    );
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  /// Retourne les notifications de l'utilisateur connecté (max 50).
  /// Inclut aussi [unreadCount] dans le résultat brut.
  Future<({List<UserNotification> notifications, int unreadCount})>
  getMyNotifications() async {
    final data = _decodeResponse(
      await _client.get(
        Uri.parse('$_baseUrl/api/notifications'),
        headers: await _authenticatedHeaders(),
      ),
      expectedStatusCode: 200,
    );
    final raw = data['notifications'];
    final unreadCount = (data['unread_count'] as int?) ?? 0;
    if (raw is! List) {
      throw const FormatException('Invalid notifications response');
    }
    final notifications = raw
        .map((item) {
          if (item is! Map<String, dynamic>) {
            throw const FormatException('Invalid notification item');
          }
          return UserNotification.fromApi(item);
        })
        .toList(growable: false);
    return (notifications: notifications, unreadCount: unreadCount);
  }


  /// Marque toutes les notifications de l'utilisateur comme lues.
  Future<void> markAllNotificationsRead() async {
    _decodeResponse(
      await _client.post(
        Uri.parse('$_baseUrl/api/notifications/read-all'),
        headers: await _authenticatedHeaders(),
      ),
      expectedStatusCode: 200,
    );
  }

  /// Enregistre le token Firebase Cloud Messaging sur Cloudflare.
  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/api/push/register'),
      headers: await _authenticatedHeaders(),
      body: jsonEncode({
        'token': token,
        'platform': platform,
      }),
    );

    final data = _decodeResponse(
      response,
      expectedStatusCode: 200,
    );

    if (data['success'] != true) {
      throw const FormatException('FCM token registration failed');
    }
  }

  /// Retourne les 200 dernières entrées du journal admin.
  Future<List<Map<String, dynamic>>> getClassificationHistory() async {
    final data = _decodeResponse(
      await _client.get(
        Uri.parse('$_baseUrl/api/admin/classification-history'),
        headers: await _authenticatedHeaders(),
      ),
      expectedStatusCode: 200,
    );

    final history = data['history'];
    if (history is! List) return [];

    return history
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  List<ClassificationRequest> _parseRequests(Object? value) {
    if (value is! List) {
      throw const FormatException(
        'Invalid classification requests response',
      );
    }

    return value
        .map((request) {
          if (request is! Map<String, dynamic>) {
            throw const FormatException(
              'Invalid classification request',
            );
          }

          return ClassificationRequest.fromApi(request);
        })
        .toList(growable: false);
  }


  Future<Map<String, String>> _authenticatedHeaders() async {
    final token = await _getAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Une session Cloudflare est requise.');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Map<String, dynamic> _decodeResponse(
    http.Response response, {
    required int expectedStatusCode,
  }) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid API response');
    }
    if (response.statusCode != expectedStatusCode) {
      final error = decoded['error'];
      throw DocumentApiException(
        statusCode: response.statusCode,
        message: error is String
            ? error
            : 'Cloudflare API error (${response.statusCode})',
      );
    }
    return decoded;
  }

  String _requiredString(Map<String, dynamic> data, String field) {
    final value = data[field];
    if (value is! String || value.isEmpty) {
      throw FormatException('Invalid API response field: $field');
    }
    return value;
  }
}

class DocumentApiException implements Exception {
  const DocumentApiException({required this.statusCode, required this.message});

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}
