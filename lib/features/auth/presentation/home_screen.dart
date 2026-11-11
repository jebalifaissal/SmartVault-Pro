import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import '../../documents/domain/document_repository.dart';
import '../../documents/domain/local_cin_repository.dart';
import '../../documents/domain/document_security_classification.dart';
import '../../documents/domain/user_notification.dart';
import '../../documents/domain/vault_document.dart';
import '../../documents/data/hybrid_national_id_ocr.dart';
import '../../documents/presentation/add_document_screen.dart';
import '../../documents/presentation/digital_wallet_screen.dart';
import '../../documents/data/document_share_service.dart';
import '../../../services/document_api_service.dart';
import 'auth_error_message.dart';

const _teal = Color(0xFF087E78);
const _ink = Color(0xFF172B3A);
const _muted = Color(0xFF71808A);
const _canvas = Color(0xFFF4F7F7);
const _line = Color(0xFFE5EBEB);

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.authRepository,
    required this.documentsRepository,
    required this.user,
    this.localCinRepository,
    this.classificationApi,
    this.documentShareService,
    super.key,
  });

  final AuthRepository authRepository;
  final DocumentRepository documentsRepository;
  final LocalDocumentRepository? localCinRepository;
  final DocumentApiService? classificationApi;
  final DocumentShareService? documentShareService;
  final AuthUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSigningOut = false;
  bool _isLoadingDocuments = true;
  bool _isLoadingCloudDocuments = true;
  bool _isLoadingLocalCins = true;
  int _selectedTab = 0;
  String? _documentLoadError;
  String? _cloudDocumentLoadError;
  String? _localCinLoadError;
  final List<VaultDocument> _documents = [];
  final List<VaultDocument> _cloudDocuments = [];
  final List<VaultDocument> _localDocuments = [];
  final _documentOcr = HybridNationalIdOcr();
  StreamSubscription<List<VaultDocument>>? _documentsSubscription;
  StreamSubscription<List<VaultDocument>>? _localCinsSubscription;
  Timer? _classificationSyncTimer;
  bool _isSyncingClassifications = false;
  String? _lastClassificationSyncError;

  // ── Notifications ────────────────────────────────────────────────────────
  List<UserNotification> _notifications = [];
  bool _notifBannerDismissed = false;

  @override
  void initState() {
    super.initState();
    _listenToDocuments();
    _classificationSyncTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => unawaited(_syncPendingClassifications()),
    );
    unawaited(_syncPendingClassifications());
    unawaited(_loadNotifications());
  }

  @override
  void dispose() {
    _documentsSubscription?.cancel();
    _localCinsSubscription?.cancel();
    _classificationSyncTimer?.cancel();
    super.dispose();
  }

  void _listenToDocuments() {
    _isLoadingCloudDocuments = true;
    _cloudDocumentLoadError = null;
    _documentsSubscription = widget.documentsRepository
        .watchDocuments(widget.user.id)
        .listen(
          (documents) {
            if (!mounted) return;
            setState(() {
              _cloudDocuments
                ..clear()
                ..addAll(documents);
              _isLoadingCloudDocuments = false;
              _cloudDocumentLoadError = null;
              _publishDocuments();
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted) return;
            setState(() {
              _isLoadingCloudDocuments = false;
              _cloudDocumentLoadError = error.toString();
              _publishDocuments();
            });
          },
        );

    final localRepository = widget.localCinRepository;
    if (localRepository == null) {
      _isLoadingLocalCins = false;
      _localDocuments.clear();
      _localCinLoadError = null;
      _publishDocuments();
      return;
    }

    _isLoadingLocalCins = true;
    _localCinLoadError = null;
    _localCinsSubscription = localRepository
        .watchDocuments(widget.user.id)
        .listen(
          (documents) {
            if (!mounted) return;
            setState(() {
              _localDocuments
                ..clear()
                ..addAll(documents);
              _isLoadingLocalCins = false;
              _localCinLoadError = null;
              _publishDocuments();
            });
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!mounted) return;
            setState(() {
              _isLoadingLocalCins = false;
              _localCinLoadError = error.toString();
              _publishDocuments();
            });
          },
        );
  }

  Future<void> _retryDocumentLoading() async {
    await Future.wait([
      _documentsSubscription?.cancel() ?? Future<void>.value(),
      _localCinsSubscription?.cancel() ?? Future<void>.value(),
    ]);
    if (!mounted) return;
    setState(() {
      _isLoadingDocuments = true;
      _documentLoadError = null;
      _isLoadingCloudDocuments = true;
      _isLoadingLocalCins = widget.localCinRepository != null;
      _cloudDocumentLoadError = null;
      _localCinLoadError = null;
    });
    _listenToDocuments();
  }

  void _publishDocuments() {
    final documentsById = <String, VaultDocument>{
      for (final document in _cloudDocuments) document.id: document,
      for (final document in _localDocuments) document.id: document,
    };
    _documents
      ..clear()
      ..addAll(documentsById.values)
      ..sort((first, second) => second.createdAt.compareTo(first.createdAt));
    _isLoadingDocuments = _isLoadingCloudDocuments || _isLoadingLocalCins;
    _documentLoadError = _cloudDocumentLoadError ?? _localCinLoadError;
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await widget.authRepository.signOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$feature sera disponible dans une prochaine étape.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _addDocument() async {
    final document = await Navigator.of(context).push<VaultDocument>(
      MaterialPageRoute<VaultDocument>(
        builder: (_) => AddDocumentScreen(
          onSave: _saveDocument,
          onSaveCin: _saveCinLocally,
          onSubmitCinForReview: _submitCinForReview,
          classifier: _documentOcr,
          nationalIdOcr: _documentOcr,
        ),
      ),
    );
    if (document != null && mounted) {
      setState(() {
        final destination = document.isLocal
            ? _localDocuments
            : _cloudDocuments;
        destination
          ..removeWhere((item) => item.id == document.id)
          ..insert(0, document);
        _publishDocuments();
        _selectedTab = 1;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Votre CIN a été ajoutée au portefeuille.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
  }

  Future<VaultDocument> _saveDocument(
    VaultDocument document,
    Uint8List? imageBytes,
    String? imageMimeType,
  ) => widget.documentsRepository.saveDocument(
    userId: widget.user.id,
    document: document,
    imageBytes: imageBytes,
    imageMimeType: imageMimeType,
  );

  Future<VaultDocument> _saveCinLocally(
    VaultDocument document,
    Uint8List? imageBytes,
    String? imageMimeType,
  ) {
    final repository = widget.localCinRepository;
    if (repository == null) {
      throw StateError('Le stockage local des CIN n’est pas disponible.');
    }
    if (imageBytes == null || imageMimeType == null) {
      throw ArgumentError('La photo de la CIN est requise.');
    }
    return repository.saveDocument(
      userId: widget.user.id,
      document: document,
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
    );
  }

  Future<bool> _submitCinForReview(
    VaultDocument document,
    Uint8List imageBytes,
    String imageMimeType,
    String message,
  ) async {
    final repository = widget.localCinRepository;
    final api = widget.classificationApi;
    if (repository == null || api == null) {
      throw StateError(
        'Le service de demandes de classement est indisponible.',
      );
    }

    await repository.stageClassificationRequest(
      userId: widget.user.id,
      id: document.id,
      title: document.title,
      message: message,
      documentType: document.documentType ?? 'UNKNOWN',
      imageBytes: imageBytes,
      imageMimeType: imageMimeType,
    );

    try {
      await api.submitClassificationRequest(
        id: document.id,
        title: document.title,
        message: message,
        documentType: document.documentType ?? 'UNKNOWN',
      );
      await repository.markClassificationRequestSubmitted(
        userId: widget.user.id,
        id: document.id,
      );
      unawaited(_syncPendingClassifications());
      return true;
    } on Exception {
      unawaited(_syncPendingClassifications());
      return false;
    }
  }

  Future<void> _syncPendingClassifications() async {
    final repository = widget.localCinRepository;
    final api = widget.classificationApi;
    if (!mounted ||
        repository == null ||
        api == null ||
        _isSyncingClassifications) {
      return;
    }
    _isSyncingClassifications = true;
    try {
      var pending = await repository.pendingClassificationRequests(
        widget.user.id,
      );
      for (final request in pending) {
        if (request.isSubmitted) continue;
        await api.submitClassificationRequest(
          id: request.id,
          title: request.title,
          message: request.message,
          documentType: request.documentType,
        );
        await repository.markClassificationRequestSubmitted(
          userId: widget.user.id,
          id: request.id,
        );
      }

      pending = await repository.pendingClassificationRequests(widget.user.id);
      if (pending.isEmpty) return;
      final remoteRequests = await api.getMyClassificationRequests();
      _lastClassificationSyncError = null;
      final remoteById = {
        for (final request in remoteRequests) request['id'] as String: request,
      };
      for (final request in pending) {
        final remote = remoteById[request.id];
        if (remote == null) continue;
        final status = remote['status'];
        if (status == 'ADMIN_REVIEWED') {
          final category = remote['category'];
          final level = remote['security_level'];
          if (category is! String || level is! String) {
            throw const FormatException(
              'La décision Admin ne contient pas de classement valide.',
            );
          }
          final securityLevel = DocumentSecurityLevel.values.firstWhere(
            (value) => value.databaseValue == level,
            orElse: () => throw FormatException(
              'Niveau de sécurité non reconnu : $level',
            ),
          );
          await repository.completeClassificationRequest(
            userId: widget.user.id,
            id: request.id,
            category: category,
            securityLevel: securityLevel,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Votre document a été accepté et classé dans « $category ».',
                ),
              ),
            );
          }
        } else if (status == 'REJECTED') {
          await repository.removeClassificationRequest(
            userId: widget.user.id,
            id: request.id,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Votre demande « ${request.title} » a été refusée.',
                ),
              ),
            );
          }
        }
      }
    } on Exception catch (error) {
      final message = error.toString();
      if (mounted && message != _lastClassificationSyncError) {
        _lastClassificationSyncError = message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synchronisation du classement en attente : $message',
            ),
          ),
        );
      }
    } finally {
      _isSyncingClassifications = false;
    }
  }

  Future<void> _deleteLocalCin(VaultDocument document) async {
    final repository = widget.localCinRepository;
    if (repository == null) {
      throw StateError('Le stockage local des CIN n’est pas disponible.');
    }
    await repository.deleteDocument(
      userId: widget.user.id,
      documentId: document.id,
    );
  }

  void _openWallet() => setState(() => _selectedTab = 1);

  // ── Notifications ──────────────────────────────────────────────────────────

  Future<void> _loadNotifications() async {
    final api = widget.classificationApi;
    if (api == null) return;
    try {
      final result = await api.getMyNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = result.notifications;
        // Réinitialise le dismiss si on a de nouvelles notifs non lues
        if (result.unreadCount > 0) _notifBannerDismissed = false;
      });
    } catch (_) {
      // Silencieux — les notifications sont optionnelles
    }
  }

    Future<void> _dismissNotificationBanner() async {
    setState(() => _notifBannerDismissed = true);
    try {
      await widget.classificationApi?.markAllNotificationsRead();
    } catch (_) {}
  }

  Future<void> _openNotifications() async {
    await _loadNotifications();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final notifications = _notifications;

        return SafeArea(
          child: Container(
            height: MediaQuery.of(sheetContext).size.height * 0.75,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: _teal,
                      size: 25,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Mes notifications',
                        style: TextStyle(
                          color: _ink,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Divider(),
                if (notifications.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.notifications_off_outlined,
                            size: 48,
                            color: _muted,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Aucune notification pour le moment',
                            style: TextStyle(color: _muted),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      itemCount: notifications.length,
                     separatorBuilder: (context, index) =>
    const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final notification = notifications[index];
                        final accepted = notification.isAccepted;
                        final color = accepted
                            ? _teal
                            : const Color(0xFFDC2626);

                        final date = notification.createdAt;
                        final formattedDate =
                            '${date.day.toString().padLeft(2, '0')}/'
                            '${date.month.toString().padLeft(2, '0')}/'
                            '${date.year} '
                            '${date.hour.toString().padLeft(2, '0')}:'
                            '${date.minute.toString().padLeft(2, '0')}';

                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: notification.isRead
                                ? const Color(0xFFF7F9FA)
                                : const Color(0xFFE8F4F2),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(
                              color: color.withValues(alpha: 0.15),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                accepted
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                color: color,
                                size: 25,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      notification.title,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 14,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      notification.body,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (notification.category != null) ...[
                                      const SizedBox(height: 7),
                                      Text(
                                        'Catégorie : ${notification.category}',
                                        style: const TextStyle(
                                          color: _teal,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    if (notification.securityLevel != null)
                                      Text(
                                        'Sensibilité : ${notification.securityLevel == 'HIGH' ? 'Très sensible' : 'Moyennement sensible'}',
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 11,
                                        ),
                                      ),
                                    const SizedBox(height: 7),
                                    Text(
                                      formattedDate,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!notification.isRead)
                                const Icon(
                                  Icons.circle,
                                  color: _teal,
                                  size: 9,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (notifications.any((n) => !n.isRead))
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          await widget.classificationApi
                              ?.markAllNotificationsRead();

                          if (!mounted) return;

                          setState(() {
                            _notifications = _notifications.map((n) {
                              return UserNotification(
                                id: n.id,
                                type: n.type,
                                title: n.title,
                                body: n.body,
                                requestId: n.requestId,
                                isRead: true,
                                createdAt: n.createdAt,
                                category: n.category,
                                securityLevel: n.securityLevel,
                              );
                            }).toList();
                            _notifBannerDismissed = true;
                          });

                          if (sheetContext.mounted) {
                            Navigator.pop(sheetContext);
                          }
                        } catch (_) {
                          if (sheetContext.mounted) {
                            ScaffoldMessenger.of(sheetContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Impossible de mettre à jour les notifications.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                      icon: const Icon(Icons.done_all_rounded),
                      label: const Text('Tout marquer comme lu'),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

    String get _firstName {
    final name = widget.user.displayName?.trim();
    if (name == null || name.isEmpty) return 'vous';
    return name.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (_isLoadingDocuments || _documentLoadError != null)
              _buildDocumentSyncStatus(),
            // ── Bannière notifications non lues ───────────────────────────
            if (!_notifBannerDismissed && _notifications.any((n) => !n.isRead))
              _NotificationBanner(
                notifications:
                    _notifications.where((n) => !n.isRead).toList(),
                onDismiss: _dismissNotificationBanner,
                onViewWallet: _openWallet,
              ),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: _selectedTab == 1
                      ? DigitalWalletScreen(
                          documents: _documents,
                          onAddDocument: _addDocument,
                          onDeleteLocalDocument: _deleteLocalCin,
                          documentShareService: widget.documentShareService,
                        )
                      : _buildDashboard(),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildDocumentSyncStatus() {
    final error = _documentLoadError;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      color: error == null ? const Color(0xFFE8F4F2) : const Color(0xFFFFECEC),
      child: Row(
        children: [
          if (error == null)
            const SizedBox(
              width: 17,
              height: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            const Icon(Icons.storage_outlined, color: Color(0xFFC83D4D)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error == null
                  ? 'Chargement de vos documents...'
                  : 'Stockage local indisponible : $error',
              style: TextStyle(
                color: error == null
                    ? const Color(0xFF087E78)
                    : const Color(0xFFC83D4D),
                fontSize: 12,
              ),
            ),
          ),
          if (error != null)
            TextButton(
              onPressed: _retryDocumentLoading,
              child: const Text('Réessayer'),
            ),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 30),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildTopBar(),
              const SizedBox(height: 28),
              _buildWelcome(),
              const SizedBox(height: 22),
              _buildVaultCard(),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addDocument,
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Classer un document sur cet appareil'),
                ),
              ),
              const SizedBox(height: 16),
              _buildSectionHeading(
                title: 'Accès rapide',
                subtitle: 'Retrouvez vos documents par catégorie',
                actionLabel: 'Tout voir',
                onAction: _openWallet,
              ),
              const SizedBox(height: 14),
              _buildCategories(),
              const SizedBox(height: 27),
              _buildSectionHeading(
                title: 'Ajoutés récemment',
                subtitle: 'Vos derniers documents enregistrés',
                actionLabel: _documents.isEmpty ? null : 'Tout voir',
                onAction: _openWallet,
              ),
              const SizedBox(height: 13),
              _buildRecentDocuments(),
              const SizedBox(height: 24),
              _buildTipCard(),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: _teal,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(
            Icons.account_balance_wallet_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 11),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SmartVault',
              style: TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              'ESPACE PERSONNEL',
              style: TextStyle(
                color: _muted,
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
        const Spacer(),
        _RoundIconButton(
          icon: Icons.notifications_none_rounded,
          label: 'Notifications',
          onPressed: _openNotifications,
        ),
        const SizedBox(width: 9),
        PopupMenuButton<String>(
          tooltip: 'Options du compte',
          onSelected: (value) {
            if (value == 'logout') _signOut();
          },
          itemBuilder: (context) => const [
            PopupMenuItem<String>(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, size: 18),
                  SizedBox(width: 10),
                  Text('Se déconnecter'),
                ],
              ),
            ),
          ],
          child: CircleAvatar(
            radius: 21,
            backgroundColor: const Color(0xFFDDEEEB),
            child: Text(
              _firstName == 'vous'
                  ? 'U'
                  : _firstName.characters.first.toUpperCase(),
              style: const TextStyle(color: _teal, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (_isSigningOut)
          const Padding(
            padding: EdgeInsets.only(left: 9),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
      ],
    );
  }

  Widget _buildWelcome() {
    final now = DateTime.now();
    final date =
        '${_weekday(now.weekday)} ${now.day} ${_month(now.month)} ${now.year}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bonjour, $_firstName',
          style: const TextStyle(
            color: _ink,
            fontSize: 27,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '$date  ·  Voici votre espace documentaire.',
          style: const TextStyle(color: _muted, fontSize: 13, height: 1.45),
        ),
      ],
    );
  }

  Widget _buildVaultCard() {
    return Container(
      height: 254,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B827B), Color(0xFF075B61)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(23),
        boxShadow: const [
          BoxShadow(
            color: Color(0x23075B61),
            blurRadius: 22,
            offset: Offset(0, 9),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -40,
            child: Container(
              width: 154,
              height: 154,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mon portefeuille',
                      style: TextStyle(
                        color: Color(0xFFE3F4F1),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ],
              ),
              const SizedBox(height: 17),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_documents.length}',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                    ),
                  ),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 10, bottom: 5),
                      child: Text(
                        _documents.length == 1
                            ? 'document enregistré'
                            : 'documents enregistrés',
                        maxLines: 2,
                        style: const TextStyle(
                          color: Color(0xFFD2ECE8),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _VaultStat(
                      icon: Icons.folder_copy_outlined,
                      label: 'Catégories',
                      value: _documentCategoryCount.toString(),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 34,
                    color: Colors.white.withValues(alpha: 0.2),
                  ),
                  Expanded(
                    child: _VaultStat(
                      icon: Icons.event_available_outlined,
                      label: 'À renouveler',
                      value: _expiringDocumentCount.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 19),
              SizedBox(
                width: double.infinity,
                height: 47,
                child: FilledButton.icon(
                  onPressed: _addDocument,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text(
                    'Ajouter un document',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeading({
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, fontSize: 11.5),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: _teal,
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              actionLabel,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }

  Widget _buildCategories() {
    final categories = [
      _CategoryData(
        title: 'Identité',
        icon: Icons.badge_outlined,
        color: Color(0xFFE8F2FF),
        iconColor: Color(0xFF3976B8),
        count: _countCategory('Pièce d’identité') + _countCategory('Passeport'),
      ),
      _CategoryData(
        title: 'Diplômes',
        icon: Icons.school_outlined,
        color: Color(0xFFF1ECFF),
        iconColor: Color(0xFF7A60B7),
        count: _countCategory('Diplôme'),
      ),
      _CategoryData(
        title: 'Permis',
        icon: Icons.directions_car_outlined,
        color: Color(0xFFFFF1E4),
        iconColor: Color(0xFFCC8240),
        count: _countCategory('Permis de conduire'),
      ),
      _CategoryData(
        title: 'Autres',
        icon: Icons.folder_open_outlined,
        color: Color(0xFFE6F4F0),
        iconColor: _teal,
        count: _countCategory('Autres'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = (constraints.maxWidth - 30) / 4;
        return Row(
          children: [
            for (var index = 0; index < categories.length; index++) ...[
              SizedBox(
                width: itemWidth,
                child: _CategoryCard(
                  category: categories[index],
                  onTap: _openWallet,
                ),
              ),
              if (index < categories.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRecentDocuments() {
    if (_documents.isNotEmpty) {
      return Column(
        children: [
          for (final document in _documents.take(3)) ...[
            _DashboardDocumentItem(document: document),
            const SizedBox(height: 9),
          ],
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F4F2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.description_outlined,
              color: _teal,
              size: 25,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Votre portefeuille est vide',
            style: TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Ajoutez votre premier document pour le retrouver ici.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.45),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _addDocument,
            style: TextButton.styleFrom(
              foregroundColor: _teal,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text(
              'Commencer',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3F2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline_rounded, color: _teal, size: 20),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Le saviez-vous ?',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Vous pourrez organiser vos pièces importantes dans un seul espace.',
                  style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return NavigationBar(
      height: 68,
      backgroundColor: Colors.white,
      indicatorColor: const Color(0xFFE5F2F0),
      selectedIndex: _selectedTab,
      onDestinationSelected: (index) {
        if (index == 0) {
          setState(() => _selectedTab = index);
          return;
        }
        if (index == 1) {
          setState(() => _selectedTab = index);
          return;
        }
        if (index == 2) {
          _addDocument();
          return;
        }
        _showComingSoon(index == 3 ? 'Les rappels' : 'Le profil');
      },
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.grid_view_rounded),
          label: 'Accueil',
        ),
        NavigationDestination(
          icon: Icon(Icons.folder_outlined),
          label: 'Documents',
        ),
        NavigationDestination(
          icon: Icon(Icons.add_circle_rounded),
          label: 'Ajouter',
        ),
        NavigationDestination(
          icon: Icon(Icons.notifications_none_rounded),
          label: 'Rappels',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          label: 'Profil',
        ),
      ],
    );
  }

  int _countCategory(String category) =>
      _documents.where((document) => document.category == category).length;

  int get _documentCategoryCount =>
      _documents.map((document) => document.category).toSet().length;

  int get _expiringDocumentCount {
    final now = DateTime.now();
    final limit = now.add(const Duration(days: 30));
    return _documents.where((document) {
      final date = document.expiryDate;
      return date != null && !date.isBefore(now) && !date.isAfter(limit);
    }).length;
  }

  String _weekday(int weekday) => const [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ][weekday - 1];

  String _month(int month) => const [
    'janvier',
    'février',
    'mars',
    'avril',
    'mai',
    'juin',
    'juillet',
    'août',
    'septembre',
    'octobre',
    'novembre',
    'décembre',
  ][month - 1];
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: _ink,
        side: const BorderSide(color: _line),
      ),
      icon: Icon(icon, size: 21),
    );
  }
}

class _VaultStat extends StatelessWidget {
  const _VaultStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFFD2ECE8), size: 18),
        const SizedBox(width: 6),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFD2ECE8), fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategoryData {
  const _CategoryData({
    required this.title,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.count,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final int count;
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final _CategoryData category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: _line),
          ),
          child: Column(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: category.color,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(category.icon, color: category.iconColor, size: 20),
              ),
              const SizedBox(height: 9),
              Text(
                category.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${category.count} ${category.count == 1 ? 'fichier' : 'fichiers'}',
                style: const TextStyle(color: _muted, fontSize: 9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardDocumentItem extends StatelessWidget {
  const _DashboardDocumentItem({required this.document});

  final VaultDocument document;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F2FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: Color(0xFF3976B8),
              size: 21,
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${document.category}  ·  ${document.holderName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bannière de notifications (affichée à la connexion si nouvelles notifs)
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({
    required this.notifications,
    required this.onDismiss,
    required this.onViewWallet,
  });

  final List<UserNotification> notifications;
  final VoidCallback onDismiss;
  final VoidCallback onViewWallet;

  @override
  Widget build(BuildContext context) {
    final accepted = notifications.where((n) => n.isAccepted).toList();
    final rejected = notifications.where((n) => n.isRejected).toList();

    final hasAccepted = accepted.isNotEmpty;

    final Color bannerBg =
        hasAccepted ? const Color(0xFFE8F4F2) : const Color(0xFFFFF1F1);
    final Color accentColor =
        hasAccepted ? _teal : const Color(0xFFDC2626);
    final IconData bannerIcon =
        hasAccepted ? Icons.check_circle_rounded : Icons.cancel_rounded;

    String title;
    if (accepted.isNotEmpty && rejected.isNotEmpty) {
      title =
          '${accepted.length} document${accepted.length > 1 ? 's' : ''} accepté${accepted.length > 1 ? 's' : ''}, '
          '${rejected.length} refusé${rejected.length > 1 ? 's' : ''}';
    } else if (accepted.isNotEmpty) {
      title = accepted.length == 1
          ? 'Votre document a été accepté'
          : '${accepted.length} documents acceptés';
    } else {
      title = rejected.length == 1
          ? 'Votre document a été refusé'
          : '${rejected.length} documents refusés';
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(bannerIcon, color: accentColor, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onDismiss,
                child: Icon(
                  Icons.close_rounded,
                  color: accentColor.withValues(alpha: 0.7),
                  size: 18,
                ),
              ),
            ],
          ),
          // Liste des documents acceptés avec leur container
          if (accepted.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...accepted.take(3).map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 30),
                    Icon(
                      Icons.folder_rounded,
                      color: _teal.withValues(alpha: 0.7),
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        n.category != null
                            ? 'Classé dans « ${n.category} »'
                            : n.body,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (accepted.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  onDismiss();
                  onViewWallet();
                },
                style: TextButton.styleFrom(
                  foregroundColor: _teal,
                  backgroundColor: _teal.withValues(alpha: 0.10),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Voir mes documents →',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
