// lib/services/device_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_config.dart';

class DeviceService {
  static const _prefsKey = 'device_token';

  /// Call right after a successful login.
  static Future<void> registerDeviceToken() async {
    final messaging = FirebaseMessaging.instance;

    // Ask for push permissions (iOS + Android 13+)
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Fetch FCM token
    final token = await messaging.getToken();
    print("🔥 FCM getToken => ${token?.substring((token?.length ?? 0) - 10)}");
    if (token == null || token.isEmpty) return;

    // Save locally for later API calls (notifications screen, etc.)
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, token);

    // Send to backend so the server knows this device
    final authToken = prefs.getString("auth_token");
    if (authToken != null && authToken.isNotEmpty) {
      final res = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/user/device-token"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $authToken",
        },
        body: '{"token":"$token"}',
      );
      print("🔥 /user/device-token => ${res.statusCode} ${res.body}");
    }
  }

  /// Optional helper if you need the token elsewhere
  static Future<String?> getStoredDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey);
  }

  /// Call on app start (e.g., main.dart) to keep token synced after refresh.
  static void listenTokenRefresh() {
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      print("♻️ FCM onTokenRefresh => ${newToken.substring(newToken.length - 10)}");

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, newToken);

      final authToken = prefs.getString("auth_token");
      if (authToken == null || authToken.isEmpty) return;

      await http.post(
        Uri.parse("${ApiConfig.baseUrl}/user/device-token"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $authToken",
        },
        body: '{"token":"$newToken"}',
      );
    });
  }

  /// Call on logout to detach this device from the user and clear local cache.
  static Future<void> logoutCleanup() async {
    final prefs = await SharedPreferences.getInstance();
    final authToken = prefs.getString("auth_token");
    final token = prefs.getString(_prefsKey);

    if (authToken != null && authToken.isNotEmpty && token != null && token.isNotEmpty) {
      await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/user/device-token"),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "Bearer $authToken",
        },
        body: '{"token":"$token"}',
      );
    }

    await prefs.remove(_prefsKey);
    // If you want to force a fresh FCM on next login, uncomment:
    // await FirebaseMessaging.instance.deleteToken();
  }
}
