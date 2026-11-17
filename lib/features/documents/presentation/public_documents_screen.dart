import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../services/cloudflare_api_config.dart';

/// Documents publiés uniquement après validation Admin avec le niveau MEDIUM.
class PublicDocumentsScreen extends StatefulWidget {
  const PublicDocumentsScreen({this.onBack, super.key});
  final VoidCallback? onBack;

  @override
  State<PublicDocumentsScreen> createState() => _PublicDocumentsScreenState();
}

class _PublicDocumentsScreenState extends State<PublicDocumentsScreen> {
  final _searchController = TextEditingController();
  String _selectedCategory = 'Tous';
  late Future<List<_PublicDoc>> _documents;

  static const _teal = Color(0xFF18B6A5);
  static const _ink = Color(0xFF172B3A);
  static const _muted = Color(0xFF71808A);
  static const _canvas = Color(0xFFF4F7F7);
  static const _line = Color(0xFFE5EBEB);
  static const _categories = ['Tous', 'Diplôme', 'Cours', 'Notes', 'Informations', 'Autres'];

  String get _baseUrl => CloudflareApiConfig.baseUrl;

  @override
  void initState() {
    super.initState();
    _documents = _loadDocuments();
  }

  Future<List<_PublicDoc>> _loadDocuments() async {
    final response = await http.get(
      Uri.parse(_baseUrl + '/api/public-documents'),
      headers: const {'Accept': 'application/json'},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Impossible de charger les documents (' + response.statusCode.toString() + ').');
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['success'] != true || data['documents'] is! List) {
      throw const FormatException('Réponse des documents publics invalide.');
    }
    return (data['documents'] as List)
        .whereType<Map<String, dynamic>>()
        .map(_PublicDoc.fromJson)
        .toList(growable: false);
  }

  Future<void> _refresh() async {
    final future = _loadDocuments();
    setState(() => _documents = future);
    await future;
  }

  Future<Uint8List> _loadPhoto(String id, {bool back = false}) async {
    final side = back ? 'back-photo' : 'photo';
    final response = await http.get(
      Uri.parse(_baseUrl + '/api/public-documents/' + Uri.encodeComponent(id) + '/' + side),
    ).timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      var serverMessage = response.body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['error'] is String) {
          serverMessage = decoded['error'] as String;
        }
      } on FormatException {
        // Keep the raw response for diagnostics when it is not JSON.
      }
      debugPrint(
        'PUBLIC DOCUMENT PHOTO ERROR: status=${response.statusCode}, '
        'side=${back ? 'back' : 'front'}, id=$id, response=$serverMessage',
      );
      throw StateError(
        'Photo indisponible (HTTP ${response.statusCode}) : $serverMessage',
      );
    }
    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.startsWith('image/')) {
      debugPrint(
        'PUBLIC DOCUMENT PHOTO INVALID CONTENT: '
        'status=${response.statusCode}, content-type=$contentType, id=$id',
      );
      throw const FormatException(
        'Le serveur n’a pas renvoyé un fichier image valide.',
      );
    }
    if (response.bodyBytes.isEmpty) {
      throw const FormatException('Le serveur a renvoyé une photo vide.');
    }
    return response.bodyBytes;
  }

  List<_PublicDoc> _filter(List<_PublicDoc> documents) {
    final query = _searchController.text.trim().toLowerCase();
    return documents.where((doc) {
      final matchesCategory = _selectedCategory == 'Tous' || doc.category == _selectedCategory;
      final matchesQuery = query.isEmpty ||
          doc.title.toLowerCase().contains(query) ||
          doc.category.toLowerCase().contains(query);
      return matchesCategory && matchesQuery;
    }).toList(growable: false);
  }

  Future<void> _openDocument(_PublicDoc doc) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PublicDocumentViewer(doc: doc, loadPhoto: _loadPhoto),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Rechercher un document…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.isEmpty ? null : IconButton(
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () { _searchController.clear(); setState(() {}); },
                  ),
                ),
              ),
            ),
            _categoryFilter(),
            Expanded(
              child: FutureBuilder<List<_PublicDoc>>(
                future: _documents,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _emptyState(
                      Icons.cloud_off_outlined,
                      'Chargement impossible',
                      snapshot.error.toString(),
                      TextButton.icon(
                        onPressed: () => setState(() => _documents = _loadDocuments()),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Réessayer'),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator(color: _teal));
                  }
                  final docs = _filter(snapshot.data!);
                  if (docs.isEmpty) {
                    return _emptyState(
                      Icons.folder_open_outlined,
                      'Aucun document publié',
                      'Les documents apparaîtront ici après leur acceptation par l’administrateur avec le niveau moyen.',
                    );
                  }
                  return RefreshIndicator(
                    color: _teal,
                    onRefresh: _refresh,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, index) => _PublicDocumentTile(
                        doc: docs[index],
                        onTap: () => _openDocument(docs[index]),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() => Container(
    padding: const EdgeInsets.fromLTRB(10, 16, 18, 14),
    decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: _line))),
    child: Row(
      children: [
        IconButton(
          onPressed: widget.onBack ?? () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19, color: _ink),
        ),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Documents partagés', style: TextStyle(color: _ink, fontSize: 18, fontWeight: FontWeight.w800)),
              Text('Documents validés par l’administrateur', style: TextStyle(color: _muted, fontSize: 11.5)),
            ],
          ),
        ),
        const Icon(Icons.public_rounded, color: _teal),
      ],
    ),
  );

  Widget _categoryFilter() => SizedBox(
    height: 52,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      itemCount: _categories.length,
      separatorBuilder: (_, __) => const SizedBox(width: 8),
      itemBuilder: (_, index) {
        final category = _categories[index];
        final selected = category == _selectedCategory;
        return GestureDetector(
          onTap: () => setState(() => _selectedCategory = category),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? _teal : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? _teal : _line),
            ),
            child: Center(
              child: Text(category, style: TextStyle(
                color: selected ? Colors.white : _muted,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              )),
            ),
          ),
        );
      },
    ),
  );

  Widget _emptyState(IconData icon, String title, String message, [Widget? action]) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _teal),
          const SizedBox(height: 14),
          Text(title, style: const TextStyle(color: _ink, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: _muted, height: 1.45)),
          if (action != null) action,
        ],
      ),
    ),
  );
}

class _PublicDoc {
  const _PublicDoc({
    required this.id,
    required this.title,
    required this.category,
    required this.hasBackImage,
  });

  final String id;
  final String title;
  final String category;
  final bool hasBackImage;

  factory _PublicDoc.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final category = json['category'];
    if (id is! String || title is! String || category is! String) {
      throw const FormatException('Document public invalide.');
    }
    return _PublicDoc(
      id: id,
      title: title,
      category: category,
      hasBackImage: json['has_back_image'] == true || json['has_back_image'] == 1,
    );
  }
}

class _PublicDocumentTile extends StatelessWidget {
  const _PublicDocumentTile({required this.doc, required this.onTap});
  final _PublicDoc doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE5EBEB)),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0x1A18B6A5),
              child: Icon(Icons.description_outlined, color: Color(0xFF18B6A5)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(doc.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF172B3A), fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(doc.category, style: const TextStyle(color: Color(0xFF18B6A5), fontSize: 11, fontWeight: FontWeight.w700)),
                  if (doc.hasBackImage)
                    const Text('Recto + Verso', style: TextStyle(color: Color(0xFF71808A), fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFF71808A)),
          ],
        ),
      ),
    ),
  );
}

class _PublicDocumentViewer extends StatelessWidget {
  const _PublicDocumentViewer({required this.doc, required this.loadPhoto});
  final _PublicDoc doc;
  final Future<Uint8List> Function(String, {bool back}) loadPhoto;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
    decoration: const BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 8, 12),
            child: Row(
              children: [
                Expanded(child: Text(doc.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _PhotoPanel(label: 'Document', photo: loadPhoto(doc.id)),
                if (doc.hasBackImage) ...[
                  const SizedBox(height: 16),
                  _PhotoPanel(label: 'Verso', photo: loadPhoto(doc.id, back: true)),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _PhotoPanel extends StatelessWidget {
  const _PhotoPanel({required this.label, required this.photo});
  final String label;
  final Future<Uint8List> photo;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      FutureBuilder<Uint8List>(
        future: photo,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Padding(padding: EdgeInsets.all(24), child: Text('Impossible de charger cette photo.'));
          }
          if (!snapshot.hasData) {
            return const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()));
          }
          return InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: Image.memory(snapshot.data!, fit: BoxFit.contain),
          );
        },
      ),
    ],
  );
}
