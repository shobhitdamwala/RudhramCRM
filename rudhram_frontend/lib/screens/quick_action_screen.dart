import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:rudhram_frontend/utils/custom_bottom_nav.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_config.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';
import '../screens/team_member_screen.dart';

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
    fetchUser();
  }

  Future<void> fetchUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("auth_token");

      if (token == null) return;

      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/me"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final user = data['user'];

        if (user['avatarUrl'] != null &&
            user['avatarUrl'].toString().startsWith('/')) {
          user['avatarUrl'] = "${ApiConfig.baseUrl}${user['avatarUrl']}";
        }

        setState(() {
          userData = user;
          isLoading = false;
        });
      } else {
        print("⚠️ Failed to fetch user: ${response.body}");
        setState(() => isLoading = false);
      }
    } catch (e) {
      print("❌ Fetch error: $e");
      setState(() => isLoading = false);
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
                  /// 🔹 Header Section
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundImage: userData?['avatarUrl'] != null
                                  ? NetworkImage(userData!['avatarUrl'])
                                  : const AssetImage('assets/user.jpg')
                                      as ImageProvider,
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  userData != null
                                      ? "Hi ${userData!['fullName'] ?? ''}"
                                      : "Hi...",
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.brown,
                                  ),
                                ),
                                Text(
                                  userData?['role'] ?? "Super Admin",
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_back_ios_new,
                                  color: Colors.brown, size: 22),
                              onPressed: () => Navigator.pop(context),
                            ),
                            IconButton(
                              icon: const Icon(Icons.notifications_none,
                                  color: Colors.brown, size: 26),
                              onPressed: () {},
                            ),
                          ],
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// 🔹 Quick Action Buttons (responsive grid)
                  Flexible(
                    fit: FlexFit.tight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 25),
                      child:GridView.builder(
  shrinkWrap: true,
  physics: const NeverScrollableScrollPhysics(),
  itemCount: _actions.length,
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
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
              builder: (context) => const TeamMemberScreen(),
            ),
          );
        } else {
          // Handle other quick actions here
          print("Tapped on ${action['label']}");
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(action['icon'], size: 28, color: Colors.brown),
          ),
          const SizedBox(height: 6),
          Text(
            action['label'],
            style: const TextStyle(fontSize: 12, color: Colors.brown),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  },
)
                    ),
                  ),

                  const SizedBox(height: 10),

                  /// 🔹 Bottom Navigation
                  CustomBottomNavBar(
                  currentIndex: 0, // you can set the active tab index
                  onTap: (index) {
                    // Handle navigation here
                    print("Tapped on $index");
                  },
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
      IconData icon, String title, double circleSize, double iconSize) {
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

  /// 🔸 Bottom Navbar (same as Home)
  
  final List<Map<String, dynamic>> _actions = [
    {'icon': Icons.calendar_month_outlined, 'label': "New Meeting"},
    {'icon': Icons.task_alt_outlined, 'label': "New Task"},
    {'icon': Icons.event_outlined, 'label': "New Event"},
    {'icon': Icons.receipt_long_outlined, 'label': "New Invoice"},
    {'icon': Icons.currency_rupee_outlined, 'label': "New Receipt"},
    {'icon': Icons.cloud_upload_outlined, 'label': "Drive"},
    {'icon': Icons.notifications_active_outlined, 'label': "Notify"},
    {'icon': Icons.group_add_outlined, 'label': "Team Member"},

  ];
}
