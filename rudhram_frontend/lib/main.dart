// lib/main.dart
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'package:rudhram_frontend/screens/splash_screen.dart';
import 'package:rudhram_frontend/screens/login_screen.dart';
import 'utils/constants.dart';
import 'services/device_service.dart';
import 'services/local_notifications.dart'; // ⬅️ NEW

// Screens you already have:
import 'screens/meeting_screen.dart';

// Background FCM handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // process message.data if needed
}

// Deep-link helpers
void _handleDeepLinkData(Map<String, dynamic> data) {
  final payload =
      data['payload'] ?? jsonEncode({'type': data['type'], 'meetingId': data['meetingId']});
  if (payload is String) _handleDeepLinkPayload(payload);
}

void _handleDeepLinkPayload(String payload) {
  try {
    final map = jsonDecode(payload) as Map<String, dynamic>;
    if (map['type'] == 'meeting' && map['meetingId'] != null) {
      navigatorKey.currentState?.pushNamed('/meeting', arguments: map['meetingId']);
    }
  } catch (_) {
    // ignore bad payload
  }
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // ⬇️ Local notifications init (taps go to the deep-link handler)
  await LocalNotifications.init(onTap: _handleDeepLinkPayload);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const RudhramApp());
}

class RudhramApp extends StatefulWidget {
  const RudhramApp({super.key});
  @override
  State<RudhramApp> createState() => _RudhramAppState();
}

class _RudhramAppState extends State<RudhramApp> {
  @override
  void initState() {
    super.initState();
    _initFirebaseMessaging();
    DeviceService.listenTokenRefresh();
  }

  Future<void> _initFirebaseMessaging() async {
    final messaging = FirebaseMessaging.instance;

    // Permissions (iOS + Android 13+)
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Foreground FCM debug log
    FirebaseMessaging.onMessage.listen((m) {
      debugPrint('📨 Foreground FCM: ${m.notification?.title} | data: ${m.data}');
    });

    // App opened from notification (background)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint("📬 App opened from notification: ${message.data}");
      _handleDeepLinkData(message.data);
    });

    // Show a local notification for foreground FCM
    FirebaseMessaging.onMessage.listen((message) async {
      final notif = message.notification;
      final data = message.data;

      if (notif != null) {
        await LocalNotifications.showBasic(
          title: notif.title,
          body: notif.body,
          payload: {
            'type': data['type'],
            'meetingId': data['meetingId'],
          },
        );
      }
    });

    // Tapped from terminated
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _handleDeepLinkData(initial.data);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Rudhram CRM',
      theme: ThemeData(
        primaryColor: AppColors.primaryColor,
        scaffoldBackgroundColor: AppColors.backgroundGradientStart,
        fontFamily: 'Poppins',
      ),
      home: const SplashScreen(),
      routes: {
        '/login': (_) => const LoginScreen(),
        '/meeting': (_) => const MeetingScreen(),
      },
    );
  }
}
