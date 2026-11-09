import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartvault_pro/features/documents/data/tesseract_national_id_ocr.dart';

void main() {
  final ocr = TesseractNationalIdOcr();

  test('rejects an empty image path before invoking Tesseract', () async {
    await expectLater(ocr.extract(' '), throwsArgumentError);
  });

  test('reports a missing photo before invoking Tesseract', () async {
    final directory = await Directory.systemTemp.createTemp('smartvault_ocr_');
    addTearDown(() => directory.delete(recursive: true));
    final missingImage =
        '${directory.path}${Platform.pathSeparator}missing.jpg';

    await expectLater(
      ocr.extract(missingImage),
      throwsA(isA<FileSystemException>()),
    );
  });
}
