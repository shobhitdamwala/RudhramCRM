import 'dart:convert';
import 'dart:ui'; // 👈 Needed for BackdropFilter (blur)
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../utils/constants.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class UpdateStatusScreen extends StatefulWidget {
  final String leadId;
  final String leadName;
  final String currentStatus;

  const UpdateStatusScreen({
    Key? key,
    required this.leadId,
    required this.leadName,
    required this.currentStatus,
  }) : super(key: key);

  @override
  State<UpdateStatusScreen> createState() => _UpdateStatusScreenState();
}

class _UpdateStatusScreenState extends State<UpdateStatusScreen> {
  final List<String> allowedStatuses = [
    "new",
    "contacted",
    "qualified",
    "lost",
  ];

  String? selectedStatus;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    selectedStatus = widget.currentStatus;
  }

  Future<void> updateStatus() async {
    if (selectedStatus == null || selectedStatus == widget.currentStatus) {
      SnackbarHelper.show(
        context,
        title: "Notice",
        message: "Please select a different status to update.",
        type: ContentType.warning,
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/lead/${widget.leadId}/status'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': selectedStatus}),
      );

      setState(() => isLoading = false);

      if (response.statusCode == 200) {
        SnackbarHelper.show(
          context,
          title: "Success",
          message: "Lead status updated successfully.",
          type: ContentType.success,
        );
        Navigator.pop(context, true);
      } else {
        SnackbarHelper.show(
          context,
          title: "Error",
          message: "Failed to update lead status.",
          type: ContentType.failure,
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      SnackbarHelper.show(
        context,
        title: "Error",
        message: e.toString(),
        type: ContentType.failure,
      );
    }
  }

  Widget _statusDropdown() {
    return DropdownButtonFormField<String>(
      value: selectedStatus,
      decoration: InputDecoration(
        labelText: "Select New Status",
        labelStyle: const TextStyle(
          color: AppColors.primaryColor,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: Colors.white.withOpacity(0.1), // 👈 Light transparent fill
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: AppColors.primaryColor,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: const BorderSide(
            color: AppColors.primaryColor,
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      icon: const Icon(
        Icons.arrow_drop_down,
        color: AppColors.primaryColor,
      ),
      dropdownColor: Colors.white,
      items: allowedStatuses.map((status) {
        return DropdownMenuItem(
          value: status,
          child: Text(
            status.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
        );
      }).toList(),
      onChanged: (val) => setState(() => selectedStatus = val),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        title: const Text(
          "Update Lead Status",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.backgroundGradientStart,
              AppColors.backgroundGradientEnd,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15), // 👈 Blur effect
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15), // 👈 Transparent Card
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.3),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.leadName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "Current Status: ${widget.currentStatus.toUpperCase()}",
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _statusDropdown(),
                    const SizedBox(height: 25),
                    ElevatedButton(
                      onPressed: isLoading ? null : updateStatus,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 3,
                      ),
                      child: isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text(
                              "Update Status",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
