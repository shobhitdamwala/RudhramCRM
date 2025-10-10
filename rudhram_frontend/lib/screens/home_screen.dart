import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:rudhram_frontend/utils/snackbar_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import '../utils/api_config.dart';
import '../utils/custom_bottom_nav.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/profile_header.dart';
import 'package:rudhram_frontend/screens/sub_company_info_screen.dart'; // 👈 Add this import at the top

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? userData;
  List<dynamic> subCompanies = [];
  List<dynamic> teamMembers = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchAllData();
  }

  Future<void> fetchAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        SnackbarHelper.show(
          context,
          title: "Not Logged In",
          message: "Please log in again.",
          type: ContentType.warning,
        );
        return;
      }

      await Future.wait([
        fetchUser(token),
        fetchSubCompanies(token),
        fetchTeamMembers(token),
      ]);
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Failed to fetch data: $e",
        type: ContentType.failure,
      );
    } finally {
      setState(() => isLoading = false);
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

  Future<void> fetchSubCompanies(String token) async {
    final response = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() => subCompanies = data['data']);
    }
  }

  Future<void> fetchTeamMembers(String token) async {
    final response = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() => teamMembers = data['teamMembers']);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.brown),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// 🔹 User Header
                            ProfileHeader(
                              avatarUrl: userData?['avatarUrl'],
                              fullName: userData?['fullName'],
                              role: userData?['role'] ?? '',
                              onNotification: () {
                                // handle notification icon tap
                                print("🔔 Notification tapped");
                              },
                            ),

                            const SizedBox(height: 15),

                            /// 🔹 Meeting Card (Static)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      "Meeting with client 03.00 PM",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.brown,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            /// 🔹 Subcompany List
                            /// 🔹 Subcompany Section (Always show 6 companies across screen)
                            if (subCompanies.isNotEmpty)
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  // Calculate width dynamically to show exactly 6 items
                                  final double itemWidth =
                                      (constraints.maxWidth - 5 * 10) / 6;

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      top: 4.0,
                                      bottom: 4.0,
                                    ),
                                    child: Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: List.generate(subCompanies.length, (
                                        index,
                                      ) {
                                        final sub = subCompanies[index];
                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    SubCompanyInfoScreen(
                                                      subCompanyId:
                                                          sub['_id'], // ✅ Pass the ID here
                                                    ),
                                              ),
                                            );
                                          },

                                          child: SizedBox(
                                            width: itemWidth,
                                            child: Column(
                                              children: [
                                                Container(
                                                  width: itemWidth * 1.4,
                                                  height: itemWidth * 1.4,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.white,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.08),
                                                        blurRadius: 4,
                                                        offset: const Offset(
                                                          0,
                                                          2,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ClipOval(
                                                    child:
                                                        sub['logoUrl'] != null
                                                        ? Image.network(
                                                            sub['logoUrl'],
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (
                                                                  _,
                                                                  __,
                                                                  ___,
                                                                ) => const Icon(
                                                                  Icons
                                                                      .image_not_supported,
                                                                  color: Colors
                                                                      .grey,
                                                                ),
                                                          )
                                                        : const Icon(
                                                            Icons.business,
                                                            color: Colors.brown,
                                                          ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  sub['name'] ?? '',
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.brown,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  );
                                },
                              ),

                            const SizedBox(height: 15),
                            _buildCalendar(),
                            const SizedBox(height: 20),

                            /// 🔹 Static Stats
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                _StatCard(
                                  title: "Leads",
                                  value: "150",
                                  icon: Icons.star_border,
                                ),
                                _StatCard(
                                  title: "Onboard",
                                  value: "25",
                                  icon: Icons.star_border,
                                ),
                                _StatCard(
                                  title: "Active",
                                  value: "10",
                                  icon: Icons.star_border,
                                ),
                              ],
                            ),
                            const SizedBox(height: 30),

                            /// 🔹 Team Members
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text(
                                  "Team Members",
                                  style: TextStyle(
                                    color: Colors.brown,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  "View All",
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildTeamRow(),
                            const SizedBox(height: 5),
                          ],
                        ),
                      ),
                    ),

                    CustomBottomNavBar(
                      currentIndex: 0, // you can set the active tab index
                      onTap: (index) {
                        // Handle navigation here
                        print("Tapped on $index");
                      },
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Calendar widget
  Widget _buildCalendar() {
    final now = DateTime.now();
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('MMMM yyyy').format(now),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.brown,
                  fontSize: 16,
                ),
              ),
              Row(
                children: const [
                  Icon(Icons.chevron_left, color: Colors.brown),
                  Icon(Icons.chevron_right, color: Colors.brown),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            itemCount: daysInMonth,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final day = index + 1;
              final isToday = day == now.day;
              return Container(
                decoration: BoxDecoration(
                  color: isToday
                      ? AppColors.primaryColor.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  "$day",
                  style: TextStyle(
                    color: isToday ? AppColors.primaryColor : Colors.brown,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Team members list
  Widget _buildTeamRow() {
    if (teamMembers.isEmpty) {
      return const Text(
        "No team members found.",
        style: TextStyle(color: Colors.grey),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: teamMembers.map((m) {
          return Container(
            margin: const EdgeInsets.only(right: 14),
            child: Column(
              children: [
                CircleAvatar(
                  backgroundImage: m['avatarUrl'] != null
                      ? NetworkImage(m['avatarUrl'])
                      : const AssetImage('assets/user.jpg') as ImageProvider,
                  radius: 28,
                ),
                const SizedBox(height: 5),
                Text(
                  m['fullName'] ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.brown),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Bottom Navbar
  Widget _buildBottomNavBar() {
    final List<Map<String, dynamic>> items = [
      {'icon': Icons.home_outlined},
      {'icon': Icons.task_alt_outlined},
      {'icon': Icons.grid_view_rounded},
      {'icon': Icons.groups_2_outlined},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ...items.take(2).map((item) => _buildSquareIcon(item['icon'])),
          _buildCenterCircleIcon(Icons.bolt_outlined),
          ...items.skip(2).map((item) => _buildSquareIcon(item['icon'])),
        ],
      ),
    );
  }

  Widget _buildSquareIcon(IconData icon) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFF5E6D3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: Colors.brown, size: 32),
    );
  }

  Widget _buildCenterCircleIcon(IconData icon) {
    return Container(
      width: 68,
      height: 68,
      decoration: const BoxDecoration(
        color: Color(0xFFF5E6D3),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppColors.primaryColor, size: 38),
    );
  }
}

/// Stat card widget (Static)
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primaryColor, size: 30),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: const TextStyle(color: Colors.brown, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
