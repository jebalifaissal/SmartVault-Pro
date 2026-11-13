import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smartvault_pro/features/documents/data/sqflite_local_document_repository.dart';
import 'package:smartvault_pro/features/documents/domain/document_security_classification.dart';
import 'package:smartvault_pro/features/documents/domain/vault_document.dart';
import 'package:smartvault_pro/models/document_type.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory root;
  late SqfliteLocalDocumentRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('smartvault-cin-test-');
    repository = SqfliteLocalDocumentRepository(
      databaseFactory: databaseFactoryFfi,
      documentsDirectoryProvider: () async => root,
    );
  });

  tearDown(() async {
    await repository.close();
    await root.delete(recursive: true);
  });

  test(
    'saves any document category and image locally, partitioned by user',
    () async {
      final saved = await repository.saveDocument(
        userId: 'user-a',
        document: _document('passport-one', category: 'Passeport'),
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        imageMimeType: 'image/jpeg',
      );

      expect(saved.localImagePath, isNotNull);
      expect(await File(saved.localImagePath!).readAsBytes(), [1, 2, 3, 4]);
      final userDocuments = await repository.watchDocuments('user-a').first;
      expect(userDocuments.map((document) => document.id), [saved.id]);
      expect(userDocuments.single.cinNumber, '00000000');
      expect(userDocuments.single.category, 'Passeport');
      expect(userDocuments.single.isLocal, isTrue);
      expect(await repository.watchDocuments('user-b').first, isEmpty);
    },
  );

  test(
    'saves no-image manual documents and prevents retry duplicates after reopen',
    () async {
      final firstSave = await repository.saveDocument(
        userId: 'user-a',
        document: _document('cin-retry'),
      );
      final retry = await repository.saveDocument(
        userId: 'user-a',
        document: _document('cin-retry'),
      );

      expect(retry.localImagePath, isNull);
      expect(retry.isLocal, isTrue);
      await repository.close();
      repository = SqfliteLocalDocumentRepository(
        databaseFactory: databaseFactoryFfi,
        documentsDirectoryProvider: () async => root,
      );
      final loaded = await repository.watchDocuments('user-a').first;
      expect(loaded, hasLength(1));
      expect(loaded.single.id, firstSave.id);
      expect(loaded.single.localImagePath, isNull);
    },
  );

  test('supports every existing wallet category', () async {
    const categories = [
      'Pièce d’identité',
      'Passeport',
      'Diplôme',
      'Permis de conduire',
      'Autres',
    ];
    for (var index = 0; index < categories.length; index++) {
      final saved = await repository.saveDocument(
        userId: 'user-categories',
        document: _document('category-$index', category: categories[index]),
      );
      expect(saved.category, categories[index]);
      expect(saved.isLocal, isTrue);
    }

    expect(
      await repository.watchDocuments('user-categories').first,
      hasLength(categories.length),
    );
  });

  test('deletes the local database row and its image', () async {
    final saved = await repository.saveDocument(
      userId: 'user-a',
      document: _document('cin-delete'),
      imageBytes: Uint8List.fromList([8, 9]),
      imageMimeType: 'image/jpeg',
    );

    await repository.deleteDocument(userId: 'user-a', documentId: saved.id);

    expect(await repository.watchDocuments('user-a').first, isEmpty);
    expect(await File(saved.localImagePath!).exists(), isFalse);
  });

  test('updates a local document without losing its image path', () async {
    final saved = await repository.saveDocument(
      userId: 'user-a',
      document: _document('cin-update'),
      imageBytes: Uint8List.fromList([5, 6]),
      imageMimeType: 'image/jpeg',
    );

    final updated = await repository.updateDocument(
      userId: 'user-a',
      document: _document(
        'cin-update',
      ).copyWith(title: 'Carte mise à jour', status: 'pending_admin'),
    );
    final loaded = await repository.watchDocuments('user-a').first;

    expect(updated.title, 'Carte mise à jour');
    expect(updated.status, 'pending_admin');
    expect(updated.localImagePath, saved.localImagePath);
    expect(updated.isLocal, isTrue);
    expect(loaded.single.title, updated.title);
    expect(loaded.single.localImagePath, saved.localImagePath);
    await expectLater(
      repository.updateDocument(
        userId: 'user-b',
        document: _document('cin-update'),
      ),
      throwsStateError,
    );
  });

  test(
    'keeps a pending classification out of the vault until approval',
    () async {
      final image = Uint8List.fromList([7, 8, 9]);
      await repository.stageClassificationRequest(
        userId: 'user-a',
        id: 'pending-cin',
        title: 'Carte nationale',
        message: 'Classer cette pièce',
        documentType: 'CIN',
        imageBytes: image,
        imageMimeType: 'image/jpeg',
      );

      expect(await repository.watchDocuments('user-a').first, isEmpty);
      var pending = await repository.pendingClassificationRequests('user-a');
      expect(pending, hasLength(1));
      expect(await File(pending.single.imagePath).readAsBytes(), image);
      expect(pending.single.isSubmitted, isFalse);

      await repository.markClassificationRequestSubmitted(
        userId: 'user-a',
        id: 'pending-cin',
      );
      await repository.close();
      repository = SqfliteLocalDocumentRepository(
        databaseFactory: databaseFactoryFfi,
        documentsDirectoryProvider: () async => root,
      );
      pending = await repository.pendingClassificationRequests('user-a');
      expect(pending.single.isSubmitted, isTrue);
      expect(await repository.watchDocuments('user-a').first, isEmpty);

      final approved = await repository.completeClassificationRequest(
        userId: 'user-a',
        id: 'pending-cin',
        category: 'Pièce d’identité',
        securityLevel: DocumentSecurityLevel.high,
        firstName: 'Faissal',
        lastName: 'Jebali',
        documentNumber: '12345678',
        dateOfBirth: '2000-01-02',
        placeOfBirth: 'Gabès',
        expirationDate: DateTime(2030, 5, 10),
      );
      final documents = await repository.watchDocuments('user-a').first;

      expect(documents, hasLength(1));
      expect(approved.id, 'pending-cin');
      expect(approved.securityLevel, DocumentSecurityLevel.high);
      expect(approved.holderName, 'Faissal Jebali');
      expect(approved.firstName, 'Faissal');
      expect(approved.lastName, 'Jebali');
      expect(approved.cinNumber, '12345678');
      expect(approved.dateOfBirth, '2000-01-02');
      expect(approved.placeOfBirth, 'Gabès');
      expect(approved.expiryDate, DateTime(2030, 5, 10));
      expect(
        approved.classificationStatus,
        DocumentClassificationStatus.adminReviewed,
      );
      expect(await File(approved.localImagePath!).readAsBytes(), image);
      expect(await repository.pendingClassificationRequests('user-a'), isEmpty);
    },
  );

  test(
    'removes a rejected pending photo without adding a vault document',
    () async {
      await repository.stageClassificationRequest(
        userId: 'user-a',
        id: 'rejected-cin',
        title: 'Carte nationale',
        message: '',
        documentType: 'CIN',
        imageBytes: Uint8List.fromList([1, 2]),
        imageMimeType: 'image/jpeg',
      );
      final pending = await repository.pendingClassificationRequests('user-a');

      await repository.removeClassificationRequest(
        userId: 'user-a',
        id: 'rejected-cin',
      );

      expect(await File(pending.single.imagePath).exists(), isFalse);
      expect(await repository.pendingClassificationRequests('user-a'), isEmpty);
      expect(await repository.watchDocuments('user-a').first, isEmpty);
    },
  );

  test('persists security classification fields in SQLite', () async {
    final classification = classifyDocumentSecurity(DocumentType.passport);
    final saved = await repository.saveDocument(
      userId: 'user-a',
      document: _document('passport-security').copyWith(
        securityLevel: classification.level,
        classificationStatus: classification.status,
        classificationSource: classification.source,
      ),
    );

    await repository.close();
    repository = SqfliteLocalDocumentRepository(
      databaseFactory: databaseFactoryFfi,
      documentsDirectoryProvider: () async => root,
    );
    final loaded = await repository.watchDocuments('user-a').first;

    expect(saved.securityLevel, DocumentSecurityLevel.high);
    expect(loaded.single.securityLevel, DocumentSecurityLevel.high);
    expect(
      loaded.single.classificationStatus,
      DocumentClassificationStatus.autoClassified,
    );
    expect(
      loaded.single.classificationSource,
      DocumentClassificationSource.automatic,
    );
  });

  test(
    'migrates existing version-one CIN rows without losing the image path',
    () async {
      final oldDatabase = await databaseFactoryFfi.openDatabase(
        '${root.path}${Platform.pathSeparator}smartvault_local_documents.db',
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (database, version) async {
            await database.execute('''
            CREATE TABLE documents (
              id TEXT PRIMARY KEY NOT NULL,
              user_id TEXT NOT NULL,
              document_type TEXT NOT NULL CHECK (document_type = 'CIN'),
              first_name TEXT,
              last_name TEXT,
              cin_number TEXT,
              date_of_birth TEXT,
              place_of_birth TEXT,
              expiration_date TEXT,
              image_path TEXT NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
            await database.execute(
              'CREATE INDEX documents_user_created '
              'ON documents (user_id, created_at DESC)',
            );
          },
        ),
      );
      final oldImage = File('${root.path}${Platform.pathSeparator}old-cin.jpg');
      await oldImage.writeAsBytes([1, 2, 3]);
      await oldDatabase.insert('documents', {
        'id': 'old-cin',
        'user_id': 'user-a',
        'document_type': 'CIN',
        'first_name': 'AMINA',
        'last_name': 'TRABELSI',
        'cin_number': '12345678',
        'date_of_birth': '1990-05-17',
        'place_of_birth': 'TUNIS',
        'expiration_date': '2030-05-17T00:00:00.000',
        'image_path': oldImage.path,
        'created_at': '2026-01-02T00:00:00.000',
      });
      await oldDatabase.close();

      final documents = await repository.watchDocuments('user-a').first;

      expect(documents, hasLength(1));
      expect(documents.single.id, 'old-cin');
      expect(documents.single.category, 'Pièce d’identité');
      expect(documents.single.firstName, 'AMINA');
      expect(documents.single.cinNumber, '12345678');
      expect(documents.single.isLocal, isTrue);
      expect(documents.single.localImagePath, oldImage.path);
      expect(documents.single.securityLevel, DocumentSecurityLevel.high);
      expect(
        documents.single.classificationStatus,
        DocumentClassificationStatus.autoClassified,
      );
    },
  );
}

VaultDocument _document(String id, {String category = 'Pièce d’identité'}) {
  final now = DateTime(2026, 1, 2);
  return VaultDocument(
    id: id,
    title: category == 'Passeport' ? 'Passeport' : 'Carte nationale d’identité',
    category: category,
    holderName: 'Test User',
    createdAt: now,
    updatedAt: now,
    documentType: switch (category) {
      'Pièce d’identité' => 'CIN',
      'Passeport' => 'PASSPORT',
      'Diplôme' => 'CERTIFICATE',
      'Permis de conduire' => 'DRIVING_LICENSE',
      _ => 'OTHER',
    },
    fullName: 'Test User',
    firstName: 'Test',
    lastName: 'User',
    cinNumber: '00000000',
    dateOfBirth: '1990-01-02',
    placeOfBirth: 'Tunis',
    status: 'verified_by_user',
  );
}
