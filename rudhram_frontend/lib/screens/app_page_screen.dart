import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rudhram_frontend/screens/meeting_screen.dart';
import 'package:rudhram_frontend/screens/drive_screen.dart';
import 'package:rudhram_frontend/screens/generate_invoice_screen.dart';
import 'package:rudhram_frontend/screens/generate_receipt_screen.dart';

import '../utils/api_config.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';
import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';

class AppPageScreen extends StatefulWidget {
  const AppPageScreen({super.key});

  @override
  State<AppPageScreen> createState() => _AppPageScreenState();
}

class _AppPageScreenState extends State<AppPageScreen> {
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      await fetchUser(token);
    }
  }

  Future<void> fetchUser(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/me"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final u = Map<String, dynamic>.from(data['user'] ?? {});
        if (u['avatarUrl'] != null && u['avatarUrl'].toString().startsWith('/')) {
          u['avatarUrl'] = _absUrl(u['avatarUrl']);
        }
        if (mounted) setState(() => userData = u);
      } else {
        _showErrorSnack(res.body, fallback: "Failed to fetch user");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("User load error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  String _absUrl(String? maybeRelative) {
    if (maybeRelative == null || maybeRelative.isEmpty) return '';
    if (maybeRelative.startsWith('http')) return maybeRelative;
    if (maybeRelative.startsWith('/uploads')) {
      return "${ApiConfig.imageBaseUrl}$maybeRelative";
    }
    return "${ApiConfig.baseUrl}$maybeRelative";
  }

  Future<void> _showErrorSnack(
    dynamic body, {
    String fallback = "Request failed",
  }) async {
    try {
      final b = body is String ? jsonDecode(body) : body;
      final msg = (b?['message'] ?? b?['error'] ?? b?['msg'] ?? fallback).toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fallback), backgroundColor: Colors.red),
      );
    }
  }

  String formatUserRole(String? role) {
    if (role == null) return '';
    switch (role.toUpperCase()) {
      case 'SUPER_ADMIN':
        return 'Super Admin';
      case 'ADMIN':
        return 'Admin';
      case 'TEAM_MEMBER':
        return 'Team Member';
      case 'CLIENT':
        return 'Client';
      default:
        return role;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              ProfileHeader(
                avatarUrl: userData?['avatarUrl'],
                fullName: userData?['fullName'],
                role: formatUserRole(userData?['role']),
                showBackButton: true,
                onBack: () => Navigator.pop(context),
                onNotification: () {
                  // Optional notification tap
                },
              ),
              const SizedBox(height: 10),

              // Only four quick actions
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: GridView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _actions.length,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2, // 2x2 grid for 4 items
                      mainAxisSpacing: 20,
                      crossAxisSpacing: 20,
                      childAspectRatio: 1,
                    ),
                    itemBuilder: (context, index) {
                      final action = _actions[index];
                      return GestureDetector(
                        onTap: () {
                          switch (action['label'] as String) {
                            case "New Meeting":
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const MeetingScreen()),
                              );
                              break;
                            case "Drive":
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const DriveScreen()),
                              );
                              break;
                            case "New Invoice":
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const GenerateInvoiceScreen()),
                              );
                              break;
                            case "New Receipt":
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const GenerateReceiptScreen()),
                              );
                              break;
                          }
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 6,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Icon(
                                action['icon'] as IconData,
                                size: 30,
                                color: Colors.brown,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              action['label'] as String,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.brown,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 10),

              CustomBottomNavBar(
                currentIndex: 3, // choose whichever tab this belongs to
                onTap: (index) {
                  // Handle bottom nav if needed
                },
                userRole: userData?['role'] ?? '',
              ),
            ],
          ),
        ),
      ),
    );
  }

  final List<Map<String, dynamic>> _actions = const [
    {'icon': Icons.calendar_month_outlined, 'label': "New Meeting"},
    {'icon': Icons.cloud_upload_outlined, 'label': "Drive"},
    {'icon': Icons.receipt_long_outlined, 'label': "New Invoice"},
    {'icon': Icons.currency_rupee_outlined, 'label': "New Receipt"},
  ];
}
