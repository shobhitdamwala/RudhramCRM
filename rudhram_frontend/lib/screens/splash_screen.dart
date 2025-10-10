import 'dart:async';
import 'package:flutter/material.dart';
import '../widgets/background_container.dart';
import '../utils/constants.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 4), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundContainer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/logo.png', // your main Rudhram logo
              height: MediaQuery.of(context).size.height * 0.18,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 25),
            const SizedBox(height: 10),
            const Text(
              "Leading, What's Next!",
              style: TextStyle(
                color: Colors.brown,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
