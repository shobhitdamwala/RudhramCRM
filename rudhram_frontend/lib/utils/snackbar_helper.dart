import 'package:flutter/material.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:rudhram_frontend/utils/constants.dart';

class SnackbarHelper {
  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required ContentType type,
  }) {
    Color themeColor;

    if (type == ContentType.success) {
      themeColor = AppColors.primaryColor; // Premium Green Success
    } else if (type == ContentType.failure) {
      themeColor = const Color(0xFFB3261E); // Rich Deep Red Failure
    } else if (type == ContentType.warning) {
      themeColor = AppColors.primaryColor; // Copper theme for warning
    } else {
      themeColor = AppColors.primaryColor;
    }

    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      content: AwesomeSnackbarContent(
        title: title,
        message: message,
        contentType: type,
        color: themeColor,
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
