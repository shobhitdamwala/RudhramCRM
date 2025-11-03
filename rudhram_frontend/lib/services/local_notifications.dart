// lib/services/local_notifications.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

typedef NotificationTapHandler = void Function(String payload);

class LocalNotifications {
  static final FlutterLocalNotificationsPlugin fln =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel highChannel = AndroidNotificationChannel(
    'high_importance',
    'High Importance',
    description: 'Heads-up notifications',
    importance: Importance.high,
  );

  /// Call once at app start (main.dart)
  static Future<void> init({NotificationTapHandler? onTap}) async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    await fln.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload != null && payload.isNotEmpty) onTap?.call(payload);
      },
    );

    if (Platform.isAndroid) {
      final android = fln.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(highChannel);
    }
  }

  /// Fire a very simple local notification (for testing)
  static Future<void> showBasic({
    String? title,
    String? body,
    Map<String, dynamic>? payload,
  }) async {
    await fln.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000), // unique id
      title ?? 'Test Notification',
      body ?? 'It works 🎉',
      NotificationDetails(
        android: AndroidNotificationDetails(
          highChannel.id,
          highChannel.name,
          channelDescription: highChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(payload ?? {'type': 'test'}),
    );
  }
}
