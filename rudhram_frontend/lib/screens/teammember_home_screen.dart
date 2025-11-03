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
  List<dynamic> allAssignedTasks = [];
  List<dynamic> assignedTasks = []; // filtered for current user
  List<dynamic> recentTasks = [];
  List<dynamic> deadlineTasks = [];
  List<Map<String, dynamic>> teamMembers = [];
  bool isLoading = true;
  bool isUpdatingTask = false;
  String? updatingTaskId;

  final Map<String, Color> statusColors = {
    'not_started': Colors.grey,
    'in_progress': Colors.orange,
    'review': Colors.blue,
    'done': Colors.green,
    'blocked': Colors.red,
    'open': Colors.orange,
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

  Future<void> fetchAllData() async {
    try {
      setState(() => isLoading = true);

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        SnackbarHelper.show(
          context,
          title: "Not Logged In",
          message: "Please log in again.",
          type: ContentType.warning,
        );
        setState(() => isLoading = false);
        return;
      }

      // fetch user first
      await fetchUser(token);

      // fetch team members and tasks in parallel (teamMembers needed to render names)
      await Future.wait([
        fetchTeamMembers(token),
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

  Future<void> fetchTeamMembers(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final raw = List<dynamic>.from(data['teamMembers'] ?? []);
        teamMembers = raw
            .map<Map<String, dynamic>>(
              (m) => Map<String, dynamic>.from(m as Map),
            )
            .toList();
        if (mounted) setState(() {});
      }
    } catch (e) {
      // silently fail; names will fallback to ids
    }
  }

  Future<void> fetchAssignedTasks(String token) async {
    try {
      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/task/mytasks"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        allAssignedTasks = List<dynamic>.from(data['data'] ?? []);

        final myId = (userData?['_id'] ?? userData?['id'])?.toString();

        if (myId != null && myId.isNotEmpty) {
          assignedTasks = allAssignedTasks.where((task) {
            // check top-level assignedTo
            final assignedTo = List<dynamic>.from(task['assignedTo'] ?? []);
            for (var a in assignedTo) {
              if (a == null) continue;
              if (a is String && a == myId) return true;
              if (a is Map &&
                  ((a['_id']?.toString() ?? a['id']?.toString()) == myId))
                return true;
            }
            // check per-service assignedTeamMembers
            final chosen = List<dynamic>.from(task['chosenServices'] ?? []);
            for (var s in chosen) {
              final at = List<dynamic>.from(
                s['assignedTeamMembers'] ?? s['assignedTo'] ?? [],
              );
              for (var a in at) {
                if (a == null) continue;
                if (a is String && a == myId) return true;
                if (a is Map &&
                    ((a['_id']?.toString() ?? a['id']?.toString()) == myId))
                  return true;
              }
            }
            return false;
          }).toList();
        } else {
          assignedTasks = List<dynamic>.from(allAssignedTasks);
        }

        if (mounted) setState(() {});
      } else {
        await _showErrorSnack(response.body, fallback: "Failed to fetch tasks");
      }
    } catch (e) {
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
        final raw = List<dynamic>.from(data['data'] ?? []);
        final myId = (userData?['_id'] ?? userData?['id'])?.toString();
        if (myId != null && myId.isNotEmpty) {
          recentTasks = raw
              .where((task) {
                final assignedTo = List<dynamic>.from(task['assignedTo'] ?? []);
                for (var a in assignedTo) {
                  if (a == null) continue;
                  if (a is String && a == myId) return true;
                  if (a is Map &&
                      ((a['_id']?.toString() ?? a['id']?.toString()) == myId))
                    return true;
                }
                final chosen = List<dynamic>.from(task['chosenServices'] ?? []);
                for (var s in chosen) {
                  final at = List<dynamic>.from(
                    s['assignedTeamMembers'] ?? s['assignedTo'] ?? [],
                  );
                  for (var a in at) {
                    if (a == null) continue;
                    if (a is String && a == myId) return true;
                    if (a is Map &&
                        ((a['_id']?.toString() ?? a['id']?.toString()) == myId))
                      return true;
                  }
                }
                return false;
              })
              .take(5)
              .toList();
        } else {
          recentTasks = raw.take(5).toList();
        }

        if (mounted) setState(() {});
      }
    } catch (e) {
      // ignore
    }
  }

  void _checkDeadlines() {
    final now = DateTime.now();
    final upcomingDeadlines = assignedTasks.where((task) {
      if (task['deadline'] == null) return false;
      try {
        final deadline = DateTime.parse(task['deadline']).toLocal();
        final difference = deadline.difference(now);
        return difference.inDays <= 3 && difference.inDays >= 0;
      } catch (_) {
        return false;
      }
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
      if (!mounted) return;
      if (deadlineTasks.length == 1) {
        SnackbarHelper.show(
          context,
          title: "⏰ Deadline Approaching",
          message: "\"${deadlineTasks.first['title']}\" is due soon!",
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

  Future<void> updateTaskStatus(
    String taskId,
    String newStatus, {
    String? taskTitle,
  }) async {
    setState(() {
      isUpdatingTask = true;
      updatingTaskId = taskId;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.put(
        Uri.parse("${ApiConfig.baseUrl}/task/$taskId/updatestatus"),
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
          message:
              "${taskTitle ?? 'Task'} status changed to ${newStatus.replaceAll('_', ' ')}",
          type: ContentType.success,
        );

        if (token != null) await fetchAssignedTasks(token);
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

  Future<void> updateTaskProgress(
    String taskId,
    int progress, {
    String? taskTitle,
  }) async {
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

        if (token != null) await fetchAssignedTasks(token);
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

  // get readable member name from id/object using teamMembers list or fallback to id
  String _getMemberName(dynamic a) {
    try {
      if (a == null) return '';
      if (a is Map) {
        final id = (a['_id'] ?? a['id'])?.toString();
        final name = a['fullName'] ?? a['name'] ?? a['email'] ?? id;
        return name?.toString() ?? id ?? '';
      }
      final sid = a.toString();
      final found = teamMembers.firstWhere(
        (m) => (m['_id']?.toString() == sid || m['id']?.toString() == sid),
        orElse: () => {},
      );
      if (found.isNotEmpty) {
        return (found['fullName'] ?? found['name'] ?? sid).toString();
      }
      return sid;
    } catch (_) {
      return a.toString();
    }
  }

  void _showTaskDetails(dynamic task) {
    final myId = (userData?['_id'] ?? userData?['id'])?.toString();
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
            final chosen = List<dynamic>.from(task['chosenServices'] ?? []);
            final visibleServices = (myId != null && myId.isNotEmpty)
                ? chosen.where((s) {
                    final at = List<dynamic>.from(
                      s['assignedTeamMembers'] ?? s['assignedTo'] ?? [],
                    );
                    for (var a in at) {
                      if (a == null) continue;
                      if (a is String && a == myId) return true;
                      if (a is Map &&
                          ((a['_id']?.toString() ?? a['id']?.toString()) ==
                              myId))
                        return true;
                    }
                    return false;
                  }).toList()
                : chosen;

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
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
                  // header gradient using AppColors.primaryColor
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 20,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryColor,
                          AppColors.primaryColor.withOpacity(0.85),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
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
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // ❗ Removed main task status chip here
                        // (no chip on header now)
                      ],
                    ),
                  ),

                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top row: show only PRIORITY chip (no main task status)
                          Row(
                            children: [
                              _buildPriorityChip(task['priority'] ?? 'medium'),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Minimal client information
                          if (task['client'] != null)
                            _buildClientInfoSectionMinimal(task['client']),

                          // Services assigned to this user (show names)
                          if (visibleServices.isNotEmpty)
                            _buildServicesSectionFiltered(visibleServices),

                          // Description
                          if (task['description'] != null &&
                              task['description'].toString().trim().isNotEmpty)
                            _buildDescriptionSection(task['description']),

                          // Deadline indicator only (no raw datetime)
                          if (task['deadline'] != null)
                            _buildDeadlineIndicator(task['deadline']),

                          const SizedBox(height: 12),
                          // Progress box already shows the user's status nicely
                          _buildProgressSection(task),
                          const SizedBox(height: 20),
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

  Widget _buildClientInfoSectionMinimal(dynamic client) {
    String name = '';
    try {
      if (client is String)
        name = client;
      else if (client is Map)
        name = client['name'] ?? client['businessName'] ?? client['_id'] ?? '';
    } catch (_) {}
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Client",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
          child: Row(
            children: [
              const Icon(Icons.person, color: Colors.brown),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(fontSize: 14))),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildServicesSectionFiltered(List<dynamic> chosenServices) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Your Assigned Services",
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
              final offerings = List<dynamic>.from(
                service['selectedOfferings'] ?? service['offerings'] ?? [],
              );
              final assigned = List<dynamic>.from(
                service['assignedTeamMembers'] ?? service['assignedTo'] ?? [],
              );
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.design_services,
                          size: 16,
                          color: Colors.brown,
                        ),
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
                        if (service['subCompanyName'] != null &&
                            service['subCompanyName'].toString().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              service['subCompanyName'].toString(),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                    if (offerings.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 24, top: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: offerings
                              .map<Widget>(
                                (o) => Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    '• ${o.toString()}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    if (assigned.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 24, top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: assigned.map<Widget>((a) {
                            final name = _getMemberName(a);
                            final amIMe =
                                ((userData?['_id']?.toString() ??
                                    userData?['id']?.toString()) ==
                                (a is String
                                    ? a
                                    : (a is Map
                                          ? (a['_id']?.toString() ??
                                                a['id']?.toString())
                                          : a.toString())));
                            return Chip(
                              label: Text(
                                amIMe ? 'You' : name,
                                style: const TextStyle(fontSize: 12),
                              ),
                              backgroundColor: amIMe
                                  ? AppColors.primaryColor.withOpacity(0.12)
                                  : Colors.grey[100],
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
        const SizedBox(height: 12),
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
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildDeadlineIndicator(String deadline) {
    Color c = _getDeadlineColor(deadline);
    String msg = _getDeadlineMessage(deadline);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 16, color: c),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(color: c, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(dynamic task) {
    final progress = (task['progress'] ?? 0) as int;
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
              LinearProgressIndicator(
                value: progress / 100,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  _getProgressColor(progress),
                ),
                minHeight: 8,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "$progress% Complete",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    "${100 - progress}% Remaining",
                    style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 👇 User's status chip (from TaskAssignment)
              Align(
                alignment: Alignment.centerLeft,
                child: _buildStatusChip(userStatus),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: isUpdatingTask && updatingTaskId == task['_id']
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
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

  void _showStatusUpdateDialog(dynamic task) {
    final List<String> statusOptions = [
      'not_started',
      'in_progress',
      'review',
      'done',
      'blocked',
    ];
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
    int currentProgress = (task['progress'] ?? 0) as int;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text("Update Progress"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "$currentProgress%",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Slider(
                  value: currentProgress.toDouble(),
                  min: 0,
                  max: 100,
                  divisions: 20,
                  onChanged: (value) =>
                      setState(() => currentProgress = value.round()),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [0, 25, 50, 75, 100].map((value) {
                    return Text(
                      "$value%",
                      style: TextStyle(
                        fontWeight: value == currentProgress
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: value == currentProgress
                            ? AppColors.primaryColor
                            : Colors.grey,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  updateTaskProgress(
                    task['_id'],
                    currentProgress,
                    taskTitle: task['title'],
                  );
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

  Color _getDeadlineColor(String deadline) {
    try {
      final now = DateTime.now();
      final taskDeadline = DateTime.parse(deadline).toLocal();
      final difference = taskDeadline.difference(now);
      if (difference.inDays < 0) return Colors.red;
      if (difference.inDays == 0) return Colors.orange;
      if (difference.inDays <= 2) return Colors.orange;
      if (difference.inDays <= 7) return Colors.blue;
      return Colors.green;
    } catch (_) {
      return Colors.grey;
    }
  }

  String _getDeadlineMessage(String deadline) {
    try {
      final now = DateTime.now();
      final taskDeadline = DateTime.parse(deadline).toLocal();
      final difference = taskDeadline.difference(now);
      if (difference.inDays < 0)
        return 'Overdue by ${difference.inDays.abs()} days';
      if (difference.inDays == 0) return 'Due today';
      if (difference.inDays == 1) return 'Due tomorrow';
      return 'Due in ${difference.inDays} days';
    } catch (_) {
      return 'Deadline information';
    }
  }

  bool _isApproachingDeadline(dynamic deadline) {
    try {
      final now = DateTime.now();
      final d = DateTime.parse(deadline).toLocal();
      final diff = d.difference(now);
      return diff.inDays <= 3;
    } catch (_) {
      return false;
    }
  }

  Widget _buildDeadlineNotification() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Colors.orange, Colors.red]),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.orange.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_active,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Deadline Alert!",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "You have ${deadlineTasks.length} task${deadlineTasks.length > 1 ? 's' : ''} due soon",
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
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

  Widget _buildTaskCard(dynamic task) {
    final progress = (task['progress'] ?? 0) as int;
    final hasApproachingDeadline =
        task['deadline'] != null && _isApproachingDeadline(task['deadline']);
    final isThisTaskUpdating = isUpdatingTask && updatingTaskId == task['_id'];
    final userStatus = task['userStatus'] ?? 'not_started';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: hasApproachingDeadline
            ? Border.all(color: Colors.orange, width: 2)
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isThisTaskUpdating ? null : () => _showTaskDetails(task),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Stack(
              children: [
                if (isThisTaskUpdating)
                  Positioned.fill(
                    child: Container(
                      color: Colors.white.withOpacity(0.8),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title + (removed main task status chip)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              if (hasApproachingDeadline)
                                const Icon(
                                  Icons.warning_amber,
                                  color: Colors.orange,
                                  size: 16,
                                ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  task['title'] ?? 'Untitled Task',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.brown,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // only PRIORITY chip on right
                        _buildPriorityChip(task['priority'] ?? 'medium'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (task['description'] != null &&
                        task['description'].toString().trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          task['description'],
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    // progress + user status
                    Text(
                      "Progress: $progress%",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getProgressColor(progress),
                      ),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 8),
                    _buildStatusChip(userStatus), // 👈 show user's status here
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Recent Activity",
          style: TextStyle(
            color: Colors.brown,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 12),
        ...recentTasks.map((task) => _buildRecentTaskItem(task)),
      ],
    );
  }

  Widget _buildRecentTaskItem(dynamic task) {
    final userStatus = task['userStatus'] ?? 'not_started';
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
              color: statusColors[userStatus] ?? Colors.grey,
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
            userStatus.replaceAll('_', ' '),
            style: TextStyle(
              fontSize: 12,
              color: statusColors[userStatus] ?? Colors.grey,
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.task_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            "No Tasks Assigned",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "You don't have any tasks assigned to you at the moment.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey),
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
                            ProfileHeader(
                              avatarUrl: userData?['avatarUrl'],
                              fullName: userData?['fullName'],
                              role: formatUserRole(userData?['role']),
                              onNotification: () =>
                                  print("🔔 Notification tapped"),
                            ),
                            const SizedBox(height: 20),

                            if (deadlineTasks.isNotEmpty)
                              _buildDeadlineNotification(),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "My Tasks",
                                  style: TextStyle(
                                    color: Colors.brown,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                Text(
                                  "${assignedTasks.length} tasks",
                                  style: const TextStyle(
                                    color: Colors.grey,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (assignedTasks.isEmpty)
                              _buildEmptyState()
                            else
                              Column(
                                children: assignedTasks
                                    .map((task) => _buildTaskCard(task))
                                    .toList(),
                              ),
                            const SizedBox(height: 20),
                            if (recentTasks.isNotEmpty)
                              _buildRecentActivitySection(),
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                    ),
                    CustomBottomNavBar(
                      currentIndex: 1,
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
}
