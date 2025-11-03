import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import '../utils/custom_bottom_nav.dart';
import '../widgets/profile_header.dart';
import '../utils/constants.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class AddAddOnServiceScreen extends StatefulWidget {
  const AddAddOnServiceScreen({Key? key}) : super(key: key);

  @override
  State<AddAddOnServiceScreen> createState() => _AddAddOnServiceScreenState();
}

class _AddAddOnServiceScreenState extends State<AddAddOnServiceScreen> {
  final _formKey = GlobalKey<FormState>();

  // Navbar index (match Drive behavior)
  int _selectedIndex = 2;

  // Authenticated user (for ProfileHeader)
  Map<String, dynamic>? _me;

  // Sub-companies + selection
  List<dynamic> _subCompanies = [];
  String? _subCompanyId;

  // Form fields
  final _titleCtrl = TextEditingController();
  final _offerCtrl = TextEditingController();
  final List<String> _offerings = [];
  DateTime? _start;
  DateTime? _end;

  bool _saving = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _offerCtrl.dispose();
    super.dispose();
  }

  // ===== Utilities (match Drive screen patterns) =====

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
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

  void _toast(String msg,{bool success=false}) {
  SnackbarHelper.show(
    context,
    title: success ? "Success" : "Error",
    message: msg,
    type: success ? ContentType.success : ContentType.failure,
  );
}


  // ===== Data bootstrap =====

  Future<void> _bootstrap() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));

      // Load user (for header)
      if (token.isNotEmpty) {
        final meRes = await http.get(
          Uri.parse("${ApiConfig.baseUrl}/user/me"),
          headers: {"Authorization": "Bearer $token"},
        );
        if (meRes.statusCode == 200) {
          final u = Map<String, dynamic>.from(
            jsonDecode(meRes.body)['user'] ?? {},
          );
          if (u['avatarUrl'] != null && u['avatarUrl'].toString().isNotEmpty) {
            u['avatarUrl'] = _absUrl(u['avatarUrl']);
          }
          _me = u;
        }
      }

      // Load sub-companies (for dropdown)
      final scRes = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"),
        headers: {if (token.isNotEmpty) "Authorization": "Bearer $token"},
      );
      if (scRes.statusCode == 200) {
        final body = jsonDecode(scRes.body);
        final data = List<dynamic>.from(body['data'] ?? []);
        _subCompanies = data;
        if (_subCompanies.isNotEmpty) {
          _subCompanyId =
              (_subCompanies.first['_id'] ?? _subCompanies.first['id'])
                  .toString();
        }
      } else {
        _toast("Failed to load sub-companies");
      }
    } catch (e) {
      _toast("Init error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ===== UI helpers =====

  InputDecoration _inp(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Colors.brown),
    ),
  );

  void _addOffering() {
    final t = _offerCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _offerings.add(t);
      _offerCtrl.clear();
    });
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: _start ?? now,
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _pickEnd() async {
    final base = _start ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      firstDate: base,
      lastDate: DateTime(base.year + 5),
      initialDate: _end ?? base,
    );
    if (d != null) setState(() => _end = d);
  }

  // ===== Submit =====

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subCompanyId == null) return _toast("Select sub-company");
    if (_start == null || _end == null)
      return _toast("Select start & end dates");

    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));

      final body = {
        "title": _titleCtrl.text.trim(),
        "offerings": _offerings,
        "startDate": _start!.toUtc().toIso8601String(),
        "endDate": _end!.toUtc().toIso8601String(),
      };

      final res = await http.post(
        Uri.parse(
          "${ApiConfig.baseUrl}/subcompany/${_subCompanyId}/addon-service",
        ),
        headers: {
          "Content-Type": "application/json",
          if (token.isNotEmpty) "Authorization": "Bearer $token",
        },
        body: jsonEncode(body),
      );
      if (res.statusCode == 201 || res.statusCode == 200) {
       _toast("Add-on service created", success: true);
        if (!mounted) return;
      } else {
        final b = jsonDecode(res.body);
        _toast(b['message']?.toString() ?? "Failed to create add-on");
      }
    } catch (e) {
      _toast("Save error: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
  // ===== Build =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      resizeToAvoidBottomInset: false,
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              // 🔹 ProfileHeader identical to Drive screen behavior
              ProfileHeader(
                avatarUrl: _me?['avatarUrl'],
                fullName: _me?['fullName'],
                role: formatUserRole(_me?['role']),
                showBackButton: true,
                onBack: () => Navigator.pop(context),
              ),

              // Title row / context
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Row(
                  children: const [
                    Icon(Icons.extension_rounded, color: Colors.brown),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Create Add-On Service",
                        style: TextStyle(
                          fontSize: 20,
                          color: Colors.brown,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.brown),
                      )
                    : SingleChildScrollView(
                       keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Sub-company dropdown (card style)
                              const Text(
                                "Sub-Company",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.brown,
                                ),
                              ),
                              const SizedBox(height: 8),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 6,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      isExpanded: true,
                                      value: _subCompanyId,
                                      items: _subCompanies
                                          .map<DropdownMenuItem<String>>((sc) {
                                            final id = (sc['_id'] ?? sc['id'])
                                                .toString();
                                            final name = (sc['name'] ?? '')
                                                .toString();
                                            return DropdownMenuItem(
                                              value: id,
                                              child: Text(name),
                                            );
                                          })
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _subCompanyId = v),
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 16),

                              // Title
                              const Text(
                                "Add-On Title",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.brown,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: _titleCtrl,
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? "Title required"
                                    : null,
                                decoration: _inp("e.g. 5-Day Social Boost"),
                              ),

                              const SizedBox(height: 16),

                              // Offerings
                              const Text(
                                "Offerings",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.brown,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _offerCtrl,
                                      decoration: _inp("e.g. 10 reels"),
                                      onSubmitted: (_) => _addOffering(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _addOffering,
                                    icon: const Icon(Icons.add),
                                    label: const Text("Add"),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryColor,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (_offerings.isEmpty)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: Colors.grey.shade300,
                                    ),
                                  ),
                                  child: const Text(
                                    "No offerings added yet.",
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _offerings
                                      .map(
                                        (o) => Chip(
                                          label: Text(o),
                                          backgroundColor: Colors.brown
                                              .withOpacity(0.08),
                                          side: BorderSide(
                                            color: Colors.brown.withOpacity(
                                              0.15,
                                            ),
                                          ),
                                          onDeleted: () => setState(
                                            () => _offerings.remove(o),
                                          ),
                                        ),
                                      )
                                      .toList(),
                                ),

                              const SizedBox(height: 16),

                              // Duration
                              const Text(
                                "Duration",
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.brown,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickStart,
                                      icon: const Icon(Icons.calendar_today),
                                      label: Text(
                                        _start == null
                                            ? "Start date"
                                            : _start!
                                                  .toLocal()
                                                  .toString()
                                                  .split(' ')
                                                  .first,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        side: BorderSide(
                                          color: Colors.brown.withOpacity(0.25),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _pickEnd,
                                      icon: const Icon(Icons.event),
                                      label: Text(
                                        _end == null
                                            ? "End date"
                                            : _end!
                                                  .toLocal()
                                                  .toString()
                                                  .split(' ')
                                                  .first,
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        side: BorderSide(
                                          color: Colors.brown.withOpacity(0.25),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Save
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _saving ? null : _save,
                                  icon: _saving
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(Icons.save_outlined),
                                  label: Text(
                                    _saving ? "Saving..." : "Create Add-On",
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),

      // Bottom nav identical pattern to Drive
      bottomNavigationBar: SafeArea(
        child: CustomBottomNavBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          userRole: _me?['role'] ?? '',
        ),
      ),
    );
  }
}
