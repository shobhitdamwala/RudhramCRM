import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../screens/home_screen.dart';
import '../screens/task_screen.dart';
import '../screens/quick_action_screen.dart';
import '../screens/team_member_screen.dart';
import '../screens/profile_screen.dart';
import '../screens/teammember_home_screen.dart';

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

    final List<IconData> icons = isTeamMember
        ? [Icons.home_outlined, Icons.person_outline]
        : [
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
        mainAxisAlignment:
            isTeamMember ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
        children: isTeamMember
            ? [
                _buildSquareIcon(context, icons[0], 0, isTeamMember),
                const SizedBox(width: 40), // 👈 spacing between the two icons
                _buildSquareIcon(context, icons[1], 1, isTeamMember),
              ]
            : [
                _buildSquareIcon(context, icons[0], 0, isTeamMember),
                _buildSquareIcon(context, icons[1], 1, isTeamMember),
                _buildCenterCircleIcon(context, icons[2]),
                _buildSquareIcon(context, icons[3], 3, isTeamMember),
                _buildSquareIcon(context, icons[4], 4, isTeamMember),
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
        decoration: BoxDecoration(
          color: isActive
              ? const Color.fromARGB(255, 0, 0, 0)
              : const Color(0xFFF5E6D3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          icon,
          color: isActive ? AppColors.primaryColor : Colors.brown,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildCenterCircleIcon(BuildContext context, IconData icon) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const QuickActionScreen()),
        );
      },
      child: Container(
        width: 68,
        height: 68,
        decoration: const BoxDecoration(
          color: Color(0xFFF5E6D3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: AppColors.primaryColor, size: 38),
      ),
    );
  }

  void _navigateToScreen(BuildContext context, int index, bool isTeamMember) {
    Widget page;

    if (isTeamMember) {
      switch (index) {
        case 0:
          page = const TeamMemberHomeScreen();
          break;
        case 1:
          page = const ProfileScreen();
          break;
        default:
          return;
      }
    } else {
      switch (index) {
        case 0:
          page = const HomeScreen();
          break;
        case 1:
          page = const TaskScreen();
          break;
        case 3:
          page = const QuickActionScreen();
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
