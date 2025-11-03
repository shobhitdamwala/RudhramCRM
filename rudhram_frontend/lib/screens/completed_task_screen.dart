import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/background_container.dart';
import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class CompletedTaskScreen extends StatefulWidget {
  const CompletedTaskScreen({super.key});

  @override
  State<CompletedTaskScreen> createState() => _CompletedTaskScreenState();
}

class _CompletedTaskScreenState extends State<CompletedTaskScreen> {
  bool isLoading = true;
  List<dynamic> completedTasks = [];
  Map<String, dynamic>? userData;

  @override
  void initState() {
    super.initState();
    _loadCompletedTasks();
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

  Future<void> _loadCompletedTasks() async {
    try {
      setState(() => isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        SnackbarHelper.show(
          context,
          title: 'Not logged in',
          message: 'Please log in again.',
          type: ContentType.warning,
        );
        return;
      }

      // ✅ 1. Get logged-in user data
      await _fetchUser(token);

      final userId = userData?['_id'];
      if (userId == null) return;

      // ✅ 2. Fetch all assigned tasks (from Task model)
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/task/gettask"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final allTasks = List<dynamic>.from(body['data'] ?? []);

        // ✅ 3. Filter by user assignment + completion
        completedTasks = allTasks.where((t) {
          final status = (t['status'] ?? '').toString().toLowerCase();
          final progress = double.tryParse(t['progress'].toString()) ?? 0;
          final assignedTo = List<Map<String, dynamic>>.from(
            t['assignedTo'] ?? [],
          );

          // Match user in assigned list
          final isAssigned = assignedTo.any(
            (a) =>
                a['_id'] == userId ||
                a['id'] == userId ||
                a['userId'] == userId,
          );

          return isAssigned && (status == 'done' || progress == 100);
        }).toList();
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to load tasks.',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: e.toString(),
        type: ContentType.failure,
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchUser(String token) async {
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
          u['avatarUrl'] = "${ApiConfig.imageBaseUrl}${u['avatarUrl']}";
        }
        if (mounted) setState(() => userData = u);
      }
    } catch (_) {}
  }

  void _showTaskDetails(dynamic task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // ✅ Top bar
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primaryColor, Colors.orangeAccent],
                      ),
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          task['title'] ?? 'Task Details',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  // ✅ Content
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _detailRow("Description", task['description']),
                          _detailRow("Priority", task['priority']),
                          _detailRow("Status", task['status']),
                          _detailRow("Progress", "${task['progress'] ?? 100}%"),
                          if (task['deadline'] != null)
                            _detailRow(
                              "Deadline",
                              DateFormat('dd MMM yyyy, hh:mm a').format(
                                DateTime.parse(task['deadline']).toLocal(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(String title, dynamic value) {
    if (value == null || value.toString().isEmpty)
      return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$title: ",
            style: const TextStyle(
              color: Colors.brown,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          Expanded(
            child: Text(
              value.toString(),
              style: const TextStyle(color: Colors.black87, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  ),
                )
              : Column(
                  children: [
                    /// 🔹 Header
                    ProfileHeader(
                      avatarUrl: userData?['avatarUrl'],
                      fullName: userData?['fullName'],
                      role: formatUserRole(userData?['role']),
                      onNotification: () {},
                    ),
                    const SizedBox(height: 16),

                    /// 🔹 Task List
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: completedTasks.isEmpty
                            ? const Center(
                                child: Text(
                                  "No completed tasks yet 🎉",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: completedTasks.length,
                                itemBuilder: (context, index) {
                                  final task = completedTasks[index];
                                  final title = task['title'] ?? 'Untitled';
                                  final desc = task['description'] ?? '';
                                  final deadline = task['deadline'];

                                  String? deadlineText;
                                  if (deadline != null && deadline != '') {
                                    try {
                                      deadlineText = DateFormat('dd MMM yyyy')
                                          .format(
                                            DateTime.parse(deadline).toLocal(),
                                          );
                                    } catch (_) {}
                                  }

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ],
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                      leading: CircleAvatar(
                                        radius: 26,
                                        backgroundColor: AppColors.primaryColor,
                                        child: const Icon(
                                          Icons.check_circle,
                                          color: Colors.white,
                                          size: 30,
                                        ),
                                      ),
                                      title: Text(
                                        title,
                                        style: const TextStyle(
                                          color: Colors.brown,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (desc.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                                bottom: 6,
                                              ),
                                              child: Text(
                                                desc,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.black54,
                                                  fontSize: 13,
                                                ),
                                              ),
                                            ),
                                          if (deadlineText != null)
                                            Text(
                                              "Deadline: $deadlineText",
                                              style: const TextStyle(
                                                color: Colors.black54,
                                                fontSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                      trailing: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              AppColors.primaryColor,
                                          side: BorderSide(
                                            color: AppColors.primaryColor,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        onPressed: () => _showTaskDetails(task),
                                        child: const Text('View'),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),

                    /// 🔹 Bottom Navbar
                    CustomBottomNavBar(
                      currentIndex: 2, // completed task tab
                      onTap: (i) {},
                      userRole: userData?['role'] ?? 'TEAM_MEMBER',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
