// lib/screens/generate_receipt_screen.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/background_container.dart';
import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';
import 'receipt_list_screen.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

// If your app defines AppColors in constants, keep it; otherwise replace with Color values.
import '../utils/constants.dart'; // for AppColors.primaryColor

class GenerateReceiptScreen extends StatefulWidget {
  const GenerateReceiptScreen({Key? key}) : super(key: key);

  @override
  State<GenerateReceiptScreen> createState() => _GenerateReceiptScreenState();
}

class _GenerateReceiptScreenState extends State<GenerateReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  bool isLoading = false;
  bool isSubmitting = false;

  List<Map<String, dynamic>> invoices = [];
  List<Map<String, dynamic>> clients = [];
  Map<String, dynamic>? userData;

  // Selected values
  String? selectedInvoiceId;
  String? selectedClientId;

  // Controllers (notes remains for optional notes/received-from text)
  final TextEditingController amountController = TextEditingController();
  final TextEditingController paymentTypeController = TextEditingController();
  final TextEditingController chequeNoController = TextEditingController();
  final TextEditingController paymentDateController = TextEditingController();
  final TextEditingController notesController = TextEditingController();

  DateTime? selectedPaymentDate;

  // Payment type options
  final List<String> _paymentTypes = ['cash', 'cheque', 'online'];

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _fetchInvoices();
    _fetchClients();
  }

  @override
  void dispose() {
    amountController.dispose();
    paymentTypeController.dispose();
    chequeNoController.dispose();
    paymentDateController.dispose();
    notesController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    if (token.isNotEmpty) {
      await fetchUser(token);
    }
  }

  Future<void> fetchUser(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/me"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        final u = Map<String, dynamic>.from(d['user'] ?? {});
        if (u['avatarUrl'] != null &&
            u['avatarUrl'].toString().startsWith('/')) {
          u['avatarUrl'] = _absUrl(u['avatarUrl']);
        }
        if (mounted) setState(() => userData = u);
      }
    } catch (e) {
      // ignore - optional
    }
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring(7).trim()
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

  Future<void> _fetchInvoices() async {
    setState(() => isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/invoice/'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['invoices'] != null) {
          final invoiceList = (data['invoices'] as List).cast<dynamic>();
          setState(() {
            invoices = invoiceList.map<Map<String, dynamic>>((e) {
              final client = e['client'] ?? {};
              return {
                '_id': e['_id'],
                'invoiceNo': e['invoiceNo'],
                'clientId': client['_id'],
                'clientName': client['name'],
                'totalAmount': e['totalAmount'],
              };
            }).toList();
          });
        }
      } else {
        // silent - optional add snackbar
      }
    } catch (e) {
      // optional logging
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _fetchClients() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/client/getclient'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // ✅ Fix: clients are inside "data" not "clients"
        if (data['success'] == true && data['data'] != null) {
          final list = (data['data'] as List).cast<dynamic>();

          setState(() {
            clients = list.map<Map<String, dynamic>>((client) {
              return {
                '_id': client['_id'],
                'name': client['name'] ?? 'Unknown',
                'email': client['email'] ?? '',
                'phone': client['phone'] ?? '',
                'businessName': client['businessName'] ?? '',
              };
            }).toList();
          });
        } else {
          debugPrint('⚠️ No clients found or bad format: ${response.body}');
        }
      } else {
        debugPrint('❌ Failed to load clients: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ Error fetching clients: $e');
    }
  }

  Future<void> _selectPaymentDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedPaymentDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        selectedPaymentDate = picked;
        paymentDateController.text =
            "${picked.day}/${picked.month}/${picked.year}";
      });
    }
  }

  Future<void> _generateReceipt() async {
    if (!_formKey.currentState!.validate()) {
      SnackbarHelper.show(
        context,
        title: 'Validation Error',
        message: 'Please fill all required fields',
        type: ContentType.warning,
      );
      return;
    }

    if (selectedInvoiceId == null) {
      SnackbarHelper.show(
        context,
        title: 'Validation Error',
        message: 'Please select an invoice',
        type: ContentType.warning,
      );
      return;
    }

    if (selectedClientId == null) {
      SnackbarHelper.show(
        context,
        title: 'Validation Error',
        message: 'Please select the client who received the payment',
        type: ContentType.warning,
      );
      return;
    }

    setState(() => isSubmitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));

      final payload = {
        "invoiceNo": invoices.firstWhere(
          (inv) => inv['_id'] == selectedInvoiceId,
        )['invoiceNo'],
        "paymentType": paymentTypeController.text.trim(),
        "chequeOrTxnNo": chequeNoController.text.trim(),
        "notes": notesController.text.trim(),
        "amount": double.tryParse(amountController.text.trim()) ?? 0,
        "paymentDate": selectedPaymentDate?.toIso8601String(),
        "clientId": selectedClientId,
      };

      final res = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/receipts/generate"),
        headers: {
          "Authorization": token.isNotEmpty ? "Bearer $token" : "",
          "Content-Type": "application/json",
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode == 201) {
        SnackbarHelper.show(
          context,
          title: 'Success',
          message: 'Receipt generated successfully!',
          type: ContentType.success,
        );

        await Future.delayed(const Duration(milliseconds: 900));
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ReceiptListScreen()),
        );
      } else {
        final data = jsonDecode(res.body);
        SnackbarHelper.show(
          context,
          title: 'Failed',
          message: data['message'] ?? 'Failed to generate receipt',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Error generating receipt: $e',
        type: ContentType.failure,
      );
    } finally {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primaryColor),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: Colors.brown.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(12),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
        borderRadius: BorderRadius.circular(12),
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.brown.withOpacity(0.12)),
      ),
      child: const Row(
        children: [
          Icon(Icons.receipt_long, color: Colors.brown, size: 28),
          SizedBox(width: 12),
          Text(
            "Generate Receipt",
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.brown,
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
    required void Function(String?) onChanged,
    String? Function(String?)? validator,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      decoration: _inputDecoration(label: label, icon: icon),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    bool readOnly = false,
    void Function()? onTap,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onTap: onTap,
      decoration: _inputDecoration(label: label, icon: icon),
      validator: validator,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              ProfileHeader(
                avatarUrl: userData?['avatarUrl'],
                fullName: userData?['fullName'] ?? '',
                role: userData != null ? (userData!['role'] ?? '') : '',
                showBackButton: true,
                onBack: () => Navigator.pop(context),
                onNotification: () {},
              ),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildHeader(),
                              const SizedBox(height: 20),

                              // Invoice Select
                              _buildDropdownField(
                                label: "Select Invoice Number",
                                icon: Icons.receipt,
                                value: selectedInvoiceId,
                                items: invoices.map((invoice) {
                                  return DropdownMenuItem<String>(
                                    value: invoice['_id']?.toString(),
                                    child: Text(
                                      invoice['invoiceNo'] ?? 'Unknown',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() => selectedInvoiceId = value);
                                  // optionally auto-fill amount from invoice:
                                  final inv = invoices.firstWhere(
                                    (i) => i['_id'] == value,
                                    orElse: () => {},
                                  );
                                  if (inv.isNotEmpty &&
                                      inv['totalAmount'] != null) {
                                    amountController.text =
                                        (inv['totalAmount'] ?? '').toString();
                                  }
                                },
                                validator: (v) =>
                                    v == null ? 'Please select invoice' : null,
                              ),
                              const SizedBox(height: 16),

                              // Client dropdown (Received from)
                              _buildDropdownField(
                                label: "Received From (Client)",
                                icon: Icons.person,
                                value: selectedClientId,
                                items: clients.map((client) {
                                  return DropdownMenuItem<String>(
                                    value: client['_id'],
                                    child: Text(
                                      "${client['name']} (${client['businessName']})",
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (v) =>
                                    setState(() => selectedClientId = v),
                                validator: (v) =>
                                    v == null ? 'Please select client' : null,
                              ),

                              const SizedBox(height: 16),

                              // Amount
                              _buildTextField(
                                controller: amountController,
                                label: "Amount (₹)",
                                icon: Icons.currency_rupee,
                                keyboardType: TextInputType.number,
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Enter amount'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Payment Type -> DROPDOWN (changed)
                              DropdownButtonFormField<String>(
                                value: paymentTypeController.text.isNotEmpty
                                    ? paymentTypeController.text
                                    : null,
                                decoration: _inputDecoration(
                                  label: "Payment Type",
                                  icon: Icons.payment,
                                ),
                                items: _paymentTypes.map((t) {
                                  return DropdownMenuItem<String>(
                                    value: t,
                                    child: Text(
                                      t[0].toUpperCase() + t.substring(1),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  // Keep controller in sync so your payload code remains unchanged
                                  paymentTypeController.text = val ?? '';
                                  setState(() {}); // update UI if needed
                                },
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Select payment type'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Cheque/Txn No
                              _buildTextField(
                                controller: chequeNoController,
                                label: "Cheque/Transaction No. (optional)",
                                icon: Icons.confirmation_num,
                              ),
                              const SizedBox(height: 16),

                              // Payment Date
                              _buildTextField(
                                controller: paymentDateController,
                                label: "Payment Date",
                                icon: Icons.calendar_today,
                                readOnly: true,
                                onTap: _selectPaymentDate,
                                validator: (v) => v == null || v.trim().isEmpty
                                    ? 'Select date'
                                    : null,
                              ),
                              const SizedBox(height: 16),

                              // Notes / Description
                              TextFormField(
                                controller: notesController,
                                minLines: 2,
                                maxLines: 5,
                                decoration: _inputDecoration(
                                  label: "Notes (optional)",
                                  icon: Icons.note,
                                ),
                              ),
                              const SizedBox(height: 28),

                              SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: isSubmitting
                                      ? null
                                      : _generateReceipt,
                                  child: isSubmitting
                                      ? const CircularProgressIndicator(
                                          color: Colors.white,
                                        )
                                      : const Text(
                                          "Generate Receipt",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 50),
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
          currentIndex: 2,
          onTap: (_) {},
          userRole: userData?['role'] ?? '',
        ),
      ),
    );
  }
}
