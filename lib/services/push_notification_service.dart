import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'document_api_service.dart';

class PushNotificationService {
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _foregroundSubscription;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel =
      AndroidNotificationChannel(
    'smartvault_user_updates',
    'SmartVault updates',
    description: 'Notifications about document review and account updates.',
    importance: Importance.max,
  );

  Future<void> initialize(DocumentApiService api) async {
    try {
      const initializationSettings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _localNotifications.initialize(initializationSettings);
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('Notification permission denied');
        return;
      }

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await api.registerPushToken(token: token, platform: 'android');
        debugPrint('FCM token registered successfully');
      } else {
        debugPrint('FCM token is not available yet');
      }

      await _tokenSubscription?.cancel();
      _tokenSubscription = messaging.onTokenRefresh.listen((newToken) async {
        try {
          await api.registerPushToken(token: newToken, platform: 'android');
          debugPrint('FCM token refreshed successfully');
        } catch (error) {
          debugPrint('FCM token refresh error: $error');
        }
      });

      await _foregroundSubscription?.cancel();
      _foregroundSubscription = FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) async {
          final notification = message.notification;
          final title = notification?.title ??
              message.data['title']?.toString() ??
              'SmartVault Pro';
          final body = notification?.body ??
              message.data['body']?.toString() ??
              'Une mise à jour de votre document est disponible.';
          try {
            await _localNotifications.show(
              message.hashCode,
              title,
              body,
              NotificationDetails(
                android: AndroidNotificationDetails(
                  _channel.id,
                  _channel.name,
                  channelDescription: _channel.description,
                  importance: Importance.max,
                  priority: Priority.high,
                  icon: '@mipmap/ic_launcher',
                ),
              ),
              payload: message.data['request_id']?.toString(),
            );
          } catch (error) {
            debugPrint('Foreground notification display failed: $error');
          }
        },
      );
      debugPrint('Foreground FCM listener registered');
    } catch (error, stackTrace) {
      debugPrint('Push notification initialization error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    await _foregroundSubscription?.cancel();
    _tokenSubscription = null;
    _foregroundSubscription = null;
  }
}
