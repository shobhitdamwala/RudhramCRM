// GenerateInvoiceScreen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';
import 'invoice_list_screen.dart';

class GenerateInvoiceScreen extends StatefulWidget {
  const GenerateInvoiceScreen({Key? key}) : super(key: key);

  @override
  State<GenerateInvoiceScreen> createState() => _GenerateInvoiceScreenState();
}

class _GenerateInvoiceScreenState extends State<GenerateInvoiceScreen> {
  final _formKey = GlobalKey<FormState>();
  List<Map<String, dynamic>> invoiceItems = [];
  List<dynamic> clients = [];
  List<dynamic> subCompanies = [];
  Map<String, dynamic>? userData;
  bool isLoading = false;
  bool isSubmitting = false;
  bool includeGst = true;

  // Services returned for selected client (normalized)
  List<Map<String, dynamic>> availableServices = [];
  // Track which service ids are selected
  final Set<String> selectedServiceIds = {};

  String? selectedClientId;
  String? selectedSubCompanyId;
  final TextEditingController dueDateController = TextEditingController();
  final TextEditingController notesController = TextEditingController();
  DateTime? selectedDueDate;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchClients();
    _fetchSubCompanies();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    if (token.isNotEmpty) {
      await fetchUser(token);
    }
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
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
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to fetch user',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      if (!mounted) return;
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'User load error: $e',
        type: ContentType.failure,
      );
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

  Future<void> _fetchClients() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/client/getclient"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          clients = data['data'] ?? [];
        });
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to fetch clients',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Client load error: $e',
        type: ContentType.failure,
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchSubCompanies() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          subCompanies = data['data'] ?? [];
        });
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to fetch sub-companies',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Sub-company load error: $e',
        type: ContentType.failure,
      );
    }
  }

  // ---------------------------
  // derive services from the selected client (no extra network call)
  // ---------------------------
  void _onClientChanged(String? clientId) {
    setState(() {
      selectedClientId = clientId;
      availableServices = [];
      selectedServiceIds.clear();
      // remove any invoiceItems linked to previous client
      invoiceItems.removeWhere((it) => it['serviceId'] != null);
    });

    if (clientId == null || clientId.isEmpty) return;

    // find client in local 'clients' list
    final clientObj = clients.firstWhere(
      (c) => (c['_id']?.toString() ?? "") == clientId,
      orElse: () => null,
    );

    if (clientObj == null) return;

    final meta = (clientObj['meta'] ?? {}) as Map<String, dynamic>;
    final chosen = (meta['chosenServices'] is List)
        ? List.from(meta['chosenServices'])
        : [];

    // normalize chosen services into availableServices entries:
    final normalized = <Map<String, dynamic>>[];
    for (final cs in chosen) {
      try {
        final m = Map<String, dynamic>.from(cs ?? {});
        final sid = (m['_id'] ?? "").toString();
        final title = (m['title'] ?? m['serviceTitle'] ?? "Service").toString();
        final offerings = (m['selectedOfferings'] is List)
            ? List.from(m['selectedOfferings'])
            : [];
        final description = offerings.join(", ");
        final scId = (m['subCompanyId'] ?? "").toString();

        // Find sub-company name from client's meta if present (or global subCompanies)
        String scName = "";
        if (meta['subCompanyNames'] is List && meta['subCompanyIds'] is List) {
          final ids = List.from(meta['subCompanyIds']);
          final names = List.from(meta['subCompanyNames']);
          final idx = ids.indexWhere((e) => e.toString() == scId);
          if (idx >= 0 && idx < names.length) scName = names[idx].toString();
        }
        if (scName.isEmpty) {
          final sc = subCompanies.firstWhere(
            (s) => (s['_id']?.toString() ?? "") == scId,
            orElse: () => null,
          );
          if (sc != null) scName = sc['name']?.toString() ?? "";
        }

        normalized.add({
          "_id": sid.isNotEmpty ? sid : "${clientObj['_id']}_${title}_$scId",
          "title": title,
          "description": description,
          "subCompanyId": scId,
          "subCompanyName": scName,
          "rate": 0.0,
          "defaultQty": 1,
        });
      } catch (e) {
        continue;
      }
    }

    // dedupe normalized services by _id
    final dedup = <String, Map<String, dynamic>>{};
    for (final s in normalized) {
      dedup[s['_id'].toString()] = s;
    }

    setState(() {
      availableServices = dedup.values.toList();
    });
  }

  // When sub-company changes, filter available services to show only those related (if any)
  void _onSubCompanyChanged(String? subCompanyId) {
    setState(() => selectedSubCompanyId = subCompanyId);

    if (selectedClientId != null && selectedClientId!.isNotEmpty) {
      _onClientChanged(selectedClientId);
      if (subCompanyId != null && subCompanyId.isNotEmpty) {
        setState(() {
          availableServices = availableServices.where((s) {
            final sc = (s['subCompanyId'] ?? "").toString();
            return sc.isEmpty || sc == subCompanyId;
          }).toList();
        });
      }
    }
  }

  void _addInvoiceItem() {
    setState(() {
      invoiceItems.add({
        'title': '', // manual item title (editable)
        'description': '',
        'qty': 1,
        'rate': 0.0,
        'serviceId': null,
        'serviceTitle': null,
      });
    });
  }

  void _addServiceAsItem(Map<String, dynamic> service) {
    final sid = (service['_id'] ?? "").toString();
    if (sid.isEmpty) return;
    if (selectedServiceIds.contains(sid)) return;

    setState(() {
      selectedServiceIds.add(sid);
      invoiceItems.add({
        // keep title separate from description
        'title':
            service['title'] ??
            '', // editable only for manual; for linked items we show serviceTitle
        'description': (service['description']?.toString().isNotEmpty == true
            ? service['description']
            : service['title']),
        'qty': service['defaultQty'] ?? 1,
        'rate': (service['rate'] is num)
            ? (service['rate'] as num).toDouble()
            : double.tryParse(service['rate']?.toString() ?? '0') ?? 0.0,
        'serviceId': sid,
        'serviceTitle': service['title'],
        'serviceSubCompany':
            service['subCompanyName'] ?? service['subCompanyId'],
      });
    });
  }

  void _removeInvoiceItem(int index) {
    final removed = invoiceItems[index];
    setState(() {
      invoiceItems.removeAt(index);
      final sid = removed['serviceId']?.toString();
      if (sid != null && sid.isNotEmpty) {
        selectedServiceIds.remove(sid);
      }
    });
  }

  void _toggleServiceCheckbox(bool? checked, Map<String, dynamic> service) {
    final sid = (service['_id'] ?? "").toString();
    if (sid.isEmpty) return;
    if (checked == true) {
      _addServiceAsItem(service);
    } else {
      setState(() {
        selectedServiceIds.remove(sid);
        invoiceItems.removeWhere(
          (it) => (it['serviceId']?.toString() ?? "") == sid,
        );
      });
    }
  }

  void _updateInvoiceItem(int index, String field, dynamic value) {
    setState(() {
      // ensure index still valid
      if (index < 0 || index >= invoiceItems.length) return;
      invoiceItems[index][field] = value;
    });
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        selectedDueDate = picked;
        dueDateController.text = "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  Future<void> _generateInvoice() async {
    if (!_formKey.currentState!.validate()) {
      SnackbarHelper.show(
        context,
        title: 'Validation Error',
        message: 'Please fix validation errors',
        type: ContentType.warning,
      );
      return;
    }

    if (selectedClientId == null || selectedSubCompanyId == null) {
      SnackbarHelper.show(
        context,
        title: 'Validation Error',
        message: 'Please select client and sub-company',
        type: ContentType.warning,
      );
      return;
    }

    if (invoiceItems.isEmpty) {
      SnackbarHelper.show(
        context,
        title: 'Validation Error',
        message: 'Please add/select at least one service',
        type: ContentType.warning,
      );
      return;
    }

    // Validate items
    for (var i = 0; i < invoiceItems.length; i++) {
      final it = invoiceItems[i];
      final desc = (it['description'] ?? '').toString();
      final qty = int.tryParse(it['qty'].toString()) ?? -1;
      final rate = double.tryParse(it['rate'].toString()) ?? -1.0;
      // Also allow title to be empty (will be inferred), but require description
      if (desc.isEmpty || qty <= 0 || rate < 0) {
        SnackbarHelper.show(
          context,
          title: 'Validation Error',
          message: 'Please fix item #${i + 1} (desc/qty/rate)',
          type: ContentType.warning,
        );
        return;
      }
    }

    setState(() => isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));

      // Build payload: include title + description for each item
      final payload = {
        "clientId": selectedClientId,
        "subCompanyId": selectedSubCompanyId,
        "items": invoiceItems.map((item) {
          final qty = int.tryParse(item['qty'].toString()) ?? 1;
          final rate = double.tryParse(item['rate'].toString()) ?? 0.0;
          // choose title priority: serviceTitle (linked) -> title (manual) -> first line of description
          String title = '';
          if (item['serviceTitle'] != null &&
              item['serviceTitle'].toString().isNotEmpty) {
            title = item['serviceTitle'].toString();
          } else if (item['title'] != null &&
              item['title'].toString().isNotEmpty) {
            title = item['title'].toString();
          } else {
            final desc = (item['description'] ?? '').toString();
            title = desc.split(RegExp(r'\r?\n')).first;
          }
          return {
            "title": title,
            "description": item['description'],
            "qty": qty,
            "rate": rate,
          };
        }).toList(),
        "dueDate": selectedDueDate?.toIso8601String(),
        "notes": notesController.text.trim(),
        "includeGst": includeGst,
      };

      final res = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/invoice/generate"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode == 201 || res.statusCode == 200) {
        SnackbarHelper.show(
          context,
          title: 'Success!',
          message: 'Invoice generated successfully!',
          type: ContentType.success,
        );

        await Future.delayed(const Duration(milliseconds: 800));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const InvoiceListScreen()),
        );
      } else {
        final errorData = jsonDecode(res.body);
        SnackbarHelper.show(
          context,
          title: 'Generation Failed',
          message: errorData['message'] ?? 'Failed to generate invoice',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Invoice generation error: $e',
        type: ContentType.failure,
      );
    } finally {
      setState(() => isSubmitting = false);
    }
  }

  @override
  void dispose() {
    dueDateController.dispose();
    notesController.dispose();
    super.dispose();
  }

  // ---------------- UI building ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBody: true,
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              ProfileHeader(
                avatarUrl: userData?['avatarUrl'],
                fullName: userData?['fullName'],
                role: userData?['role'] ?? '',
                showBackButton: true,
                onBack: () => Navigator.pop(context),
              ),
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.brown),
                      )
                    : _buildInvoiceForm(),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: Container(
        color: Colors.transparent,
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
        child: CustomBottomNavBar(
          currentIndex: 2,
          onTap: (index) {},
          userRole: userData?['role'] ?? '',
        ),
      ),
    );
  }

  Widget _buildInvoiceForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(
              icon: Icons.receipt_long,
              title: "Generate New Invoice",
              subtitle: "Pick client, services and generate invoice PDF",
            ),
            const SizedBox(height: 16),

            // Client dropdown
            _buildDropdownField(
              label: "Select Client",
              icon: Icons.person_outline,
              value: selectedClientId,
              items: clients.map<DropdownMenuItem<String>>((client) {
                return DropdownMenuItem<String>(
                  value: client['_id']?.toString() ?? '',
                  child: Text(
                    "${client['name'] ?? 'Unknown'} — ${client['businessName'] ?? ''}",
                  ),
                );
              }).toList(),
              onChanged: (value) => _onClientChanged(value),
              validator: (value) => value == null || value.isEmpty
                  ? 'Please select a client'
                  : null,
            ),
            const SizedBox(height: 12),

            // Sub-company dropdown
            _buildDropdownField(
              label: "Select Sub-company",
              icon: Icons.business_center_outlined,
              value: selectedSubCompanyId,
              items: subCompanies.map<DropdownMenuItem<String>>((company) {
                return DropdownMenuItem<String>(
                  value: company['_id']?.toString() ?? '',
                  child: Text(company['name']?.toString() ?? 'Unknown Company'),
                );
              }).toList(),
              onChanged: (value) => _onSubCompanyChanged(value),
              validator: (value) => value == null || value.isEmpty
                  ? 'Please select a sub-company'
                  : null,
            ),
            const SizedBox(height: 12),

            // Due date + GST toggle
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: dueDateController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "Due Date",
                      prefixIcon: const Icon(
                        Icons.calendar_today,
                        color: Colors.brown,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.brown),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                    onTap: _selectDueDate,
                    validator: (value) => (value == null || value.isEmpty)
                        ? 'Please select due date'
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      const Text(
                        'Include GST',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Switch(
                        value: includeGst,
                        activeColor: Colors.brown,
                        onChanged: (v) => setState(() => includeGst = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // Available services (from client meta)
            if (availableServices.isNotEmpty) ...[
              const Text(
                "Available Services",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.brown,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  color: Colors.white,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: availableServices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, idx) {
                    final s = availableServices[idx];
                    final sid = (s['_id'] ?? '').toString();
                    final subName = (s['subCompanyName'] ?? '').toString();
                    return CheckboxListTile(
                      value: selectedServiceIds.contains(sid),
                      onChanged: (checked) =>
                          _toggleServiceCheckbox(checked, s),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              s['title'] ?? 'Service',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (subName.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                subName,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        (s['description'] ?? '').toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      secondary: Text(
                        "₹${(s['rate'] ?? 0).toString()}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Invoice Items heading + add button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Invoice Items",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                  ),
                ),
                IconButton(
                  onPressed: _addInvoiceItem,
                  icon: const Icon(Icons.add_circle, color: Colors.brown),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (invoiceItems.isEmpty)
              _buildEmptyItemsPlaceholder()
            else
              Column(
                children: invoiceItems.asMap().entries.map((entry) {
                  final index = entry.key;
                  final item = Map<String, dynamic>.from(entry.value);
                  return _buildInvoiceItemCard(index, item);
                }).toList(),
              ),

            const SizedBox(height: 14),
            _buildNotesSection(),
            const SizedBox(height: 18),
            _buildGenerateButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 255, 244, 236),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.brown.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.brown, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownField({
    required String label,
    required IconData icon,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required Function(String?) onChanged,
    required String? Function(String?) validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.brown),
        prefixIcon: Icon(icon, color: Colors.brown),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.brown),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
      icon: const Icon(Icons.arrow_drop_down, color: Colors.brown),
      dropdownColor: Colors.white,
      style: const TextStyle(color: Colors.brown),
    );
  }

  Widget _buildEmptyItemsPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 44,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 8),
          const Text("No items added", style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 6),
          Text(
            "Use the + button or select services above to add invoice items",
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // IMPORTANT: Build invoice item card WITHOUT ephemeral controllers.
  // Use initialValue and onChanged to keep invoiceItems state as source-of-truth.
  Widget _buildInvoiceItemCard(int index, Map<String, dynamic> item) {
    final serviceTitle = item['serviceTitle']?.toString();
    final titleEditable = (serviceTitle == null || serviceTitle.isEmpty);
    final qtyStr = (item['qty'] ?? 1).toString();
    final rateStr = (item['rate'] ?? 0.0).toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "Item ${index + 1}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                  ),
                ),
                const Spacer(),
                if (item['serviceId'] != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.brown.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("Linked", style: TextStyle(fontSize: 12)),
                  ),
                IconButton(
                  onPressed: () => _removeInvoiceItem(index),
                  icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),

            // Show service title prominently (non-editable if linked, editable otherwise)
            if (!titleEditable &&
                serviceTitle != null &&
                serviceTitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                serviceTitle,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ] else ...[
              const SizedBox(height: 8),
              TextFormField(
                initialValue: item['title']?.toString() ?? '',
                decoration: const InputDecoration(
                  labelText: "Title (optional)",
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.brown),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: (v) => _updateInvoiceItem(index, 'title', v),
              ),
            ],

            const SizedBox(height: 8),

            // Editable description field (multiline)
            TextFormField(
              initialValue: item['description']?.toString() ?? '',
              decoration: const InputDecoration(
                labelText: "Description",
                border: OutlineInputBorder(),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.brown),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              maxLines: 3,
              onChanged: (v) => _updateInvoiceItem(index, 'description', v),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),

            const SizedBox(height: 8),

            // qty & rate
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: qtyStr,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "Quantity",
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.brown),
                      ),
                    ),
                    onChanged: (v) {
                      final val = int.tryParse(v) ?? 1;
                      _updateInvoiceItem(index, 'qty', val);
                    },
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (int.tryParse(v) == null) return 'Invalid';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: rateStr,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: "Rate (₹)",
                      border: OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.brown),
                      ),
                    ),
                    onChanged: (v) {
                      final val = double.tryParse(v) ?? 0.0;
                      _updateInvoiceItem(index, 'rate', val);
                    },
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Required';
                      if (double.tryParse(v) == null) return 'Invalid';
                      return null;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Additional Notes (Optional)",
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: notesController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: "Add any additional notes or terms for the invoice...",
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.brown),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: isSubmitting ? null : _generateInvoice,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
        child: isSubmitting
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    "Generating Invoice...",
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.picture_as_pdf, color: Colors.white),
                  SizedBox(width: 12),
                  Text(
                    "Generate PDF Invoice",
                    style: TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }
}
