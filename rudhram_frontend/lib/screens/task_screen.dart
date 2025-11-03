import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import '../utils/custom_bottom_nav.dart';
import 'add_edit_task.dart';
import '../screens/task_details_screen.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/profile_header.dart';

class TaskScreen extends StatefulWidget {
  const TaskScreen({Key? key}) : super(key: key);

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  List<dynamic> tasks = [];
  bool isLoading = true;
  int _selectedIndex = 1;
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    fetchTasks();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      await fetchUser(token);
    }
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
  }

  Future<void> fetchTasks() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));

      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/task/gettask"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          tasks = data['data'] ?? [];
        });
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to fetch tasks',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Task load error: $e',
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

  Future<void> deleteTask(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));

      final res = await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/task/$id"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        setState(() {
          tasks.removeWhere((t) => t['_id'] == id);
        });
        SnackbarHelper.show(
          context,
          title: 'Deleted',
          message: 'Task deleted successfully',
          type: ContentType.success,
        );
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to delete task',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Delete error: $e',
        type: ContentType.failure,
      );
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.orange.shade400;
      case 'in_progress':
        return Colors.blue.shade400;
      case 'review':
        return Colors.purple.shade400;
      case 'done':
        return Colors.green.shade400;
      case 'blocked':
        return Colors.red.shade400;
      default:
        return Colors.grey;
    }
  }

  Color _priorityColor(String priority) {
    switch (priority) {
      case 'low':
        return Colors.green.shade400;
      case 'medium':
        return Colors.orange.shade400;
      case 'high':
        return Colors.red.shade400;
      default:
        return Colors.grey;
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

  Widget _buildMemberProgressList(dynamic task) {
    final assignments = task['assignments'] ?? [];

    if (assignments.isEmpty) {
      return const SizedBox();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text(
          "Assigned Members",
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 6),
        ...assignments.map<Widget>((a) {
          final user = a['user'] ?? {};
          final name = user['fullName'] ?? 'Unknown';
          final progress = a['progress'] ?? 0;
          final status = a['status'] ?? 'not_started';

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Colors.grey.shade100,
            ),
            child: Row(
              children: [
                const Icon(Icons.person, size: 18, color: Colors.brown),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: progress / 100,
                        minHeight: 6,
                        backgroundColor: Colors.grey.shade300,
                        valueColor: AlwaysStoppedAnimation(
                          AppColors.primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "${progress.toString()}%",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
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
                  print("🔔 Notification tapped");
                },
              ),
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.brown),
                      )
                    : RefreshIndicator(
                        onRefresh: fetchTasks,
                        child: tasks.isEmpty
                            ? const Center(
                                child: Text(
                                  'No Tasks Found',
                                  style: TextStyle(
                                    color: Colors.brown,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: tasks.length,
                                itemBuilder: (context, index) {
                                  final t = tasks[index];
                                  return _buildTaskCard(t);
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 80.0),
          child: FloatingActionButton.extended(
            backgroundColor: AppColors.primaryColor,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              "New Task",
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () async {
              final created = await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddEditTaskScreen()),
              );
              if (created == true) fetchTasks();
            },
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: SafeArea(
        child: CustomBottomNavBar(
          currentIndex: _selectedIndex,
          onTap: (index) {
            setState(() => _selectedIndex = index);
          },
          userRole: userData?['role'] ?? '',
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            "Tasks",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryColor,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.brown),
            onPressed: fetchTasks,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(dynamic task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(14),
        title: Text(
          task['title'] ?? '',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.brown,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (task['description'] != null &&
                task['description'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Text(
                  task['description'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  label: Text(task['status'] ?? ''),
                  backgroundColor: _statusColor(task['status'] ?? ''),
                  labelStyle: const TextStyle(color: Colors.white),
                ),
                Chip(
                  label: Text(task['priority'] ?? ''),
                  backgroundColor: _priorityColor(task['priority'] ?? ''),
                  labelStyle: const TextStyle(color: Colors.white),
                ),
                if (task['deadline'] != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.brown,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateTime.parse(
                          task['deadline'],
                        ).toLocal().toString().split(' ')[0],
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.brown,
                        ),
                      ),
                    ],
                  ),
              ],
            ),

            if (task['project'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "📌 Project: ${task['project']['title'] ?? ''}",
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (task['client'] != null && task['client'] is Map)
              Text(
                "👤 Client: ${(task['client'] as Map)['name'] ?? ''}",
                style: const TextStyle(fontSize: 12),
              ),
            // show assigned member progress
            _buildMemberProgressList(task),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) async {
            if (value == 'edit') {
              final updated = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddEditTaskScreen(task: task),
                ),
              );
              if (updated == true) fetchTasks();
            } else if (value == 'delete') {
              deleteTask(task['_id']);
            } else if (value == 'details') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TaskDetailsScreen(task: task),
                ),
              );
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18),
                  SizedBox(width: 8),
                  Text('Details'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 18, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Delete'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundImage: userData?['avatarUrl'] != null
                    ? NetworkImage(userData!['avatarUrl'])
                    : const AssetImage('assets/user.jpg') as ImageProvider,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userData != null
                        ? 'Hi ${userData!['fullName'] ?? ''}'
                        : 'Hi...',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                  Text(
                    userData?['role'] ?? '',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.notifications_none,
              color: Colors.brown,
              size: 30,
            ),
          ),
        ],
      ),
    );
  }
}
