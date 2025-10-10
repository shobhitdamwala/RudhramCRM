import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class AddEditTaskScreen extends StatefulWidget {
  final Map<String, dynamic>? task;
  const AddEditTaskScreen({Key? key, this.task}) : super(key: key);

  @override
  State<AddEditTaskScreen> createState() => _AddEditTaskScreenState();
}

class _AddEditTaskScreenState extends State<AddEditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();
  String? _selectedServiceId;
  List<dynamic> serviceOfferings = [];

  DateTime? _deadline;

  String? _selectedClientId;
  Map<String, dynamic>? _selectedClient;

  String? _selectedStatus;
  String? _selectedPriority;
  List<String> _selectedTeamMembers = [];

  List<dynamic> clients = [];
  List<dynamic> teamMembers = [];
  List<dynamic> clientServices = [];
  List<dynamic> clientSubCompanies = [];

  bool isLoading = false;
  bool isEditing = false;

  @override
  void initState() {
    super.initState();
    isEditing = widget.task != null;
    _fetchClients();
    _fetchTeamMembers();

    if (isEditing) {
      _titleCtrl.text = widget.task?['title'] ?? '';
      _descriptionCtrl.text = widget.task?['description'] ?? '';
      _selectedStatus = widget.task?['status'];
      _selectedPriority = widget.task?['priority'];
      _deadline = widget.task?['deadline'] != null
          ? DateTime.parse(widget.task!['deadline'])
          : null;

      if (widget.task?['client'] != null) {
        _selectedClientId = widget.task?['client']['_id'];
        _selectedClient = widget.task?['client'];
        _updateClientDependentFields();
      }

      if (widget.task?['assignedTo'] != null) {
        _selectedTeamMembers = List<String>.from(
          widget.task?['assignedTo'].map((m) => m['_id']),
        );
      }
    }
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
  }

  Future<void> _fetchClients() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/client/getclient"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => clients = data['data'] ?? []);
    }
  }

  Future<void> _fetchTeamMembers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => teamMembers = data['teamMembers'] ?? []);
    }
  }

  void _updateClientDependentFields() {
    if (_selectedClient == null) return;

    final meta = _selectedClient!['meta'] ?? {};
    clientServices = meta['chosenServices'] ?? [];
    clientSubCompanies = meta['subCompanyNames'] ?? [];

    // Reset service & offerings when client changes
    _selectedServiceId = null;
    serviceOfferings = [];
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));

    final body = {
      "title": _titleCtrl.text.trim(),
      "description": _descriptionCtrl.text.trim(),
      "client": _selectedClientId,
      "assignedTo": _selectedTeamMembers,
      "status": _selectedStatus,
      "priority": _selectedPriority,
      "deadline": _deadline?.toIso8601String(),
    };

    setState(() => isLoading = true);

    final url = isEditing
        ? Uri.parse("${ApiConfig.baseUrl}/task/${widget.task!['_id']}")
        : Uri.parse("${ApiConfig.baseUrl}/task/addtask");

    final res = await (isEditing
        ? http.put(
            url,
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
            },
            body: jsonEncode(body),
          )
        : http.post(
            url,
            headers: {
              "Authorization": "Bearer $token",
              "Content-Type": "application/json",
            },
            body: jsonEncode(body),
          ));

    setState(() => isLoading = false);

    if (res.statusCode == 200 || res.statusCode == 201) {
      if (!mounted) return;
      SnackbarHelper.show(
        context,
        title: 'Success',
        message: isEditing
            ? 'Task updated successfully'
            : 'Task created successfully',
        type: ContentType.success,
      );
      Navigator.pop(context, true);
    } else {
      final err = jsonDecode(res.body);
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: err['message'] ?? 'Failed to save task',
        type: ContentType.failure,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Edit Task" : "Add Task"),
        backgroundColor: AppColors.primaryColor,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    _buildTextField(_titleCtrl, "Title", Icons.title),
                    _buildTextField(
                      _descriptionCtrl,
                      "Description",
                      Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    // 👉 Select Client
                    DropdownButtonFormField<String>(
                      value: _selectedClientId,
                      decoration: _inputDecoration(
                        "Select Client",
                        Icons.person,
                      ),
                      items: clients
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c['_id'],
                              child: Text(c['name']),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedClientId = value;
                          _selectedClient = clients.firstWhere(
                            (c) => c['_id'] == value,
                          );
                          _updateClientDependentFields();
                        });
                      },
                      validator: (val) =>
                          val == null ? 'Please select a client' : null,
                    ),

                    if (clientSubCompanies.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Sub Companies",
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.brown,
                          ),
                        ),
                      ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.brown.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Sub Companies",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.brown,
                              ),
                            ),
                            const SizedBox(height: 8),
                            if (clientSubCompanies.isEmpty)
                              const Text(
                                "No sub companies linked",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ...clientSubCompanies.map(
                              (s) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.business,
                                      color: Colors.brown,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      s,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (clientServices.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _selectedServiceId,
                        isExpanded: true,
                        decoration: _inputDecoration(
                          "Choose Service",
                          Icons.design_services,
                        ),
                        items: clientServices.map((service) {
                          return DropdownMenuItem<String>(
                            value: service['_id'],

                            child: Text(
                              service['title'],
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedServiceId = value;
                            final selected = clientServices.firstWhere(
                              (s) => s['_id'] == value,
                            );
                            serviceOfferings = selected['offerings'] ?? [];
                          });
                        },
                        validator: (val) =>
                            val == null ? 'Please choose a service' : null,
                      ),

                      if (serviceOfferings.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            "Offerings",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.brown,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.brown.shade300),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Offerings",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.brown,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: serviceOfferings.map((o) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.brown.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: Colors.brown.shade200,
                                      ),
                                    ),
                                    child: Text(
                                      o,
                                      style: const TextStyle(
                                        color: Colors.brown,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],

                    const SizedBox(height: 16),
                    _buildMultiTeamAssign(),

                    const SizedBox(height: 16),
                    _buildStatusDropdown(),
                    const SizedBox(height: 16),
                    _buildPriorityDropdown(),
                    const SizedBox(height: 16),
                    _buildDeadlinePicker(),

                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      onPressed: _saveTask,
                      icon: const Icon(Icons.check, color: Colors.white),
                      label: Text(
                        isEditing ? "Update Task" : "Create Task",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: _inputDecoration(label, icon),
        validator: (val) =>
            val == null || val.trim().isEmpty ? '$label is required' : null,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.brown),
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primaryColor, width: 1.5),
      ),
    );
  }

  Widget _buildMultiTeamAssign() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Assign To",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.brown),
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.brown.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Assign To",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.brown,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: teamMembers.map((tm) {
                  final isSelected = _selectedTeamMembers.contains(tm['_id']);
                  return FilterChip(
                    label: Text(tm['fullName']),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedTeamMembers.add(tm['_id']);
                        } else {
                          _selectedTeamMembers.remove(tm['_id']);
                        }
                      });
                    },
                    selectedColor: AppColors.primaryColor.withOpacity(0.2),
                    checkmarkColor: AppColors.primaryColor,
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusDropdown() {
    final statuses = ['open', 'in_progress', 'review', 'done', 'blocked'];
    return DropdownButtonFormField<String>(
      value: _selectedStatus,
      decoration: _inputDecoration("Status", Icons.flag),
      items: statuses
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: (v) => setState(() => _selectedStatus = v),
      validator: (val) => val == null ? 'Please select status' : null,
    );
  }

  Widget _buildPriorityDropdown() {
    final priorities = ['low', 'medium', 'high'];
    return DropdownButtonFormField<String>(
      value: _selectedPriority,
      decoration: _inputDecoration("Priority", Icons.priority_high),
      items: priorities
          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
          .toList(),
      onChanged: (v) => setState(() => _selectedPriority = v),
      validator: (val) => val == null ? 'Please select priority' : null,
    );
  }

  Widget _buildDeadlinePicker() {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _deadline ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) setState(() => _deadline = picked);
      },
      child: InputDecorator(
        decoration: _inputDecoration("Deadline", Icons.calendar_today),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _deadline == null
                  ? "Select Date"
                  : _deadline!.toLocal().toString().split(' ')[0],
            ),
            const Icon(Icons.calendar_today, color: Colors.brown),
          ],
        ),
      ),
    );
  }
}
