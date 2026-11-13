import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../data/document_share_service.dart';
import '../domain/vault_document.dart';

const _teal = Color(0xFF087E78);
const _ink = Color(0xFF172B3A);
const _muted = Color(0xFF71808A);
const _line = Color(0xFFE5EBEB);

class DigitalWalletScreen extends StatefulWidget {
  const DigitalWalletScreen({
    required this.documents,
    required this.onAddDocument,
    this.onDeleteLocalDocument,
    this.documentShareService,
    this.initialCategory = 'Tous',
    super.key,
  });

  final List<VaultDocument> documents;
  final VoidCallback onAddDocument;
  final Future<void> Function(VaultDocument document)? onDeleteLocalDocument;
  final DocumentShareService? documentShareService;
  final String initialCategory;

  @override
  State<DigitalWalletScreen> createState() => _DigitalWalletScreenState();
}

class _DigitalWalletScreenState extends State<DigitalWalletScreen> {
  final _searchController = TextEditingController();
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
  }

  static const _filters = ['Tous', ...VaultDocument.categories];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<VaultDocument> get _visibleDocuments {
    final query = _searchController.text.trim().toLowerCase();
    return widget.documents.where((document) {
      final matchesCategory =
          _selectedCategory == 'Tous' || document.category == _selectedCategory;
      final matchesSearch =
          query.isEmpty ||
          document.title.toLowerCase().contains(query) ||
          document.category.toLowerCase().contains(query) ||
          document.holderName.toLowerCase().contains(query);
      return matchesCategory && matchesSearch;
    }).toList()..sort(
      (first, second) => second.createdAt.compareTo(first.createdAt),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = _visibleDocuments;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 30),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _buildHeader(),
              const SizedBox(height: 19),
              _buildSearchField(),
              const SizedBox(height: 16),
              _buildFilters(),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Mes documents',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${documents.length} ${documents.length == 1 ? 'document' : 'documents'}',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (documents.isEmpty)
                _buildEmptyState()
              else
                ...documents.map(
                  (document) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _WalletDocumentTile(
                      document: document,
                      onDeleteLocalDocument: widget.onDeleteLocalDocument,
                      documentShareService: widget.documentShareService,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Mon portefeuille',
                style: TextStyle(
                  color: _ink,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Tous vos documents au même endroit.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Ajouter un document',
          onPressed: widget.onAddDocument,
          style: IconButton.styleFrom(
            backgroundColor: _teal,
            foregroundColor: Colors.white,
            fixedSize: const Size(46, 46),
          ),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Rechercher un document...',
        hintStyle: const TextStyle(color: Color(0xFF9AA7B0), fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Effacer la recherche',
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: _teal, width: 1.4),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < _filters.length; index++) ...[
            ChoiceChip(
              label: Text(_filters[index]),
              selected: _selectedCategory == _filters[index],
              onSelected: (_) {
                setState(() => _selectedCategory = _filters[index]);
              },
              showCheckmark: false,
              labelStyle: TextStyle(
                color: _selectedCategory == _filters[index]
                    ? Colors.white
                    : _ink,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              selectedColor: _teal,
              backgroundColor: Colors.white,
              side: BorderSide(
                color: _selectedCategory == _filters[index] ? _teal : _line,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 5),
            ),
            if (index < _filters.length - 1) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilters =
        _selectedCategory != 'Tous' || _searchController.text.trim().isNotEmpty;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 31),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: const BoxDecoration(
              color: Color(0xFFE8F4F2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasFilters ? Icons.search_off_rounded : Icons.folder_open_rounded,
              color: _teal,
              size: 26,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            hasFilters ? 'Aucun résultat' : 'Votre portefeuille est vide',
            style: const TextStyle(
              color: _ink,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hasFilters
                ? 'Essayez une autre recherche ou catégorie.'
                : 'Ajoutez vos documents importants pour les retrouver facilement.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
          if (!hasFilters) ...[
            const SizedBox(height: 15),
            FilledButton.icon(
              onPressed: widget.onAddDocument,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Ajouter un document'),
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WalletDocumentTile extends StatelessWidget {
  const _WalletDocumentTile({
    required this.document,
    required this.onDeleteLocalDocument,
    required this.documentShareService,
  });

  final VaultDocument document;
  final Future<void> Function(VaultDocument document)? onDeleteLocalDocument;
  final DocumentShareService? documentShareService;

  @override
  Widget build(BuildContext context) {
    final accent = _categoryColor(document.category);
    final expiryDate = document.expiryDate;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: () => _openDetails(context),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: _line),
          ),
          child: Row(
            children: [
              _DocumentThumbnail(document: document, accent: accent),
              const SizedBox(width: 12),
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
                        fontSize: 13,
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
                    const SizedBox(height: 4),
                    Text(
                      'Ajouté le ${_formatDate(document.createdAt)}',
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                    if (expiryDate != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Expire le ${_formatDate(expiryDate)}',
                        style: TextStyle(
                          color: _isExpired(expiryDate)
                              ? const Color(0xFFC83D4D)
                              : _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (document.isLocal && onDeleteLocalDocument != null)
                IconButton(
                  tooltip: 'Supprimer ce document local',
                  onPressed: () => _deleteDocument(context),
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFC83D4D),
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: _muted,
                  size: 21,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetails(BuildContext context) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => _DocumentDetailsScreen(
            document: document,
            onDelete: document.isLocal ? onDeleteLocalDocument : null,
            documentShareService: documentShareService,
          ),
        ),
      );

  Future<void> _deleteDocument(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette CIN ?'),
        content: const Text(
          'La photo et les informations stockées sur cet appareil seront supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true || onDeleteLocalDocument == null) return;
    try {
      await onDeleteLocalDocument!(document);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('CIN supprimée de cet appareil.')),
        );
      }
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Suppression impossible : $error')),
        );
      }
    }
  }

  static _CategoryStyle _categoryColor(String category) {
    if (category == 'Passeport') {
      return const _CategoryStyle(
        Icons.flight_outlined,
        Color(0xFFFFF1E4),
        Color(0xFFCC8240),
      );
    }
    if (category == 'Diplôme') {
      return const _CategoryStyle(
        Icons.school_outlined,
        Color(0xFFF1ECFF),
        Color(0xFF7A60B7),
      );
    }
    if (category == 'Permis de conduire') {
      return const _CategoryStyle(
        Icons.directions_car_outlined,
        Color(0xFFEAF0FB),
        Color(0xFF537AB2),
      );
    }
    if (category == 'Autres') {
      return const _CategoryStyle(
        Icons.folder_outlined,
        Color(0xFFE6F4F0),
        _teal,
      );
    }
    return const _CategoryStyle(
      Icons.badge_outlined,
      Color(0xFFE8F2FF),
      Color(0xFF3976B8),
    );
  }

  static bool _isExpired(DateTime date) =>
      date.isBefore(DateTime.now()) && !_isToday(date);

  static bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}

class _CategoryStyle {
  const _CategoryStyle(this.icon, this.background, this.foreground);

  final IconData icon;
  final Color background;
  final Color foreground;
}

class _DocumentThumbnail extends StatefulWidget {
  const _DocumentThumbnail({required this.document, required this.accent});

  final VaultDocument document;
  final _CategoryStyle accent;

  @override
  State<_DocumentThumbnail> createState() => _DocumentThumbnailState();
}

class _DocumentThumbnailState extends State<_DocumentThumbnail> {
  late Future<Uint8List?>? _imageData;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _DocumentThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document.imageStoragePath !=
            widget.document.imageStoragePath ||
        oldWidget.document.localImagePath != widget.document.localImagePath) {
      _loadImage();
    }
  }

  void _loadImage() {
    final localPath = widget.document.localImagePath;
  
    _imageData = localPath == null ? null : File(localPath).readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.accent.background;
    final foreground = widget.accent.foreground;
    final imageFuture = _imageData;
    if (imageFuture == null) {
      return _placeholder(background, foreground);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 45,
        height: 45,
        child: FutureBuilder<Uint8List?>(
          future: imageFuture,
          builder: (context, snapshot) {
            final imageBytes = snapshot.data;
            if (snapshot.hasError || imageBytes == null || imageBytes.isEmpty) {
              return _placeholder(background, foreground);
            }
            return Image.memory(
              imageBytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _placeholder(background, foreground),
            );
          },
        ),
      ),
    );
  }

  Widget _placeholder(Color background, Color foreground) {
    return Container(
      width: 45,
      height: 45,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(widget.accent.icon, color: foreground, size: 22),
    );
  }
}

class _DocumentDetailsScreen extends StatelessWidget {
  const _DocumentDetailsScreen({
    required this.document,
    required this.onDelete,
    required this.documentShareService,
  });

  final VaultDocument document;
  final Future<void> Function(VaultDocument document)? onDelete;
  final DocumentShareService? documentShareService;

  @override
  Widget build(BuildContext context) {
    final imagePath = document.localImagePath;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        title: Text(document.title),
        actions: [
          if (onDelete != null)
            IconButton(
              tooltip: 'Supprimer la CIN',
              onPressed: () => _delete(context),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (imagePath != null) ...[
            const Text('Recto', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(imagePath),
                height: 240,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 190,
                  child: Center(
                    child: Text('Photo locale du document introuvable.'),
                  ),
                ),
              ),
            ),
          ],
          if (document.localBackImagePath != null) ...[
            const SizedBox(height: 12),
            const Text('Verso', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(
                File(document.localBackImagePath!),
                height: 240,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  height: 190,
                  child: Center(child: Text('Photo Verso introuvable.')),
                ),
              ),
            ),
          ],
          if (imagePath == null && document.imageStoragePath != null)
            const Text(
              'La photo de ce document distant n’est pas disponible localement.',
            ),
          const SizedBox(height: 18),
          _DetailLine(label: 'Type', value: document.category),
          _DetailLine(label: 'Titulaire', value: document.holderName),
          _DetailLine(label: 'Nom', value: document.lastName),
          _DetailLine(label: 'Prénom', value: document.firstName),
          _DetailLine(
            label: document.category == 'Passeport'
                ? 'Numéro de passeport'
                : 'Numéro du document',
            value: document.documentNumber ?? document.cinNumber,
          ),
          _DetailLine(label: 'Date de naissance', value: document.dateOfBirth),
          _DetailLine(label: 'Lieu de naissance', value: document.placeOfBirth),
          _DetailLine(
            label: 'Date d’expiration',
            value: document.expiryDate == null
                ? null
                : _WalletDocumentTile._formatDate(document.expiryDate!),
          ),
          _DetailLine(
            label: 'Date d’ajout',
            value: _WalletDocumentTile._formatDate(document.createdAt),
          ),
          const SizedBox(height: 24),
          _DocumentShareSection(
            document: document,
            service: documentShareService,
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context) async {
    final callback = onDelete;
    if (callback == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer cette CIN ?'),
        content: const Text(
          'La photo et les informations stockées sur cet appareil seront supprimées.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await callback(document);
      if (context.mounted) Navigator.of(context).pop();
    } on Exception catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Suppression impossible : $error')),
        );
      }
    }
  }
}

class _DocumentShareSection extends StatefulWidget {
  const _DocumentShareSection({required this.document, required this.service});

  final VaultDocument document;
  final DocumentShareService? service;

  @override
  State<_DocumentShareSection> createState() => _DocumentShareSectionState();
}

class _DocumentShareSectionState extends State<_DocumentShareSection> {
  static const _fieldLabels = {
    'category': 'Catégorie',
    'holderName': 'Titulaire',
    'firstName': 'Prénom',
    'lastName': 'Nom',
    'documentNumber': 'Numéro du document',
    'dateOfBirth': 'Date de naissance',
    'placeOfBirth': 'Lieu de naissance',
    'expirationDate': 'Date d’expiration',
  };
  static const _durations = [5, 15, 30, 60, 1440];

  final Set<String> _selectedFields = {};
  List<DocumentShareSession> _shares = const [];
  DocumentShareSession? _createdShare;
  String? _displayMode;
  String? _loadError;
  int _durationMinutes = 15;
  bool _isLoading = true;
  bool _hasLoadedShares = false;
  bool _isCreating = false;
  String? _revokingShareId;

  DocumentShareService? get _shareService => widget.service;

  @override
  void initState() {
    super.initState();
    _isLoading = false;
    // Preselect the available document fields so the QR action is usable
    // immediately. Users can still uncheck any field before sharing.
    _selectedFields.addAll(_availableFields.keys);
  }

  Map<String, String> get _availableFields {
    final document = widget.document;
    final expiry = document.expirationDate ?? document.expiryDate;
    final values = <String, String?>{
      'category': document.category,
      'holderName': document.holderName,
      'firstName': document.firstName ?? document.name,
      'lastName': document.lastName ?? document.surname,
      'documentNumber': document.documentNumber ?? document.cinNumber,
      'dateOfBirth': document.dateOfBirth,
      'placeOfBirth': document.placeOfBirth,
      'expirationDate': expiry == null ? null : _formatIsoDate(expiry),
    };
    return Map<String, String>.fromEntries(
      values.entries
          .where(
            (entry) => entry.value != null && entry.value!.trim().isNotEmpty,
          )
          .map((entry) => MapEntry(entry.key, entry.value!.trim())),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fields = _availableFields;
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Partager temporairement',
              style: TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Choisissez les informations et les photos Recto/Verso à transmettre. Les images seront accessibles uniquement via ce lien temporaire.',
              style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 12),
            if (fields.isEmpty)
              const Text(
                'Aucune information disponible pour le partage.',
                style: TextStyle(color: _muted, fontSize: 12),
              )
            else
              ...fields.entries.map(
                (entry) => CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    _fieldLabels[entry.key]!,
                    style: const TextStyle(color: _ink, fontSize: 13),
                  ),
                  subtitle: Text(
                    entry.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
                  value: _selectedFields.contains(entry.key),
                  onChanged: _isCreating
                      ? null
                      : (selected) {
                          setState(() {
                            if (selected == true) {
                              _selectedFields.add(entry.key);
                            } else {
                              _selectedFields.remove(entry.key);
                            }
                          });
                        },
                ),
              ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _durationMinutes,
              decoration: const InputDecoration(
                labelText: 'Durée du partage',
                border: OutlineInputBorder(),
              ),
              items: _durations
                  .map(
                    (minutes) => DropdownMenuItem(
                      value: minutes,
                      child: Text(_durationLabel(minutes)),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _isCreating
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _durationMinutes = value);
                      }
                    },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isCreating || _selectedFields.isEmpty
                        ? null
                        : () => _createShare('qr'),
                    icon: const Icon(Icons.qr_code_2_rounded),
                    label: const Text('Partager par QR Code'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isCreating || _selectedFields.isEmpty
                    ? null
                    : () => _createShare('link'),
                icon: const Icon(Icons.link_rounded),
                label: const Text('Partager par lien'),
              ),
            ),
            if (_isCreating) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(color: _teal),
            ],
            if (_loadError != null) ...[
              const SizedBox(height: 10),
              Text(
                _loadError!,
                style: const TextStyle(color: Color(0xFFC83D4D), fontSize: 12),
              ),
            ],
            if (_createdShare != null) ...[
              const Divider(height: 24),
              _buildCreatedShare(_createdShare!),
            ],
            const Divider(height: 24),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Sessions de partage',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Actualiser les sessions',
                  onPressed: _isLoading ? null : _loadShares,
                  icon: const Icon(Icons.refresh_rounded, color: _teal),
                ),
              ],
            ),
            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: _teal))
            else if (_hasLoadedShares && _shares.isEmpty)
              const Text(
                'Aucun partage actif ou expiré.',
                style: TextStyle(color: _muted, fontSize: 12),
              )
            else if (_shares.isNotEmpty) ...[
              ..._shares.map(_buildShareStatus),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCreatedShare(DocumentShareSession share) {
    final isQr = _displayMode == 'qr';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Expire le ${_formatDateTime(share.expiresAt)}',
          style: const TextStyle(
            color: _teal,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (isQr) ...[
          const SizedBox(height: 12),
          Center(
            child: QrImageView(
              data: share.url,
              size: 210,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: _ink,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: _ink,
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          SelectableText(
            share.url,
            style: const TextStyle(color: _ink, fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _copyLink(share.url),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copier le lien'),
            ),
            TextButton.icon(
              onPressed: () => _shareLink(share.url),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: const Text('Partager'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildShareStatus(DocumentShareSession share) {
    final expired = share.isExpired || share.status == 'expired';
    final revoked = share.status == 'revoked';
    final status = revoked
        ? 'Révoqué'
        : expired
        ? 'Expiré'
        : 'Actif';
    final color = revoked || expired ? _muted : _teal;
    final isRevoking = _revokingShareId == share.id;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        'Partage $status',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        'Expire le ${_formatDateTime(share.expiresAt)}',
        style: const TextStyle(color: _muted, fontSize: 11),
      ),
      trailing: expired || revoked
          ? null
          : TextButton(
              onPressed: isRevoking ? null : () => _revokeShare(share),
              child: isRevoking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Révoquer'),
            ),
    );
  }

  Future<void> _loadShares() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final service = _shareService;
      if (service == null) {
        throw StateError('Le service de partage Cloudflare est indisponible.');
      }
      final shares = await service.listShares(documentId: widget.document.id);
      if (!mounted) return;
      setState(() {
        _shares = shares;
        _hasLoadedShares = true;
        _loadError = null;
        _isLoading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError =
            'Chargement des partages impossible : ${_errorText(error)}';
        _isLoading = false;
      });
    }
  }

  Future<Uint8List?> _readShareImage(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) {
      throw StateError('Une des photos du document est introuvable sur cet appareil.');
    }
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || bytes.length > 6 * 1024 * 1024) {
      throw StateError('Chaque photo doit être valide et peser au maximum 6 Mo.');
    }
    return bytes;
  }

  String _mimeForPath(String path) =>
      path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';

  Future<void> _createShare(String displayMode) async {
    if (_isCreating || _selectedFields.isEmpty) return;
    setState(() {
      _isCreating = true;
      _loadError = null;
    });
    try {
      final selected = Map.fromEntries(
        _availableFields.entries.where(
          (entry) => _selectedFields.contains(entry.key),
        ),
      );
      final service = _shareService;
      if (service == null) {
        throw StateError('Le service de partage Cloudflare est indisponible.');
      }
      final frontBytes = await _readShareImage(widget.document.localImagePath);
      final backBytes = await _readShareImage(widget.document.localBackImagePath);
      if (widget.document.category == 'Pièce d’identité' && backBytes == null) {
        throw StateError('Ajoutez la photo du Verso de votre CIN avant de créer le QR Code.');
      }
      if (frontBytes == null) {
        throw StateError('La photo Recto du document est introuvable sur cet appareil.');
      }
      final share = await service.createShare(
        documentId: widget.document.id,
        fields: selected,
        durationMinutes: _durationMinutes,
        frontImageBytes: frontBytes,
        frontImageMimeType: _mimeForPath(widget.document.localImagePath!),
        backImageBytes: backBytes,
        backImageMimeType: backBytes == null
            ? null
            : _mimeForPath(widget.document.localBackImagePath!),
      );
      if (!mounted) return;
      setState(() {
        _createdShare = share;
        _displayMode = displayMode;
        _shares = [share, ..._shares];
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _loadError = 'Création impossible : ${_errorText(error)}');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Future<void> _revokeShare(DocumentShareSession share) async {
    setState(() => _revokingShareId = share.id);
    try {
      final service = _shareService;
      if (service == null) {
        throw StateError('Le service de partage Cloudflare est indisponible.');
      }
      await service.revokeShare(share.id);
      if (!mounted) return;
      setState(() {
        final revokedShare = DocumentShareSession(
          id: share.id,
          url: share.url,
          expiresAt: share.expiresAt,
          createdAt: share.createdAt,
          status: 'revoked',
        );
        _shares = _shares
            .map((item) => item.id == share.id ? revokedShare : item)
            .toList();
        if (_createdShare?.id == share.id) _createdShare = null;
      });
      _showMessage('Partage révoqué.');
    } on Exception catch (error) {
      if (mounted) {
        _showMessage('Révocation impossible : ${_errorText(error)}');
      }
    } finally {
      if (mounted) setState(() => _revokingShareId = null);
    }
  }

  Future<void> _copyLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) _showMessage('Lien copié.');
  }

  Future<void> _shareLink(String url) async {
    try {
      await SharePlus.instance.share(ShareParams(text: url));
    } on Exception catch (error) {
      if (mounted) _showMessage('Partage impossible : ${_errorText(error)}');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  static String _durationLabel(int minutes) {
    if (minutes == 1440) return '24 heures';
    if (minutes >= 60) return '${minutes ~/ 60} heure';
    return '$minutes minutes';
  }

  static String _formatIsoDate(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _formatDateTime(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} à ${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String _errorText(Exception error) => error.toString();
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final displayValue = value?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              displayValue == null || displayValue.isEmpty
                  ? 'Non renseigné'
                  : displayValue,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
