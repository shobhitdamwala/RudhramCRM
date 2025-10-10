import 'package:flutter/material.dart';
import '../utils/constants.dart';

class TaskDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> task;
  const TaskDetailsScreen({Key? key, required this.task}) : super(key: key);

  String _formatDate(String? date) {
    if (date == null) return 'N/A';
    return DateTime.parse(date).toLocal().toString().split(' ')[0];
  }

  @override
  Widget build(BuildContext context) {
    final assignedTo = task['assignedTo'] ?? [];
    final logs = task['logs'] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Task Details'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRow("📝 Title", task['title']),
            _buildRow("📃 Description", task['description']),
            _buildRow("📅 Deadline", _formatDate(task['deadline'])),
            _buildRow("🚦 Status", task['status']),
            _buildRow("🔥 Priority", task['priority']),
            if (task['client'] != null && task['client'] is Map)
              _buildRow("👤 Client", task['client']['name'] ?? ''),
            const SizedBox(height: 12),
            const Text("👥 Assigned To",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            ...assignedTo.map<Widget>((tm) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person, color: Colors.brown),
                  title: Text(tm['fullName'] ?? ''),
                  subtitle: Text(tm['email'] ?? ''),
                )),
            const SizedBox(height: 12),
            if (logs.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("📜 Logs",
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 6),
                  ...logs.map<Widget>((log) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.history, color: Colors.brown),
                        title: Text(log['action']),
                        subtitle: Text(
                          DateTime.parse(log['at'])
                              .toLocal()
                              .toString()
                              .split(' ')[0],
                        ),
                      )),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$label: ",
            style: const TextStyle(
                fontWeight: FontWeight.bold, color: Colors.brown),
          ),
          Expanded(
            child: Text(value ?? 'N/A'),
          ),
        ],
      ),
    );
  }
}
