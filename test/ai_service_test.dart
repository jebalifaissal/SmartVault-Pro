import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartvault_pro/models/document_type.dart';
import 'package:smartvault_pro/services/ai_service.dart';

void main() {
  late Directory tempDirectory;
  late File imageFile;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('smartvault-ai-');
    imageFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}document.jpg',
    );
    await imageFile.writeAsBytes([1, 2, 3]);
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test('sends an authenticated image and returns a validated type', () async {
    final service = AIService(
      callableUri: Uri.https(
        'us-central1-demo.cloudfunctions.net',
        '/classifyDocumentType',
      ),
      getIdToken: () async => 'test-id-token',
      httpClient: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer test-id-token');
        expect(request.headers['content-type'], 'application/json');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final data = payload['data'] as Map<String, dynamic>;
        expect(data['imageBase64'], 'AQID');
        expect(data['mimeType'], 'image/jpeg');
        return http.Response('{"result":{"category":"CIN"}}', 200);
      }),
    );

    expect(await service.classifyDocument(imageFile), DocumentType.cin);
  });

  test('rejects categories outside the supported enum', () async {
    final service = AIService(
      callableUri: Uri.https(
        'us-central1-demo.cloudfunctions.net',
        '/classifyDocumentType',
      ),
      getIdToken: () async => 'test-id-token',
      httpClient: MockClient(
        (_) async => http.Response('{"result":{"category":"BANK_CARD"}}', 200),
      ),
    );

    await expectLater(
      service.classifyDocument(imageFile),
      throwsA(isA<AIServiceException>()),
    );
  });

  test('rejects unsupported image formats before sending a request', () async {
    final textFile = File(
      '${tempDirectory.path}${Platform.pathSeparator}document.txt',
    );
    await textFile.writeAsString('not an image');
    final service = AIService(
      callableUri: Uri.https(
        'us-central1-demo.cloudfunctions.net',
        '/classifyDocumentType',
      ),
      getIdToken: () async => 'test-id-token',
      httpClient: MockClient((_) async {
        fail('The request must not be sent for an unsupported image format.');
      }),
    );

    await expectLater(
      service.classifyDocument(textFile),
      throwsA(isA<AIServiceException>()),
    );
  });
}
