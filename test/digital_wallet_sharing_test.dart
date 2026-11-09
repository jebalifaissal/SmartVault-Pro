import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartvault_pro/features/documents/domain/vault_document.dart';
import 'package:smartvault_pro/features/documents/presentation/digital_wallet_screen.dart';

void main() {
  testWidgets('requires explicit field selection before creating a share', (
    tester,
  ) async {
    final document = VaultDocument(
      id: 'passport-local-1',
      title: 'Passeport de test',
      category: 'Passeport',
      holderName: 'Sana Ben Ali',
      firstName: 'Sana',
      lastName: 'Ben Ali',
      documentNumber: 'AB123456',
      dateOfBirth: '1990-05-17',
      placeOfBirth: 'Tunis',
      createdAt: DateTime(2026, 1, 1),
      isLocal: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DigitalWalletScreen(
            documents: [document],
            onAddDocument: () {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Passeport de test'));
    await tester.pumpAndSettle();

    expect(find.text('Partager temporairement'), findsOneWidget);
    expect(find.text('Partager par QR Code'), findsOneWidget);
    expect(find.text('Partager par lien'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(7));

    final createButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Partager par QR Code'),
    );
    expect(createButton.onPressed, isNull);

    final firstNameOption = find.widgetWithText(CheckboxListTile, 'Prénom');
    await tester.ensureVisible(firstNameOption);
    await tester.pumpAndSettle();
    await tester.tap(firstNameOption);
    await tester.pumpAndSettle();
    final enabledButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Partager par QR Code'),
    );
    expect(enabledButton.onPressed, isNotNull);
  });
}
