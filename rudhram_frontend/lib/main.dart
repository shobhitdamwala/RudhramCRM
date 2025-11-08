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
import 'screens/task_route.dart';

// Screens you already have:
import 'screens/meeting_screen.dart';

// Background FCM handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  // process message.data if needed
}

void _handleDeepLinkData(Map<String, dynamic> data) {
  final type = (data['type'] ?? '').toString();

  // 🔔 Handle all task-related server types

  // ✅ NEW: Lead converted deep link
  if (type == 'lead_converted') {
    final clientId = data['clientId']?.toString();
    final leadId = data['leadId']?.toString();
    // Prefer a client screen if you have one. Example:
    // navigatorKey.currentState?.pushNamed('/client', arguments: clientId);
    // Fallback: navigate to a generic route with params bundle:
    navigatorKey.currentState?.pushNamed(
      '/task', // <-- replace with your client route if you have it
      arguments: {
        'deeplink': 'lead_converted',
        'clientId': clientId,
        'leadId': leadId,
        'clientCode': data['clientCode']?.toString(),
      },
    );
    return;
  }

  if (type == 'task' ||
      type == 'task_assigned' ||
      type == 'task_assigned_update' ||
      type == 'task_deadline') {
    final taskId = data['taskId']?.toString();
    if (taskId != null && taskId.isNotEmpty) {
      navigatorKey.currentState?.pushNamed('/task', arguments: taskId);
      return;
    }
  }

  // (existing) meeting deep-link
  if (type == 'meeting' && data['meetingId'] != null) {
    navigatorKey.currentState?.pushNamed(
      '/meeting',
      arguments: data['meetingId'],
    );
  }
}

void _handleDeepLinkPayload(String payload) {
  try {
    final map = jsonDecode(payload) as Map<String, dynamic>;
    _handleDeepLinkData(map);
  } catch (_) {
    // ignore malformed payload
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
    FirebaseMessaging.onMessage.listen((message) async {
      final notif = message.notification;
      final data = message.data;

      if (notif != null) {
        await LocalNotifications.showBasic( 
          title: notif.title,
          body: notif.body,
          // ⬅️ include taskId + type so tap can deep-link
          payload: {
            'type': data['type'],
            'taskId': data['taskId'],
            'meetingId': data['meetingId'],
          },
        );
      }
    });
    // App opened from notification (background)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      debugPrint("📬 App opened from notification: ${message.data}");
      _handleDeepLinkData(message.data);
    });

    // // Show a local notification for foreground FCM
    // FirebaseMessaging.onMessage.listen((message) async {
    //   final notif = message.notification;
    //   final data = message.data;

    //   if (notif != null) {
    //     await LocalNotifications.showBasic(
    //       title: notif.title,
    //       body: notif.body,
    //       payload: {'type': data['type'], 'meetingId': data['meetingId']},
    //     );
    //   }
    // });

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
        '/task': (_) => const TaskRoute(),
      },
    );
  }
}
