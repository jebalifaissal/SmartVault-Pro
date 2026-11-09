import 'package:flutter_test/flutter_test.dart';
import 'package:smartvault_pro/features/documents/domain/national_id_text_parser.dart';

void main() {
  test('extracts labeled French CIN fields', () {
    final result = parseTunisianNationalIdText('''
N° CIN : 12345678
Nom : TRABELSI
Prénom(s) : AMINA
Date de naissance : 17/05/1990
Date d'expiration : 17/05/2030
Lieu de naissance : TUNIS
''');

    expect(result.firstName, 'AMINA');
    expect(result.lastName, 'TRABELSI');
    expect(result.dateOfBirth, '1990-05-17');
    expect(result.expirationDate, '2030-05-17');
    expect(result.placeOfBirth, 'TUNIS');
    expect(result.documentNumber, '12345678');
    expect(result.rawText, contains('N° CIN : 12345678'));
  });

  test('extracts Arabic fields and converts Arabic-Indic digits', () {
    final result = parseTunisianNationalIdText('''
الاسم: أمينة
اللقب: الطرابلسي
تاريخ الولادة: ١٧/٠٥/١٩٩٠
تاريخ انتهاء الصلاحية: ١٧/٠٥/٢٠٣٠
مكان الولادة: تونس
رقم بطاقة التعريف الوطنية: ١٢٣٤٥٦٧٨
''');

    expect(result.firstName, 'أمينة');
    expect(result.lastName, 'الطرابلسي');
    expect(result.dateOfBirth, '1990-05-17');
    expect(result.expirationDate, '2030-05-17');
    expect(result.placeOfBirth, 'تونس');
    expect(result.documentNumber, '12345678');
  });

  test('accepts fields on the line after their labels', () {
    final result = parseTunisianNationalIdText('''
Prénom
AMINA
Nom
TRABELSI
Date de naissance
17-05-1990
N° CIN
12345678
''');

    expect(result.firstName, 'AMINA');
    expect(result.lastName, 'TRABELSI');
    expect(result.dateOfBirth, '1990-05-17');
    expect(result.documentNumber, '12345678');
  });

  test('leaves unlabeled or invalid fields empty rather than guessing', () {
    final result = parseTunisianNationalIdText('''
AMINA TRABELSI
17/05/1990
12345678
Date de naissance: 31/02/1990
Date d’expiration: 31/02/2030
N° CIN: 1234567
Prénom: 123
''');

    expect(result.firstName, isNull);
    expect(result.lastName, isNull);
    expect(result.dateOfBirth, isNull);
    expect(result.expirationDate, isNull);
    expect(result.documentNumber, isNull);
  });

  test('extracts labeled passport fields without inferring missing values', () {
    final result = parsePassportText('''
PASSPORT NO: AB123456
SURNAME: TRABELSI
GIVEN NAMES: AMINA
DATE OF BIRTH: 17/05/1990
PLACE OF BIRTH: TUNIS
DATE OF EXPIRY: 17/05/2030
''');

    expect(result.documentNumber, 'AB123456');
    expect(result.lastName, 'TRABELSI');
    expect(result.firstName, 'AMINA');
    expect(result.dateOfBirth, '1990-05-17');
    expect(result.placeOfBirth, 'TUNIS');
    expect(result.expirationDate, '2030-05-17');
  });

  test('passport fields remain empty when no labels identify them', () {
    final result = parsePassportText('''
AMINA TRABELSI
17/05/1990
AB123456
''');

    expect(result.firstName, isNull);
    expect(result.lastName, isNull);
    expect(result.documentNumber, isNull);
    expect(result.dateOfBirth, isNull);
    expect(result.expirationDate, isNull);
  });
}
