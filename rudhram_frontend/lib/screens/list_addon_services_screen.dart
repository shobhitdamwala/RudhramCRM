import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import '../utils/custom_bottom_nav.dart';
import '../widgets/profile_header.dart';
import '../utils/constants.dart';
import 'add_addon_service_screen.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import '../utils/snackbar_helper.dart';

class ListAddOnServicesScreen extends StatefulWidget {
  const ListAddOnServicesScreen({Key? key}) : super(key: key);

  @override
  State<ListAddOnServicesScreen> createState() =>
      _ListAddOnServicesScreenState();
}

class _ListAddOnServicesScreenState extends State<ListAddOnServicesScreen> {
  List<dynamic> _subCompanies = [];
  String? _subCompanyId;
  List<dynamic> _items = [];
  bool _loading = true;
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadMe();
    await _fetchSubCompanies();
    await _fetchItems();
  }

  Future<void> _loadMe() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/me"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final u = Map<String, dynamic>.from(jsonDecode(res.body)['user'] ?? {});

        // Avatar fix (VERY IMPORTANT)
        if (u['avatarUrl'] != null &&
            u['avatarUrl'].toString().startsWith('/')) {
          u['avatarUrl'] = "${ApiConfig.imageBaseUrl}${u['avatarUrl']}";
        }

        setState(() => _me = u);
      }
    } catch (e) {
      // optional error toast if you want
      // print(e);
    }
  }

  Future<void> _fetchSubCompanies() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"),
      headers: {if (token != null) "Authorization": "Bearer $token"},
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final data = List<dynamic>.from(body['data'] ?? []);
      setState(() {
        _subCompanies = data;
        if (_subCompanyId == null && data.isNotEmpty) {
          _subCompanyId = (data.first['_id'] ?? data.first['id']).toString();
        }
      });
    }
  }

  Future<void> _fetchItems() async {
    if (_subCompanyId == null) {
      setState(() {
        _items = [];
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final res = await http.get(
        Uri.parse(
          "${ApiConfig.baseUrl}/subcompany/${_subCompanyId}/addon-services",
        ),
        headers: {if (token != null) "Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        setState(() {
          _items = List<dynamic>.from(body['data'] ?? []);
          _loading = false;
        });
      } else {
        setState(() {
          _items = [];
          _loading = false;
        });
      }
    } catch (_) {
      setState(() {
        _items = [];
        _loading = false;
      });
    }
  }

  void _toast(String msg, {bool success = false}) {
    SnackbarHelper.show(
      context,
      title: success ? "Success" : "Error",
      message: msg,
      type: success ? ContentType.success : ContentType.failure,
    );
  }

  Future<void> _delete(String addonId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete add-on?"),
        content: const Text("This cannot be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final res = await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/subcompany/addon-services/$addonId"),
        headers: {if (token != null) "Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        _toast("Deleted");
        _fetchItems();
      } else {
        final b = jsonDecode(res.body);
        _toast(b['message']?.toString() ?? "Delete failed");
      }
    } catch (e) {
      _toast("Error: $e");
    }
  }

  String _fmt(String? iso) {
    if (iso == null || iso.isEmpty) return "-";
    try {
      return DateTime.parse(iso).toLocal().toString().split(' ').first;
    } catch (_) {
      return "-";
    }
  }

  Color _status(String s) {
    switch (s) {
      case "active":
        return Colors.green;
      case "scheduled":
        return Colors.blue;
      case "expired":
        return Colors.grey;
      default:
        return Colors.grey;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              ProfileHeader(
                avatarUrl: _me?['avatarUrl'],
                fullName: _me?['fullName'],
                role: formatUserRole(_me?['role']),
                showBackButton: true,
                onBack: () => Navigator.pop(context),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _subCompanyId,
                        items: _subCompanies.map<DropdownMenuItem<String>>((
                          sc,
                        ) {
                          final id = (sc['_id'] ?? sc['id']).toString();
                          final name = (sc['name'] ?? '').toString();
                          return DropdownMenuItem(value: id, child: Text(name));
                        }).toList(),
                        onChanged: (v) async {
                          setState(() => _subCompanyId = v);
                          await _fetchItems();
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.brown),
                      )
                    : _items.isEmpty
                    ? const Center(child: Text("No add-on services"))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final it = _items[i] as Map<String, dynamic>;
                          final title = (it['title'] ?? '').toString();
                          final offerings = List<String>.from(
                            (it['offerings'] ?? []).map((e) => e.toString()),
                          );
                          final status = (it['status'] ?? '').toString();
                          final start = _fmt(it['startDate']?.toString());
                          final end = _fmt(it['endDate']?.toString());

                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16,
                                          color: Colors.brown,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _status(status).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(
                                          color: _status(status),
                                        ),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: _status(status),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: "Delete",
                                      onPressed: () =>
                                          _delete(it['_id'].toString()),
                                      icon: const Icon(
                                        Icons.delete_outline,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                                if (offerings.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: offerings
                                        .map(
                                          (o) => Chip(
                                            label: Text(o),
                                            backgroundColor: Colors.brown
                                                .withOpacity(0.08),
                                          ),
                                        )
                                        .toList(),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      size: 14,
                                      color: Colors.brown,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      "Start: $start   End: $end",
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final ok = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddAddOnServiceScreen(),
                        ),
                      );
                      if (ok == true) _fetchItems();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Add Add-On Service"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: CustomBottomNavBar(
          currentIndex: 6,
          onTap: (_) {},
          userRole: _me?['role'] ?? '',
        ),
      ),
    );
  }
}
