import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import '../utils/api_config.dart';
import '../utils/custom_bottom_nav.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/profile_header.dart';

class TeamMemberHomeScreen extends StatefulWidget {
  const TeamMemberHomeScreen({super.key});

  @override
  State<TeamMemberHomeScreen> createState() => _TeamMemberHomeScreenState();
}

class _TeamMemberHomeScreenState extends State<TeamMemberHomeScreen> {
  Map<String, dynamic>? userData;
  List<dynamic> assignedTasks = [];
  List<dynamic> recentTasks = [];
  List<dynamic> deadlineTasks = [];
  bool isLoading = true;
  bool isUpdatingTask = false;
  String? updatingTaskId;

  // Task status colors
  final Map<String, Color> statusColors = {
    'not_started': Colors.grey,
    'in_progress': Colors.orange,
    'review': Colors.blue,
    'done': Colors.green,
    'blocked': Colors.red,
  };

  final Map<String, Color> priorityColors = {
    'low': Colors.green,
    'medium': Colors.orange,
    'high': Colors.red,
  };

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
        fetchAssignedTasks(token),
        fetchRecentTasks(token),
      ]);
      
      _checkDeadlines();
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

  void _checkDeadlines() {
    final now = DateTime.now();
    final upcomingDeadlines = assignedTasks.where((task) {
      if (task['deadline'] == null) return false;
      final deadline = DateTime.parse(task['deadline']).toLocal();
      final difference = deadline.difference(now);
      return difference.inDays <= 3 && difference.inDays >= 0;
    }).toList();

    setState(() {
      deadlineTasks = upcomingDeadlines;
    });

    if (deadlineTasks.isNotEmpty) {
      _showDeadlineNotification();
    }
  }

  void _showDeadlineNotification() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (deadlineTasks.length == 1) {
        SnackbarHelper.show(
          context,
          title: "⏰ Deadline Approaching",
          message: "${deadlineTasks.first['title']} is due soon!",
          type: ContentType.warning,
        );
      } else if (deadlineTasks.length > 1) {
        SnackbarHelper.show(
          context,
          title: "⏰ Multiple Deadlines",
          message: "You have ${deadlineTasks.length} tasks due soon!",
          type: ContentType.warning,
        );
      }
    });
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
        if (u['avatarUrl'] != null && u['avatarUrl'].toString().startsWith('/')) {
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

  Future<void> fetchAssignedTasks(String token) async {
    try {
      print("🔄 Fetching tasks from: ${ApiConfig.baseUrl}/task/mytasks");
      
      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/task/mytasks"),
        headers: {"Authorization": "Bearer $token"},
      );

      print("📡 Response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("✅ Tasks fetched successfully: ${data['data']?.length ?? 0} tasks");
        
        setState(() {
          assignedTasks = List<dynamic>.from(data['data'] ?? []);
        });
      } else {
        print("❌ Failed to fetch tasks: ${response.statusCode}");
        await _showErrorSnack(response.body, fallback: "Failed to fetch tasks");
      }
    } catch (e) {
      print("💥 Error fetching tasks: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Tasks load error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> fetchRecentTasks(String token) async {
    try {
      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/task/mytasks?limit=5"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          recentTasks = List<dynamic>.from(data['data'] ?? []).take(5).toList();
        });
      }
    } catch (e) {
      // Silently fail for recent tasks
    }
  }

  Future<void> updateTaskStatus(String taskId, String newStatus, {String? taskTitle}) async {
    setState(() {
      isUpdatingTask = true;
      updatingTaskId = taskId;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.put(
        Uri.parse("${ApiConfig.baseUrl}/task/$taskId"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"status": newStatus}),
      );

      if (response.statusCode == 200) {
        SnackbarHelper.show(
          context,
          title: "✅ Status Updated",
          message: "${taskTitle ?? 'Task'} status changed to ${newStatus.replaceAll('_', ' ')}",
          type: ContentType.success,
        );

        if (token != null) {
          await fetchAssignedTasks(token);
        }
      } else {
        await _showErrorSnack(
          response.body,
          fallback: "Failed to update task status",
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Failed to update task: $e",
        type: ContentType.failure,
      );
    } finally {
      setState(() {
        isUpdatingTask = false;
        updatingTaskId = null;
      });
    }
  }

  Future<void> updateTaskProgress(String taskId, int progress, {String? taskTitle}) async {
    setState(() {
      isUpdatingTask = true;
      updatingTaskId = taskId;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.put(
        Uri.parse("${ApiConfig.baseUrl}/task/assignment/$taskId/progress"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode({"progress": progress}),
      );

      if (response.statusCode == 200) {
        SnackbarHelper.show(
          context,
          title: "📊 Progress Updated",
          message: "${taskTitle ?? 'Task'} progress set to $progress%",
          type: ContentType.success,
        );

        if (token != null) {
          await fetchAssignedTasks(token);
        }
      } else {
        await _showErrorSnack(
          response.body,
          fallback: "Failed to update progress",
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Failed to update progress: $e",
        type: ContentType.failure,
      );
    } finally {
      setState(() {
        isUpdatingTask = false;
        updatingTaskId = null;
      });
    }
  }

  String _absUrl(String? maybeRelative) {
    if (maybeRelative == null || maybeRelative.isEmpty) return '';
    if (maybeRelative.startsWith('http')) return maybeRelative;
    if (maybeRelative.startsWith('/uploads')) {
      return "${ApiConfig.imageBaseUrl}$maybeRelative";
    }
    return "${ApiConfig.baseUrl}$maybeRelative";
  }

  Future<void> _showErrorSnack(
    dynamic body, {
    String fallback = "Request failed",
  }) async {
    try {
      final b = body is String ? jsonDecode(body) : body;
      final msg = (b?['message'] ?? b?['error'] ?? b?['msg'] ?? fallback).toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fallback), backgroundColor: Colors.red),
      );
    }
  }

  void _showTaskDetails(dynamic task) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF8B5E3C), Color(0xFFD2B48C)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task['title'] ?? 'Untitled Task',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Task Details',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(Icons.close_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                  ),

                  // Content
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Status and Priority
                          Row(
                            children: [
                              _buildStatusChip(task['status'] ?? 'not_started'),
                              const SizedBox(width: 8),
                              _buildPriorityChip(task['priority'] ?? 'medium'),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Client Information
                          if (task['client'] != null)
                            _buildClientInfoSection(task['client']),

                          // Service Information
                          if (task['client']?['meta']?['chosenServices'] != null)
                            _buildServicesSection(task['client']?['meta']?['chosenServices']),

                          // Team Information
                          _buildTeamSection(task),

                          // Description
                          if (task['description'] != null && task['description'].isNotEmpty)
                            _buildDescriptionSection(task['description']),

                          // Deadline
                          if (task['deadline'] != null)
                            _buildDeadlineSection(task['deadline']),

                          // Progress Section
                          _buildProgressSection(task),

                          const SizedBox(height: 20),

                          // Action Buttons
                          _buildActionButtons(task),
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

  Widget _buildClientInfoSection(Map<String, dynamic> client) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Client Information",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              _buildDetailRow("Name", client['name'] ?? 'N/A', Icons.person),
              if (client['businessName'] != null)
                _buildDetailRow("Business", client['businessName']!, Icons.business),
              if (client['email'] != null)
                _buildDetailRow("Email", client['email']!, Icons.email),
              if (client['phone'] != null)
                _buildDetailRow("Phone", client['phone']!, Icons.phone),
              if (client['meta']?['businessCategory'] != null)
                _buildDetailRow("Category", client['meta']?['businessCategory']!, Icons.category),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildServicesSection(List<dynamic> chosenServices) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Chosen Services",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: chosenServices.map((service) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.design_services, size: 16, color: Colors.brown),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            service['title'] ?? 'Service',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.brown,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (service['offerings'] != null && service['offerings'].isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 24, top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: (service['offerings'] as List).map((offering) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '• $offering',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTeamSection(dynamic task) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Team Information",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              if (task['assignedTo'] != null && task['assignedTo'].isNotEmpty)
                _buildTeamMembers(task['assignedTo']),
              if (task['createdBy'] != null)
                _buildDetailRow("Created By", task['createdBy']['fullName'] ?? 'Unknown', Icons.person_add),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildTeamMembers(List<dynamic> assignedTo) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.group, size: 16, color: Colors.brown),
            SizedBox(width: 8),
            Text(
              "Assigned Team Members:",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.brown,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...assignedTo.map((member) {
          return Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.person_outline, size: 14, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${member['fullName']} (${member['email']})',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildDescriptionSection(String description) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Description",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            description,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDeadlineSection(String deadline) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Deadline",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _getDeadlineColor(deadline).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _getDeadlineColor(deadline)),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 16, color: _getDeadlineColor(deadline)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE, MMMM dd, yyyy - hh:mm a').format(
                        DateTime.parse(deadline).toLocal(),
                      ),
                      style: TextStyle(
                        fontSize: 14,
                        color: _getDeadlineColor(deadline),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getDeadlineMessage(deadline),
                      style: TextStyle(
                        fontSize: 12,
                        color: _getDeadlineColor(deadline),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildProgressSection(dynamic task) {
    final progress = task['progress'] ?? 0;
    final userStatus = task['userStatus'] ?? 'not_started';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Your Progress",
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Column(
            children: [
              // Progress Bar
              LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(_getProgressColor(progress)),
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "$progress% Complete",
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    "${100 - progress}% Remaining",
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // User Status
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColors[userStatus]?.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColors[userStatus] ?? Colors.grey),
                ),
                child: Text(
                  "Your Status: ${userStatus.replaceAll('_', ' ').toUpperCase()}",
                  style: TextStyle(
                    color: statusColors[userStatus] ?? Colors.grey,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(dynamic task) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: isUpdatingTask && updatingTaskId == task['_id']
                ? null
                : () {
                    Navigator.pop(context);
                    _showStatusUpdateDialog(task);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: isUpdatingTask && updatingTaskId == task['_id']
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.update, size: 18),
            label: isUpdatingTask && updatingTaskId == task['_id']
                ? const Text('Updating...')
                : const Text('Update Status'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: isUpdatingTask && updatingTaskId == task['_id']
                ? null
                : () {
                    Navigator.pop(context);
                    _showProgressUpdateDialog(task);
                  },
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryColor,
              side: const BorderSide(color: AppColors.primaryColor),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: isUpdatingTask && updatingTaskId == task['_id']
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.trending_up, size: 18),
            label: isUpdatingTask && updatingTaskId == task['_id']
                ? const Text('Updating...')
                : const Text('Update Progress'),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.brown),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.brown),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Color _getDeadlineColor(String deadline) {
    final now = DateTime.now();
    final taskDeadline = DateTime.parse(deadline).toLocal();
    final difference = taskDeadline.difference(now);
    
    if (difference.inDays < 0) return Colors.red;
    if (difference.inDays == 0) return Colors.orange;
    if (difference.inDays <= 2) return Colors.orange;
    if (difference.inDays <= 7) return Colors.blue;
    return Colors.green;
  }

  String _getDeadlineMessage(String deadline) {
    final now = DateTime.now();
    final taskDeadline = DateTime.parse(deadline).toLocal();
    final difference = taskDeadline.difference(now);
    
    if (difference.inDays < 0) return 'Overdue by ${difference.inDays.abs()} days';
    if (difference.inDays == 0) return 'Due today';
    if (difference.inDays == 1) return 'Due tomorrow';
    return 'Due in ${difference.inDays} days';
  }

  Widget _buildStatusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: statusColors[status]?.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColors[status] ?? Colors.grey),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: statusColors[status] ?? Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPriorityChip(String priority) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: priorityColors[priority]?.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: priorityColors[priority] ?? Colors.grey),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: priorityColors[priority] ?? Colors.grey,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getProgressColor(int progress) {
    if (progress < 30) return Colors.red;
    if (progress < 70) return Colors.orange;
    return Colors.green;
  }

  void _showStatusUpdateDialog(dynamic task) {
    final List<String> statusOptions = ['not_started', 'in_progress', 'review', 'done', 'blocked'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Update Task Status"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: statusOptions.map((status) {
            return ListTile(
              leading: Icon(Icons.circle, color: statusColors[status]),
              title: Text(status.replaceAll('_', ' ').toUpperCase()),
              onTap: () {
                Navigator.pop(context);
                updateTaskStatus(task['_id'], status, taskTitle: task['title']);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showProgressUpdateDialog(dynamic task) {
    int currentProgress = task['progress'] ?? 0;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Update Progress"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("$currentProgress%", style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Slider(
                  value: currentProgress.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (value) => setState(() => currentProgress = value.round()),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [0, 25, 50, 75, 100].map((value) {
                    return Text(
                      "$value%",
                      style: TextStyle(
                        fontWeight: value == currentProgress ? FontWeight.bold : FontWeight.normal,
                        color: value == currentProgress ? AppColors.primaryColor : Colors.grey,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  updateTaskProgress(task['_id'], currentProgress, taskTitle: task['title']);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text("Update"),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.brown))
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Profile Header
                            ProfileHeader(
                              avatarUrl: userData?['avatarUrl'],
                              fullName: userData?['fullName'],
                              role: userData?['role'] ?? 'Team Member',
                              onNotification: () => print("🔔 Notification tapped"),
                            ),

                            const SizedBox(height: 20),

                            // Deadline Notifications
                            if (deadlineTasks.isNotEmpty) _buildDeadlineNotification(),

                            // Welcome Card
                            _buildWelcomeCard(),

                            const SizedBox(height: 20),

                            // Assigned Tasks Section
                            _buildTasksSection(),

                            const SizedBox(height: 20),

                            // Recent Activity
                            if (recentTasks.isNotEmpty) _buildRecentActivitySection(),

                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),

                    // Bottom Navigation
                    CustomBottomNavBar(
                      currentIndex: 0,
                      onTap: (index) {
                        if (index == 1) print("Navigate to profile");
                      },
                      userRole: userData?['role'] ?? '',
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildDeadlineNotification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Colors.orange, Colors.red]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Deadline Alert!", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text("You have ${deadlineTasks.length} task${deadlineTasks.length > 1 ? 's' : ''} due soon", 
                         style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => deadlineTasks = []),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF8B5E3C), Color(0xFFD2B48C)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Welcome back, ${userData?['fullName']?.split(' ').first ?? 'Team Member'}!", 
               style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 8),
          Text("You have ${assignedTasks.length} assigned tasks", 
               style: const TextStyle(fontSize: 14, color: Colors.white70)),
        ],
      ),
    );
  }

  Widget _buildTasksSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("My Tasks", style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 18)),
            Text("${assignedTasks.length} tasks", style: const TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 12),
        if (assignedTasks.isEmpty) _buildEmptyState() else ...assignedTasks.map((task) => _buildTaskCard(task)),
      ],
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Recent Activity", style: TextStyle(color: Colors.brown, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 12),
        ...recentTasks.map((task) => _buildRecentTaskItem(task)),
      ],
    );
  }

  Widget _buildTaskCard(dynamic task) {
    final deadline = task['deadline'] != null ? DateTime.parse(task['deadline']).toLocal() : null;
    final progress = task['progress'] ?? 0;
    final hasApproachingDeadline = deadlineTasks.any((t) => t['_id'] == task['_id']);
    final isThisTaskUpdating = isUpdatingTask && updatingTaskId == task['_id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 2))],
        border: hasApproachingDeadline ? Border.all(color: Colors.orange, width: 2) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isThisTaskUpdating ? null : () => _showTaskDetails(task),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Stack(
              children: [
                if (isThisTaskUpdating)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withOpacity(0.8),
                      child: const Center(
                        child: CircularProgressIndicator(color: AppColors.primaryColor),
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (hasApproachingDeadline)
                                const Icon(Icons.warning_amber, color: Colors.orange, size: 16),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  task['title'] ?? 'Untitled Task',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildStatusChip(task['status'] ?? 'not_started'),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (task['description'] != null && task['description'].isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task['description'],
                            style: const TextStyle(fontSize: 14, color: Colors.grey),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),

                    // Progress Bar
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Progress: $progress%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey)),
                            Text("${100 - progress}% remaining", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: progress / 100,
                          backgroundColor: Colors.grey[300],
                          valueColor: AlwaysStoppedAnimation<Color>(_getProgressColor(progress)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Footer with deadline and priority
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (deadline != null)
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 14, color: _getDeadlineColor(task['deadline'])),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('MMM dd').format(deadline),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: _getDeadlineColor(task['deadline']),
                                  fontWeight: hasApproachingDeadline ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        _buildPriorityChip(task['priority'] ?? 'medium'),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentTaskItem(dynamic task) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColors[task['status']] ?? Colors.grey,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              task['title'] ?? 'Untitled Task',
              style: const TextStyle(fontSize: 14),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            task['status']?.replaceAll('_', ' ') ?? 'not started',
            style: TextStyle(
              fontSize: 12,
              color: statusColors[task['status']] ?? Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          Icon(Icons.task_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text("No Tasks Assigned", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          const Text("You don't have any tasks assigned to you at the moment.", 
               textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      ),
    );
  }
}