import 'package:flutter/material.dart';
import '../utils/constants.dart';

class BackgroundContainer extends StatelessWidget {
  final Widget child;

  const BackgroundContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      width: size.width,
      height: size.height,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.backgroundGradientStart,
            AppColors.backgroundGradientEnd,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          /// Bottom-left white logo pattern
          Positioned(
            bottom: 0,
            left: 0,
            child: Opacity(
              opacity: 0.25,
              child: Image.asset(
                'assets/white_logo.png',  // 👈 your bottom-left white design
                width: size.width * 0.40,
                fit: BoxFit.contain,
              ),
            ),
          ),

          /// Main content
          Center(child: child),
        ],
      ),
    );
  }
}
