import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import '../models/document_type.dart';

typedef AuthTokenProvider = Future<String?> Function();

class AIService {
  AIService({
    required Uri callableUri,
    required AuthTokenProvider getIdToken,
    http.Client? httpClient,
    this.requestTimeout = const Duration(seconds: 45),
    this.maxImageBytes = 6 * 1024 * 1024,
  }) : _callableUri = callableUri,
       _getIdToken = getIdToken,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null {
    if (_callableUri.scheme != 'https' &&
        !(_callableUri.scheme == 'http' &&
            (_callableUri.host == 'localhost' ||
                _callableUri.host == '127.0.0.1'))) {
      throw ArgumentError.value(
        callableUri,
        'callableUri',
        'Use HTTPS for the secure backend URL.',
      );
    }
  }

  final Uri _callableUri;
  final AuthTokenProvider _getIdToken;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  final Duration requestTimeout;
  final int maxImageBytes;

  /// Sends an image to the authenticated backend and returns its validated type.
  ///
  /// The backend is responsible for calling Gemini. The Gemini API key must
  /// never be added to this Flutter app.
  Future<DocumentType> classifyDocument(File imageFile) async {
    late final List<int> imageBytes;
    try {
      if (!await imageFile.exists()) {
        throw const AIServiceException(
          'The selected image could not be found.',
        );
      }
      imageBytes = await imageFile.readAsBytes();
    } on AIServiceException {
      rethrow;
    } on FileSystemException {
      throw const AIServiceException('The selected image could not be read.');
    }

    if (imageBytes.isEmpty) {
      throw const AIServiceException('The selected image is empty.');
    }
    if (imageBytes.length > maxImageBytes) {
      throw const AIServiceException('Choose an image smaller than 6 MB.');
    }

    final mimeType = lookupMimeType(imageFile.path);
    if (mimeType != 'image/jpeg' && mimeType != 'image/png') {
      throw const AIServiceException('Choose a JPEG or PNG image.');
    }

    final idToken = await _getIdToken();
    if (idToken == null || idToken.isEmpty) {
      throw const AIServiceException('Sign in before classifying a document.');
    }

    late final http.Response response;
    try {
      response = await _httpClient
          .post(
            _callableUri,
            headers: {
              HttpHeaders.authorizationHeader: 'Bearer $idToken',
              HttpHeaders.contentTypeHeader: 'application/json',
            },
            body: jsonEncode({
              'data': {
                'imageBase64': base64Encode(imageBytes),
                'mimeType': mimeType,
              },
            }),
          )
          .timeout(requestTimeout);
    } on TimeoutException {
      throw const AIServiceException(
        'Document classification timed out. Please try again.',
      );
    } on SocketException {
      throw const AIServiceException(
        'Could not connect to the classification service. Check your internet connection.',
      );
    } on http.ClientException {
      throw const AIServiceException(
        'Could not send the image to the classification service.',
      );
    }

    final Map<String, dynamic> responseBody;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }
      responseBody = decoded;
    } on FormatException {
      throw const AIServiceException(
        'The classification service returned an invalid response.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = responseBody['error'];
      final message = error is Map<String, dynamic> ? error['message'] : null;
      throw AIServiceException(
        message is String && message.isNotEmpty
            ? message
            : 'The classification service returned an error '
                  '(${response.statusCode}).',
      );
    }

    final result = responseBody['result'] ?? responseBody['data'];
    if (result is! Map<String, dynamic>) {
      throw const AIServiceException(
        'The classification response is missing its result.',
      );
    }

    final category = result['category'];
    if (category is! String) {
      throw const AIServiceException(
        'The service returned an unsupported document category.',
      );
    }
    try {
      return DocumentType.fromApiValue(category);
    } on FormatException {
      throw const AIServiceException(
        'The service returned an unsupported document category.',
      );
    }
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}

class AIServiceException implements Exception {
  const AIServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}
