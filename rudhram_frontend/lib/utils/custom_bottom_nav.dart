import 'package:flutter/material.dart';
import 'package:rudhram_frontend/screens/completed_task_screen.dart';
import 'package:rudhram_frontend/screens/message_center_screen.dart';
import 'package:rudhram_frontend/screens/team_member_dashboard.dart';
import 'package:rudhram_frontend/screens/team_member_message_screen.dart';
import '../utils/constants.dart';
import '../screens/home_screen.dart';
import '../screens/task_screen.dart';
import '../screens/quick_action_screen.dart';
import '../screens/team_member_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/teammember_home_screen.dart';
import '../screens/app_page_screen.dart';
 // ✅ Add your completed task screen

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final String userRole;

  const CustomBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
    required this.userRole,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool isTeamMember = userRole == "TEAM_MEMBER";

    // ✅ Team Member Icons: Home, Task, Completed Task, Profile
    final List<IconData> teamIcons = [
      Icons.home_outlined,
      Icons.task_alt_outlined,
      Icons.chat_bubble_outline, // completed task
      Icons.person_outline,
    ];

    // Admin / Super Admin Icons
    final List<IconData> adminIcons = [
      Icons.home_outlined,
      Icons.task_alt_outlined,
      Icons.bolt_outlined,
      Icons.grid_view_rounded,
      Icons.person_outline,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: isTeamMember
            ? List.generate(teamIcons.length, (index) {
                return _buildSquareIcon(context, teamIcons[index], index, true);
              })
            : [
                _buildSquareIcon(context, adminIcons[0], 0, false),
                _buildSquareIcon(context, adminIcons[1], 1, false),
                _buildCenterImageIcon(context, 2),
                _buildSquareIcon(context, adminIcons[3], 3, false),
                _buildSquareIcon(context, adminIcons[4], 4, false),
              ],
      ),
    );
  }

  Widget _buildSquareIcon(
    BuildContext context,
    IconData icon,
    int index,
    bool isTeamMember,
  ) {
    final isActive = currentIndex == index;

    return GestureDetector(
      onTap: () {
        onTap(index);
        _navigateToScreen(context, index, isTeamMember);
      },
      child: Container(
        width: 50,
        height: 50,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.black : const Color(0xFFF5E6D3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          color: isActive ? AppColors.primaryColor : Colors.brown,
          size: 30,
        ),
      ),
    );
  }

  /// Center circular logo button (for Admin roles only)
  Widget _buildCenterImageIcon(BuildContext context, int index) {
    final bool isActive = currentIndex == index;

    return GestureDetector(
      onTap: () {
        onTap(index);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const QuickActionScreen()),
        );
      },
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: isActive ? Colors.black : const Color(0xFFF5E6D3),
          shape: BoxShape.circle,
          boxShadow: [
            if (isActive)
              BoxShadow(
                color: AppColors.primaryColor.withOpacity(0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: ClipOval(
          child: Padding(
            padding: const EdgeInsets.all(10.0),
            child: Image.asset(
              'assets/logo_bottom.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, int index, bool isTeamMember) {
    Widget page;

    if (isTeamMember) {
      // ✅ TEAM MEMBER NAVIGATION
      switch (index) {
        case 0:
          page = const TeamMemberDashboard(); // Home
          break;
        case 1:
          page = const TeamMemberHomeScreen(); // Task
          break;
        case 2:
          page = const TeamMemberMessageScreen(); // ✅ Completed Task page
          break;
        case 3:
          page = const ProfileScreen(); // Profile
          break;
        default:
          return;
      }
    } else {
      // ✅ ADMIN / SUPER ADMIN NAVIGATION
      switch (index) {
        case 0:
          page = const HomeScreen();
          break;
        case 1:
          page = const TaskScreen();
          break;
        case 2:
          page = const QuickActionScreen();
          break;
        case 3:
          page = const AppPageScreen();
          break;
        case 4:
          page = const ProfileScreen();
          break;
        default:
          return;
      }
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }
}
