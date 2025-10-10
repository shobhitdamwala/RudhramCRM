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
    final snackBar = SnackBar(
      elevation: 0,
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      content: AwesomeSnackbarContent(
        title: title,
        message: message,
        contentType: type,
        color: type == ContentType.failure
            ? Colors.red.shade700
            : type == ContentType.success
                ? const Color.fromARGB(255, 113, 234, 88)
                : const Color.fromARGB(255, 255, 0, 0),
      ),
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
