import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api_client.dart';

class DeviceService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Call this AFTER login succeeds (token saved) to register device → backend
  static Future<void> registerDeviceToken() async {
    final fcmToken = await _messaging.getToken();
    if (fcmToken == null) return;
    await apiPost('/api/device/register', {
      'token': fcmToken,
      'platform': Platform.isAndroid ? 'android' : 'ios',
      'appVersion': '1.0.0',
    });
  }

  /// Call this on logout (optional but recommended)
  static Future<void> unregisterDeviceToken() async {
    final fcmToken = await _messaging.getToken();
    if (fcmToken == null) return;
    await apiDelete('/api/device/unregister', {'token': fcmToken});
  }

  /// Start listening once (e.g., in main/initState) to update backend on refresh
  static void listenTokenRefresh() {
    _messaging.onTokenRefresh.listen((newToken) async {
      await apiPost('/api/device/register', {
        'token': newToken,
        'platform': Platform.isAndroid ? 'android' : 'ios',
        'appVersion': '1.0.0',
      });
    });
  }
}
