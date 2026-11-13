import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartvault_pro/app/smart_vault_app.dart';
import 'package:smartvault_pro/features/documents/domain/national_id_ocr.dart';
import 'package:smartvault_pro/features/documents/domain/vault_document.dart';
import 'package:smartvault_pro/features/documents/presentation/cin_confirmation_screen.dart';

void main() {
  testWidgets('prefills editable OCR fields and saves user corrections', (
    WidgetTester tester,
  ) async {
    VaultDocument? savedDocument;
    await tester.pumpWidget(
      SmartVaultMaterialApp(
        home: CinConfirmationScreen(
          onSaveCin: (document, imageBytes, imageMimeType, [backImageBytes, backImageMimeType]) async {
            savedDocument = document;
            return document;
          },
          imageBytes: Uint8List.fromList(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/pWQAAAAASUVORK5CYII=',
            ),
          ),
          imageMimeType: 'image/png',
          ocrResult: const NationalIdOcrResult(
            firstName: 'AMINA',
            lastName: 'TRABELSI',
            documentNumber: '12345678',
            dateOfBirth: '1990-05-17',
            placeOfBirth: 'TUNIS',
            expirationDate: '2030-05-17',
          ),
        ),
      ),
    );

    expect(find.text('Prénom(s)'), findsOneWidget);
    final textFields = tester.widgetList<TextField>(find.byType(TextField));
    expect(textFields.map((field) => field.controller!.text), [
      'AMINA',
      'TRABELSI',
      '12345678',
      '1990-05-17',
      'TUNIS',
    ]);
    expect(find.text('17/05/2030'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'AMINA MODIFIÉE');
    await tester.ensureVisible(find.text('Oui, confirmer'));
    await tester.tap(find.text('Oui, confirmer'));
    await tester.pumpAndSettle();

    expect(savedDocument, isNotNull);
    expect(savedDocument!.firstName, 'AMINA MODIFIÉE');
    expect(savedDocument!.lastName, 'TRABELSI');
    expect(savedDocument!.cinNumber, '12345678');
    expect(savedDocument!.dateOfBirth, '1990-05-17');
    expect(savedDocument!.placeOfBirth, 'TUNIS');
    expect(savedDocument!.expirationDate, DateTime(2030, 5, 17));
  });
}
