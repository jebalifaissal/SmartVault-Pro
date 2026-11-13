import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../features/documents/domain/vault_document.dart';

class DocumentReminderService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Tunis'));
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
    );
    await _notifications.initialize(settings: settings);
    final android = _notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    _initialized = true;
  }

  int notificationId(String documentId) {
    var hash = 0x811c9dc5;
    for (final unit in documentId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }

  Future<bool> isScheduled(String documentId) async {
    await initialize();
    final id = notificationId(documentId);
    final pending = await _notifications.pendingNotificationRequests();
    return pending.any((request) => request.id == id);
  }

  Future<void> scheduleExpiryReminder(
    VaultDocument document, {
    int daysBefore = 7,
  }) async {
    await initialize();
    final expiry = document.expirationDate ?? document.expiryDate;
    if (expiry == null) {
      throw StateError('Ce document ne possède pas de date d’expiration.');
    }
    final now = tz.TZDateTime.now(tz.local);
    final expiryDay = tz.TZDateTime(
      tz.local,
      expiry.year,
      expiry.month,
      expiry.day,
    );
    if (!expiryDay.isAfter(
      tz.TZDateTime(tz.local, now.year, now.month, now.day),
    )) {
      throw StateError('Ce document est déjà expiré.');
    }

    var reminderDate = tz.TZDateTime(
      tz.local,
      expiry.year,
      expiry.month,
      expiry.day,
      9,
    ).subtract(Duration(days: daysBefore));
    if (!reminderDate.isAfter(now)) {
      reminderDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9);
      if (!reminderDate.isAfter(now)) {
        reminderDate = now.add(const Duration(minutes: 2));
      }
    }

    final id = notificationId(document.id);
    await _notifications.cancel(id: id);
    await _notifications.zonedSchedule(
      id: id,
      title: 'Rappel SmartVault Pro',
      body: 'Le document « ${document.title} » expire le ${_formatDate(expiry)}.',
      scheduledDate: reminderDate,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'document_expiry_reminders',
          'Rappels des documents',
          channelDescription: 'Rappels avant expiration des documents',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: document.id,
    );
  }

  Future<void> cancelExpiryReminder(String documentId) async {
    await initialize();
    await _notifications.cancel(id: notificationId(documentId));
  }

  static String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
