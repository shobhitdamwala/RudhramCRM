import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:rudhram_frontend/screens/lead_list_screen.dart';
import 'package:rudhram_frontend/screens/quick_action_screen.dart';
import 'package:rudhram_frontend/screens/team_member_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/constants.dart';
import 'screens/task_screen.dart';
import 'screens/meeting_screen.dart';
import 'screens/login_screen.dart';

// 🔹 Handle background notifications
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("✅ Background Message: ${message.notification?.title}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // 🔹 Setup background message handler
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
  }

  Future<void> _initFirebaseMessaging() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;

    // 🔹 Request notification permission (for Android & iOS)
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print('🔔 Permission granted: ${settings.authorizationStatus}');

    // 🔹 Get FCM token (send to backend)
    String? token = await messaging.getToken();
    print("📱 FCM Token: $token");

    // TODO: Send this token to your Node.js backend for storing

    // 🔹 Foreground notification listener
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print("🔥 Foreground Message: ${message.notification?.title}");

      // Optional: Show in-app alert
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.notification?.title ?? "New Notification"),
          duration: const Duration(seconds: 2),
        ),
      );
    });

    // 🔹 When app opened from background via notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print("📬 App opened from notification: ${message.notification?.title}");
      // Navigate to screen if needed
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Rudhram CRM',
      theme: ThemeData(
        primaryColor: AppColors.primaryColor,
        scaffoldBackgroundColor: AppColors.backgroundGradientStart,
        fontFamily: 'Poppins',
      ),
      home: const SplashScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
      },
    );
  }
}
