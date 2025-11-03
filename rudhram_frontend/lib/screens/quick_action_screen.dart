import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rudhram_frontend/screens/drive_screen.dart';
import 'package:rudhram_frontend/screens/generate_invoice_screen.dart';
import 'package:rudhram_frontend/screens/invoice_list_screen.dart';
import 'package:rudhram_frontend/utils/custom_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_config.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';
import '../screens/team_member_screen.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/profile_header.dart';
import '../screens/task_screen.dart';
import '../screens/meeting_screen.dart';
import 'package:rudhram_frontend/screens/generate_receipt_screen.dart';
import 'package:rudhram_frontend/screens/receipt_list_screen.dart';
import 'package:rudhram_frontend/screens/add_addon_service_screen.dart';
import 'package:rudhram_frontend/screens/list_addon_services_screen.dart';

class QuickActionScreen extends StatefulWidget {
  const QuickActionScreen({super.key});

  @override
  State<QuickActionScreen> createState() => _QuickActionScreenState();
}

class _QuickActionScreenState extends State<QuickActionScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;

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
        if (u['avatarUrl'] != null &&
            u['avatarUrl'].toString().startsWith('/')) {
          u['avatarUrl'] = _absUrl(u['avatarUrl']);
        }
        if (mounted) setState(() => userData = u);
      } else {
        await _showErrorSnack(res.body, fallback: "Failed to fetch user");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("User load error: $e"),
          backgroundColor: Colors.red,
        ),
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

  String _absUrl(String? maybeRelative) {
    if (maybeRelative == null || maybeRelative.isEmpty) return '';
    if (maybeRelative.startsWith('http')) return maybeRelative;

    if (maybeRelative.startsWith('/uploads')) {
      // 🟢 Use image base URL
      return "${ApiConfig.imageBaseUrl}$maybeRelative";
    }

    // Default
    return "${ApiConfig.baseUrl}$maybeRelative";
  }

  Future<void> _showErrorSnack(
    dynamic body, {
    String fallback = "Request failed",
  }) async {
    try {
      final b = body is String ? jsonDecode(body) : body;
      final msg = (b?['message'] ?? b?['error'] ?? b?['msg'] ?? fallback)
          .toString();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fallback), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              double gridSpacing = size.width * 0.05;
              double iconSize = constraints.maxWidth * 0.09;
              double circleSize = constraints.maxWidth * 0.18;

              return Column(
                children: [
                  ProfileHeader(
                    avatarUrl: userData?['avatarUrl'],
                    fullName: userData?['fullName'],
                    role: formatUserRole(userData?['role']),
                    showBackButton: true,
                    onBack: () => Navigator.pop(context),
                    onNotification: () {
                      print("🔔 Notification tapped");
                    },
                  ),
                  const SizedBox(height: 10),

                  // Quick Actions Grid ↓
                  Flexible(
                    fit: FlexFit.tight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _actions.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: 20,
                              crossAxisSpacing: 20,
                            ),
                        itemBuilder: (context, index) {
                          final action = _actions[index];
                          return GestureDetector(
                            onTap: () {
                              if (action['label'] == "Team Member") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const TeamMemberScreen(),
                                  ),
                                );
                              } else if (action['label'] == "New Task") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const TaskScreen(),
                                  ),
                                );
                              } else if (action['label'] == "New Meeting") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const MeetingScreen(),
                                  ),
                                );
                              } else if (action['label'] == "Drive") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const DriveScreen(),
                                  ),
                                );
                              } else if (action['label'] == "New Invoice") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const GenerateInvoiceScreen(),
                                  ),
                                );
                              } else if (action['label'] == "Invoice List") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const InvoiceListScreen(),
                                  ),
                                );
                              } else if (action['label'] == "New Receipt") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const GenerateReceiptScreen(),
                                  ),
                                );
                              } else if (action['label'] == "Receipt List") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const ReceiptListScreen(),
                                  ),
                                );
                              } else if (action['label'] ==
                                  "Add-On Service") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const AddAddOnServiceScreen(),
                                  ),
                                );
                              } else if (action['label'] ==
                                  "List Services") {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const ListAddOnServicesScreen(),
                                  ),
                                );
                              } else {
                                print("Tapped on ${action['label']}");
                              }
                            },

                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    action['icon'],
                                    size: 28,
                                    color: Colors.brown,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  action['label'],
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.brown,
                                  ),
                                  textAlign: TextAlign.center,
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
                    currentIndex: 2,
                    onTap: (index) {
                      print("Tapped on $index");
                    },
                    userRole: userData?['role'] ?? '',
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// 🔸 Reusable Quick Action Icon Card (Responsive)
  Widget _buildAction(
    IconData icon,
    String title,
    double circleSize,
    double iconSize,
  ) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.brown, size: iconSize),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.brown,
          ),
        ),
      ],
    );
  }

  final List<Map<String, dynamic>> _actions = [
    {'icon': Icons.calendar_month_outlined, 'label': "New Meeting"},
    {'icon': Icons.task_alt_outlined, 'label': "New Task"},
    {'icon': Icons.group_add_outlined, 'label': "Team Member"},
    {'icon': Icons.cloud_upload_outlined, 'label': "Drive"},
    {'icon': Icons.receipt_long_outlined, 'label': "New Invoice"},
    {'icon': Icons.list_alt_outlined, 'label': "Invoice List"},
    {'icon': Icons.currency_rupee_outlined, 'label': "New Receipt"},
    {'icon': Icons.receipt_outlined, 'label': "Receipt List"},

    // 🔻 New actions
    {'icon': Icons.add_circle_outline, 'label': "Add-On Service"},
    {'icon': Icons.view_list_outlined, 'label': "List Services"},
  ];
}
