import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../screens/profile_screen.dart'; // <-- Import your Profile Screen here

class ProfileHeader extends StatelessWidget {
  final String? avatarUrl;
  final String? fullName;
  final String? role;
  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onNotification;

  const ProfileHeader({
    Key? key,
    required this.avatarUrl,
    required this.fullName,
    required this.role,
    this.showBackButton = false,
    this.onBack,
    this.onNotification,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 🔹 Avatar + Name + Role
          Row(
            children: [
              // 👇 Wrap avatar with GestureDetector to handle click
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ProfileScreen(),
                    ),
                  );
                },
                child: CircleAvatar(
                  radius: 28,
                  backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                      ? NetworkImage(avatarUrl!)
                      : const AssetImage('assets/user.jpg') as ImageProvider,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName ?? 'Hi...',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                  Text(
                    role ?? '',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),

          // 🔹 Right side icons (Back + Notification)
          Row(
            children: [
              if (showBackButton)
                IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.brown,
                  ),
                  onPressed: onBack ?? () => Navigator.pop(context),
                ),
              IconButton(
                icon: const Icon(
                  Icons.notifications_none,
                  color: Colors.brown,
                  size: 26,
                ),
                onPressed: onNotification ??
                    () {
                      // Default behavior
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No new notifications'),
                        ),
                      );
                    },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
