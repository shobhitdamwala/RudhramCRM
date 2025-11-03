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

class OnboardLeadScreen extends StatefulWidget {
  const OnboardLeadScreen({Key? key}) : super(key: key);

  @override
  State<OnboardLeadScreen> createState() => _OnboardLeadScreenState();
}

class _OnboardLeadScreenState extends State<OnboardLeadScreen> {
  bool isLoading = true;
  List<dynamic> leads = [];
  List<dynamic> filteredLeads = [];
  int currentIndex = 1;
  Map<String, dynamic>? userData;

  String searchQuery = "";
  String selectedStatus = "All";

  // Only onboard statuses
  final List<String> onboardStatuses = ["contacted", "qualified", "lost"];

  final List<String> statusFilters = ["All", "contacted", "qualified", "lost"];

  @override
  void initState() {
    super.initState();
    fetchLeads();
    _loadUserData();
  }

  Color get _primary => Theme.of(context).colorScheme.primary;

  String _absUrl(String? maybeRelative) {
    if (maybeRelative == null || maybeRelative.isEmpty) return '';
    if (maybeRelative.startsWith('http')) return maybeRelative;
    if (maybeRelative.startsWith('/uploads')) {
      return "${ApiConfig.imageBaseUrl}$maybeRelative";
    }
    return "${ApiConfig.baseUrl}$maybeRelative";
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
        final u = Map<String, dynamic>.from(data['user'] ?? {});
        if (u['avatarUrl'] != null &&
            u['avatarUrl'].toString().startsWith('/')) {
          u['avatarUrl'] = _absUrl(u['avatarUrl']);
        }
        if (mounted) setState(() => userData = u);
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

  Future<void> fetchLeads() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/lead/getlead'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = List<dynamic>.from(data['data'] ?? []);

        // Only onboard status leads (contacted/qualified/lost)
        final onboardOnly = list.where((lead) {
          final status = (lead['status'] ?? '').toString();
          return onboardStatuses.contains(status);
        }).toList();

        setState(() {
          leads = onboardOnly;
          filteredLeads = onboardOnly;
          isLoading = false;
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


  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '—';
    try {
      final date = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (_) {
      return '—';
    }

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

  void showLeadDetails(BuildContext context, dynamic lead) {
    // Defensive retrieval of fields that could be null / missing
    final String status = (lead['status'] ?? 'contacted').toString();
    final String token = (lead['token'] ?? '').toString();
    final String phone = (lead['phone'] ?? '').toString();

    // get subCompanyIds safely
    final dynamic rawSubCompanies = lead['subCompanyIds'];
    final List<dynamic> subCompanies = (rawSubCompanies is List)
        ? List<dynamic>.from(rawSubCompanies)
        : [];

    // get chosenServices safely
    final dynamic rawChosen = lead['chosenServices'];
    final List<dynamic> chosenServices = (rawChosen is List)
        ? List<dynamic>.from(rawChosen)
        : [];
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

                  // 🧰 Chosen Services with Selected Offerings
                  if (lead['chosenServices'] != null &&
                      (lead['chosenServices'] as List).isNotEmpty) ...[
                    const Text(
                      "Chosen Services:",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    ...(lead['chosenServices'] as List).map((service) {
                      final serviceTitle = service is Map
                          ? service['title'] ?? service.toString()
                          : service.toString();
                      final selectedOfferings = service is Map
                          ? (service['selectedOfferings'] as List?)?.map((offering) => offering.toString()).toList() ?? []
                          : [];
                      final subCompanyId = service is Map
                          ? service['subCompanyId']?.toString()
                          : null;

                      // Find sub-company name
                      String subCompanyName = '';
                      if (subCompanyId != null && lead['subCompanyIds'] != null) {
                        for (final sub in lead['subCompanyIds'] as List) {
                          if (sub is Map && sub['_id']?.toString() == subCompanyId) {
                            subCompanyName = sub['name']?.toString() ?? '';
                            break;
                          }
                        }
                      }

                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Service title and sub-company
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    serviceTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (subCompanyName.isNotEmpty)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      subCompanyName,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blue,
                                      ),
                                    ),
                                  ),
                              ],
                            ),

                            // Selected offerings
                            if (selectedOfferings.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              const Text(
                                "Selected Offerings:",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Wrap(
                                spacing: 4,
                                runSpacing: 2,
                                children: selectedOfferings.map((offering) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.green.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Text(
                                      offering,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.green,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
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

  Widget buildStatusChip(String status) {
    Color color;
    switch (status) {
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
                fullName: userData?['fullName'] ?? '',
                role: formatUserRole(userData?['role']),
                showBackButton: true,
                onBack: () => Navigator.pop(context),
                onNotification: () {
                  debugPrint("🔔 Notification tapped");
                },
              ),
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
                          hintText: "Search onboard leads...",
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 0,
                            horizontal: 16,
                          ),
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
                    ? const Center(child: Text("No onboard leads found"))
                    : RefreshIndicator(
                        onRefresh: fetchLeads,
                        child: ListView.builder(
                          itemCount: filteredLeads.length,
                          itemBuilder: (context, index) {
                            final lead = filteredLeads[index];
                            final leadId = lead['_id']?.toString() ?? '';
                            final status = (lead['status'] ?? 'contacted')
                                .toString();
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
                                    Row(
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
                                              Flexible(
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
                                        buildStatusChip(status),
                                      ],
                                    ),

                                    const SizedBox(height: 6),

                                    if (token.isNotEmpty) ...[
                                      Row(children: [tokenBadge(token)]),
                                      const SizedBox(height: 6),
                                    ],

                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.phone,
                                          size: 18,
                                          color: Colors.green,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(lead['phone'] ?? ''),
                                        ),
                                        if ((lead['phone'] ?? '')
                                            .toString()
                                            .isNotEmpty)
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
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.email_outlined,
                                          size: 18,
                                          color: Colors.orange,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(lead['email'] ?? ''),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
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
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Divider(),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.info_outline,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () =>
                                              showLeadDetails(context, lead),
                                        ),
                                        IconButton(
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
                                              await deleteLead(leadId);
                                            }
                                          },
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 6),

                                    // Three full-width action buttons
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
                                                  leadName: lead['name'] ?? '',
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
                                    ElevatedButton.icon(
                                      onPressed: () => convertToClient(leadId),
                                      icon: const Icon(Icons.person_add_alt_1),
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
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: currentIndex,
        onTap: (i) => setState(() => currentIndex = i),
        userRole: userData?['role'] ?? '',
      ),
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

  void filterLeads() {
    final q = searchQuery.toLowerCase();
    final temp = leads.where((lead) {
      final matchSearch =
          (lead['name'] ?? '').toString().toLowerCase().contains(q) ||
          (lead['email'] ?? '').toString().toLowerCase().contains(q) ||
          (lead['phone'] ?? '').toString().toLowerCase().contains(q) ||
          (lead['businessName'] ?? '').toString().toLowerCase().contains(q);

      final matchStatus =
          selectedStatus == "All" || lead['status'] == selectedStatus;
      return matchSearch && matchStatus;
    }).toList();

    setState(() => filteredLeads = temp);
  }
}
