import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import '../utils/custom_bottom_nav.dart';
import '../utils/constants.dart';
import '../widgets/profile_header.dart';

class AddServiceScreen extends StatefulWidget {
  const AddServiceScreen({Key? key}) : super(key: key);

  @override
  State<AddServiceScreen> createState() => _AddServiceScreenState();
}

class _AddServiceScreenState extends State<AddServiceScreen> {
  final _formKey = GlobalKey<FormState>();
  List<dynamic> _subCompanies = [];
  String? _subCompanyId;

  final _titleCtrl = TextEditingController();
  final _offeringCtrl = TextEditingController();
  final List<String> _offerings = [];

  bool _saving = false;
  Map<String, dynamic>? _me;

  @override
  void initState() {
    super.initState();
    _loadMe();
    _fetchSubCompanies();
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
        setState(() => _me = jsonDecode(res.body)['user']);
      }
    } catch (_) {}
  }

  Future<void> _fetchSubCompanies() async {
    try {
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
          if (data.isNotEmpty) {
            _subCompanyId = (data.first['_id'] ?? data.first['id']).toString();
          }
        });
      } else {
        _toast("Failed to load sub-companies");
      }
    } catch (e) {
      _toast("Error: $e");
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _addOffering() {
    final t = _offeringCtrl.text.trim();
    if (t.isEmpty) return;
    setState(() {
      _offerings.add(t);
      _offeringCtrl.clear();
    });
  }

  void _removeOffering(String s) {
    setState(() => _offerings.remove(s));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_subCompanyId == null) {
      _toast("Please select a sub-company");
      return;
    }
    setState(() => _saving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final body = {"title": _titleCtrl.text.trim(), "offerings": _offerings};

      // ⚠️ Adjust URL to your actual backend route for adding a core service
      final url = Uri.parse(
        "${ApiConfig.baseUrl}/subcompany/${_subCompanyId}/services/add",
      );

      final res = await http.post(
        url,
        headers: {
          "Content-Type": "application/json",
          if (token != null) "Authorization": "Bearer $token",
        },
        body: jsonEncode(body),
      );

      if (res.statusCode == 201 || res.statusCode == 200) {
        _toast("Service added");
        if (mounted) Navigator.pop(context, true);
      } else {
        final b = jsonDecode(res.body);
        _toast(b['message']?.toString() ?? "Failed to save service");
      }
    } catch (e) {
      _toast("Save error: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _offeringCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              ProfileHeader(
                avatarUrl: _me?['avatarUrl'],
                fullName: _me?['fullName'],
                role: _me?['role'] ?? '',
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12.0,
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
                                      final logo = (sc['logoUrl'] ?? '')
                                          .toString();
                                      return DropdownMenuItem(
                                        value: id,
                                        child: Row(
                                          children: [
                                            if (logo.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 8,
                                                ),
                                                child: CircleAvatar(
                                                  radius: 12,
                                                  backgroundImage: NetworkImage(
                                                    logo,
                                                  ),
                                                ),
                                              ),
                                            Expanded(child: Text(name)),
                                          ],
                                        ),
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
                        const Text(
                          "Service Title",
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.brown,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _titleCtrl,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? "Title is required"
                              : null,
                          decoration: _inp("e.g. Website Maintenance"),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Offerings (multiple)",
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
                                controller: _offeringCtrl,
                                decoration: _inp("e.g. Bug fixes"),
                                onSubmitted: (_) => _addOffering(),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _addOffering,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryColor,
                                foregroundColor: Colors.white,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text("Add"),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _offerings
                              .map(
                                (o) => Chip(
                                  label: Text(o),
                                  backgroundColor: Colors.brown.withOpacity(
                                    0.08,
                                  ),
                                  onDeleted: () => _removeOffering(o),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _saving ? null : _save,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
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
                            label: Text(_saving ? "Saving..." : "Save Service"),
                          ),
                        ),
                        const SizedBox(height: 80),
                      ],
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
          onTap: (i) {},
          userRole: _me?['role'] ?? '',
        ),
      ),
    );
  }

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
}
