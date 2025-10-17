import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';
import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import '../utils/snackbar_helper.dart';
import 'package:rudhram_frontend/screens/update_lead_screen.dart';
import 'package:rudhram_frontend/screens/update_status_screen.dart';

import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class LeadListScreen extends StatefulWidget {
  const LeadListScreen({Key? key}) : super(key: key);

  @override
  State<LeadListScreen> createState() => _LeadListScreenState();
}

class _LeadListScreenState extends State<LeadListScreen> {
  bool isLoading = true;
  List<dynamic> leads = [];
  List<dynamic> filteredLeads = [];
  int currentIndex = 1;
  Map<String, dynamic>? userData;

  String searchQuery = "";
  String selectedStatus = "All";

  final Map<String, String?> statusSelections = {};
  final List<String> statusFilters = [
    "All",
    "new",
    "contacted",
    "qualified",
    "converted",
    "lost",
  ];
  final List<String> editableStatuses = [
    "new",
    "contacted",
    "qualified",
    "lost",
  ];

  @override
  void initState() {
    super.initState();
    fetchLeads();
    _loadUserData();
  }

  bool get _isAdmin {
    final role = userData?['role']?.toString().toLowerCase();
    return role == 'admin' || role == 'super_admin';
  }

  Color get _primary => Theme.of(context).colorScheme.primary;

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (_) {
      return '—';
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) await fetchUser(token);
  }

  Future<void> fetchUser(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/me"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) setState(() => userData = data['user']);
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "User load error: $e",
        type: ContentType.failure,
      );
    }
  }

  Future<void> fetchLeads() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/lead/getlead'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = List<dynamic>.from(data['data'] ?? []);
        setState(() {
          leads = list;
          filteredLeads = list;
          isLoading = false;
          statusSelections.clear();
          for (final lead in list) {
            final id = lead['_id']?.toString() ?? '';
            final st = lead['status']?.toString();
            statusSelections[id] = editableStatuses.contains(st) ? st : null;
          }
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> deleteLead(String id) async {
    try {
      final response = await http.delete(
        Uri.parse('${ApiConfig.baseUrl}/lead/$id'),
      );
      if (response.statusCode == 200) {
        setState(() {
          leads.removeWhere((lead) => lead['_id'] == id);
          filteredLeads.removeWhere((lead) => lead['_id'] == id);
          statusSelections.remove(id);
        });
        SnackbarHelper.show(
          context,
          title: "Success",
          message: "Lead deleted successfully",
          type: ContentType.success,
        );
      } else {
        SnackbarHelper.show(
          context,
          title: "Error",
          message: "Failed to delete lead",
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: e.toString(),
        type: ContentType.failure,
      );
    }
  }

  Future<void> convertToClient(String leadId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/lead/convert/$leadId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        SnackbarHelper.show(
          context,
          title: "Success",
          message: "Lead converted to client successfully",
          type: ContentType.success,
        );
        await fetchLeads();
      } else {
        final data = jsonDecode(res.body);
        SnackbarHelper.show(
          context,
          title: "Failed",
          message: data['message'] ?? "Conversion failed",
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: e.toString(),
        type: ContentType.failure,
      );
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Cannot make call",
        type: ContentType.failure,
      );
    }
  }

  Future<void> updateLeadStatus(String id, String status) async {
    try {
      final res = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/lead/$id/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': status}),
      );

      if (res.statusCode == 200) {
        SnackbarHelper.show(
          context,
          title: "Updated",
          message: "Lead status changed to $status",
          type: ContentType.success,
        );
        await fetchLeads();
      } else {
        SnackbarHelper.show(
          context,
          title: "Failed",
          message: "Failed to update status",
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: e.toString(),
        type: ContentType.failure,
      );
    }
  }

  void showLeadDetails(BuildContext context, dynamic lead) {
    final String status = (lead['status'] ?? 'new').toString();
    final String token = (lead['token'] ?? '').toString();
    final String phone = (lead['phone'] ?? '').toString();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag handle + Close
                  Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Container(
                            width: 50,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Title + Status (overflow-safe)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          lead['name'] ?? '',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: buildStatusChip(status),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Token badge
                  if (token.isNotEmpty)
                    Row(
                      children: [
                        const Icon(
                          Icons.confirmation_number_outlined,
                          size: 18,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.teal.withOpacity(0.3),
                            ),
                          ),
                          child: Text(
                            token,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),

                  const SizedBox(height: 12),

                  // 📞 Phone Row with Call
                  Row(
                    children: [
                      const Icon(Icons.phone, size: 18, color: Colors.blueGrey),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          phone,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      if (phone.isNotEmpty)
                        IconButton(
                          tooltip: "Call",
                          icon: const Icon(Icons.call, color: Colors.green),
                          onPressed: () => _makePhoneCall(phone),
                        ),
                    ],
                  ),
                  _infoRow(Icons.email_outlined, lead['email']),
                  _infoRow(Icons.business, lead['businessName']),
                  _infoRow(
                    Icons.category,
                    "Category: ${lead['businessCategory'] ?? '-'}",
                  ),
                  _infoRow(Icons.web, "Source: ${lead['source'] ?? '-'}"),
                  const Divider(),

                  // 📅 Important Dates
                  _infoRow(
                    Icons.cake,
                    "Birth Date: ${_formatDate(lead['birthDate'])}",
                  ),
                  _infoRow(
                    Icons.favorite,
                    "Anniversary: ${_formatDate(lead['anniversaryDate'])}",
                  ),
                  _infoRow(
                    Icons.apartment,
                    "Company Establish: ${_formatDate(lead['companyEstablishDate'])}",
                  ),
                  const Divider(),

                  // 🏢 Sub Companies
                  if (lead['subCompanyIds'] != null &&
                      (lead['subCompanyIds'] as List).isNotEmpty) ...[
                    const Text(
                      "Sub Companies:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: (lead['subCompanyIds'] as List).map((sub) {
                        final name = sub is Map
                            ? sub['name'] ?? sub['_id']
                            : sub.toString();
                        return Chip(label: Text(name));
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 🧰 Chosen Services
                  if (lead['chosenServices'] != null &&
                      (lead['chosenServices'] as List).isNotEmpty) ...[
                    const Text(
                      "Chosen Services:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      children: (lead['chosenServices'] as List).map((service) {
                        final text = service is Map
                            ? service['title'] ?? service.toString()
                            : service.toString();
                        return Chip(
                          label: Text(text),
                          backgroundColor: Colors.grey[200],
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 8),
                  ],

                  // 📝 Logs
                  if (lead['logs'] != null &&
                      (lead['logs'] as List).isNotEmpty) ...[
                    const Divider(),
                    const Text(
                      "Activity Log:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      children: (lead['logs'] as List).map((log) {
                        final String action = log['action'] ?? '-';
                        final String message = log['message'] ?? '-';
                        final dynamic user = log['performedBy'];
                        final String performedBy = (user is Map)
                            ? (user['fullName'] ?? user['_id'] ?? 'System')
                            : (user?.toString() ?? 'System');
                        final String time = _formatDateTime(log['timestamp']);
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Action: $action",
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                "By: $performedBy",
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                              Text(
                                "On: $time",
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String? text) {
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (e) {
      return '—';
    }
  }

  filterLeads() {
    final q = searchQuery.toLowerCase();
    final temp = leads.where((lead) {
      final matchSearch =
          (lead['name'] ?? '').toString().toLowerCase().contains(q) ||
          (lead['email'] ?? '').toString().toLowerCase().contains(q) ||
          (lead['phone'] ?? '').toString().toLowerCase().contains(q) ||
          (lead['businessName'] ?? '').toString().toLowerCase().contains(q) ||
          (lead['token'] ?? '').toString().toLowerCase().contains(q);
      final matchStatus =
          selectedStatus == "All" || lead['status'] == selectedStatus;
      return matchSearch && matchStatus;
    }).toList();
    setState(() => filteredLeads = temp);
  }

  Widget buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'converted':
        color = Colors.green;
        break;
      case 'new':
        color = Colors.blue;
        break;
      case 'contacted':
        color = Colors.orange;
        break;
      case 'qualified':
        color = Colors.purple;
        break;
      case 'lost':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }
    return Chip(
      label: Text(
        status.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: color,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget tokenBadge(String? token) {
    if (token == null || token.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.teal.withOpacity(0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.teal.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.confirmation_number_outlined, size: 14),
          const SizedBox(width: 4),
          Text(
            token,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget shimmerLoader() {
    return ListView.builder(
      itemCount: 4,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ListTile(
              leading: Container(width: 50, height: 50, color: Colors.white),
              title: Container(height: 15, color: Colors.white),
              subtitle: Container(height: 10, color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              ProfileHeader(
                avatarUrl: userData?['avatarUrl'],
                fullName: userData?['fullName'],
                role: userData?['role'] ?? "Super Admin",
                showBackButton: true,
                onBack: () => Navigator.pop(context),
              ),
              // 🔍 Search + Filter
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) {
                          setState(() => searchQuery = val);
                          filterLeads();
                        },
                        decoration: InputDecoration(
                          hintText:
                              "Search leads (name, phone, email, token)...",
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: selectedStatus,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.filter_list),
                      onChanged: (value) {
                        setState(() => selectedStatus = value!);
                        filterLeads();
                      },
                      items: statusFilters.map((String status) {
                        return DropdownMenuItem<String>(
                          value: status,
                          child: Text(status.toUpperCase()),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isLoading
                    ? shimmerLoader()
                    : filteredLeads.isEmpty
                    ? const Center(child: Text("No leads found"))
                    : RefreshIndicator(
                        onRefresh: fetchLeads,
                        child: ListView.builder(
                          itemCount: filteredLeads.length,
                          itemBuilder: (context, index) {
                            final lead = filteredLeads[index];
                            final leadId = lead['_id'].toString();
                            final status = (lead['status'] ?? 'new').toString();
                            final token = (lead['token'] ?? '').toString();
                            final phone = (lead['phone'] ?? '').toString();

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              elevation: 2,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // 👤 Top Row: Name + Status
                                    Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.person,
                                                size: 22,
                                                color: Colors.blueAccent,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  lead['name'] ?? '',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  maxLines: 1,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: buildStatusChip(status),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),

                                    // 🪪 Token row (if present)
                                    if (token.isNotEmpty) ...[
                                      Row(children: [tokenBadge(token)]),
                                      const SizedBox(height: 6),
                                    ],

                                    // 📞 Phone row with call option
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.phone,
                                          size: 18,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(phone)),
                                        if (phone.isNotEmpty)
                                          IconButton(
                                            tooltip: "Call",
                                            icon: const Icon(
                                              Icons.call,
                                              color: Colors.green,
                                            ),
                                            onPressed: () =>
                                                _makePhoneCall(phone),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),

                                    // ✉️ Email
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.email_outlined,
                                          size: 18,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            lead['email'] ?? '',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),

                                    // 🏢 Business name
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.business,
                                          size: 18,
                                          color: Colors.purple,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            lead['businessName'] ?? '',
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const Divider(),

                                    // ℹ️ Action buttons
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          tooltip: 'Details',
                                          icon: const Icon(
                                            Icons.info_outline,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () =>
                                              showLeadDetails(context, lead),
                                        ),
                                        IconButton(
                                          tooltip: 'Delete',
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                          ),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) {
                                                return AlertDialog(
                                                  title: const Text(
                                                    "Delete Lead",
                                                  ),
                                                  content: const Text(
                                                    "Are you sure you want to delete this lead?",
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            context,
                                                            false,
                                                          ),
                                                      child: const Text(
                                                        "Cancel",
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                            context,
                                                            true,
                                                          ),
                                                      child: const Text(
                                                        "Delete",
                                                        style: TextStyle(
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                            if (confirm == true) {
                                              deleteLead(leadId);
                                            }
                                          },
                                        ),
                                      ],
                                    ),

                                    // ✏️ Update Lead & Status (only if not converted)
                                    if (status != 'converted') ...[
                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  UpdateLeadScreen(lead: lead),
                                            ),
                                          );
                                          if (result == true) fetchLeads();
                                        },
                                        icon: const Icon(Icons.edit),
                                        label: const Text("Update Lead"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: _primary,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(
                                            double.infinity,
                                            40,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),

                                      ElevatedButton.icon(
                                        onPressed: () async {
                                          final result = await Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  UpdateStatusScreen(
                                                    leadId: leadId,
                                                    leadName:
                                                        lead['name'] ?? '',
                                                    currentStatus: status,
                                                  ),
                                            ),
                                          );
                                          if (result == true) fetchLeads();
                                        },
                                        icon: const Icon(Icons.sync_alt),
                                        label: const Text("Update Status"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(
                                            double.infinity,
                                            40,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                    ],

                                    // ✅ Convert to Client
                                    if (status != 'converted')
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            convertToClient(leadId),
                                        icon: const Icon(
                                          Icons.person_add_alt_1,
                                        ),
                                        label: const Text("Convert to Client"),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                          foregroundColor: Colors.white,
                                          minimumSize: const Size(
                                            double.infinity,
                                            40,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.only(bottom: 6), // optional extra space
        child: CustomBottomNavBar(
          currentIndex: currentIndex,
          onTap: (i) => setState(() => currentIndex = i),
          userRole: userData?['role'] ?? '',
        ),
        
      ),
    );
  }
}
