import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../domain/document_security_classification.dart';
import '../domain/document_repository.dart';
import '../domain/local_cin_repository.dart';
import '../domain/vault_document.dart';

class SqfliteLocalDocumentRepository
    implements LocalDocumentRepository, DocumentRepository {
  SqfliteLocalDocumentRepository({
    DatabaseFactory? databaseFactory,
    Future<Directory> Function()? documentsDirectoryProvider,
  }) : _databaseFactory = databaseFactory ?? sqflite.databaseFactory,
       _documentsDirectoryProvider =
           documentsDirectoryProvider ?? getApplicationDocumentsDirectory;

  static const _databaseName = 'smartvault_local_documents.db';
  static const _tableName = 'documents';

  final DatabaseFactory _databaseFactory;
  final Future<Directory> Function() _documentsDirectoryProvider;
  final StreamController<void> _changes = StreamController<void>.broadcast(
    sync: true,
  );
  Future<Database>? _databaseOpening;

  @override
  Stream<List<VaultDocument>> watchDocuments(String userId) async* {
    yield await _loadDocuments(userId);
    yield* _changes.stream.asyncMap((_) => _loadDocuments(userId));
  }

  @override
  Future<VaultDocument> saveDocument({
    required String userId,
    required VaultDocument document,
    Uint8List? imageBytes,
    String? imageMimeType,
    Uint8List? backImageBytes,
    String? backImageMimeType,
  }) async {
    if (userId.trim().isEmpty || document.id.trim().isEmpty) {
      throw ArgumentError(
        'L’utilisateur et le document doivent être identifiés.',
      );
    }
    if (!VaultDocument.categories.contains(document.category)) {
      throw ArgumentError.value(document.category, 'category');
    }
    if ((imageBytes == null) != (imageMimeType == null)) {
      throw ArgumentError(
        'Données image et type MIME doivent être fournis ensemble.',
      );
    }
    if (imageBytes != null && imageBytes.isEmpty) {
      throw ArgumentError.value(imageBytes, 'imageBytes', 'La photo est vide.');
    }
    if ((backImageBytes == null) != (backImageMimeType == null)) {
      throw ArgumentError('Données Verso et type MIME doivent être fournis ensemble.');
    }
    if (backImageBytes != null && backImageBytes.isEmpty) {
      throw ArgumentError.value(backImageBytes, 'backImageBytes', 'La photo Verso est vide.');
    }
    if (backImageMimeType != null && backImageMimeType != 'image/jpeg' && backImageMimeType != 'image/png') {
      throw ArgumentError.value(backImageMimeType, 'backImageMimeType', 'Seules les images JPEG et PNG sont acceptées.');
    }
    if (imageMimeType != null &&
        imageMimeType != 'image/jpeg' &&
        imageMimeType != 'image/png') {
      throw ArgumentError.value(
        imageMimeType,
        'imageMimeType',
        'Seules les images JPEG et PNG sont acceptées.',
      );
    }

    late final Database database;
    late final List<Map<String, Object?>> existing;
    try {
      database = await _openDatabase();
      existing = await database.query(
        _tableName,
        where: 'id = ? AND user_id = ?',
        whereArgs: [document.id, userId],
        limit: 1,
      );
    } on DatabaseException catch (error) {
      throw LocalCinException(
        stage: LocalCinSaveStage.databaseWrite,
        cause: error,
      );
    }
    if (existing.isNotEmpty) return _fromDatabase(existing.first);

    File? copiedImage;
    File? copiedBackImage;
    if (imageBytes != null && imageMimeType != null) {
      try {
        final root = await _documentsDirectoryProvider();
        final userDirectory = Directory(
          '${root.path}${Platform.pathSeparator}documents'
          '${Platform.pathSeparator}${Uri.encodeComponent(userId)}',
        );
        await userDirectory.create(recursive: true);
        final extension = imageMimeType == 'image/png' ? 'png' : 'jpg';
        final imagePath =
            '${userDirectory.path}${Platform.pathSeparator}'
            '${Uri.encodeComponent(document.id)}.$extension';
        copiedImage = File(imagePath);
        await copiedImage.writeAsBytes(imageBytes, flush: true);
      } on FileSystemException catch (error) {
        Object? cleanupError;
        try {
          if (copiedImage != null && await copiedImage.exists()) {
            await copiedImage.delete();
          }
        } on FileSystemException catch (failure) {
          cleanupError = failure;
        }
        throw LocalCinException(
          stage: LocalCinSaveStage.imageCopy,
          cause: error,
          rollbackError: cleanupError,
        );
      }
    }

    if (backImageBytes != null && backImageMimeType != null) {
      try {
        final root = await _documentsDirectoryProvider();
        final userDirectory = Directory(
          '${root.path}${Platform.pathSeparator}documents'
          '${Platform.pathSeparator}${Uri.encodeComponent(userId)}',
        );
        await userDirectory.create(recursive: true);
        final extension = backImageMimeType == 'image/png' ? 'png' : 'jpg';
        copiedBackImage = File(
          '${userDirectory.path}${Platform.pathSeparator}'
          '${Uri.encodeComponent(document.id)}_verso.$extension',
        );
        await copiedBackImage.writeAsBytes(backImageBytes, flush: true);
      } on FileSystemException catch (error) {
        Object? cleanupError;
        try {
          if (copiedImage != null && await copiedImage.exists()) await copiedImage.delete();
          if (copiedBackImage != null && await copiedBackImage.exists()) await copiedBackImage.delete();
        } on FileSystemException catch (failure) { cleanupError = failure; }
        throw LocalCinException(stage: LocalCinSaveStage.imageCopy, cause: error, rollbackError: cleanupError);
      }
    }

    final savedDocument = document.copyWith(
      localImagePath: copiedImage?.path,
      localBackImagePath: copiedBackImage?.path,
      isLocal: true,
      updatedAt: DateTime.now(),
    );
    try {
      await database.transaction((transaction) async {
        await transaction.insert(
          _tableName,
          _toDatabase(userId, savedDocument),
        );
      });
    } on DatabaseException catch (error) {
      try {
        if (copiedImage != null) await copiedImage.delete();
        if (copiedBackImage != null) await copiedBackImage.delete();
      } on FileSystemException catch (cleanupError) {
        throw LocalCinException(
          stage: LocalCinSaveStage.databaseWrite,
          cause: error,
          rollbackError: cleanupError,
        );
      }
      throw LocalCinException(
        stage: LocalCinSaveStage.databaseWrite,
        cause: error,
      );
    }

    _changes.add(null);
    return savedDocument;
  }

  @override
  Future<VaultDocument> updateDocument({
    required String userId,
    required VaultDocument document,
  }) async {
    if (userId.trim().isEmpty || document.id.trim().isEmpty) {
      throw ArgumentError(
        'L’utilisateur et le document doivent être identifiés.',
      );
    }
    if (!VaultDocument.categories.contains(document.category)) {
      throw ArgumentError.value(document.category, 'category');
    }

    late final VaultDocument updatedDocument;
    try {
      final database = await _openDatabase();
      updatedDocument = await database.transaction((transaction) async {
        final existing = await transaction.query(
          _tableName,
          where: 'id = ? AND user_id = ?',
          whereArgs: [document.id, userId],
          limit: 1,
        );
        if (existing.isEmpty) {
          throw StateError(
            'Le document local n’existe pas pour cet utilisateur.',
          );
        }

        final savedDocument = document.copyWith(
          localImagePath:
              document.localImagePath ??
              existing.first['image_path'] as String?,
          localBackImagePath:
              document.localBackImagePath ??
              existing.first['back_image_path'] as String?,
          isLocal: true,
          updatedAt: DateTime.now(),
        );
        await transaction.update(
          _tableName,
          _toDatabase(userId, savedDocument),
          where: 'id = ? AND user_id = ?',
          whereArgs: [document.id, userId],
        );
        return savedDocument;
      });
    } on DatabaseException catch (error) {
      throw LocalCinException(
        stage: LocalCinSaveStage.databaseWrite,
        cause: error,
      );
    }

    _changes.add(null);
    return updatedDocument;
  }

  @override
  Future<void> stageClassificationRequest({
    required String userId,
    required String id,
    required String title,
    required String message,
    required String documentType,
    required Uint8List imageBytes,
    required String imageMimeType,
  }) async {
    if (userId.trim().isEmpty || id.trim().isEmpty || title.trim().isEmpty) {
      throw ArgumentError(
        'L’utilisateur, le document et son titre sont requis.',
      );
    }
    if (imageBytes.isEmpty ||
        (imageMimeType != 'image/jpeg' && imageMimeType != 'image/png')) {
      throw ArgumentError('Une image JPEG ou PNG non vide est requise.');
    }

    final root = await _documentsDirectoryProvider();
    final stagingDirectory = Directory(
      '${root.path}${Platform.pathSeparator}pending_classification'
      '${Platform.pathSeparator}${Uri.encodeComponent(userId)}',
    );
    await stagingDirectory.create(recursive: true);
    final extension = imageMimeType == 'image/png' ? 'png' : 'jpg';
    final imageFile = File(
      '${stagingDirectory.path}${Platform.pathSeparator}'
      '${Uri.encodeComponent(id)}.$extension',
    );
    await imageFile.writeAsBytes(imageBytes, flush: true);
    try {
      await (await _openDatabase()).insert(
        'pending_classification_requests',
        {
          'id': id,
          'user_id': userId,
          'title': title.trim(),
          'message': message.trim(),
          'document_type': documentType,
          'image_path': imageFile.path,
          'image_mime_type': imageMimeType,
          'is_submitted': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } on DatabaseException catch (error) {
      try {
        await imageFile.delete();
      } on FileSystemException catch (cleanupError) {
        throw LocalCinException(
          stage: LocalCinSaveStage.databaseWrite,
          cause: error,
          rollbackError: cleanupError,
        );
      }
      throw LocalCinException(
        stage: LocalCinSaveStage.databaseWrite,
        cause: error,
      );
    }
  }

  @override
  Future<List<PendingLocalClassification>> pendingClassificationRequests(
    String userId,
  ) async {
    final rows = await (await _openDatabase()).query(
      'pending_classification_requests',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    return rows
        .map(
          (row) => PendingLocalClassification(
            id: row['id'] as String,
            title: row['title'] as String,
            message: row['message'] as String,
            documentType: row['document_type'] as String,
            imagePath: row['image_path'] as String,
            imageMimeType: row['image_mime_type'] as String,
            isSubmitted: row['is_submitted'] == 1,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markClassificationRequestSubmitted({
    required String userId,
    required String id,
  }) async {
    await (await _openDatabase()).update(
      'pending_classification_requests',
      {'is_submitted': 1},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  @override
  Future<VaultDocument> completeClassificationRequest({
    required String userId,
    required String id,
    required String category,
    required DocumentSecurityLevel securityLevel,
    String? firstName,
    String? lastName,
    String? documentNumber,
    String? dateOfBirth,
    String? placeOfBirth,
    DateTime? expirationDate,
  }) async {
    if (!VaultDocument.categories.contains(category) ||
        securityLevel == DocumentSecurityLevel.pending) {
      throw ArgumentError('Le niveau et le container sont invalides.');
    }
    final database = await _openDatabase();
    final rows = await database.query(
      'pending_classification_requests',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
      limit: 1,
    );
    if (rows.isEmpty) throw StateError('La demande locale est introuvable.');
    final row = rows.first;
    final source = File(row['image_path'] as String);
    if (!await source.exists()) {
      throw FileSystemException(
        'La photo en attente est introuvable.',
        source.path,
      );
    }
    final root = await _documentsDirectoryProvider();
    final finalDirectory = Directory(
      '${root.path}${Platform.pathSeparator}documents'
      '${Platform.pathSeparator}${Uri.encodeComponent(userId)}',
    );
    await finalDirectory.create(recursive: true);
    final target = File(
      '${finalDirectory.path}${Platform.pathSeparator}'
      '${Uri.encodeComponent(id)}.${row['image_mime_type'] == 'image/png' ? 'png' : 'jpg'}',
    );
    await source.copy(target.path);
    final now = DateTime.now();
    final normalizedFirstName = firstName?.trim();
    final normalizedLastName = lastName?.trim();
    final fullName = [
      normalizedFirstName,
      normalizedLastName,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' ');
    final normalizedNumber = documentNumber?.trim();
    final document = VaultDocument(
      id: id,
      title: row['title'] as String,
      category: category,
      holderName: fullName.isNotEmpty ? fullName : 'À compléter',
      createdAt: now,
      updatedAt: now,
      documentType: category == 'Pièce d’identité'
          ? 'CIN'
          : row['document_type'] as String,
      firstName: normalizedFirstName,
      lastName: normalizedLastName,
      fullName: fullName.isEmpty ? null : fullName,
      documentNumber: normalizedNumber?.isEmpty == true
          ? null
          : normalizedNumber,
      cinNumber: category == 'Pièce d’identité' &&
              normalizedNumber?.isNotEmpty == true
          ? normalizedNumber
          : null,
      dateOfBirth: dateOfBirth?.trim(),
      placeOfBirth: placeOfBirth?.trim(),
      expirationDate: expirationDate,
      expiryDate: expirationDate,
      localImagePath: target.path,
      isLocal: true,
      status: 'verified_by_admin',
      securityLevel: securityLevel,
      classificationStatus: DocumentClassificationStatus.adminReviewed,
      classificationSource: DocumentClassificationSource.administrator,
    );
    try {
      await database.transaction((transaction) async {
        await transaction.insert(_tableName, _toDatabase(userId, document));
        await transaction.delete(
          'pending_classification_requests',
          where: 'id = ? AND user_id = ?',
          whereArgs: [id, userId],
        );
      });
    } on DatabaseException catch (error) {
      try {
        await target.delete();
      } on FileSystemException catch (cleanupError) {
        throw LocalCinException(
          stage: LocalCinSaveStage.databaseWrite,
          cause: error,
          rollbackError: cleanupError,
        );
      }
      throw LocalCinException(
        stage: LocalCinSaveStage.databaseWrite,
        cause: error,
      );
    }
    try {
      await source.delete();
    } on FileSystemException catch (error) {
      throw LocalCinException(
        stage: LocalCinSaveStage.imageDelete,
        cause: error,
      );
    }
    _changes.add(null);
    return document;
  }

  @override
  Future<void> removeClassificationRequest({
    required String userId,
    required String id,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      'pending_classification_requests',
      columns: ['image_path'],
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final imageFile = File(rows.first['image_path'] as String);
    await database.delete(
      'pending_classification_requests',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
    try {
      if (await imageFile.exists()) await imageFile.delete();
    } on FileSystemException catch (error) {
      throw LocalCinException(
        stage: LocalCinSaveStage.imageDelete,
        cause: error,
      );
    }
  }

  @override
  Future<void> deleteDocument({
    required String userId,
    required String documentId,
  }) async {
    final database = await _openDatabase();
    final rows = await database.query(
      _tableName,
      where: 'id = ? AND user_id = ?',
      whereArgs: [documentId, userId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = rows.first;
    await database.transaction(
      (transaction) => transaction.delete(
        _tableName,
        where: 'id = ? AND user_id = ?',
        whereArgs: [documentId, userId],
      ),
    );

    final imagePath = row['image_path'] as String?;
    final backImagePath = row['back_image_path'] as String?;
    try {
      if (imagePath != null) {
        final imageFile = File(imagePath);
        if (await imageFile.exists()) await imageFile.delete();
      }
      if (backImagePath != null) {
        final backImageFile = File(backImagePath);
        if (await backImageFile.exists()) await backImageFile.delete();
      }
    } on FileSystemException catch (error) {
      try {
        await database.insert(_tableName, row);
      } on DatabaseException catch (rollbackError) {
        throw LocalCinException(
          stage: LocalCinSaveStage.imageDelete,
          cause: error,
          rollbackError: rollbackError,
        );
      }
      throw LocalCinException(
        stage: LocalCinSaveStage.imageDelete,
        cause: error,
      );
    }
    _changes.add(null);
  }

  Future<void> close() async {
    final opening = _databaseOpening;
    if (opening == null) return;
    await (await opening).close();
    _databaseOpening = null;
  }

  Future<List<VaultDocument>> _loadDocuments(String userId) async {
    final rows = await (await _openDatabase()).query(
      _tableName,
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromDatabase).toList(growable: false);
  }

  Future<Database> _openDatabase() async {
    final opening = _databaseOpening ??= _createDatabase();
    try {
      return await opening;
    } catch (_) {
      if (identical(_databaseOpening, opening)) _databaseOpening = null;
      rethrow;
    }
  }

  Future<Database> _createDatabase() async {
    final root = await _documentsDirectoryProvider();
    final path = '${root.path}${Platform.pathSeparator}$_databaseName';
    return _databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (database, version) async {
          await _createDocumentsTable(database, _tableName);
          await _createDocumentIndex(database);
          await _createPendingClassificationTable(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await _migrateCinTable(database);
          } else if (oldVersion < 3) {
            await _addSecurityClassificationColumns(database);
          }
          if (oldVersion < 4) {
            await _createPendingClassificationTable(database);
          }
          if (oldVersion < 5) {
            await database.execute('ALTER TABLE $_tableName ADD COLUMN back_image_path TEXT');
          }
        },
      ),
    );
  }

  Future<void> _createPendingClassificationTable(DatabaseExecutor database) =>
      database.execute('''
    CREATE TABLE pending_classification_requests (
      id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      message TEXT NOT NULL,
      document_type TEXT NOT NULL,
      image_path TEXT NOT NULL,
      image_mime_type TEXT NOT NULL,
      is_submitted INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (id, user_id)
    )
  ''');

  Future<void> _addSecurityClassificationColumns(
    DatabaseExecutor database,
  ) async {
    await database.execute(
      "ALTER TABLE $_tableName ADD COLUMN security_level TEXT NOT NULL "
      "DEFAULT 'PENDING'",
    );
    await database.execute(
      "ALTER TABLE $_tableName ADD COLUMN classification_status TEXT NOT NULL "
      "DEFAULT 'PENDING'",
    );
    await database.execute(
      "ALTER TABLE $_tableName ADD COLUMN classification_source TEXT NOT NULL "
      "DEFAULT 'AUTOMATIC'",
    );
    await database.execute('''
      UPDATE $_tableName
      SET security_level = CASE
            WHEN category IN ('Pièce d’identité', 'Passeport', 'Permis de conduire')
              THEN 'HIGH'
            WHEN category IN ('Diplôme', 'Cours', 'Notes', 'Informations')
              THEN 'MEDIUM'
            ELSE 'PENDING'
          END,
          classification_status = CASE
            WHEN category IN (
              'Pièce d’identité', 'Passeport', 'Permis de conduire',
              'Diplôme', 'Cours', 'Notes', 'Informations'
            ) THEN 'AUTO_CLASSIFIED'
            ELSE 'PENDING'
          END
    ''');
  }

  Future<void> _migrateCinTable(DatabaseExecutor database) async {
    await _createDocumentsTable(database, 'documents_v2');
    await database.execute('''
      INSERT INTO documents_v2 (
        id, user_id, title, category, holder_name, document_type,
        first_name, last_name, full_name, document_number, cin_number,
        date_of_birth, place_of_birth, expiry_date, image_path,
        created_at, updated_at, status, security_level,
        classification_status, classification_source
      )
      SELECT id, user_id, 'Carte nationale d’identité', 'Pièce d’identité',
        trim(COALESCE(first_name, '') || ' ' || COALESCE(last_name, '')),
        document_type, first_name, last_name, NULL, cin_number, cin_number,
        date_of_birth, place_of_birth, expiration_date, image_path,
        created_at, created_at, 'verified_by_user',
        'HIGH', 'AUTO_CLASSIFIED', 'AUTOMATIC'
      FROM documents
    ''');
    await database.execute('DROP TABLE documents');
    await database.execute('ALTER TABLE documents_v2 RENAME TO documents');
    await _createDocumentIndex(database);
  }

  Future<void> _createDocumentsTable(
    DatabaseExecutor database,
    String tableName,
  ) => database.execute('''
    CREATE TABLE $tableName (
      id TEXT NOT NULL,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      category TEXT NOT NULL,
      holder_name TEXT NOT NULL,
      document_type TEXT,
      first_name TEXT,
      last_name TEXT,
      full_name TEXT,
      document_number TEXT,
      cin_number TEXT,
      date_of_birth TEXT,
      place_of_birth TEXT,
      expiry_date TEXT,
      image_path TEXT,
      back_image_path TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      status TEXT,
      security_level TEXT NOT NULL DEFAULT 'PENDING',
      classification_status TEXT NOT NULL DEFAULT 'PENDING',
      classification_source TEXT NOT NULL DEFAULT 'AUTOMATIC',
      PRIMARY KEY (id, user_id)
    )
  ''');

  Future<void> _createDocumentIndex(DatabaseExecutor database) =>
      database.execute(
        'CREATE INDEX documents_user_created '
        'ON $_tableName (user_id, created_at DESC)',
      );

  Map<String, Object?> _toDatabase(String userId, VaultDocument document) => {
    'id': document.id,
    'user_id': userId,
    'title': document.title,
    'category': document.category,
    'holder_name': document.holderName,
    'document_type': document.documentType,
    'first_name': document.firstName ?? document.name,
    'last_name': document.lastName ?? document.surname,
    'full_name': document.fullName,
    'document_number': document.documentNumber,
    'cin_number': document.cinNumber,
    'date_of_birth': document.dateOfBirth,
    'place_of_birth': document.placeOfBirth,
    'expiry_date': (document.expirationDate ?? document.expiryDate)
        ?.toIso8601String(),
    'image_path': document.localImagePath,
    'back_image_path': document.localBackImagePath,
    'created_at': document.createdAt.toIso8601String(),
    'updated_at': (document.updatedAt ?? document.createdAt).toIso8601String(),
    'status': document.status,
    'security_level': document.securityLevel.databaseValue,
    'classification_status': document.classificationStatus.databaseValue,
    'classification_source': document.classificationSource.databaseValue,
  };

  VaultDocument _fromDatabase(Map<String, Object?> row) {
    final firstName = row['first_name'] as String?;
    final lastName = row['last_name'] as String?;
    final fullName =
        row['full_name'] as String? ??
        [
          firstName,
          lastName,
        ].whereType<String>().where((value) => value.isNotEmpty).join(' ');
    final createdAt = DateTime.parse(row['created_at'] as String);
    final updatedAt = DateTime.parse(row['updated_at'] as String);
    final expiryDate = row['expiry_date'] as String?;
    final documentNumber = row['document_number'] as String?;

    return VaultDocument(
      id: row['id'] as String,
      title: row['title'] as String,
      category: row['category'] as String,
      holderName: row['holder_name'] as String,
      createdAt: createdAt,
      updatedAt: updatedAt,
      documentType: row['document_type'] as String?,
      fullName: fullName,
      firstName: firstName,
      lastName: lastName,
      cinNumber: row['cin_number'] as String? ?? documentNumber,
      documentNumber: documentNumber,
      dateOfBirth: row['date_of_birth'] as String?,
      placeOfBirth: row['place_of_birth'] as String?,
      expirationDate: expiryDate == null ? null : DateTime.parse(expiryDate),
      expiryDate: expiryDate == null ? null : DateTime.parse(expiryDate),
      localImagePath: row['image_path'] as String?,
      localBackImagePath: row['back_image_path'] as String?,
      isLocal: true,
      name: firstName,
      surname: lastName,
      status: row['status'] as String?,
      securityLevel: DocumentSecurityLevel.fromDatabaseValue(
        row['security_level'] as String,
      ),
      classificationStatus: DocumentClassificationStatus.fromDatabaseValue(
        row['classification_status'] as String,
      ),
      classificationSource: DocumentClassificationSource.fromDatabaseValue(
        row['classification_source'] as String,
      ),
    );
  }
}
