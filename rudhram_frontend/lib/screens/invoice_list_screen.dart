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
import 'package:open_file/open_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/background_container.dart';
import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({Key? key}) : super(key: key);

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  bool isLoading = true;
  List<dynamic> invoices = [];
  List<dynamic> filteredInvoices = [];
  int currentIndex = 2;
  Map<String, dynamic>? userData;
  String searchQuery = "";
  String filterType = "All";

  @override
  void initState() {
    super.initState();
    fetchInvoices();
    _loadUserData();
  }

  Future<void> fetchInvoices() async {
    setState(() => isLoading = true);
    try {
      final res = await http.get(Uri.parse("${ApiConfig.baseUrl}/invoice"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<dynamic>.from(data['invoices'] ?? []);
        setState(() {
          invoices = list;
          filteredInvoices = list;
          isLoading = false;
        });
      } else {
        setState(() => isLoading = false);
        SnackbarHelper.show(
          context,
          title: "Error",
          message: "Failed to fetch invoices",
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

  Future<bool> requestStoragePermission(BuildContext context) async {
    if (Platform.isAndroid) {
      // For Android 11 and above
      if (await Permission.manageExternalStorage.isGranted) {
        return true;
      }

      if (await Permission.manageExternalStorage.request().isGranted) {
        return true;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Storage permission is required to save the invoice.',
            ),
          ),
        );
        return false;
      }
    } else {
      // For iOS or other platforms
      return true;
    }
  }

  void saveInvoice(BuildContext context) async {
    bool hasPermission = await requestStoragePermission(context);
    if (!hasPermission) return;

    // Proceed to save PDF here
    print("✅ Saving invoice...");
  }

  void filterInvoices() {
    final q = searchQuery.toLowerCase();
    final temp = invoices.where((inv) {
      if (filterType == "All") {
        return (inv['invoiceNo'] ?? '').toString().toLowerCase().contains(q) ||
            (inv['client']?['name'] ?? '').toString().toLowerCase().contains(q);
      } else if (filterType == "InvoiceNo") {
        return (inv['invoiceNo'] ?? '').toString().toLowerCase().contains(q);
      } else {
        return (inv['client']?['_id'] ?? '').toString().toLowerCase().contains(
          q,
        );
      }
    }).toList();

    setState(() => filteredInvoices = temp);
  }

  Future<void> deleteInvoice(String id, String invoiceNo) async {
    try {
      final res = await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/invoice/$id"),
      );
      if (res.statusCode == 200) {
        setState(() {
          invoices.removeWhere((inv) => inv['_id'] == id);
          filteredInvoices.removeWhere((inv) => inv['_id'] == id);
        });
        SnackbarHelper.show(
          context,
          title: "Deleted",
          message: "Invoice $invoiceNo deleted successfully",
          type: ContentType.success,
        );
      } else {
        SnackbarHelper.show(
          context,
          title: "Failed",
          message: "Could not delete invoice",
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

Future<void> downloadPDF(String invoiceId, String invoiceNo) async {
  try {
    // Request permission as a courtesy. If user denies, we can still try saving to app dir on many Android versions.
    final perm = await _requestStoragePermission();
    if (!perm) {
      // show a friendly message but continue — app dir may still work.
      SnackbarHelper.show(
        context,
        title: "Permission",
        message: "Storage permission denied. Attempting to save to app folder (should still work).",
        type: ContentType.warning,
      );
    }

    final uri = Uri.parse("${ApiConfig.baseUrl}/invoice/$invoiceId/download");
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception("Failed to download PDF: ${response.statusCode}");
    }

    // Use app-specific external directory (Android: /Android/data/<package>/files)
    Directory? baseDir;
    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory(); // returns Android/data/<package>/files
      if (baseDir == null) {
        // Fallback: app documents dir
        baseDir = await getApplicationDocumentsDirectory();
      }
    } else {
      baseDir = await getApplicationDocumentsDirectory();
    }

    final invoicesDir = Directory('${baseDir.path}/Rudhram_Invoices');
    if (!await invoicesDir.exists()) await invoicesDir.create(recursive: true);

    final filePath = '${invoicesDir.path}/$invoiceNo.pdf';
    final file = File(filePath);
    await file.writeAsBytes(response.bodyBytes);

    SnackbarHelper.show(
      context,
      title: "Download Successful",
      message: "Saved to: ${invoicesDir.path}",
      type: ContentType.success,
    );

    // Try to open; if open fails, fallback to share
    final openRes = await OpenFile.open(filePath);
    // OpenResult has fields: type, message (open_file package)
    if (openRes.type != ResultType.done) {
      // fallback: share file
      await Share.shareFiles([filePath], text: 'Invoice $invoiceNo');
    }
  } catch (e, st) {
    print("downloadPDF error: $e\n$st");
    SnackbarHelper.show(
      context,
      title: "Download Failed",
      message: e.toString(),
      type: ContentType.failure,
    );
  }
}

  /// ✅ FIXED: Share actual PDF file instead of just link
  Future<void> sharePDF(String invoiceId, String invoiceNo) async {
    try {
      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/invoice/$invoiceId/download"),
      );

      if (response.statusCode == 200) {
        // Get temporary directory
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$invoiceNo.pdf';
        final file = File(filePath);

        // Write PDF bytes to file
        await file.writeAsBytes(response.bodyBytes);

        // Share the actual PDF file
        await Share.shareFiles(
          [filePath],
          text: 'Invoice $invoiceNo',
          subject: 'Invoice $invoiceNo',
        );
      } else {
        throw Exception(
          'Failed to download PDF for sharing: ${response.statusCode}',
        );
      }
    } catch (e) {
      // Fallback: Share the link if file sharing fails
      await _sharePDFLink(invoiceId, invoiceNo);
    }
  }

  Future<void> _sharePDFLink(String invoiceId, String invoiceNo) async {
    try {
      String fullUrl = "${ApiConfig.baseUrl}/invoice/$invoiceId/view";
      await Share.share(
        'Invoice $invoiceNo\n\nYou can view and download the invoice here: $fullUrl',
        subject: 'Invoice $invoiceNo',
      );
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Share Failed",
        message: "Failed to share invoice",
        type: ContentType.failure,
      );
    }
  }

  /// Helper: Download and open PDF locally
  Future<void> _downloadAndOpenPDF(String invoiceId) async {
    try {
      final response = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/invoice/$invoiceId/download"),
      );

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/temp_invoice.pdf';
        final file = File(filePath);

        await file.writeAsBytes(response.bodyBytes);

        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          throw Exception('Cannot open downloaded PDF');
        }
      } else {
        throw Exception('Failed to download PDF: ${response.statusCode}');
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Cannot open PDF: ${e.toString()}",
        type: ContentType.failure,
      );
    }
  }

  /// Helper: Request storage permission
 /// Call as: final ok = await _requestStoragePermission(context);
Future<bool> _requestStoragePermission() async {
  if (!Platform.isAndroid) return true;
  // Writing to app external dir usually does NOT require runtime permission on Android 11+
  // but some OEMs still require it for certain directories — we check and request storage permission as fallback
  final status = await Permission.storage.status;
  if (status.isGranted) return true;
  final result = await Permission.storage.request();
  return result.isGranted;
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

  String _formatDate(String? date) {
    if (date == null) return "—";
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(date));
    } catch (_) {
      return "—";
    }
  }

  Widget _buildActionButtons(Map<String, dynamic> invoice) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final accentColor = Colors.teal;
    final invoiceId = invoice['_id'];
    final invoiceNo = invoice['invoiceNo'] ?? '';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(width: 6),

        // Download PDF Button
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 18),
            label: const Text("Download"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onPressed: () => downloadPDF(invoiceId, invoiceNo),
          ),
        ),
        const SizedBox(width: 6),

        // Share PDF Button
        Expanded(
          child: ElevatedButton.icon(
            icon: const Icon(Icons.share, size: 18),
            label: const Text("Share"),
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onPressed: () => sharePDF(invoiceId, invoiceNo),
          ),
        ),
        const SizedBox(width: 6),

        // Delete Button
        IconButton(
          tooltip: "Delete Invoice",
          icon: const Icon(Icons.delete, color: Colors.redAccent, size: 22),
          onPressed: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text("Delete Invoice"),
                content: Text(
                  "Are you sure you want to delete invoice $invoiceNo?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("Cancel"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text(
                      "Delete",
                      style: TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              deleteInvoice(invoiceId, invoiceNo);
            }
          },
        ),
      ],
    );
  }

  Widget _buildInvoiceCard(Map<String, dynamic> invoice) {
    final client = invoice['client'] ?? {};
    final subCompany = invoice['subCompany'] ?? {};
    final status = invoice['status'] ?? 'Pending';
    final statusColor = _getStatusColor(status);
    final hasPDF = invoice['pdfUrl'] != null && invoice['pdfUrl'].isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      elevation: 3,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        invoice['invoiceNo'] ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (!hasPDF) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.warning_amber,
                          color: Colors.orange,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          "No PDF",
                          style: TextStyle(color: Colors.orange, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Amount
            Text(
              "₹${(invoice['totalAmount'] ?? 0).toStringAsFixed(2)}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 12),

            // Client and Company Info
            _buildInfoRow("Client", client['name'] ?? '-'),
            _buildInfoRow("Company", subCompany['name'] ?? '-'),
            _buildInfoRow("Date", _formatDate(invoice['createdAt'])),
            _buildInfoRow("Due Date", _formatDate(invoice['dueDate'])),

            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),

            // Action Buttons
            _buildActionButtons(invoice),
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
            child: Text(
              "$label:",
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      await fetchUser(token);
    }
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
                fullName: userData?['fullName'],
                role: formatUserRole(userData?['role']),
                showBackButton: true,
                onBack: () => Navigator.pop(context),
                onNotification: () {
                  print("🔔 Notification tapped");
                },
              ),

              // Search and Filter Section
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (val) {
                          setState(() => searchQuery = val);
                          filterInvoices();
                        },
                        decoration: InputDecoration(
                          hintText: "Search by client name or invoice no...",
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
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: filterType,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.filter_alt),
                      onChanged: (value) {
                        setState(() => filterType = value!);
                        filterInvoices();
                      },
                      items: const [
                        DropdownMenuItem(value: "All", child: Text("All")),
                        DropdownMenuItem(
                          value: "InvoiceNo",
                          child: Text("Invoice No"),
                        ),
                        DropdownMenuItem(
                          value: "ClientId",
                          child: Text("Client ID"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Loading Indicator
              if (isLoading) const LinearProgressIndicator(),

              // Invoices List
              Expanded(
                child: isLoading
                    ? shimmerLoader()
                    : filteredInvoices.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.receipt_long,
                              size: 64,
                              color: Colors.grey,
                            ),
                            SizedBox(height: 16),
                            Text(
                              "No invoices found",
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: fetchInvoices,
                        child: ListView.builder(
                          itemCount: filteredInvoices.length,
                          itemBuilder: (context, index) {
                            final invoice = filteredInvoices[index];
                            return _buildInvoiceCard(invoice);
                          },
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: CustomBottomNavBar(
          currentIndex: currentIndex,
          onTap: (i) => setState(() => currentIndex = i),
          userRole: "admin",
        ),
      ),
    );
  }
}
