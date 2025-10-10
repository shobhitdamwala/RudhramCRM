import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../screens/home_screen.dart';
import '../screens/task_screen.dart';
import '../screens/quick_action_screen.dart';

import '../screens/team_member_screen.dart';

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavBar({
    Key? key,
    required this.currentIndex,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final List<IconData> icons = [
      Icons.home_outlined,
      Icons.task_alt_outlined,
      Icons.bolt_outlined,
      Icons.grid_view_rounded,
      Icons.groups_2_outlined,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSquareIcon(context, icons[0], 0),
          _buildSquareIcon(context, icons[1], 1),
          _buildCenterCircleIcon(context, icons[2]),
          _buildSquareIcon(context, icons[3], 3),
          _buildSquareIcon(context, icons[4], 4),
        ],
      ),
    );
  }

  Widget _buildSquareIcon(BuildContext context, IconData icon, int index) {
    final isActive = currentIndex == index;
    return GestureDetector(
      onTap: () {
        onTap(index);
        _navigateToScreen(context, index);
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

  void _navigateToScreen(BuildContext context, int index) {
    Widget page;

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
        page = const TeamMemberScreen();
        break;
      default:
        return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }
}
