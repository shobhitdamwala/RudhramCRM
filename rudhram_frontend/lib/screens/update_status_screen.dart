import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../utils/constants.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class UpdateStatusScreen extends StatefulWidget {
  final String leadId;
  final String leadName;
  final String currentStatus;

  const UpdateStatusScreen({
    Key? key,
    required this.leadId,
    required this.leadName,
    required this.currentStatus,
  }) : super(key: key);

  @override
  State<UpdateStatusScreen> createState() => _UpdateStatusScreenState();
}

class _UpdateStatusScreenState extends State<UpdateStatusScreen> {
  final List<String> allowedStatuses = [
    "new",
    "contacted",
    "qualified",
    "lost",
  ];

  String? selectedStatus;
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    selectedStatus = widget.currentStatus;
  }

  Future<void> updateStatus() async {
    if (selectedStatus == null || selectedStatus == widget.currentStatus) {
      SnackbarHelper.show(
        context,
        title: "Notice",
        message: "Please select a different status to update.",
        type: ContentType.warning,
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final response = await http.put(
        Uri.parse('${ApiConfig.baseUrl}/lead/${widget.leadId}/status'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'status': selectedStatus}),
      );

      setState(() => isLoading = false);

      if (response.statusCode == 200) {
        SnackbarHelper.show(
          context,
          title: "Success",
          message: "Lead status updated successfully.",
          type: ContentType.success,
        );
        Navigator.pop(context, true);
      } else {
        SnackbarHelper.show(
          context,
          title: "Error",
          message: "Failed to update lead status.",
          type: ContentType.failure,
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      SnackbarHelper.show(
        context,
        title: "Error",
        message: e.toString(),
        type: ContentType.failure,
      );
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'contacted':
        return Colors.orange.shade700;
      case 'qualified':
        return Colors.green.shade700;
      case 'lost':
        return Colors.red.shade700;
      default:
        return AppColors.primaryColor;
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(
        color: AppColors.primaryColor,
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: AppColors.primaryColor),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primaryColor, width: 1.6),
      ),
    );
  }

  Widget _headerCard() {
    // initials
    final initials = widget.leadName.trim().isEmpty
        ? '?'
        : widget.leadName
            .trim()
            .split(' ')
            .where((p) => p.isNotEmpty)
            .map((p) => p[0])
            .take(2)
            .join()
            .toUpperCase();

    final statusColor = _statusColor(widget.currentStatus);

    return Card(
      color: Colors.white,
      elevation: 3,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Row(
          children: [
            // CircleAvatar(
            //   radius: 28,
            //   backgroundColor: statusColor,
            //   child: Text(initials,
            //       style: const TextStyle(
            //           color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            // ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name (wrap if long)
                  Text(
                    widget.leadName,
                    style: const TextStyle(
                      color: AppColors.primaryColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.info_outline, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'ID: ${widget.leadId}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // status pill aligned right (fixed size to avoid overflow)
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96, maxWidth: 120),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                ),
                child: Row(
                  children: [
                    // small label
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text('Current',
                              style: TextStyle(fontSize: 10, color: Colors.grey)),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              widget.currentStatus.toUpperCase(),
                              style: TextStyle(fontWeight: FontWeight.bold, color: statusColor),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // colored dot
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusCard() {
    return Card(
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.flag, color: AppColors.primaryColor),
                SizedBox(width: 8),
                Text('Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            Text('Current: ${widget.currentStatus.toUpperCase()}',
                style: const TextStyle(fontSize: 14, color: Colors.black87)),
            const SizedBox(height: 10),
            // label
            const Text('Select New Status',
                style: TextStyle(color: AppColors.primaryColor, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),

            // dropdown
            InputDecorator(
              decoration: _inputDecoration('', Icons.swap_horiz),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedStatus,
                  isExpanded: true,
                  icon: Icon(Icons.arrow_drop_down, color: AppColors.primaryColor),
                  items: allowedStatuses.map((status) {
                    final color = _statusColor(status);
                    return DropdownMenuItem<String>(
                      value: status,
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                          ),
                          Text(status.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => selectedStatus = val),
                ),
              ),
            ),

            const SizedBox(height: 12),
            const Text(
              'Choose a different status and click Update. Only changes will be submitted.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _helpFooter() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.help_outline, color: AppColors.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Statuses are used to track lead progress. "Lost" means the lead will no longer be pursued.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // main layout
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        elevation: 0,
        title: const Text('Update Lead Status', style: TextStyle(color: Colors.white)),
      ),
      backgroundColor: AppColors.backgroundGradientStart,
      
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // _headerCard(),
                      const SizedBox(height: 14),
                      _statusCard(),
                      const SizedBox(height: 18),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : updateStatus,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 4,
                          ),
                          child: isLoading
                              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Update Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _helpFooter(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
