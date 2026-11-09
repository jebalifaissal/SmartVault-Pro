import 'package:flutter/material.dart';

import '../features/auth/data/cloudflare_auth_repository.dart';
import '../features/auth/data/cloudflare_session_store.dart';
import '../features/auth/presentation/auth_gate.dart';
import '../features/documents/data/document_share_service.dart';
import '../features/documents/data/sqflite_local_document_repository.dart';
import '../services/document_api_service.dart';
import 'smart_vault_app.dart';

class ApplicationBootstrap extends StatefulWidget {
  const ApplicationBootstrap({super.key});

  @override
  State<ApplicationBootstrap> createState() => _ApplicationBootstrapState();
}

class _ApplicationBootstrapState extends State<ApplicationBootstrap> {
  late final _sessionStore = CloudflareSessionStore();
  late final _authRepository = CloudflareAuthRepository(
    sessionStore: _sessionStore,
  );
  late final _documentsRepository = SqfliteLocalDocumentRepository();
  late final _documentApi = DocumentApiService(
    getAccessToken: _authRepository.getAccessToken,
    getCachedAdministrator: _authRepository.getCachedAdministrator,
  );
  late final _documentShareService = DocumentShareService(api: _documentApi);

  @override
  Widget build(BuildContext context) => SmartVaultMaterialApp(
    home: AuthGate(
      authRepository: _authRepository,
      documentsRepository: _documentsRepository,
      localCinRepository: _documentsRepository,
      classificationApi: _documentApi,
      documentShareService: _documentShareService,
    ),
  );
}
