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

  List<dynamic> subCompanies = [];
  List<String> selectedSubCompanyIds = [];

  @override
  void initState() {
    super.initState();
    final lead = widget.lead;

    nameCtrl = TextEditingController(text: lead['name'] ?? '');
    phoneCtrl = TextEditingController(text: lead['phone'] ?? '');
    emailCtrl = TextEditingController(text: lead['email'] ?? '');
    businessCtrl = TextEditingController(text: lead['businessName'] ?? '');
    categoryCtrl = TextEditingController(text: lead['businessCategory'] ?? '');
    sourceCtrl = TextEditingController(text: lead['source'] ?? '');
    servicesCtrl = TextEditingController(
      text: (lead['chosenServices'] as List?)?.join(", ") ?? '',
    );

    birthDate = lead['birthDate'] != null
        ? DateTime.tryParse(lead['birthDate'])
        : null;
    anniversaryDate = lead['anniversaryDate'] != null
        ? DateTime.tryParse(lead['anniversaryDate'])
        : null;
    companyDate = lead['companyEstablishDate'] != null
        ? DateTime.tryParse(lead['companyEstablishDate'])
        : null;

    selectedSubCompanyIds =
        (lead['subCompanyIds'] as List?)
            ?.map((e) => e is Map ? e['_id'].toString() : e.toString())
            .toList() ??
        [];

    fetchSubCompanies();
  }

  Future<void> fetchSubCompanies() async {
    try {
      final res = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/subcompany/getsubcompany'),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          subCompanies = List<Map<String, dynamic>>.from(data['data']);
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

  Future<void> updateLead() async {
    setState(() => loading = true);
    try {
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
        "chosenServices": servicesCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        "subCompanyIds": selectedSubCompanyIds,
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
          message: "Failed to update lead",
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

  Widget _textField(
    String label,
    TextEditingController controller, {
    TextInputType type = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        keyboardType: type,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(
              color: AppColors.primaryColor,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          labelStyle: const TextStyle(color: AppColors.primaryColor),
        ),
      ),
    );
  }

  Widget _datePickerTile(
    String label,
    DateTime? date,
    Function(DateTime) onPicked,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: date ?? DateTime.now(),
            firstDate: DateTime(1950),
            lastDate: DateTime(2100),
          );
          if (picked != null) setState(() => onPicked(picked));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.black),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: Colors.black, // 👈 Black border on focus
                width: 1.5,
              ),
            ),
            labelStyle: const TextStyle(color: AppColors.primaryColor),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 16,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                date != null
                    ? DateFormat('dd MMM yyyy').format(date)
                    : 'Select $label',
                style: TextStyle(
                  color: date != null ? Colors.black87 : Colors.grey.shade500,
                  fontSize: 16,
                ),
              ),
              const Icon(Icons.calendar_today, color: AppColors.primaryColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _subCompanyDropdown() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color.fromARGB(255, 0, 0, 0).withOpacity(0.6),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Select Sub Companies",
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.primaryColor,
              ),
            ),
            const SizedBox(height: 8),
            if (subCompanies.isEmpty)
              const Text("No sub companies found")
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: subCompanies.map((company) {
                  final id = company['_id'].toString();
                  final name = company['name'] ?? id;
                  final isSelected = selectedSubCompanyIds.contains(id);

                  return FilterChip(
                    selected: isSelected,
                    label: Text(
                      name,
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : AppColors.primaryColor,
                      ),
                    ),
                    selectedColor: AppColors.primaryColor,
                    backgroundColor: Colors.white,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          selectedSubCompanyIds.add(id);
                        } else {
                          selectedSubCompanyIds.remove(id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Update Lead"),
        backgroundColor: AppColors.primaryColor,
      ),
      backgroundColor: AppColors.backgroundGradientStart,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _textField("Full Name", nameCtrl),
            _textField("Phone", phoneCtrl, type: TextInputType.phone),
            _textField("Email", emailCtrl, type: TextInputType.emailAddress),
            _textField("Business Name", businessCtrl),
            _textField("Business Category", categoryCtrl),
            _textField("Source", sourceCtrl),
            _datePickerTile("Birth Date", birthDate, (d) => birthDate = d),
            _datePickerTile(
              "Anniversary Date",
              anniversaryDate,
              (d) => anniversaryDate = d,
            ),
            _datePickerTile(
              "Company Establishment Date",
              companyDate,
              (d) => companyDate = d,
            ),
            _textField("Chosen Services (comma separated)", servicesCtrl),
            _subCompanyDropdown(),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: loading ? null : updateLead,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: loading
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      "Update Lead",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
