import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/admin_user.dart';
import '../../../services/document_api_service.dart';
import '../../documents/domain/classification_request.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tokens de design
// ─────────────────────────────────────────────────────────────────────────────
const _bg = Color(0xFFF4F7F7);
const _white = Colors.white;
const _teal = Color(0xFF087E78);
const _ink = Color(0xFF172B3A);
const _muted = Color(0xFF71808A);
const _border = Color(0xFFE1EAEA);

const _highBg = Color(0xFFFFF1F1);
const _highAccent = Color(0xFFDC2626);
const _highBorder = Color(0xFFFFCDD2);

const _medBg = Color(0xFFFFF8E1);
const _medAccent = Color(0xFFF59E0B);
const _medBorder = Color(0xFFFFE082);

// ─────────────────────────────────────────────────────────────────────────────
// AdminInboxScreen
// ─────────────────────────────────────────────────────────────────────────────
class AdminInboxScreen extends StatefulWidget {
  const AdminInboxScreen({
    required this.api,
    required this.user,
    required this.onSignOut,
    super.key,
  });

  final DocumentApiService api;
  final AdminUser user;
  final Future<void> Function() onSignOut;

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen>
    with SingleTickerProviderStateMixin {
  late Future<List<ClassificationRequest>> _requests;
  bool _isSigningOut = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _requests = widget.api.getPendingClassificationRequests();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final requests = widget.api.getPendingClassificationRequests();
    setState(() => _requests = requests);
    await requests;
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    try {
      await widget.onSignOut();
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  Future<void> _openRequest(ClassificationRequest request) async {
    final imageBytes = widget.api.getClassificationRequestPhoto(request.id);
    final decision = await showModalBottomSheet<_AdminDecision>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _DecisionSheet(request: request, imageBytes: imageBytes),
    );
    if (decision == null || !mounted) return;

    try {
      await widget.api.decideClassificationRequest(
        id: request.id,
        decision: decision.accept ? 'accept' : 'reject',
        securityLevel: decision.level,
        category: decision.category,
        rejectionReason: decision.rejectionReason,
        firstName: decision.firstName,
        lastName: decision.lastName,
        documentNumber: decision.documentNumber,
        dateOfBirth: decision.dateOfBirth,
        placeOfBirth: decision.placeOfBirth,
        expirationDate: decision.expirationDate,
      );
      await _refresh();
      if (mounted) {
        _showSnack(
          decision.accept
              ? '✅ Dossier classé dans « ${decision.category} »'
              : '❌ Demande refusée.',
          decision.accept ? _teal : _highAccent,
        );
      }
    } catch (error) {
      if (mounted) {
        _showSnack('Erreur : $error', _highAccent);
      }
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, style: const TextStyle(color: _white)),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: _white,
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _teal,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: _white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Espace Administrateur',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  widget.user.email,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Actualiser',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, color: _teal),
          ),
          IconButton(
            tooltip: 'Déconnexion',
            onPressed: _isSigningOut ? null : _signOut,
            icon: _isSigningOut
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _muted,
                    ),
                  )
                : const Icon(Icons.logout_rounded, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: _white,
      child: TabBar(
        controller: _tabController,
        labelColor: _teal,
        unselectedLabelColor: _muted,
        indicatorColor: _teal,
        indicatorWeight: 2.5,
        labelStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
        tabs: const [
          Tab(text: 'En attente'),
          Tab(text: 'Historique'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    return TabBarView(
      controller: _tabController,
      children: [
        _PendingTab(
          requests: _requests,
          onRefresh: _refresh,
          onOpenRequest: _openRequest,
        ),
        _HistoryTab(api: widget.api),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet "En attente"
// ─────────────────────────────────────────────────────────────────────────────
class _PendingTab extends StatelessWidget {
  const _PendingTab({
    required this.requests,
    required this.onRefresh,
    required this.onOpenRequest,
  });

  final Future<List<ClassificationRequest>> requests;
  final Future<void> Function() onRefresh;
  final Future<void> Function(ClassificationRequest) onOpenRequest;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClassificationRequest>>(
      future: requests,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ErrorState(
            message: snapshot.error.toString(),
            onRetry: onRefresh,
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _teal),
          );
        }
        final all = snapshot.data!;
        if (all.isEmpty) {
          return const _EmptyState();
        }

        // Sépare HIGH (identifiables par documentType) et MEDIUM
        final highTypes = {'CIN', 'PASSPORT', 'DRIVING_LICENSE'};
        final high = all
            .where((r) => highTypes.contains(r.documentType.toUpperCase()))
            .toList();
        final medium = all
            .where((r) => !highTypes.contains(r.documentType.toUpperCase()))
            .toList();

        return RefreshIndicator(
          onRefresh: onRefresh,
          color: _teal,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (high.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Très sensibles',
                  count: high.length,
                  color: _highAccent,
                  icon: Icons.shield_rounded,
                  bg: _highBg,
                ),
                const SizedBox(height: 10),
                ...high.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RequestCard(
                      request: r,
                      level: 'HIGH',
                      onTap: () => onOpenRequest(r),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (medium.isNotEmpty) ...[
                _SectionHeader(
                  label: 'Moyennement sensibles',
                  count: medium.length,
                  color: _medAccent,
                  icon: Icons.folder_special_rounded,
                  bg: _medBg,
                ),
                const SizedBox(height: 10),
                ...medium.map(
                  (r) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _RequestCard(
                      request: r,
                      level: 'MEDIUM',
                      onTap: () => onOpenRequest(r),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// En-tête de section
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
    required this.bg,
  });

  final String label;
  final int count;
  final Color color;
  final IconData icon;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count dossier${count > 1 ? 's' : ''}',
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte d'une demande
// ─────────────────────────────────────────────────────────────────────────────
class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.level,
    required this.onTap,
  });

  final ClassificationRequest request;
  final String level; // 'HIGH' | 'MEDIUM'
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isHigh = level == 'HIGH';
    final accent = isHigh ? _highAccent : _medAccent;
    final bg = isHigh ? _highBg : _medBg;
    final borderColor = isHigh ? _highBorder : _medBorder;

    final docLabel = switch (request.documentType.toUpperCase()) {
      'CIN' => 'Carte nationale d\u2019identit\u00e9',
      'PASSPORT' => 'Passeport',
      'DRIVING_LICENSE' => 'Permis de conduire',
      'CERTIFICATE' => 'Certificat / Dipl\u00f4me',
      _ => request.documentType,
    };

    return Material(
      color: _white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              // Indicateur coloré à gauche
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: borderColor),
                ),
                child: Icon(
                  isHigh
                      ? Icons.security_rounded
                      : Icons.folder_special_outlined,
                  color: accent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      docLabel,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.userEmail,
                      style: TextStyle(
                        color: _teal.withValues(alpha: 0.85),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: _muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Onglet "Historique"
// ─────────────────────────────────────────────────────────────────────────────
class _HistoryTab extends StatefulWidget {
  const _HistoryTab({required this.api});

  final DocumentApiService api;

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _history;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _history = _fetchHistory();
  }

  Future<List<Map<String, dynamic>>> _fetchHistory() async {
    return widget.api.getClassificationHistory();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _history,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                snapshot.error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(color: _teal),
          );
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(
            child: Text(
              'Aucune action dans l\u2019historique.',
              style: TextStyle(color: _muted),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final item = items[index];
            final action = item['action'] as String? ?? '';
            final isAccepted = action == 'ADMIN_REVIEWED';
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color:
                          isAccepted
                              ? _teal.withValues(alpha: 0.10)
                              : _highBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAccepted
                          ? Icons.check_circle_outline_rounded
                          : Icons.cancel_outlined,
                      color: isAccepted ? _teal : _highAccent,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isAccepted ? 'Dossier accepté' : 'Dossier refusé',
                          style: TextStyle(
                            color: isAccepted ? _teal : _highAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          item['details'] as String? ?? '',
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feuille de décision (BottomSheet)
// ─────────────────────────────────────────────────────────────────────────────
class _DecisionSheet extends StatefulWidget {
  const _DecisionSheet({required this.request, required this.imageBytes});

  final ClassificationRequest request;
  final Future<Uint8List> imageBytes;

  @override
  State<_DecisionSheet> createState() => _DecisionSheetState();
}

class _DecisionSheetState extends State<_DecisionSheet> {
  String _level = 'HIGH';
  String _category = 'Pi\u00e8ce d\u2019identit\u00e9';
  final _rejectController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _documentNumberController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _placeOfBirthController = TextEditingController();
  final _expirationDateController = TextEditingController();
  bool _showRejectField = false;

  static const _highCategories = [
    'Pi\u00e8ce d\u2019identit\u00e9',
    'Passeport',
    'Permis de conduire',
    'Autres',
  ];
  static const _medCategories = [
    'Dipl\u00f4me',
    'Cours',
    'Notes',
    'Informations',
    'Autres',
  ];

  List<String> get _categories =>
      _level == 'HIGH' ? _highCategories : _medCategories;

  @override
  void dispose() {
    _rejectController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _documentNumberController.dispose();
    _dateOfBirthController.dispose();
    _placeOfBirthController.dispose();
    _expirationDateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + bottomInset),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // En-tête dossier
                Row(
                  children: [
                    const Icon(Icons.description_outlined, color: _teal, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.request.title,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${widget.request.userEmail} · ${widget.request.documentType}',
                  style: const TextStyle(color: _muted, fontSize: 12.5),
                ),
                if (widget.request.message?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      widget.request.message!,
                      style: const TextStyle(color: _ink, fontSize: 13),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Photo du document
                FutureBuilder<Uint8List>(
                  future: widget.imageBytes,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_not_supported_outlined,
                                  color: _muted, size: 28),
                              SizedBox(height: 6),
                              Text(
                                'Photo non disponible',
                                style: TextStyle(color: _muted, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    if (!snapshot.hasData) {
                      return Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(
                            color: _teal,
                            strokeWidth: 2,
                          ),
                        ),
                      );
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 18),

                // Séparateur
                const Divider(color: _border),
                const SizedBox(height: 14),

                // Titre de section
                const Text(
                  'Classifier ce dossier',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),

                // Niveau de sensibilité — sélecteur visuel
                Row(
                  children: [
                    Expanded(
                      child: _LevelTile(
                        label: 'Très sensible',
                        sublabel: 'CIN, Passeport…',
                        icon: Icons.shield_rounded,
                        selected: _level == 'HIGH',
                        accent: _highAccent,
                        bg: _highBg,
                        borderColor: _highBorder,
                        onTap: () => setState(() {
                          _level = 'HIGH';
                          _category = _highCategories.first;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _LevelTile(
                        label: 'Moy. sensible',
                        sublabel: 'Diplôme, Cours…',
                        icon: Icons.folder_special_rounded,
                        selected: _level == 'MEDIUM',
                        accent: _medAccent,
                        bg: _medBg,
                        borderColor: _medBorder,
                        onTap: () => setState(() {
                          _level = 'MEDIUM';
                          _category = _medCategories.first;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Container cible
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: InputDecoration(
                    labelText: 'Container de destination',
                    prefixIcon: const Icon(Icons.folder_open_rounded),
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border),
                    ),
                  ),
                  items: [
                    for (final cat in _categories)
                      DropdownMenuItem(value: cat, child: Text(cat)),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _category = value);
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Informations du document (à vérifier sur la photo)',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _firstNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Prénom',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _lastNameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nom',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _documentNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Numéro CIN / document',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _dateOfBirthController,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: 'Date de naissance (AAAA-MM-JJ)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _placeOfBirthController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Lieu de naissance',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _expirationDateController,
                  keyboardType: TextInputType.datetime,
                  decoration: const InputDecoration(
                    labelText: 'Date d’expiration (AAAA-MM-JJ)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 20),

                // Bouton Accepter
                SizedBox(
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(
                      context,
                      _AdminDecision(
                        accept: true,
                        level: _level,
                        category: _category,
                        firstName: _firstNameController.text.trim(),
                        lastName: _lastNameController.text.trim(),
                        documentNumber: _documentNumberController.text.trim(),
                        dateOfBirth: _dateOfBirthController.text.trim(),
                        placeOfBirth: _placeOfBirthController.text.trim(),
                        expirationDate: _expirationDateController.text.trim(),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text(
                      'Accepter et enregistrer',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Bouton Refuser (toggle)
                if (!_showRejectField)
                  TextButton.icon(
                    onPressed: () => setState(() => _showRejectField = true),
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text('Refuser la demande'),
                    style: TextButton.styleFrom(foregroundColor: _highAccent),
                  )
                else ...[
                  TextField(
                    controller: _rejectController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Motif du refus (optionnel)',
                      filled: true,
                      fillColor: _highBg,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _highBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: _highBorder),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(
                        context,
                        _AdminDecision(
                          accept: false,
                          rejectionReason:
                              _rejectController.text.trim().isEmpty
                                  ? null
                                  : _rejectController.text.trim(),
                        ),
                      ),
                      icon: const Icon(Icons.cancel_outlined),
                      label: const Text(
                        'Confirmer le refus',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _highAccent,
                        side: const BorderSide(color: _highAccent),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tile de niveau de sensibilité
// ─────────────────────────────────────────────────────────────────────────────
class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.selected,
    required this.accent,
    required this.bg,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final String sublabel;
  final IconData icon;
  final bool selected;
  final Color accent;
  final Color bg;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? bg : _white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? accent : _border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? accent : _muted, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? accent : _ink,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              sublabel,
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// États vides / erreurs
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_rounded, size: 52, color: _muted),
          SizedBox(height: 14),
          Text(
            'Aucun dossier en attente',
            style: TextStyle(
              color: _ink,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Les nouveaux dossiers apparaîtront ici.',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 40, color: _highAccent),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(backgroundColor: _teal),
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Modèle de décision
// ─────────────────────────────────────────────────────────────────────────────
class _AdminDecision {
  const _AdminDecision({
    required this.accept,
    this.level,
    this.category,
    this.rejectionReason,
    this.firstName,
    this.lastName,
    this.documentNumber,
    this.dateOfBirth,
    this.placeOfBirth,
    this.expirationDate,
  });

  final bool accept;
  final String? level;
  final String? category;
  final String? rejectionReason;
  final String? firstName;
  final String? lastName;
  final String? documentNumber;
  final String? dateOfBirth;
  final String? placeOfBirth;
  final String? expirationDate;
}


