import 'package:flutter/material.dart';

import '../domain/vault_document.dart';
import '../../../services/document_reminder_service.dart';

const _teal = Color(0xFF087E78);
const _ink = Color(0xFF172B3A);
const _muted = Color(0xFF71808A);

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({
    required this.documents,
    required this.reminderService,
    super.key,
  });

  final List<VaultDocument> documents;
  final DocumentReminderService reminderService;

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final Set<String> _scheduled = {};
  bool _loading = true;
  String? _error;

  List<VaultDocument> get _documentsWithExpiry {
    final documents = widget.documents
        .where((document) =>
            (document.expirationDate ?? document.expiryDate) != null)
        .toList();
    documents.sort((a, b) =>
        (a.expirationDate ?? a.expiryDate)!
            .compareTo((b.expirationDate ?? b.expiryDate)!));
    return documents;
  }

  @override
  void initState() {
    super.initState();
    _loadScheduled();
  }

  Future<void> _loadScheduled() async {
    try {
      for (final document in _documentsWithExpiry) {
        if (await widget.reminderService.isScheduled(document.id)) {
          _scheduled.add(document.id);
        }
      }
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _toggleReminder(VaultDocument document) async {
    final enabled = _scheduled.contains(document.id);
    try {
      if (enabled) {
        await widget.reminderService.cancelExpiryReminder(document.id);
        _scheduled.remove(document.id);
      } else {
        await widget.reminderService.scheduleExpiryReminder(
          document,
          daysBefore: 7,
        );
        _scheduled.add(document.id);
      }
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled
                ? 'Rappel désactivé.'
                : 'Rappel programmé 7 jours avant expiration.'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Impossible de programmer le rappel : $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final documents = _documentsWithExpiry;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F7),
      appBar: AppBar(
        title: const Text('Mes rappels'),
        backgroundColor: Colors.white,
        foregroundColor: _ink,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : documents.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_active_outlined,
                                size: 52, color: _teal),
                            SizedBox(height: 14),
                            Text(
                              'Aucune date d’expiration enregistrée',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _ink,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Ajoutez une date d’expiration à un document pour programmer un rappel.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: _muted, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const Text(
                          'Recevez une notification locale 7 jours avant l’expiration de vos documents.',
                          style: TextStyle(color: _muted, height: 1.4),
                        ),
                        const SizedBox(height: 14),
                        for (final document in documents)
                          _ReminderCard(
                            document: document,
                            enabled: _scheduled.contains(document.id),
                            onPressed: () => _toggleReminder(document),
                          ),
                      ],
                    ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.document,
    required this.enabled,
    required this.onPressed,
  });

  final VaultDocument document;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final expiry = document.expirationDate ?? document.expiryDate!;
    final expired = !DateTime(expiry.year, expiry.month, expiry.day)
        .isAfter(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE5EBEB)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(document.title,
                style: const TextStyle(
                    color: _ink, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              '${document.category} · Expire le ${expiry.day.toString().padLeft(2, '0')}/${expiry.month.toString().padLeft(2, '0')}/${expiry.year}',
              style: TextStyle(
                color: expired ? const Color(0xFFC83D4D) : _muted,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: expired ? null : onPressed,
                icon: Icon(enabled
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined),
                label: Text(expired
                    ? 'Document expiré'
                    : enabled
                        ? 'Désactiver le rappel'
                        : 'Activer le rappel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
