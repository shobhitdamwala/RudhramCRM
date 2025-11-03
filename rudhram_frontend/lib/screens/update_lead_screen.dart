import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../utils/constants.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class UpdateLeadScreen extends StatefulWidget {
  final dynamic lead;
  const UpdateLeadScreen({Key? key, required this.lead}) : super(key: key);

  @override
  State<UpdateLeadScreen> createState() => _UpdateLeadScreenState();
}

class _UpdateLeadScreenState extends State<UpdateLeadScreen> {
  late TextEditingController nameCtrl;
  late TextEditingController phoneCtrl;
  late TextEditingController emailCtrl;
  late TextEditingController businessCtrl;
  late TextEditingController categoryCtrl;
  late TextEditingController sourceCtrl;
  late TextEditingController servicesCtrl;

  DateTime? birthDate;
  DateTime? anniversaryDate;
  DateTime? companyDate;
  bool loading = false;

  List<Map<String, dynamic>> subCompanies = [];
  List<String> selectedSubCompanyIds = [];
  List<Map<String, dynamic>> chosenServices = [];

  @override
  void initState() {
    super.initState();
    final lead = widget.lead ?? {};

    nameCtrl = TextEditingController(text: lead['name'] ?? '');
    phoneCtrl = TextEditingController(text: lead['phone'] ?? '');
    emailCtrl = TextEditingController(text: lead['email'] ?? '');
    businessCtrl = TextEditingController(text: lead['businessName'] ?? '');
    categoryCtrl = TextEditingController(text: lead['businessCategory'] ?? '');
    sourceCtrl = TextEditingController(text: lead['source'] ?? '');

    final cs = lead['chosenServices'] ?? lead['rawForm']?['services'];
    if (cs is List) {
      chosenServices = cs
          .map<Map<String, dynamic>>(
            (e) => e is Map ? Map<String, dynamic>.from(e) : {},
          )
          .toList();
    }

    servicesCtrl = TextEditingController(text: _servicesSummary());
    birthDate = _tryParseDate(lead['birthDate']);
    anniversaryDate = _tryParseDate(lead['anniversaryDate']);
    companyDate = _tryParseDate(lead['companyEstablishDate']);

    selectedSubCompanyIds = chosenServices
        .map((s) => s['subCompanyId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    fetchSubCompanies();
  }

  DateTime? _tryParseDate(dynamic v) {
    if (v == null) return null;
    try {
      return DateTime.tryParse(v.toString());
    } catch (_) {
      return null;
    }
  }

  Future<void> fetchSubCompanies() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/subcompany/getsubcompany'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        List<Map<String, dynamic>> comps = (data['data'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

        // NOW FETCH ADDONS FOR EACH SUBCOMPANY
        for (var sc in comps) {
          final id = sc['_id'];
          final addonRes = await http.get(
            Uri.parse('${ApiConfig.baseUrl}/subcompany/$id/addon-services'),
          );
          if (addonRes.statusCode == 200) {
            final body = jsonDecode(addonRes.body);
            sc['addonServices'] = (body['data'] ?? []);
          } else {
            sc['addonServices'] = [];
          }
        }

        setState(() {
          subCompanies = comps;
        });
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Failed to load sub companies",
        type: ContentType.failure,
      );
    }
  }

  String _servicesSummary() {
    if (chosenServices.isEmpty) return '';
    final bySub = <String, List<String>>{};
    for (var s in chosenServices) {
      final subId = s['subCompanyId']?.toString() ?? 'unknown';
      final title = s['title']?.toString() ?? '';
      bySub.putIfAbsent(subId, () => []).add(title);
    }
    return bySub.entries
        .map((e) => '${_subCompanyName(e.key) ?? e.key}: ${e.value.join(", ")}')
        .join(' | ');
  }

  String? _subCompanyName(String id) {
    final found = subCompanies.firstWhere(
      (c) => c['_id'].toString() == id,
      orElse: () => {},
    );
    if (found.isEmpty) return null;
    return found['name']?.toString();
  }

  Future<void> updateLead() async {
    setState(() => loading = true);
    try {
      // only include subcompanies that have at least one service
      final validSubIds = chosenServices
          .map((e) => e['subCompanyId']?.toString())
          .where((e) => e != null && e.isNotEmpty)
          .toSet()
          .toList();

      final body = {
        "name": nameCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "email": emailCtrl.text.trim(),
        "businessName": businessCtrl.text.trim(),
        "businessCategory": categoryCtrl.text.trim(),
        "source": sourceCtrl.text.trim(),
        "birthDate": birthDate?.toIso8601String(),
        "anniversaryDate": anniversaryDate?.toIso8601String(),
        "companyEstablishDate": companyDate?.toIso8601String(),
        "chosenServices": chosenServices,
        "subCompanyIds": validSubIds,
      };

      final res = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/lead/update/${widget.lead['_id']}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (res.statusCode == 200) {
        SnackbarHelper.show(
          context,
          title: "Success",
          message: "Lead updated successfully",
          type: ContentType.success,
        );
        Navigator.pop(context, true);
      } else {
        SnackbarHelper.show(
          context,
          title: "Failed",
          message: "Failed to update lead: ${res.body}",
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
    setState(() => loading = false);
  }

  // --- UI helpers (styling only) ---

  InputDecoration _inputDecoration(
    String label,
    IconData icon, {
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.primaryColor),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primaryColor, width: 1.8),
      ),
      labelStyle: const TextStyle(color: AppColors.primaryColor),
    );
  }

  Widget _fieldCard({required Widget child}) {
    return Card(
      color: Colors.white, // explicit white background
      elevation: 2,
      shadowColor: Colors.black12,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }

  Widget _textField(
    String label,
    TextEditingController ctrl, {
    bool readOnly = false,
    VoidCallback? onTap,
    IconData icon = Icons.text_fields,
    TextInputType keyboardType = TextInputType.text,
  }) {
    // use the styled field card with explicit white background
    return _fieldCard(
      child: TextField(
        controller: ctrl,
        readOnly: readOnly,
        keyboardType: keyboardType,
        onTap: onTap,
        decoration: _inputDecoration(label, icon),
      ),
    );
  }

  Widget _dateTile(
    String label,
    DateTime? date,
    Function(DateTime) onPicked, {
    IconData icon = Icons.event,
  }) {
    final display = date != null
        ? DateFormat('dd MMM yyyy').format(date)
        : 'Select $label';
    return _fieldCard(
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
          );
          if (picked != null) onPicked(picked);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primaryColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: AppColors.primaryColor,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      display,
                      style: TextStyle(
                        color: date != null ? Colors.black87 : Colors.grey[500],
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.calendar_today, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subCompanyChips() {
    final displayIds = chosenServices
        .map((s) => s['subCompanyId']?.toString())
        .where((id) => id != null && id!.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();

    return _fieldCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sub Companies',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryColor,
            ),
          ),
          const SizedBox(height: 8),
          if (displayIds.isEmpty)
            const Text(
              'No sub companies selected',
              style: TextStyle(color: Colors.grey),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: displayIds.map((id) {
                return Chip(
                  label: Text(_subCompanyName(id) ?? 'Unknown'),
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(
                    side: BorderSide(
                      color: AppColors.primaryColor.withOpacity(0.6),
                    ),
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  void _openAddServiceSheet() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        String? pickedSubId = selectedSubCompanyIds.isNotEmpty
            ? selectedSubCompanyIds.first
            : null;
        String? pickedServiceTitle;
        Map<String, dynamic>? pickedService;
        final selectedOfferings = <String>{};

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setModalState) {
                final matched = subCompanies
                    .where((c) => c['_id'].toString() == pickedSubId)
                    .toList();
                final servicesFromModel = matched.isEmpty
                    ? []
                    : (List.from(
                        matched.first['services'] ?? [],
                      ).map((e) => Map<String, dynamic>.from(e)).toList());

                final addonServices = matched.isEmpty
                    ? []
                    : (List.from(
                        matched.first['addonServices'] ?? [],
                      ).map((e) => Map<String, dynamic>.from(e)).toList());

                final List<Map<String, dynamic>> servicesForSub = [
                  ...servicesFromModel,
                  ...addonServices
                      .map(
                        (a) => {
                          "title": "[ADD-ON] ${a['title']}",
                          "offerings": a['offerings'],
                          "isAddOn": true,
                        },
                      )
                      .toList(),
                ];

                return Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, -2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: SingleChildScrollView(
                    controller: scrollController,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 60,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Add / Edit Service',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(
                                Icons.close,
                                color: AppColors.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Subcompany dropdown
                        InputDecorator(
                          decoration: _inputDecoration(
                            'Sub Company',
                            Icons.business,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: pickedSubId,
                              items: subCompanies
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c['_id'].toString(),
                                      child: Text(c['name'] ?? 'Unknown'),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setModalState(() {
                                pickedSubId = v;
                                pickedService = null;
                                pickedServiceTitle = null;
                                selectedOfferings.clear();
                              }),
                              hint: const Text('Select sub company'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Service dropdown
                        InputDecorator(
                          decoration: _inputDecoration(
                            'Service',
                            Icons.design_services,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: pickedServiceTitle,
                              items: servicesForSub
                                  .map(
                                    (s) => DropdownMenuItem<String>(
                                      value:
                                          s['title']?.toString() ??
                                          s['name']?.toString() ??
                                          'Untitled',
                                      child: Text(
                                        s['title'] ?? s['name'] ?? 'Untitled',
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setModalState(() {
                                pickedServiceTitle = v;
                                final found = servicesForSub.firstWhere(
                                  (s) => s['title']?.toString() == v,
                                  orElse: () => <String, dynamic>{},
                                );
                                pickedService = found.isEmpty ? null : found;
                                selectedOfferings.clear();
                              }),
                              hint: const Text('Select service'),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (pickedService != null)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Offerings',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children:
                                    (pickedService!['offerings'] as List? ?? [])
                                        .map((o) => o.toString())
                                        .map((off) {
                                          final isSel = selectedOfferings
                                              .contains(off);
                                          return ChoiceChip(
                                            label: Text(off),
                                            selected: isSel,
                                            selectedColor:
                                                AppColors.primaryColor,
                                            onSelected: (sel) => setModalState(
                                              () {
                                                if (sel) {
                                                  selectedOfferings.add(off);
                                                } else {
                                                  selectedOfferings.remove(off);
                                                }
                                              },
                                            ),
                                          );
                                        })
                                        .toList(),
                              ),
                            ],
                          ),
                        const SizedBox(height: 18),
                        ElevatedButton.icon(
                          onPressed:
                              (pickedSubId == null || pickedService == null)
                              ? null
                              : () {
                                  final entry = {
                                    'subCompanyId': pickedSubId,
                                    'title': pickedService!['title'],
                                    'isAddOn':
                                        pickedService!['isAddOn'] == true,
                                    'selectedOfferings': selectedOfferings
                                        .toList(),
                                  };
                                  final idx = chosenServices.indexWhere(
                                    (s) =>
                                        s['subCompanyId'] == pickedSubId &&
                                        s['title'] == entry['title'],
                                  );
                                  setState(() {
                                    if (idx >= 0) {
                                      chosenServices[idx] = entry;
                                    } else {
                                      chosenServices.add(entry);
                                    }
                                    selectedSubCompanyIds = chosenServices
                                        .map(
                                          (e) => e['subCompanyId'].toString(),
                                        )
                                        .toSet()
                                        .toList();
                                    servicesCtrl.text = _servicesSummary();
                                  });
                                  Navigator.of(context).pop();
                                },
                          icon: const Icon(Icons.add),
                          label: const Text('Add Service'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: AppColors.primaryColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _chosenServicesList() {
    if (chosenServices.isEmpty) return const SizedBox.shrink();
    return Card(
      color: Colors.white, // explicit white background
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chosen Services',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            ...chosenServices.map((s) {
              final subName =
                  _subCompanyName(s['subCompanyId']?.toString() ?? '') ?? '';
              final title = s['title'] ?? '';
              final offerings =
                  (s['selectedOfferings'] as List?)?.cast<String>() ?? [];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  '${subName}${offerings.isNotEmpty ? ' • ${offerings.join(', ')}' : ''}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () {
                    setState(() {
                      chosenServices.remove(s);
                      servicesCtrl.text = _servicesSummary();
                    });
                  },
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // main layout
    return Scaffold(
      appBar: AppBar(
        title: const Text("Update Lead"),
        backgroundColor: AppColors.primaryColor,
        elevation: 2,
        foregroundColor: Colors.white,
      ),
      backgroundColor: AppColors.backgroundGradientStart,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            children: [
              // Basic info card (explicit white)
              Card(
                color: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: const [
                          Icon(Icons.person, color: AppColors.primaryColor),
                          SizedBox(width: 8),
                          Text(
                            'Lead Details',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // fields inside white card
                      TextField(
                        controller: nameCtrl,
                        decoration: _inputDecoration('Full Name', Icons.person),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: _inputDecoration('Phone', Icons.phone),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDecoration('Email', Icons.email),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: businessCtrl,
                        decoration: _inputDecoration(
                          'Business Name',
                          Icons.business,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: categoryCtrl,
                        decoration: _inputDecoration(
                          'Business Category',
                          Icons.category,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: sourceCtrl,
                        decoration: _inputDecoration('Source', Icons.source),
                      ),
                    ],
                  ),
                ),
              ),

              // Dates card (explicit white)
              Card(
                color: Colors.white,
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                margin: const EdgeInsets.only(top: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: const [
                          Icon(
                            Icons.event_available,
                            color: AppColors.primaryColor,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Dates',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: birthDate ?? DateTime.now(),
                            firstDate: DateTime(1950),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null)
                            setState(() => birthDate = picked);
                        },
                        child: _dateTile(
                          'Birth Date',
                          birthDate,
                          (d) => setState(() => birthDate = d),
                        ),
                      ),
                      _dateTile(
                        'Anniversary Date',
                        anniversaryDate,
                        (d) => setState(() => anniversaryDate = d),
                      ),
                      _dateTile(
                        'Company Establishment Date',
                        companyDate,
                        (d) => setState(() => companyDate = d),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Services summary (read-only) — white card style

              // Subcompanies (read-only chips)
              _subCompanyChips(),

              // Chosen services detailed list
              _chosenServicesList(),

              const SizedBox(height: 8),

              // Add service button
              ElevatedButton.icon(
                onPressed: _openAddServiceSheet,
                icon: const Icon(Icons.add),
                label: const Text('Add / Edit Service'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // Update button
              ElevatedButton(
                onPressed: loading ? null : updateLead,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: loading
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Text(
                        'Update Lead',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),

              const SizedBox(height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
