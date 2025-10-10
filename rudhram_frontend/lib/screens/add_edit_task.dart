import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class AddEditTaskScreen extends StatefulWidget {
  final dynamic task;
  const AddEditTaskScreen({Key? key, this.task}) : super(key: key);

  @override
  State<AddEditTaskScreen> createState() => _AddEditTaskScreenState();
}

class _AddEditTaskScreenState extends State<AddEditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _description = TextEditingController();
  DateTime? _deadline;

  String _status = "open";
  String _priority = "medium";
  String? _projectId;
  String? _clientId;
  String? _subCompanyId;
  List<String> _assignedTo = [];

  List<dynamic> projects = [];
  List<dynamic> clients = [];
  List<dynamic> subCompanies = [];
  List<dynamic> teamMembers = [];

  @override
  void initState() {
    super.initState();
    fetchDropdownData();
    if (widget.task != null) {
      _title.text = widget.task['title'] ?? '';
      _description.text = widget.task['description'] ?? '';
      _status = widget.task['status'] ?? 'open';
      _priority = widget.task['priority'] ?? 'medium';
      if (widget.task['deadline'] != null) {
        _deadline = DateTime.parse(widget.task['deadline']);
      }
      _projectId = widget.task['project']?['_id'];
      _clientId = widget.task['client']?['_id'];
      _subCompanyId = widget.task['subCompany']?['_id'];
      if (widget.task['assignedTo'] != null) {
        _assignedTo = (widget.task['assignedTo'] as List)
            .map((e) => e['_id'] as String)
            .toList();
      }
    }
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
  }

  Future<void> fetchDropdownData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));

    Future<List<dynamic>> fetch(String endpoint) async {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/$endpoint"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return data['data'] ?? [];
      }
      return [];
    }

    final results = await Future.wait([
      fetch("project/getproject"),
      fetch("client/getclient"),
      fetch("subcompany/getsubcompany"),
      fetch("user/team-members"),
    ]);

    setState(() {
      projects = results[0];
      clients = results[1];
      subCompanies = results[2];
      teamMembers = results[3];
    });
  }

  Future<void> saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));

    final Map<String, dynamic> body = {
      'title': _title.text.trim(),
      'description': _description.text.trim(),
      'status': _status,
      'priority': _priority,
      'project': _projectId,
      'client': _clientId,
      'subCompany': _subCompanyId,
      'assignedTo': _assignedTo,
      'deadline': _deadline?.toIso8601String(),
    };

    try {
      final url = widget.task == null
          ? Uri.parse("${ApiConfig.baseUrl}/task/addtask")
          : Uri.parse("${ApiConfig.baseUrl}/task/${widget.task['_id']}");

      final res = widget.task == null
          ? await http.post(
              url,
              headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer $token",
              },
              body: jsonEncode(body),
            )
          : await http.put(
              url,
              headers: {
                "Content-Type": "application/json",
                "Authorization": "Bearer $token",
              },
              body: jsonEncode(body),
            );

      if (res.statusCode == 200 || res.statusCode == 201) {
        SnackbarHelper.show(
          context,
          title: 'Success',
          message: widget.task == null
              ? 'Task added successfully'
              : 'Task updated successfully',
          type: ContentType.success,
        );
        Navigator.pop(context, true);
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to save task',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Error: $e',
        type: ContentType.failure,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.task == null ? "Add Task" : "Edit Task"),
        backgroundColor: AppColors.primaryColor,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                TextFormField(
                  controller: _title,
                  decoration: const InputDecoration(
                    labelText: "Title",
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (v) => v == null || v.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: "Description",
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 15),

                // Project
                DropdownButtonFormField<String>(
                  value: _projectId,
                  decoration: const InputDecoration(
                    labelText: "Project",
                    prefixIcon: Icon(Icons.work_outline),
                  ),
                  items: projects
                      .map<DropdownMenuItem<String>>(
                        (e) => DropdownMenuItem<String>(
                          value: e['_id']?.toString(),
                          child: Text(e['title'] ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _projectId = v),
                ),

                const SizedBox(height: 15),

                // Client
                DropdownButtonFormField<String>(
                  value: _clientId,
                  decoration: const InputDecoration(
                    labelText: "Client",
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  items: clients
                      .map<DropdownMenuItem<String>>(
                        (e) => DropdownMenuItem<String>(
                          value: e['_id']?.toString(),
                          child: Text(e['name'] ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _clientId = v),
                ),

                const SizedBox(height: 15),

                // SubCompany
                DropdownButtonFormField<String>(
                  value: _subCompanyId,
                  decoration: const InputDecoration(
                    labelText: "Sub Company",
                    prefixIcon: Icon(Icons.business),
                  ),
                  items: subCompanies
                      .map<DropdownMenuItem<String>>(
                        (e) => DropdownMenuItem<String>(
                          value: e['_id']?.toString(),
                          child: Text(e['name'] ?? ''),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => _subCompanyId = v),
                ),

                const SizedBox(height: 15),

                // Assigned To
               // Assigned To
InputDecorator(
  decoration: const InputDecoration(
    labelText: 'Assign To',
    prefixIcon: Icon(Icons.group),
  ),
  child: Wrap(
    spacing: 8,
    runSpacing: 8,
    children: teamMembers.map<Widget>((e) {
      final id = e['_id'].toString();
      final name = e['fullName'] ?? 'Unknown';
      final selected = _assignedTo.contains(id);

      return FilterChip(
        label: Text(name),
        selected: selected,
        onSelected: (v) {
          setState(() {
            if (v) {
              _assignedTo.add(id);
            } else {
              _assignedTo.remove(id);
            }
          });
        },
        avatar: CircleAvatar(
          backgroundColor: selected ? Colors.white : Colors.brown.shade200,
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
              color: selected ? Colors.brown : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        selectedColor: AppColors.primaryColor,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black,
        ),
      );
    }).toList(),
  ),
),


                const SizedBox(height: 15),

                // Status
                DropdownButtonFormField<String>(
                  value: _status,
                  decoration: const InputDecoration(
                    labelText: "Status",
                    prefixIcon: Icon(Icons.flag),
                  ),
                  items: const [
                    DropdownMenuItem(value: "open", child: Text("Open")),
                    DropdownMenuItem(
                      value: "in_progress",
                      child: Text("In Progress"),
                    ),
                    DropdownMenuItem(value: "review", child: Text("Review")),
                    DropdownMenuItem(value: "done", child: Text("Done")),
                    DropdownMenuItem(value: "blocked", child: Text("Blocked")),
                  ],
                  onChanged: (val) => setState(() => _status = val!),
                ),
                const SizedBox(height: 15),

                // Priority
                DropdownButtonFormField<String>(
                  value: _priority,
                  decoration: const InputDecoration(
                    labelText: "Priority",
                    prefixIcon: Icon(Icons.low_priority),
                  ),
                  items: const [
                    DropdownMenuItem(value: "low", child: Text("Low")),
                    DropdownMenuItem(value: "medium", child: Text("Medium")),
                    DropdownMenuItem(value: "high", child: Text("High")),
                  ],
                  onChanged: (val) => setState(() => _priority = val!),
                ),
                const SizedBox(height: 15),

                // Deadline Picker
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month),
                  title: Text(
                    _deadline == null
                        ? "Select Deadline"
                        : _deadline!.toLocal().toString().split(' ')[0],
                  ),
                  trailing: const Icon(Icons.edit_calendar),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _deadline ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => _deadline = picked);
                  },
                ),

                const SizedBox(height: 25),
                ElevatedButton.icon(
                  onPressed: saveTask,
                  icon: const Icon(Icons.check, color: Colors.white),
                  label: Text(
                    widget.task == null ? "Create Task" : "Update Task",
                    style: const TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
