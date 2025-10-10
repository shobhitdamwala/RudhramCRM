import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../screens/quick_action_screen.dart';

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
      Icons.grid_view_rounded,
      Icons.groups_2_outlined,
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildSquareIcon(icons[0], 0),
          _buildSquareIcon(icons[1], 1),
          _buildCenterCircleIcon(context, Icons.bolt_outlined),
          _buildSquareIcon(icons[2], 2),
          _buildSquareIcon(icons[3], 3),
        ],
      ),
    );
  }

  Widget _buildSquareIcon(IconData icon, int index) {
    final isActive = currentIndex == index;
    return GestureDetector(
      onTap: () => onTap(index),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primaryColor.withOpacity(0.1)
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
}
