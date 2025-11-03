import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';

class TaskDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> task;
  const TaskDetailsScreen({Key? key, required this.task}) : super(key: key);

  String _formatDate(String? date) {
    if (date == null) return 'Not set';
    try {
      final parsedDate = DateTime.parse(date).toLocal();
      return '${parsedDate.day}/${parsedDate.month}/${parsedDate.year}';
    } catch (e) {
      return 'Invalid date';
    }
  }

  String _formatDateTime(String? date) {
    if (date == null) return 'N/A';
    try {
      final parsedDate = DateTime.parse(date).toLocal();
      return '${parsedDate.day}/${parsedDate.month}/${parsedDate.year} at ${parsedDate.hour.toString().padLeft(2, '0')}:${parsedDate.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return 'N/A';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.blue;
      case 'in_progress':
        return Colors.orange;
      case 'review':
        return Colors.purple;
      case 'done':
        return Colors.green;
      case 'blocked':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  /// Try to resolve a user object from the assignedTo list (if it's populated)
  /// Returns a map with at minimum keys: 'id' and optional 'fullName' and 'email'
  Map<String, String> _resolveMember(
    dynamic memberOrId,
    List<dynamic> assignedToList,
  ) {
    // If memberOrId is a Map (object), prefer that
    if (memberOrId is Map) {
      final id = (memberOrId['_id'] ?? memberOrId['id'] ?? '').toString();
      final name = (memberOrId['fullName'] ?? memberOrId['name'] ?? '')
          .toString();
      final email = (memberOrId['email'] ?? '').toString();
      return {'id': id, 'name': name, 'email': email};
    }

    // If assignedToList contains full objects, find matching one
    final idStr = memberOrId?.toString() ?? '';
    for (var a in assignedToList) {
      if (a is Map) {
        final aid = (a['_id'] ?? a['id'])?.toString() ?? '';
        if (aid == idStr) {
          final name = (a['fullName'] ?? a['name'] ?? '').toString();
          final email = (a['email'] ?? '').toString();
          return {'id': aid, 'name': name, 'email': email};
        }
      }
    }

    // fallback: return id-only
    return {'id': idStr, 'name': idStr, 'email': ''};
  }

  @override
  Widget build(BuildContext context) {
    final assignedToRaw = List<dynamic>.from(task['assignedTo'] ?? []);
    final chosenServicesRaw = List<dynamic>.from(task['chosenServices'] ?? []);
    final logs = List<dynamic>.from(task['logs'] ?? []);
    final client = task['client'] ?? {};

    // Build a map: memberId -> list of service titles they are assigned to
    final Map<String, List<String>> memberToServices = {};
    for (var s in chosenServicesRaw) {
      final serviceTitle =
          (s['title'] ??
                  s['serviceTitle'] ??
                  s['name'] ??
                  s['title'] ??
                  'Service')
              .toString();
      final assignedList = List<dynamic>.from(
        s['assignedTeamMembers'] ?? s['assignedTo'] ?? [],
      );
      for (var m in assignedList) {
        final mid = m is Map
            ? (m['_id'] ?? m['id'] ?? '').toString()
            : m.toString();
        if (mid.isEmpty) continue;
        memberToServices.putIfAbsent(mid, () => []).add(serviceTitle);
      }
    }

    // If server stored assignedTo as objects, ensure those members appear in mapping even if not in chosenServices
    for (var a in assignedToRaw) {
      final aid = a is Map
          ? (a['_id'] ?? a['id'] ?? '').toString()
          : a.toString();
      if (aid.isEmpty) continue;
      memberToServices.putIfAbsent(aid, () => []);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Task Details',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: BackgroundContainer(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTaskHeaderCard(),

              const SizedBox(height: 20),

              if (client != null && (client is Map) && client.isNotEmpty) ...[
                _buildSectionTitle("Client Information", Icons.person),
                const SizedBox(height: 12),
                _buildClientCard(client as Map<String, dynamic>),
                const SizedBox(height: 20),
              ],

              if (chosenServicesRaw.isNotEmpty) ...[
                _buildSectionTitle("Selected Services", Icons.design_services),
                const SizedBox(height: 12),
                ...chosenServicesRaw
                    .map(
                      (s) => _buildServiceCard(
                        s as Map<String, dynamic>,
                        assignedToRaw,
                      ),
                    )
                    .toList(),
                const SizedBox(height: 20),
              ],
              _buildSectionTitle("Assigned Team Progress", Icons.people),
              const SizedBox(height: 12),

              if (task['assignments'] != null &&
                  (task['assignments'] as List).isNotEmpty)
                ...List.from(
                  task['assignments'],
                ).map((a) => _buildMemberProgress(a))
              else
                _buildEmptyState(
                  "No team members assigned",
                  Icons.people_outline,
                ),
              const SizedBox(height: 20),

              if (logs.isNotEmpty) ...[
                _buildSectionTitle("Activity Log", Icons.history),
                const SizedBox(height: 12),
                ...logs.map((log) => _buildLogCard(log)).toList(),
              ],

              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskHeaderCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task['title'] ?? 'No Title',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          if (task['description'] != null &&
              (task['description'] as String).isNotEmpty)
            Column(
              children: [
                Text(
                  task['description'],
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          Row(
            children: [
              _buildStatusChip(task['status'] ?? 'open'),
              const SizedBox(width: 12),
              _buildPriorityChip(task['priority'] ?? 'medium'),
            ],
          ),
          const SizedBox(height: 16),
          _buildInfoRow(
            Icons.calendar_today,
            "Deadline",
            _formatDate(task['deadline']),
          ),
          _buildInfoRow(
            Icons.access_time,
            "Created",
            _formatDateTime(task['createdAt']?.toString()),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.replaceAll('_', ' ').toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriorityChip(String priority) {
    final color = _getPriorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flag, size: 12, color: color),
          const SizedBox(width: 6),
          Text(
            priority.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientCard(Map<String, dynamic> client) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: AppColors.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client['name'] ?? 'Unknown Client',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  'Client ID: ${client['clientId'] ?? client['_id'] ?? 'N/A'}',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(dynamic service, List<dynamic> assignedToList) {
    // service may be Map or dynamic structure; normalize
    final title =
        (service['title'] ??
                service['serviceTitle'] ??
                service['name'] ??
                'Unknown Service')
            .toString();
    final subCompanyName = (service['subCompanyName'] ?? '').toString();
    final offerings = List<dynamic>.from(
      service['selectedOfferings'] ?? service['offerings'] ?? [],
    );

    final assignedIds = List<dynamic>.from(
      service['assignedTeamMembers'] ?? service['assignedTo'] ?? [],
    );
    // Resolve member objects/names
    final assignedMembers = assignedIds
        .map<Map<String, String>>((m) => _resolveMember(m, assignedToList))
        .toList();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.design_services,
                  color: AppColors.primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    if (subCompanyName.isNotEmpty)
                      Text(
                        subCompanyName,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (offerings.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              "Selected Offerings:",
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: offerings.map<Widget>((off) {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.primaryColor.withOpacity(0.3),
                    ),
                  ),
                  child: Text(
                    off.toString(),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            "Assigned Members:",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          assignedMembers.isNotEmpty
              ? Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: assignedMembers.map((m) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primaryColor.withOpacity(0.12),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person,
                            size: 14,
                            color: AppColors.primaryColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            m['name'] ?? m['id'] ?? '',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                )
              : Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Text(
                    'No members assigned',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ),
        ],
      ),
    );
  }

  Widget _buildTeamMemberCardWithServices(
    Map<String, dynamic> member,
    List<String> services,
  ) {
    final displayName = member['name'] ?? member['id'] ?? 'Unknown';
    final email = member['email'] ?? '';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.person, color: AppColors.primaryColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                if (services.isNotEmpty) const SizedBox(height: 8),
                if (services.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: services.map((s) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final action = log['action'] ?? 'Unknown Action';
    final at = _formatDateTime(log['at']?.toString());
    final by = log['by'];
    final byText = by is Map
        ? (by['fullName'] ?? 'System')
        : (by?.toString() ?? 'System');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.history, color: Colors.blue, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  at,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  'By: $byText',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
              fontSize: 14,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primaryColor, size: 18),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

Widget _buildMemberProgress(dynamic assignment) {
  final user = assignment['user'] ?? {};
  final name = user['fullName'] ?? 'Unknown';
  final progress = assignment['progress'] ?? 0;
  final status = assignment['status'] ?? 'not_started';

  return Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.grey.shade200),
    ),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.person, color: AppColors.primaryColor, size: 18),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress / 100,
                minHeight: 6,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation(AppColors.primaryColor),
              ),
              const SizedBox(height: 4),
              Text(
                "Status: $status",
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          "${progress.toString()}%",
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}
