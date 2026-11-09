import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartvault_pro/services/document_api_service.dart';

void main() {
  test(
    'submits classification metadata without transmitting the image',
    () async {
      final service = DocumentApiService(
        getAccessToken: () async => 'test-session-token',
        baseUrl: 'https://example.com',
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/classification-requests');
          expect(request.headers['authorization'], 'Bearer test-session-token');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body, {
            'id': 'request-1',
            'title': 'Passport',
            'message': 'Please review',
            'document_type': 'PASSPORT',
          });
          expect(body, isNot(contains('image_base64')));
          expect(body, isNot(contains('image_mime_type')));
          return http.Response('{"success":true,"status":"PENDING"}', 201);
        }),
      );

      await service.submitClassificationRequest(
        id: 'request-1',
        title: 'Passport',
        message: 'Please review',
        documentType: 'PASSPORT',
      );
    },
  );
}
