import 'package:flutter/material.dart';
import 'package:rudhram_frontend/screens/quick_action_screen.dart';
import 'package:rudhram_frontend/screens/team_member_screen.dart';
import 'screens/splash_screen.dart';
import 'utils/constants.dart';
import 'screens/task_screen.dart';

void main() {
  runApp(const RudhramApp());
}

class RudhramApp extends StatelessWidget {
  const RudhramApp({super.key});

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
    );
  }
}
