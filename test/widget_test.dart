import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartvault_pro/app/smart_vault_app.dart';
import 'package:smartvault_pro/features/auth/domain/auth_exception.dart';
import 'package:smartvault_pro/features/auth/domain/auth_repository.dart';
import 'package:smartvault_pro/features/auth/domain/auth_user.dart';
import 'package:smartvault_pro/features/auth/presentation/auth_gate.dart';
import 'package:smartvault_pro/features/auth/presentation/idle_session_gate.dart';
import 'package:smartvault_pro/features/auth/presentation/session_lock_activity.dart';
import 'package:smartvault_pro/features/documents/domain/document_repository.dart';
import 'package:smartvault_pro/features/documents/domain/vault_document.dart';
import 'package:smartvault_pro/features/documents/presentation/review_document_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('affiche l’accueil vidéo avant le formulaire de connexion', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();

    expect(find.text('Commencer'), findsOneWidget);
    expect(
      find.textContaining('assets/videos/smartvault_intro.mp4'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Commencer'));
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(find.text('Ravi de vous revoir'), findsOneWidget);
  });

  testWidgets('affiche le formulaire de connexion', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    expect(find.text('Ravi de vous revoir'), findsOneWidget);
    expect(find.text('Adresse e-mail'), findsOneWidget);
    expect(find.text('Mot de passe'), findsOneWidget);
    expect(find.text('Se connecter'), findsOneWidget);
  });

  testWidgets('valide les champs requis', (WidgetTester tester) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);
    await tester.ensureVisible(find.text('Se connecter'));
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(find.text('Champ obligatoire.'), findsNWidgets(2));
  });

  testWidgets('permet de masquer et afficher le mot de passe', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    await tester.ensureVisible(find.byTooltip('Afficher le mot de passe'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Afficher le mot de passe'), findsOneWidget);
    await tester.tap(find.byTooltip('Afficher le mot de passe'));
    await tester.pump();
    expect(find.byTooltip('Masquer le mot de passe'), findsOneWidget);
  });

  testWidgets('connecte un utilisateur et affiche son espace', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository();
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    await tester.enterText(find.byType(EditableText).first, 'lea@example.com');
    await tester.enterText(find.byType(EditableText).last, 'motdepasse123');
    await tester.ensureVisible(find.text('Se connecter'));
    await tester.tap(find.text('Se connecter'));
    await tester.pumpAndSettle();

    expect(repository.lastEmail, 'lea@example.com');
    expect(find.text('Bonjour, Léa'), findsOneWidget);
    expect(find.text('Mon portefeuille'), findsOneWidget);
    expect(find.text('Ajouter un document'), findsOneWidget);
    await _scrollToText(tester, 'Votre portefeuille est vide');
    expect(find.text('Votre portefeuille est vide'), findsOneWidget);
  });

  testWidgets('affiche le tableau de bord pour une session existante', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'existing-user',
        email: 'lea@example.com',
        displayName: 'Léa Martin',
      );
    final documentsRepository = _FakeDocumentRepository();
    addTearDown(repository.dispose);
    addTearDown(documentsRepository.dispose);
    await _pumpApp(
      tester,
      repository,
      documentsRepository: documentsRepository,
    );

    expect(find.text('Bonjour, Léa'), findsOneWidget);
    expect(find.text('Accès rapide'), findsOneWidget);
    await _scrollToText(tester, 'Ajoutés récemment');
    expect(find.text('Ajoutés récemment'), findsOneWidget);
    expect(find.text('Votre portefeuille est vide'), findsOneWidget);
  });

  testWidgets(
    'ouvre le parcours local de classification depuis le tableau de bord',
    (WidgetTester tester) async {
      final repository = _FakeAuthRepository()
        ..currentUser = const AuthUser(
          id: 'scanner-user',
          email: 'lea@example.com',
          displayName: 'Léa Martin',
        );
      addTearDown(repository.dispose);
      await _pumpApp(tester, repository);

      await tester.ensureVisible(
        find.text('Classer un document sur cet appareil'),
      );
      await tester.tap(find.text('Classer un document sur cet appareil'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Comment souhaitez-vous'), findsOneWidget);
      expect(find.text('Photographier un document'), findsOneWidget);
      expect(find.text('Importer une photo'), findsOneWidget);
      expect(
        find.text('Classification locale par reconnaissance de texte'),
        findsOneWidget,
      );
    },
  );

  testWidgets('verrouille une session restaurée après un redémarrage', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'smartvault_pro.last_active_user_id': 'existing-user',
    });
    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'existing-user',
        email: 'lea@example.com',
        displayName: 'Léa Martin',
      );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    expect(find.text('Session verrouillée'), findsOneWidget);
    expect(find.text('Bonjour, Léa'), findsNothing);
  });

  testWidgets('ne verrouille pas la session pendant la prise de photo', (
    WidgetTester tester,
  ) async {
    final externalActivityStarted = Completer<void>();
    final finishExternalActivity = Completer<void>();
    final externalActivityEnded = Completer<void>();
    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'camera-user',
        email: 'lea@example.com',
        displayName: 'Léa',
      );
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      SmartVaultMaterialApp(
        home: IdleSessionGate(
          authRepository: repository,
          user: repository.currentUser!,
          child: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  unawaited(
                    SessionLockActivityScope.run(context, () async {
                      externalActivityStarted.complete();
                      await finishExternalActivity.future;
                    }).then((_) => externalActivityEnded.complete()),
                  );
                },
                child: const Text('Ouvrir caméra'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ouvrir caméra'));
    await externalActivityStarted.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(find.text('Session verrouillée'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Session verrouillée'), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    finishExternalActivity.complete();
    await externalActivityEnded.future;
    await tester.pumpAndSettle();
    expect(find.text('Session verrouillée'), findsNothing);
  });

  testWidgets('adapte le tableau de bord à un écran Android étroit', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'small-screen-user',
        email: 'lea@example.com',
        displayName: 'Léa',
      );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    expect(find.text('Bonjour, Léa'), findsOneWidget);
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('ajoute manuellement un document au portefeuille', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'document-user',
        email: 'lea@example.com',
        displayName: 'Léa',
      );
    final documentsRepository = _FakeDocumentRepository();
    addTearDown(repository.dispose);
    addTearDown(documentsRepository.dispose);
    await _pumpApp(
      tester,
      repository,
      documentsRepository: documentsRepository,
    );

    await tester.tap(find.text('Ajouter un document').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Comment souhaitez-vous'), findsOneWidget);

    await tester.tap(find.text('Saisie manuelle'));
    await tester.pumpAndSettle();
    expect(find.text('Vérifier les informations'), findsOneWidget);

    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Carte nationale d’identité',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Léa Martin');
    await tester.ensureVisible(find.text('Enregistrer dans le portefeuille'));
    await tester.tap(find.text('Enregistrer dans le portefeuille'));
    await tester.pumpAndSettle();

    expect(find.text('Mon portefeuille'), findsOneWidget);
    expect(find.text('Carte nationale d’identité'), findsOneWidget);
    expect(find.textContaining('Léa Martin'), findsOneWidget);
    expect(find.text('1 document'), findsOneWidget);
    expect(documentsRepository.documents, hasLength(1));
    expect(
      documentsRepository.documents.single.title,
      'Carte nationale d’identité',
    );
  });

  testWidgets('préremplit les informations analysées par IA', (
    WidgetTester tester,
  ) async {
    final documentsRepository = _FakeDocumentRepository();
    addTearDown(documentsRepository.dispose);

    await tester.pumpWidget(
      SmartVaultMaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push<VaultDocument>(
                  MaterialPageRoute(
                    builder: (_) => ReviewDocumentScreen(
                      onSave: (document, imageBytes, imageMimeType) =>
                          documentsRepository.saveDocument(
                            userId: 'ocr-user',
                            document: document,
                            imageBytes: imageBytes,
                            imageMimeType: imageMimeType,
                          ),
                      initialCategory: 'Passeport',
                      initialTitle: 'Passeport',
                      initialHolderName: 'LÉA MARTIN',
                      initialDocumentNumber: 'AB123456',
                      initialExpiryDate: DateTime(2032, 2, 14),
                    ),
                  ),
                );
              },
              child: const Text('Vérifier le document analysé'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Vérifier le document analysé'));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(0))
          .controller!
          .text,
      'Passeport',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      'LÉA MARTIN',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(2))
          .controller!
          .text,
      'AB123456',
    );
    expect(find.text('14/02/2032'), findsOneWidget);

    await tester.ensureVisible(find.text('Enregistrer dans le portefeuille'));
    await tester.tap(find.text('Enregistrer dans le portefeuille'));
    await tester.pumpAndSettle();

    expect(documentsRepository.documents, hasLength(1));
    expect(documentsRepository.documents.single.category, 'Passeport');
    expect(documentsRepository.documents.single.holderName, 'LÉA MARTIN');
    expect(documentsRepository.documents.single.documentNumber, 'AB123456');
    expect(
      documentsRepository.documents.single.expiryDate,
      DateTime(2032, 2, 14),
    );
  });

  testWidgets('enregistre les champs extraits de la CIN', (
    WidgetTester tester,
  ) async {
    final documentsRepository = _FakeDocumentRepository();
    addTearDown(documentsRepository.dispose);

    await tester.pumpWidget(
      SmartVaultMaterialApp(
        home: ReviewDocumentScreen(
          onSave: (document, imageBytes, imageMimeType) =>
              documentsRepository.saveDocument(
                userId: 'cin-user',
                document: document,
                imageBytes: imageBytes,
                imageMimeType: imageMimeType,
              ),
          initialCategory: 'Pièce d’identité',
          initialTitle: 'Carte nationale d’identité',
          initialName: 'Léa',
          initialSurname: 'Martin',
          initialDateOfBirth: '1998-06-17',
          initialPlaceOfBirth: 'Lyon',
          initialExpiryDate: DateTime(2030, 5, 17),
          nationalIdFieldsEnabled: true,
        ),
      ),
    );

    expect(find.text('Prénom(s)'), findsOneWidget);
    expect(find.text('Nom'), findsOneWidget);
    expect(find.text('Date de naissance'), findsOneWidget);
    expect(find.text('Lieu de naissance'), findsOneWidget);
    await tester.ensureVisible(find.text('Enregistrer dans le portefeuille'));
    await tester.tap(find.text('Enregistrer dans le portefeuille'));
    await tester.pumpAndSettle();

    final savedDocument = documentsRepository.documents.single;
    expect(savedDocument.category, 'Pièce d’identité');
    expect(savedDocument.holderName, 'Léa Martin');
    expect(savedDocument.name, 'Léa');
    expect(savedDocument.surname, 'Martin');
    expect(savedDocument.dateOfBirth, '1998-06-17');
    expect(savedDocument.placeOfBirth, 'Lyon');
    expect(savedDocument.expiryDate, DateTime(2030, 5, 17));
  });

  testWidgets(
    'explique pourquoi un document incomplet ne peut pas être sauvé',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        SmartVaultMaterialApp(
          home: ReviewDocumentScreen(
            onSave: (document, imageBytes, imageMimeType) async => document,
            initialTitle: 'Passeport',
          ),
        ),
      );

      await tester.ensureVisible(find.text('Enregistrer dans le portefeuille'));
      await tester.tap(find.text('Enregistrer dans le portefeuille'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Complétez les champs obligatoires'),
        findsOneWidget,
      );
      expect(find.text('Saisissez le nom du titulaire.'), findsOneWidget);
    },
  );

  testWidgets('valide le numéro de huit chiffres de la CIN', (
    WidgetTester tester,
  ) async {
    var saveCalled = false;
    await tester.pumpWidget(
      SmartVaultMaterialApp(
        home: ReviewDocumentScreen(
          onSave: (document, imageBytes, imageMimeType) async {
            saveCalled = true;
            return document;
          },
          initialTitle: 'Carte nationale d’identité',
          initialCategory: 'Pièce d’identité',
          initialName: 'Amina',
          initialSurname: 'Trabelsi',
          initialDocumentNumber: '1234567',
          nationalIdFieldsEnabled: true,
        ),
      ),
    );

    await tester.ensureVisible(find.text('Enregistrer dans le portefeuille'));
    await tester.tap(find.text('Enregistrer dans le portefeuille'));
    await tester.pumpAndSettle();

    expect(find.text('Saisissez les 8 chiffres de la CIN.'), findsOneWidget);
    expect(saveCalled, isFalse);
  });

  testWidgets('verrouille après une minute sans activité', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'idle-user',
        email: 'lea@example.com',
        displayName: 'Léa',
      );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    expect(find.text('Bonjour, Léa'), findsOneWidget);
    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Bonjour, Léa'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Session verrouillée'), findsOneWidget);
    expect(
      find.textContaining('Déverrouiller avec biométrie ou code'),
      findsOneWidget,
    );
    expect(find.text('Bonjour, Léa'), findsNothing);
  });

  testWidgets('une interaction redémarre le délai d’inactivité', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'activity-user',
        email: 'lea@example.com',
        displayName: 'Léa',
      );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);

    await tester.pump(const Duration(seconds: 55));
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 59));
    expect(find.text('Session verrouillée'), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Session verrouillée'), findsOneWidget);
  });

  testWidgets('propose la biométrie après verrouillage par inactivité', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'unlock-user',
        email: 'lea@example.com',
        displayName: 'Léa',
      );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('Session verrouillée'), findsOneWidget);
    expect(
      find.textContaining('Déverrouiller avec biométrie ou code'),
      findsOneWidget,
    );
    expect(find.text('Bonjour, Léa'), findsNothing);
  });

  testWidgets(
    'garde les pages privées masquées derrière le verrou biométrique',
    (WidgetTester tester) async {
      final repository = _FakeAuthRepository()
        ..currentUser = const AuthUser(
          id: 'private-route-user',
          email: 'lea@example.com',
          displayName: 'Léa',
        );
      addTearDown(repository.dispose);
      await _pumpApp(tester, repository);

      await tester.tap(find.text('Ajouter un document').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Comment souhaitez-vous'), findsOneWidget);

      await tester.pump(const Duration(minutes: 1));
      expect(find.text('Session verrouillée'), findsOneWidget);
      expect(find.textContaining('Comment souhaitez-vous'), findsNothing);
      expect(
        find.textContaining('Déverrouiller avec biométrie ou code'),
        findsOneWidget,
      );
    },
  );

  testWidgets('le verrou propose la reconnaissance faciale', (
    WidgetTester tester,
  ) async {
    final repository = _FakeAuthRepository()
      ..currentUser = const AuthUser(
        id: 'invalid-unlock-user',
        email: 'lea@example.com',
        displayName: 'Léa',
      );
    addTearDown(repository.dispose);
    await _pumpApp(tester, repository);
    await tester.pump(const Duration(minutes: 1));

    expect(find.text('Session verrouillée'), findsOneWidget);
    expect(
      find.textContaining('Déverrouiller avec biométrie ou code'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
  });
}

Future<void> _scrollToText(WidgetTester tester, String text) async {
  for (var attempt = 0; attempt < 6; attempt++) {
    if (find.text(text).evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text(text));
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -350));
    await tester.pumpAndSettle();
  }
  expect(find.text(text), findsOneWidget);
}

Widget _app(
  AuthRepository repository, {
  DocumentRepository documentsRepository = const _EmptyDocumentRepository(),
  Duration idleTimeout = const Duration(minutes: 1),
}) {
  return SmartVaultMaterialApp(
    home: AuthGate(
      authRepository: repository,
      documentsRepository: documentsRepository,
      idleTimeout: idleTimeout,
    ),
  );
}

Future<void> _pumpApp(
  WidgetTester tester,
  AuthRepository repository, {
  DocumentRepository documentsRepository = const _EmptyDocumentRepository(),
  Duration idleTimeout = const Duration(minutes: 1),
}) async {
  await tester.pumpWidget(
    _app(
      repository,
      documentsRepository: documentsRepository,
      idleTimeout: idleTimeout,
    ),
  );
  await tester.pumpAndSettle();
  if (find.text('Commencer').evaluate().isNotEmpty) {
    await tester.ensureVisible(find.text('Commencer'));
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
  }
}

class _EmptyDocumentRepository implements DocumentRepository {
  const _EmptyDocumentRepository();

  @override
  Stream<List<VaultDocument>> watchDocuments(String userId) =>
      Stream.value(const []);

  @override
  Future<VaultDocument> saveDocument({
    required String userId,
    required VaultDocument document,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async => document;
}

class _FakeDocumentRepository implements DocumentRepository {
  final _controller = StreamController<List<VaultDocument>>.broadcast();
  final List<VaultDocument> documents = [];

  @override
  Stream<List<VaultDocument>> watchDocuments(String userId) async* {
    yield List.unmodifiable(documents);
    yield* _controller.stream;
  }

  @override
  Future<VaultDocument> saveDocument({
    required String userId,
    required VaultDocument document,
    Uint8List? imageBytes,
    String? imageMimeType,
  }) async {
    documents.removeWhere((item) => item.id == document.id);
    documents.insert(0, document);
    _controller.add(List.unmodifiable(documents));
    return document;
  }

  Future<void> dispose() => _controller.close();
}

class _FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? currentUser;
  String? lastEmail;
  String? lastReauthenticationPassword;
  bool rejectReauthentication = false;

  @override
  Stream<AuthUser?> get authStateChanges async* {
    yield currentUser;
    yield* _controller.stream;
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    lastEmail = email;
    currentUser = const AuthUser(
      id: 'test-user',
      email: 'lea@example.com',
      displayName: 'Léa',
    );
    _controller.add(currentUser);
    return currentUser!;
  }

  @override
  Future<AuthUser> createAccount({
    required String name,
    required String email,
    required String password,
  }) async => AuthUser(id: 'test-user', email: email, displayName: name);

  @override
  Future<void> sendPasswordResetEmail(String email) async {}

  @override
  Future<void> reauthenticate({required String password}) async {
    lastReauthenticationPassword = password;
    if (rejectReauthentication) {
      throw const AuthException('invalid-credential');
    }
  }

  @override
  Future<void> signOut() async {
    currentUser = null;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();
}
