import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/background_container.dart';
import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';

class ReceiptListScreen extends StatefulWidget {
  const ReceiptListScreen({Key? key}) : super(key: key);

  @override
  State<ReceiptListScreen> createState() => _ReceiptListScreenState();
}

class _ReceiptListScreenState extends State<ReceiptListScreen> {
  bool isLoading = true;
  List<dynamic> receipts = [];
  List<dynamic> filteredReceipts = [];
  int currentIndex = 2;
  Map<String, dynamic>? userData;
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    fetchReceipts();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      await fetchUser(token);
    }
  }

  Future<void> fetchReceipts() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/receipts/all"),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<dynamic>.from(data['data'] ?? []);
        setState(() {
          receipts = list;
          filteredReceipts = list;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        SnackbarHelper.show(
          context,
          title: "Error",
          message: "Failed to fetch receipts",
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

  void filterReceipts(String query) {
    final q = query.toLowerCase();
    final temp = receipts.where((rec) {
      return (rec['receiptNo'] ?? '').toString().toLowerCase().contains(q) ||
          (rec['client']?['name'] ?? '').toString().toLowerCase().contains(q) ||
          (rec['invoice']?['invoiceNo'] ?? '')
              .toString()
              .toLowerCase()
              .contains(q);
    }).toList();

    setState(() {
      searchQuery = query;
      filteredReceipts = temp;
    });
  }

  Future<void> deleteReceipt(String id, String receiptNo) async {
    try {
      final res = await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/receipts/delete/$id"),
      );
      if (res.statusCode == 200) {
        setState(() {
          receipts.removeWhere((r) => r['_id'] == id);
          filteredReceipts.removeWhere((r) => r['_id'] == id);
        });
        SnackbarHelper.show(
          context,
          title: "Deleted",
          message: "Receipt $receiptNo deleted successfully",
          type: ContentType.success,
        );
      } else {
        SnackbarHelper.show(
          context,
          title: "Failed",
          message: "Could not delete receipt",
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

  Future<void> downloadReceiptPDF(String receiptNo) async {
    try {
      if (!await _requestStoragePermission()) {
        SnackbarHelper.show(
          context,
          title: "Permission Denied",
          message: "Storage permission is required to save the receipt.",
          type: ContentType.warning,
        );
        return;
      }

      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      } else {
        downloadsDir = await getApplicationDocumentsDirectory();
      }

      final folder = Directory('${downloadsDir.path}/Receipts');
      if (!await folder.exists()) {
        await folder.create(recursive: true);
      }

      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/receipts/view/$receiptNo"),
      );

      if (response.statusCode == 200) {
        final filePath = '${folder.path}/$receiptNo.pdf';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        SnackbarHelper.show(
          context,
          title: "Downloaded",
          message: "Receipt saved to: ${folder.path}",
          type: ContentType.success,
        );
      } else {
        throw Exception('Failed to download receipt PDF');
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

  Future<void> shareReceiptPDF(String receiptNo) async {
    try {
      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/receipts/view/$receiptNo"),
      );

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$receiptNo.pdf';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        await Share.shareFiles(
          [filePath],
          text: 'Receipt $receiptNo',
          subject: 'Receipt $receiptNo',
        );
      } else {
        await Share.share(
          'View your receipt here:\n${ApiConfig.baseUrl}/receipt/view/$receiptNo',
          subject: 'Receipt $receiptNo',
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Share Failed",
        message: e.toString(),
        type: ContentType.failure,
      );
    }
  }

  Future<void> openReceiptPDF(String receiptNo) async {
    final url = "${ApiConfig.baseUrl}/receipts/view/$receiptNo";
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Cannot open receipt PDF",
        type: ContentType.failure,
      );
    }
  }

  Future<bool> _requestStoragePermission() async {
    if (await Permission.storage.isGranted) return true;
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  String _formatDate(String? date) {
    if (date == null) return "—";
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(date));
    } catch (_) {
      return "—";
    }
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
              title: Container(height: 15, color: Colors.white),
              subtitle: Container(height: 10, color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  Widget _buildReceiptCard(Map<String, dynamic> receipt) {
    final client = receipt['client'] ?? {};
    final invoice = receipt['invoice'] ?? {};

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  receipt['receiptNo'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  "₹${receipt['amount'] ?? 0}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            _buildInfoRow("Client", client['name'] ?? '-'),
            _buildInfoRow("Invoice", invoice['invoiceNo'] ?? '-'),
            _buildInfoRow("Payment", receipt['paymentType'] ?? '-'),
            _buildInfoRow("Date", _formatDate(receipt['createdAt'])),

            const Divider(height: 20),

            // Action Buttons (2 Rows for Better Layout)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                // ElevatedButton.icon(
                //   onPressed: () => downloadReceiptPDF(receipt['receiptNo']),
                //   icon: const Icon(Icons.download, size: 18),
                //   label: const Text("Download"),
                //   style: ElevatedButton.styleFrom(
                //     backgroundColor: Colors.blue,
                //     foregroundColor: Colors.white,
                //     padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                //     shape: RoundedRectangleBorder(
                //       borderRadius: BorderRadius.circular(8),
                //     ),
                //   ),
                // ),
                ElevatedButton.icon(
                  onPressed: () => shareReceiptPDF(receipt['receiptNo']),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text("Share"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                // ElevatedButton.icon(
                //   onPressed: () async {
                //     final confirm = await showDialog<bool>(
                //       context: context,
                //       builder: (context) => AlertDialog(
                //         title: const Text("Delete Receipt"),
                //         content: Text(
                //           "Are you sure you want to delete ${receipt['receiptNo']}?",
                //         ),
                //         actions: [
                //           TextButton(
                //             onPressed: () => Navigator.pop(context, false),
                //             child: const Text("Cancel"),
                //           ),
                //           TextButton(
                //             onPressed: () => Navigator.pop(context, true),
                //             child: const Text(
                //               "Delete",
                //               style: TextStyle(color: Colors.red),
                //             ),
                //           ),
                //         ],
                //       ),
                //     );
                //     if (confirm == true) {
                //       deleteReceipt(receipt['_id'], receipt['receiptNo']);
                //     }
                //   },
                //   icon: const Icon(Icons.delete, size: 18),
                //   label: const Text("Delete"),
                //   style: ElevatedButton.styleFrom(
                //     backgroundColor: Colors.redAccent,
                //     foregroundColor: Colors.white,
                //     padding: const EdgeInsets.symmetric(
                //       horizontal: 16,
                //       vertical: 10,
                //     ),
                //     shape: RoundedRectangleBorder(
                //       borderRadius: BorderRadius.circular(8),
                //     ),
                //   ),
                // ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text("$label:", style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
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
        await _showErrorSnack(res.body, fallback: "Failed to fetch user");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("User load error: $e"),
          backgroundColor: Colors.red,
        ),
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

  Future<void> _showErrorSnack(
    dynamic body, {
    String fallback = "Request failed",
  }) async {
    try {
      final b = body is String ? jsonDecode(body) : body;
      final msg = (b?['message'] ?? b?['error'] ?? b?['msg'] ?? fallback)
          .toString();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fallback), backgroundColor: Colors.red),
      );
    }
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
                child: TextField(
                  onChanged: filterReceipts,
                  decoration: InputDecoration(
                    hintText: "Search by client, receipt or invoice...",
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (isLoading) const LinearProgressIndicator(),
              Expanded(
                child: isLoading
                    ? shimmerLoader()
                    : filteredReceipts.isEmpty
                    ? const Center(
                        child: Text(
                          "No receipts found",
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: fetchReceipts,
                        child: ListView.builder(
                          itemCount: filteredReceipts.length,
                          itemBuilder: (context, i) {
                            final receipt = filteredReceipts[i];
                            return _buildReceiptCard(receipt);
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
        userRole: "admin",
      ),
    );
  }
}
