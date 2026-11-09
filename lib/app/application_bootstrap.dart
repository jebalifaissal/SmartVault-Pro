
import 'package:flutter/material.dart';

import '../features/admin/data/admin_auth_repository.dart';
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
  State<ApplicationBootstrap> createState() =>
      _ApplicationBootstrapState();
}

class _ApplicationBootstrapState extends State<ApplicationBootstrap> {
  // Normal user authentication
  late final _sessionStore = CloudflareSessionStore();

  late final _authRepository = CloudflareAuthRepository(
    sessionStore: _sessionStore,
  );

  // Independent Admin authentication
  late final _adminAuthRepository = AdminAuthRepository();

  // Local documents database
  late final _documentsRepository =
      SqfliteLocalDocumentRepository();

  // Normal user API
  late final _documentApi = DocumentApiService(
    getAccessToken: _authRepository.getAccessToken,
    getCachedAdministrator:
        _authRepository.getCachedAdministrator,
  );

  // Admin API using the independent Admin token
  late final _adminDocumentApi = DocumentApiService(
    getAccessToken: _adminAuthRepository.getAccessToken,
  );

  late final _documentShareService =
      DocumentShareService(api: _documentApi);

  @override
  Widget build(BuildContext context) {
    return SmartVaultMaterialApp(
      home: AuthGate(
        authRepository: _authRepository,
        documentsRepository: _documentsRepository,
        localCinRepository: _documentsRepository,
        classificationApi: _documentApi,
        documentShareService: _documentShareService,

        // Independent Admin authentication and API
        adminAuthRepository: _adminAuthRepository,
        adminApi: _adminDocumentApi,
      ),
    );
  }
}
