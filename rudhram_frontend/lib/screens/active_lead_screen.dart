import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';
import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class ActiveLeadScreen extends StatefulWidget {
  const ActiveLeadScreen({Key? key}) : super(key: key);

  @override
  State<ActiveLeadScreen> createState() => _ActiveLeadScreenState();
}

class _ActiveLeadScreenState extends State<ActiveLeadScreen> {
  bool isLoading = true;
  List<dynamic> leads = [];
  List<dynamic> filteredLeads = [];
  int currentIndex = 1;
  Map<String, dynamic>? userData;

  String searchQuery = "";
  String selectedStatus = "All";

  // Only active status
  final List<String> activeStatuses = [
    "converted",
  ];

  final List<String> statusFilters = [
    "All",
    "converted",
  ];

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

  Future<void> fetchLeads() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/lead/getlead'),
      );
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final list = List<dynamic>.from(data['data'] ?? []);

        // Only active status leads (converted)
        final activeOnly = list.where((lead) {
          final status = (lead['status'] ?? '').toString();
          return activeStatuses.contains(status);
        }).toList();

        setState(() {
          leads = activeOnly;
          filteredLeads = activeOnly;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
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

  Widget buildStatusChip(String status) {
    Color color;
    switch (status) {
      case 'converted':
        color = Colors.green;
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

  void showLeadDetails(BuildContext context, dynamic lead) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 50,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Colors.grey[400],
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

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
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    buildStatusChip((lead['status'] ?? 'converted').toString()),
                  ],
                ),

                const SizedBox(height: 8),
                Text("Phone: ${lead['phone'] ?? ''}"),
                Text("Email: ${lead['email'] ?? ''}"),
                Text("Business: ${lead['businessName'] ?? ''}"),
                Text("Category: ${lead['businessCategory'] ?? ''}"),
                const Divider(),
                if (lead['subCompanyIds'] != null &&
                    (lead['subCompanyIds'] as List).isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Sub Companies:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Wrap(
                        spacing: 6,
                        children: (lead['subCompanyIds'] as List).map((sub) {
                          return Chip(
                            label: Text(sub['name']),
                            backgroundColor: Colors.indigo,
                            labelStyle: const TextStyle(color: Colors.white),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                if (lead['chosenServices'] != null &&
                    (lead['chosenServices'] as List).isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Services:",
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ...((lead['chosenServices'] as List).map((service) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                service['title'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Wrap(
                                spacing: 4,
                                children:
                                    (service['offerings'] as List).map((off) {
                                  return Chip(
                                    label: Text(off),
                                    backgroundColor: Colors.grey[200],
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                      }).toList()),
                    ],
                  ),
              ],
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

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) {
                          setState(() => searchQuery = val);
                          filterLeads();
                        },
                        decoration: InputDecoration(
                          hintText: "Search active leads...",
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
                        ? const Center(child: Text("No active leads found"))
                        : RefreshIndicator(
                            onRefresh: fetchLeads,
                            child: ListView.builder(
                              itemCount: filteredLeads.length,
                              itemBuilder: (context, index) {
                                final lead = filteredLeads[index];
                                final status =
                                    (lead['status'] ?? 'converted').toString();

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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                        fontWeight:
                                                            FontWeight.bold,
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
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.phone,
                                              size: 18,
                                              color: Colors.green,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(lead['phone'] ?? ''),
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
                                            Text(lead['businessName'] ?? ''),
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
                                              onPressed: () => showLeadDetails(
                                                  context, lead),
                                            ),
                                          ],
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
}
