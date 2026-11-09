import 'dart:typed_data';

abstract interface class NationalIdExtractor {
  Future<Map<String, String?>> extract({
    required Uint8List imageBytes,
    required String mimeType,
  });
}
