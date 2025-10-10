import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/profile_header.dart';
import '../widgets/background_container.dart';
import '../utils/custom_bottom_nav.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class SubCompanyInfoScreen extends StatefulWidget {
  final String subCompanyId;
  const SubCompanyInfoScreen({Key? key, required this.subCompanyId})
    : super(key: key);

  @override
  State<SubCompanyInfoScreen> createState() => _SubCompanyInfoScreenState();
}

class _SubCompanyInfoScreenState extends State<SubCompanyInfoScreen> {
  Map<String, dynamic>? subCompany;
  List<dynamic> clients = [];
  List<dynamic> teamMembers = [];
  List<dynamic> tasks = [];

  String? selectedClientId;
  Map<String, dynamic>? selectedClient;
  List<dynamic> teamUnderClient = [];

  bool isLoading = true;
  bool isLoadingTasks = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token == null) return;

    try {
      await Future.wait([
        _fetchSubCompany(widget.subCompanyId, token),
        _fetchClients(widget.subCompanyId, token),
        _fetchTeamMembers(token),
      ]);
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Failed to load data",
        type: ContentType.failure,
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchSubCompany(String id, String token) async {
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany/$id"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => subCompany = data['data']);
    }
  }

  Future<void> _fetchClients(String id, String token) async {
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/client/getclient?subCompany=$id"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => clients = List.from(data['data']));
    }
  }

  Future<void> _fetchTeamMembers(String token) async {
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => teamMembers = List.from(data['teamMembers']));
    }
  }

  Future<void> _fetchTasksForClient(String clientId) async {
    setState(() {
      isLoadingTasks = true;
      tasks.clear();
    });
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/task/gettask?client=$clientId"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => tasks = List.from(data['data']));
    }
    setState(() => isLoadingTasks = false);
  }

  void _onSelectClient(Map<String, dynamic> client) {
    selectedClientId = client['_id'];
    selectedClient = client;

    teamUnderClient = teamMembers.where((member) {
      final assignedClient = member['client'];
      if (assignedClient is Map)
        return assignedClient['_id'] == selectedClientId;
      if (assignedClient is String) return assignedClient == selectedClientId;
      return false;
    }).toList();

    _fetchTasksForClient(selectedClientId!);
  }

  Color _getStatusColor(String status) {
    final s = status.toLowerCase();
    if (s.contains('done') || s.contains('completed')) return Colors.green;
    if (s.contains('progress')) return Colors.blue;
    if (s.contains('hold')) return Colors.orange;
    return Colors.grey;
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
                    /// 🏢 Sub Company Header
                    _buildCompanyHeader(),

                    const SizedBox(height: 12),

                    /// 🧾 Client List
                    if (clients.isNotEmpty) _buildClientDropdown(),

                    const SizedBox(height: 12),

                    /// 👥 Team Members under selected client
                    if (selectedClient != null) _buildTeamMemberList(),

                    const SizedBox(height: 12),

                    /// 📊 Tasks / Work Status
                    if (selectedClient != null) _buildTaskList(),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: 0,
        onTap: (index) {},
      ),
    );
  }

  Widget _buildCompanyHeader() {
    if (subCompany == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundImage: subCompany!['logoUrl'] != null
                ? NetworkImage(subCompany!['logoUrl'])
                : null,
            backgroundColor: Colors.brown[100],
            child: subCompany!['logoUrl'] == null
                ? Text(
                    subCompany!['name']?.substring(0, 1).toUpperCase() ?? '',
                    style: const TextStyle(
                      color: Colors.brown,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subCompany!['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                  ),
                ),
                Text(
                  subCompany!['description'] ?? '',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonFormField<String>(
        value: selectedClientId,
        decoration: InputDecoration(
          labelText: 'Select Client',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: clients
            .map(
              (client) => DropdownMenuItem<String>(
                value: client['_id']?.toString(), // 👈 convert to String
                child: Text(client['name'] ?? ''),
              ),
            )
            .toList(),
        onChanged: (String? id) {
          // 👈 explicit type
          if (id == null) return;
          final c = clients.firstWhere((e) => e['_id'].toString() == id);
          _onSelectClient(c);
        },
      ),
    );
  }

  Widget _buildTeamMemberList() {
    if (teamUnderClient.isEmpty) {
      return const Text(
        "No team members assigned.",
        style: TextStyle(color: Colors.grey),
      );
    }
    return SizedBox(
      height: 90,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: teamUnderClient.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final member = teamUnderClient[i];
          return Column(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.brown[200],
                backgroundImage: member['avatarUrl'] != null
                    ? NetworkImage(
                        "${ApiConfig.imageBaseUrl}${member['avatarUrl']}",
                      )
                    : null,
                child: member['avatarUrl'] == null
                    ? Text(
                        member['fullName']?.substring(0, 1).toUpperCase() ?? '',
                        style: const TextStyle(color: Colors.white),
                      )
                    : null,
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 80,
                child: Text(
                  member['fullName'] ?? '',
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTaskList() {
    if (isLoadingTasks) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.brown),
      );
    }
    if (tasks.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          "No tasks found for this client.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Work Status",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.brown,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 10),
            ...tasks.map((task) {
              final title = task['title'] ?? '';
              final assignee = (task['assignee'] is Map)
                  ? task['assignee']['fullName'] ?? ''
                  : task['assignee']?.toString() ?? '';
              final status = task['status'] ?? 'Pending';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(title, style: const TextStyle(fontSize: 14)),
                    ),
                    Text(
                      assignee,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.brown,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _getStatusColor(status),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }
}
