
import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'document_api_service.dart';

class PushNotificationService {
  StreamSubscription<String>? _tokenSubscription;

  Future<void> initialize(DocumentApiService api) async {
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus ==
          AuthorizationStatus.denied) {
        debugPrint('Notification permission denied');
        return;
      }

      final token = await messaging.getToken();

      if (token != null && token.isNotEmpty) {
        await api.registerPushToken(
          token: token,
          platform: 'android',
        );

        debugPrint('FCM token registered successfully');
      }

      await _tokenSubscription?.cancel();

      _tokenSubscription =
          messaging.onTokenRefresh.listen((newToken) async {
        try {
          await api.registerPushToken(
            token: newToken,
            platform: 'android',
          );

          debugPrint('FCM token refreshed successfully');
        } catch (e) {
          debugPrint('FCM token refresh error: $e');
        }
      });
    } catch (e) {
      debugPrint('Push notification initialization error: $e');
    }
  }

  Future<void> dispose() async {
    await _tokenSubscription?.cancel();
    _tokenSubscription = null;
  }
}
