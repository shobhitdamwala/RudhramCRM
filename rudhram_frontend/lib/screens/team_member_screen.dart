import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:rudhram_frontend/utils/custom_bottom_nav.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/profile_header.dart';
import 'package:shimmer/shimmer.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class TeamMemberScreen extends StatefulWidget {
  const TeamMemberScreen({super.key});

  @override
  State<TeamMemberScreen> createState() => _TeamMemberScreenState();
}

class _TeamMemberScreenState extends State<TeamMemberScreen> {
  Map<String, dynamic>? userData;
  List<dynamic> teamMembers = [];
  bool isLoading = true;

  String _fmtYMD(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  DateTime? _tryParseYMD(String? ymd) {
    if (ymd == null || ymd.isEmpty) return null;
    try {
      final p = ymd.split('-');
      if (p.length != 3) return null;
      return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    } catch (_) {
      return null;
    }
  }

  String _isoToYMD(dynamic iso) {
    if (iso == null) return '';
    try {
      return _fmtYMD(DateTime.parse(iso.toString()));
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    fetchAllData();
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
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

  Future<void> fetchAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('auth_token');
      if (raw == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Not logged in"),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final token = _cleanToken(raw);
      await Future.wait([fetchUser(token), fetchTeamMembers(token)]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to load: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
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

  /// Only ADMIN + TEAM_MEMBER; hide SUPER_ADMIN and others
  Future<void> fetchTeamMembers(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/users"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final rawList = data is List
            ? data
            : (data['data'] ?? data['users'] ?? []);
        final members = <dynamic>[];
        for (final m in rawList) {
          final role = (m['role'] ?? '').toString().toUpperCase();
          if (role == 'SUPER_ADMIN') continue;
          if (role != 'ADMIN' && role != 'TEAM_MEMBER') continue;
          if (m['avatarUrl'] != null &&
              m['avatarUrl'].toString().startsWith('/')) {
            m['avatarUrl'] = _absUrl(m['avatarUrl']);
          }
          members.add(m);
        }
        if (mounted) setState(() => teamMembers = members);
      } else {
        await _showErrorSnack(res.body, fallback: "Failed to fetch users");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Users load error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> deleteMember(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      if (token.isEmpty) return;

      final res = await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/user/team-members/$id"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        setState(() {
          teamMembers.removeWhere(
            (m) => (m['_id'] ?? m['id']).toString() == id,
          );
        });
        SnackbarHelper.show(
          context,
          title: 'Success',
          message: 'Member deleted successfully',
          type: ContentType.success,
        );
      } else {
        await _showErrorSnack(res.body, fallback: "Failed to delete member");
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: "Delete error: $e",
        type: ContentType.failure,
      );
    }
  }

  Future<void> updateMember(
    String id,
    Map<String, dynamic> updateData,
    File? avatarFile,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      if (token.isEmpty) return;

      final uri = Uri.parse("${ApiConfig.baseUrl}/user/team-members/$id");
      final req = http.MultipartRequest('PUT', uri)
        ..headers['Authorization'] = "Bearer $token";

      updateData.forEach((k, v) {
        if (v != null) req.fields[k] = v.toString();
      });
      if (avatarFile != null) {
        req.files.add(
          await http.MultipartFile.fromPath('avatar', avatarFile.path),
        );
      }

      final resp = await req.send();
      await resp.stream.bytesToString(); // not used, but consumed

      if (resp.statusCode == 200) {
        SnackbarHelper.show(
          context,
          title: 'Success',
          message: 'Member updated successfully',
          type: ContentType.success,
        );
        await fetchTeamMembers(token);
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to update member',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Update error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _registerInit(
    Map<String, dynamic> data,
    File? avatarFile,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    if (token.isEmpty) throw Exception("Not logged in");

    final uri = Uri.parse("${ApiConfig.baseUrl}/user/register-init");
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = "Bearer $token";

    data.forEach((k, v) {
      if (v != null && v.toString().isNotEmpty) req.fields[k] = v.toString();
    });

    if (avatarFile != null) {
      req.files.add(
        await http.MultipartFile.fromPath('avatar', avatarFile.path),
      );
    }

    final resp = await req.send();
    final body = await resp.stream.bytesToString();
    final json = jsonDecode(body);
    if (resp.statusCode == 200 && json['success'] == true) {
      return json;
    } else {
      throw Exception(json['message'] ?? 'Failed to start registration');
    }
  }

  Future<void> _registerVerify(String tempId, String email, String otp) async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    if (token.isEmpty) throw Exception("Not logged in");

    final res = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/user/register-verify"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"tempId": tempId, "email": email, "otp": otp}),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode != 201 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Verification failed');
    }
  }

  Future<void> _registerResendOtp(String tempId, String email) async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    if (token.isEmpty) throw Exception("Not logged in");

    final res = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/user/register-resend-otp"),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
      body: jsonEncode({"tempId": tempId, "email": email}),
    );

    final data = jsonDecode(res.body);
    if (res.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? 'Resend failed');
    }
  }

  Future<void> _showDeleteConfirmationDialog(
    String memberId,
    String memberName,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20.0),
          ),
          backgroundColor: const Color(0xFFFDF6EE),
          child: Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_rounded,
                    size: 40,
                    color: Colors.red.shade600,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Delete Team Member',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Are you sure you want to delete "$memberName"?',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Colors.brown),
                ),
                const SizedBox(height: 8),
                Text(
                  'This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.red.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.brown,
                          side: const BorderSide(color: Colors.brown),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          deleteMember(memberId);
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.delete_outline, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Delete',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // 2-column layout sizing
    final w = MediaQuery.of(context).size.width;
    final available = w - 16 - 16 - 16; // padding + spacing
    final cardWidth = available / 2;
    final cardHeight = 210.0; // slightly shorter to avoid overflow
    final ratio = cardWidth / cardHeight;

    return Scaffold(
      extendBody:
          true, // ← lets content show under the navbar blur/transparent area
      backgroundColor: Colors.transparent,

      body: BackgroundContainer(
        child: SafeArea(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.brown),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ProfileHeader(
                      avatarUrl: userData?['avatarUrl'],
                      fullName: userData?['fullName'],
                      role: formatUserRole(userData?['role']),
                      showBackButton: true,
                      onBack: () => Navigator.pop(context),
                    ),
                    const SizedBox(height: 8),
                    Expanded(child: _buildGrid(teamMembers, ratio)),
                    const SizedBox(height: 8),
                  ],
                ),
        ),
      ),

      // Put navbar in the Scaffold footer so FAB can float above it
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6), // feel free to tweak
          child: CustomBottomNavBar(
            currentIndex: 2,
            onTap: (i) {},
            userRole: userData?['role'] ?? '',
          ),
        ),
      ),

      // FAB above navbar
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Transform.translate(
        offset: const Offset(0, -12), // lift a bit above the navbar
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.primaryColor,
          onPressed: () => _showAddMemberDialog(context),
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text("Add Member"),
          foregroundColor: Colors.white,
        ),
      ),
    );
  }

  Widget _buildGrid(List<dynamic> members, double aspectRatio) {
    if (isLoading) return _buildShimmerGrid();
    if (members.isEmpty) {
      return Center(
        child: Text(
          "No team members found",
          style: TextStyle(color: Colors.brown[600]),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        itemCount: members.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: aspectRatio,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        // room for FAB + navbar so nothing is hidden
        padding: const EdgeInsets.only(bottom: 140),
        itemBuilder: (context, i) {
          final m = Map<String, dynamic>.from(members[i] as Map);
          return _memberCard(m);
        },
      ),
    );
  }

  Widget _memberCard(Map m) {
    final role = (m['role'] ?? '').toString().toUpperCase();
    final isAdmin = role == 'ADMIN';
    final id = (m['_id'] ?? m['id']).toString();

    final borderColor = isAdmin ? const Color(0xFFFFD54F) : Colors.transparent;
    final chipColor = isAdmin ? const Color(0xFFFFB300) : Colors.teal;
    final chipLabel = isAdmin ? "ADMIN" : "TEAM MEMBER";

    return GestureDetector(
      onTap: () => _showEditMemberDialog(m),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: borderColor, width: isAdmin ? 1.5 : 0.6),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            // avatar + admin tag
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundImage:
                      (m['avatarUrl'] != null &&
                          (m['avatarUrl'] as String).isNotEmpty)
                      ? NetworkImage(m['avatarUrl'])
                      : const AssetImage('assets/user.jpg') as ImageProvider,
                ),
                if (isAdmin)
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF3CD),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFFD54F)),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.workspace_premium,
                            size: 14,
                            color: Color(0xFFFFB300),
                          ),
                          SizedBox(width: 4),
                          Text(
                            "Admin",
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8D6E63),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // name + email
            Text(
              (m['fullName'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.brown,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              (m['email'] ?? '').toString(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),

            // role chip
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: chipColor.withOpacity(.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: chipColor.withOpacity(.4)),
              ),
              child: Text(
                chipLabel,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: .5,
                  fontWeight: FontWeight.w700,
                  color: chipColor,
                ),
              ),
            ),

            // compact spacing (no big Spacer)
            const SizedBox(height: 8),

            // icon-only actions
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  // EDIT - outlined with primary color
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        side: BorderSide(color: AppColors.primaryColor),
                        foregroundColor: AppColors.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _showEditMemberDialog(m),
                      child: const Icon(Icons.edit, size: 18),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // DELETE - red filled
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () => _showDeleteConfirmationDialog(
                        id,
                        m['fullName'] ?? 'this member',
                      ),
                      child: const Icon(Icons.delete_outline, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        itemCount: 4,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.78,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        padding: const EdgeInsets.only(bottom: 140),
        itemBuilder: (_, __) => Shimmer.fromColors(
          baseColor: Colors.grey[300]!,
          highlightColor: Colors.grey[100]!,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }

  void _showAddMemberDialog(BuildContext context) {
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final cityController = TextEditingController();
    final stateController = TextEditingController();
    final passwordController = TextEditingController();
    final birthDateController = TextEditingController();
    String role = "TEAM_MEMBER";
    File? selectedImage;

    String? tempId;
    int secondsLeft = 0;
    bool canResend = false;
    bool isSendingCode = false;
    bool isVerifying = false;
    bool emailVerified = false;
    final otpController = TextEditingController();
    _SimpleTicker? ticker;

    String? bannerMsg;
    ContentType? bannerType;

    void showBanner(
      String msg,
      ContentType type,
      void Function(void Function()) setStateDialog,
    ) {
      setStateDialog(() {
        bannerMsg = msg;
        bannerType = type;
      });
    }

    String mmss(int s) {
      final m = (s ~/ 60).toString().padLeft(2, '0');
      final ss = (s % 60).toString().padLeft(2, '0');
      return "$m:$ss";
    }

    void startTimer(int s, void Function(void Function()) setStateDialog) {
      secondsLeft = s;
      canResend = false;
      ticker?.dispose();
      ticker = _SimpleTicker((_) {
        if (!mounted) return;
        setStateDialog(() {
          if (secondsLeft > 0) secondsLeft -= 1;
          if (secondsLeft <= 0) canResend = true;
        });
      })..start();
    }

    showDialog(
      context: context,
      builder: (context) {
        final maxHeight = MediaQuery.of(context).size.height * 0.9;
        final maxWidth = MediaQuery.of(context).size.width * 0.95;

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: const Color(0xFFFDF6EE),
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              Future<void> sendCode() async {
                final name = fullNameController.text.trim();
                final pwd = passwordController.text;
                final email = emailController.text.trim();
                if (name.isEmpty || pwd.isEmpty || email.isEmpty) {
                  showBanner(
                    "Please fill Full Name, Password and Email before verification.",
                    ContentType.warning,
                    setStateDialog,
                  );
                  return;
                }

                setStateDialog(() => isSendingCode = true);
                try {
                  final data = {
                    'fullName': name,
                    'email': email,
                    'phone': phoneController.text.trim(),
                    'city': cityController.text.trim(),
                    'state': stateController.text.trim(),
                    'role': role,
                    'password': pwd,
                    if (birthDateController.text.trim().isNotEmpty)
                      'birthDate': birthDateController.text.trim(),
                  };

                  final init = await _registerInit(data, selectedImage);
                  tempId = init['tempId'] as String?;
                  final expiresInSec =
                      (init['expiresInSec'] as num?)?.toInt() ?? 600;

                  otpController.clear();
                  startTimer(expiresInSec, setStateDialog);

                  showBanner(
                    "OTP sent to $email",
                    ContentType.success,
                    setStateDialog,
                  );
                } catch (e) {
                  showBanner(e.toString(), ContentType.failure, setStateDialog);
                } finally {
                  setStateDialog(() => isSendingCode = false);
                }
              }

              Future<void> verifyCode() async {
                if (emailVerified) return;

                final code = otpController.text.trim();
                final email = emailController.text.trim();
                if (code.length != 6) {
                  showBanner(
                    "Enter the 6-digit code.",
                    ContentType.warning,
                    setStateDialog,
                  );
                  return;
                }
                if (tempId == null) return;

                setStateDialog(() => isVerifying = true);
                try {
                  await _registerVerify(tempId!, email, code);
                  emailVerified = true;
                  ticker?.dispose();
                  setStateDialog(() {});
                  final prefs = await SharedPreferences.getInstance();
                  final token = _cleanToken(prefs.getString('auth_token'));
                  await fetchTeamMembers(token);
                  showBanner(
                    "Member added & email verified.",
                    ContentType.success,
                    setStateDialog,
                  );
                } catch (e) {
                  showBanner(e.toString(), ContentType.failure, setStateDialog);
                } finally {
                  setStateDialog(() => isVerifying = false);
                }
              }

              Future<void> resendCode() async {
                if (!canResend || tempId == null) return;
                try {
                  await _registerResendOtp(
                    tempId!,
                    emailController.text.trim(),
                  );
                  startTimer(600, setStateDialog);
                  showBanner(
                    "OTP resent. Check your inbox.",
                    ContentType.success,
                    setStateDialog,
                  );
                } catch (e) {
                  showBanner(e.toString(), ContentType.failure, setStateDialog);
                }
              }

              Widget buildBanner() {
                if (bannerMsg == null || bannerType == null)
                  return const SizedBox.shrink();
                Color bg, border;
                IconData icon;
                switch (bannerType!) {
                  case ContentType.success:
                    bg = Colors.green.shade50;
                    border = Colors.green.shade200;
                    icon = Icons.check_circle;
                    break;
                  case ContentType.failure:
                    bg = Colors.red.shade50;
                    border = Colors.red.shade200;
                    icon = Icons.error_outline;
                    break;
                  case ContentType.warning:
                  default:
                    bg = Colors.orange.shade50;
                    border = Colors.orange.shade200;
                    icon = Icons.warning_amber_rounded;
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bg,
                    border: Border.all(color: border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(icon, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          bannerMsg!,
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => setStateDialog(() {
                          bannerMsg = null;
                          bannerType = null;
                        }),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                );
              }

              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: maxHeight,
                  maxWidth: maxWidth,
                ),
                child: SizedBox(
                  height: maxHeight * 0.95,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              "Add New Member",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryColor,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.brown,
                              ),
                              onPressed: () {
                                ticker?.dispose();
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Divider(color: Colors.brown),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 6),
                            buildBanner(),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              child: emailVerified
                                  ? Container(
                                      key: const ValueKey('ok'),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                        horizontal: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.green.shade200,
                                        ),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.verified_rounded,
                                            color: Colors.green,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            "Email verified",
                                            style: TextStyle(
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  : const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () async {
                                    final picker = ImagePicker();
                                    final picked = await picker.pickImage(
                                      source: ImageSource.gallery,
                                    );
                                    if (picked != null)
                                      setStateDialog(
                                        () => selectedImage = File(picked.path),
                                      );
                                  },
                                  child: selectedImage == null
                                      ? Container(
                                          width: double.infinity,
                                          height: 120,
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.brown.shade200,
                                            ),
                                          ),
                                          child: const Center(
                                            child: Text(
                                              "Select Member Photo",
                                              style: TextStyle(
                                                color: Colors.brown,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        )
                                      : Stack(
                                          children: [
                                            Container(
                                              width: double.infinity,
                                              height: 120,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                image: DecorationImage(
                                                  image: FileImage(
                                                    selectedImage!,
                                                  ),
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 6,
                                              right: 6,
                                              child: GestureDetector(
                                                onTap: () => setStateDialog(
                                                  () => selectedImage = null,
                                                ),
                                                child: Container(
                                                  decoration:
                                                      const BoxDecoration(
                                                        color: Colors.white,
                                                        shape: BoxShape.circle,
                                                      ),
                                                  padding: const EdgeInsets.all(
                                                    4,
                                                  ),
                                                  child: const Icon(
                                                    Icons.close,
                                                    color: Colors.brown,
                                                    size: 20,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                                const SizedBox(height: 16),
                                _buildTextField(
                                  fullNameController,
                                  "Full Name",
                                  Icons.person,
                                ),
                                _buildTextField(
                                  passwordController,
                                  "Password",
                                  Icons.lock,
                                  obscure: true,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: emailController,
                                        readOnly: emailVerified,
                                        decoration: InputDecoration(
                                          prefixIcon: const Icon(
                                            Icons.email,
                                            color: Colors.brown,
                                          ),
                                          labelText: emailVerified
                                              ? "Email (verified)"
                                              : "Email",
                                          labelStyle: const TextStyle(
                                            color: Colors.brown,
                                          ),
                                          filled: true,
                                          fillColor: emailVerified
                                              ? Colors.brown.shade50
                                              : Colors.white,
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: BorderSide(
                                              color: AppColors.primaryColor,
                                              width: 1.5,
                                            ),
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            borderSide: const BorderSide(
                                              color: Colors.brown,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primaryColor,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 14,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      onPressed:
                                          (emailVerified || isSendingCode)
                                          ? null
                                          : sendCode,
                                      child: isSendingCode
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Text(
                                              "Send Code",
                                              style: TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                    ),
                                  ],
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: (tempId != null && !emailVerified)
                                      ? Column(
                                          key: const ValueKey('otpSection'),
                                          children: [
                                            const SizedBox(height: 14),
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade50,
                                                border: Border.all(
                                                  color: Colors.orange.shade200,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    "Email Verification",
                                                    style: TextStyle(
                                                      color: Colors.brown,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  Text(
                                                    "Enter the 6-digit code sent to ${emailController.text.trim()}",
                                                    style: const TextStyle(
                                                      color: Colors.brown,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                  TextField(
                                                    controller: otpController,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    maxLength: 6,
                                                    textAlign: TextAlign.center,
                                                    decoration: InputDecoration(
                                                      counterText: "",
                                                      hintText: "Enter OTP",
                                                      filled: true,
                                                      fillColor: Colors.white,
                                                      border: OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      focusedBorder:
                                                          OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            borderSide: BorderSide(
                                                              color: AppColors
                                                                  .primaryColor,
                                                              width: 1.5,
                                                            ),
                                                          ),
                                                    ),
                                                    onSubmitted: (_) =>
                                                        verifyCode(),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: OutlinedButton.icon(
                                                          onPressed: canResend
                                                              ? resendCode
                                                              : null,
                                                          icon: const Icon(
                                                            Icons.refresh,
                                                          ),
                                                          label: Text(
                                                            canResend
                                                                ? "Resend Code"
                                                                : "Resend in ${mmss(secondsLeft)}",
                                                          ),
                                                          style: OutlinedButton.styleFrom(
                                                            foregroundColor:
                                                                Colors.brown,
                                                            side:
                                                                const BorderSide(
                                                                  color: Colors
                                                                      .brown,
                                                                ),
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 12,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 12),
                                                      Expanded(
                                                        child: ElevatedButton.icon(
                                                          onPressed: isVerifying
                                                              ? null
                                                              : verifyCode,
                                                          icon: isVerifying
                                                              ? const SizedBox(
                                                                  width: 18,
                                                                  height: 18,
                                                                  child: CircularProgressIndicator(
                                                                    strokeWidth:
                                                                        2,
                                                                    color: Colors
                                                                        .white,
                                                                  ),
                                                                )
                                                              : const Icon(
                                                                  Icons
                                                                      .verified_user,
                                                                  color: Colors
                                                                      .white,
                                                                ),
                                                          label: const Text(
                                                            "Verify",
                                                            style: TextStyle(
                                                              color:
                                                                  Colors.white,
                                                            ),
                                                          ),
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                AppColors
                                                                    .primaryColor,
                                                            padding:
                                                                const EdgeInsets.symmetric(
                                                                  vertical: 12,
                                                                ),
                                                            shape: RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                const SizedBox(height: 18),
                                _buildTextField(
                                  phoneController,
                                  "Phone",
                                  Icons.phone,
                                ),
                                _buildTextField(
                                  cityController,
                                  "City",
                                  Icons.location_city,
                                ),
                                _buildTextField(
                                  stateController,
                                  "State",
                                  Icons.map,
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: TextField(
                                    controller: birthDateController,
                                    readOnly: true,
                                    onTap: () => _pickDate(
                                      context: context,
                                      controller: birthDateController,
                                    ),
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(
                                        Icons.cake,
                                        color: Colors.brown,
                                      ),
                                      labelText: "Birth Date (optional)",
                                      hintText: "YYYY-MM-DD",
                                      labelStyle: const TextStyle(
                                        color: Colors.brown,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: AppColors.primaryColor,
                                          width: 1.5,
                                        ),
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(
                                          color: Colors.brown,
                                        ),
                                      ),
                                      suffixIcon: IconButton(
                                        icon: const Icon(
                                          Icons.calendar_today,
                                          color: Colors.brown,
                                        ),
                                        onPressed: () => _pickDate(
                                          context: context,
                                          controller: birthDateController,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                DropdownButtonFormField<String>(
                                  value: role,
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(
                                      Icons.work_outline,
                                      color: Colors.brown,
                                    ),
                                    labelText: "Role",
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                      value: "SUPER_ADMIN",
                                      child: Text("Super Admin"),
                                    ),
                                    DropdownMenuItem(
                                      value: "ADMIN",
                                      child: Text("Admin"),
                                    ),
                                    DropdownMenuItem(
                                      value: "TEAM_MEMBER",
                                      child: Text("Team Member"),
                                    ),
                                    DropdownMenuItem(
                                      value: "CLIENT",
                                      child: Text("Client"),
                                    ),
                                  ],
                                  onChanged: emailVerified
                                      ? (v) => role = v!
                                      : null,
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () {
                                  ticker?.dispose();
                                  Navigator.pop(context);
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.brown,
                                  side: const BorderSide(color: Colors.brown),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text("Cancel"),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: emailVerified
                                      ? AppColors.primaryColor
                                      : Colors.brown.shade300,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: !emailVerified
                                    ? null
                                    : () {
                                        ticker?.dispose();
                                        Navigator.pop(context);
                                      },
                                icon: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                ),
                                label: const Text(
                                  "Finish",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    ).then((_) {
      ticker?.dispose();
    });
  }

  void _showEditMemberDialog(dynamic member) {
    final fullNameController = TextEditingController(text: member['fullName']);
    final emailController = TextEditingController(text: member['email']);
    final phoneController = TextEditingController(text: member['phone']);
    final cityController = TextEditingController(text: member['city']);
    final stateController = TextEditingController(text: member['state']);
    final passwordController = TextEditingController();
    final birthDateController = TextEditingController(
      text: _isoToYMD(member['birthDate']),
    );
    String role = member['role'] ?? "TEAM_MEMBER";
    File? selectedImage;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: const Color(0xFFFDF6EE),
          insetPadding: const EdgeInsets.all(16),
          child: StatefulBuilder(
            builder: (context, setStateDialog) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            "Edit Member",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryColor,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.brown),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.brown),
                      GestureDetector(
                        onTap: () async {
                          final picker = ImagePicker();
                          final picked = await picker.pickImage(
                            source: ImageSource.gallery,
                          );
                          if (picked != null)
                            setStateDialog(
                              () => selectedImage = File(picked.path),
                            );
                        },
                        child: selectedImage == null
                            ? CircleAvatar(
                                radius: 50,
                                backgroundImage:
                                    (member['avatarUrl'] != null &&
                                        (member['avatarUrl'] as String)
                                            .isNotEmpty)
                                    ? NetworkImage(member['avatarUrl'])
                                    : const AssetImage('assets/user.jpg')
                                          as ImageProvider,
                              )
                            : CircleAvatar(
                                radius: 50,
                                backgroundImage: FileImage(selectedImage!),
                              ),
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        fullNameController,
                        "Full Name",
                        Icons.person,
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: emailController,
                          readOnly: true,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.email,
                              color: Colors.brown,
                            ),
                            labelText: "Email (read-only)",
                            labelStyle: const TextStyle(color: Colors.brown),
                            filled: true,
                            fillColor: Colors.brown.shade50,
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: Colors.brown.shade300,
                                width: 1.5,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.brown),
                            ),
                          ),
                        ),
                      ),
                      _buildTextField(phoneController, "Phone", Icons.phone),
                      _buildTextField(
                        cityController,
                        "City",
                        Icons.location_city,
                      ),
                      _buildTextField(stateController, "State", Icons.map),
                      _buildTextField(
                        passwordController,
                        "New Password (optional)",
                        Icons.lock,
                        obscure: true,
                      ),
                      DropdownButtonFormField<String>(
                        value: role,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(
                            Icons.work_outline,
                            color: Colors.brown,
                          ),
                          labelText: "Role",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: "SUPER_ADMIN",
                            child: Text("Super Admin"),
                          ),
                          DropdownMenuItem(
                            value: "ADMIN",
                            child: Text("Admin"),
                          ),
                          DropdownMenuItem(
                            value: "TEAM_MEMBER",
                            child: Text("Team Member"),
                          ),
                          DropdownMenuItem(
                            value: "CLIENT",
                            child: Text("Client"),
                          ),
                        ],
                        onChanged: (v) => role = v!,
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: birthDateController,
                          readOnly: true,
                          onTap: () => _pickDate(
                            context: context,
                            controller: birthDateController,
                          ),
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.cake,
                              color: Colors.brown,
                            ),
                            labelText: "Birth Date (optional)",
                            hintText: "YYYY-MM-DD",
                            labelStyle: const TextStyle(color: Colors.brown),
                            filled: true,
                            fillColor: Colors.white,
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColors.primaryColor,
                                width: 1.5,
                              ),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.brown),
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(
                                Icons.calendar_today,
                                color: Colors.brown,
                              ),
                              onPressed: () => _pickDate(
                                context: context,
                                controller: birthDateController,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              final id = (member['_id'] ?? member['id'])
                                  .toString();
                              _showDeleteConfirmationDialog(
                                id,
                                member['fullName'] ?? 'this member',
                              );
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                            ),
                            label: const Text(
                              "Delete",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                            ),
                            onPressed: () {
                              final id = (member['_id'] ?? member['id'])
                                  .toString();
                              final data = {
                                'fullName': fullNameController.text.trim(),
                                'phone': phoneController.text.trim(),
                                'city': cityController.text.trim(),
                                'state': stateController.text.trim(),
                                'role': role,
                                'birthDate': birthDateController.text.trim(),
                              };
                              if (passwordController.text.trim().isNotEmpty) {
                                data['password'] = passwordController.text
                                    .trim();
                              }
                              Navigator.pop(context);
                              updateMember(id, data, selectedImage);
                            },
                            icon: const Icon(Icons.check, color: Colors.white),
                            label: const Text(
                              "Update",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTextField(
    TextEditingController c,
    String hint,
    IconData icon, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: obscure,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.brown),
          labelText: hint,
          labelStyle: const TextStyle(color: Colors.brown),
          filled: true,
          fillColor: Colors.white,
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primaryColor, width: 1.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.brown),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate({
    required BuildContext context,
    required TextEditingController controller,
  }) async {
    final initial = _tryParseYMD(controller.text) ?? DateTime(1995, 1, 1);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      helpText: "Select Birth Date",
    );
    if (picked != null) controller.text = _fmtYMD(picked);
  }
}

class _SimpleTicker {
  final void Function(Duration elapsed) onTick;
  bool _active = false;
  Duration _elapsed = Duration.zero;

  _SimpleTicker(this.onTick);

  bool get isActive => _active;

  void start() {
    _active = true;
    _loop();
  }

  Future<void> _loop() async {
    while (_active) {
      await Future.delayed(const Duration(seconds: 1));
      if (!_active) break;
      _elapsed += const Duration(seconds: 1);
      onTick(_elapsed);
    }
  }

  void dispose() {
    _active = false;
  }
}

// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
// import 'package:flutter/material.dart';
// import 'package:image_picker/image_picker.dart';
// import 'package:http/http.dart' as http;
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:rudhram_frontend/utils/custom_bottom_nav.dart';
// import '../utils/constants.dart';
// import '../widgets/background_container.dart';
// import '../utils/api_config.dart';
// import '../utils/snackbar_helper.dart';
// import '../widgets/profile_header.dart';
// import 'package:shimmer/shimmer.dart';
// import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

// class TeamMemberScreen extends StatefulWidget {
//   const TeamMemberScreen({super.key});

//   @override
//   State<TeamMemberScreen> createState() => _TeamMemberScreenState();
// }

// class _TeamMemberScreenState extends State<TeamMemberScreen> {
//   Map<String, dynamic>? userData;
//   List<dynamic> teamMembers = [];
//   bool isLoading = true;
//   bool showAll = false;
//   // --- add near your other state fields ---
//   final ScrollController _teamRowController = ScrollController();
//   Timer? _autoScrollTimer;
//   double _autoDir = 1; // 1 = forward (right), -1 = back (left)
//   @override
//   void initState() {
//     super.initState();
//     fetchAllData().then((_) {
//     if (mounted && !showAll && teamMembers.length > 1) {
//       _startAutoScrollRow();
//     }
//   });
//   }

//   // ---------- Helpers ----------
//   String _cleanToken(String? token) {
//     if (token == null) return '';
//     return token.startsWith('Bearer ')
//         ? token.substring('Bearer '.length).trim()
//         : token.trim();
//   }

//   Future<void> _showErrorSnack(
//     dynamic body, {
//     String fallback = "Request failed",
//   }) async {
//     try {
//       final b = body is String ? jsonDecode(body) : body;
//       final msg = (b?['message'] ?? b?['error'] ?? b?['msg'] ?? fallback)
//           .toString();
//       if (!mounted) return;
//       ScaffoldMessenger.of(
//         context,
//       ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
//     } catch (_) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text(fallback), backgroundColor: Colors.red),
//       );
//     }
//   }

//   // ---------- Fetch All ----------
//   Future<void> fetchAllData() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final raw = prefs.getString('auth_token');
//       if (raw == null) {
//         if (!mounted) return;
//         ScaffoldMessenger.of(context).showSnackBar(
//           const SnackBar(
//             content: Text("Not logged in"),
//             backgroundColor: Colors.red,
//           ),
//         );
//         return;
//       }
//       final token = _cleanToken(raw);

//       await Future.wait([fetchUser(token), fetchTeamMembers(token)]);
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text("Failed to load: $e"),
//           backgroundColor: Colors.red,
//         ),
//       );
//     } finally {
//       if (mounted) setState(() => isLoading = false);
//     }
//   }

//   String formatUserRole(String? role) {
//     if (role == null) return '';
//     switch (role.toUpperCase()) {
//       case 'SUPER_ADMIN':
//         return 'Super Admin';
//       case 'ADMIN':
//         return 'Admin';
//       case 'TEAM_MEMBER':
//         return 'Team Member';
//       case 'CLIENT':
//         return 'Client';
//       default:
//         return role;
//     }
//   }

//   Future<void> fetchUser(String token) async {
//     try {
//       final res = await http.get(
//         Uri.parse("${ApiConfig.baseUrl}/user/me"),
//         headers: {"Authorization": "Bearer $token"},
//       );
//       if (res.statusCode == 200) {
//         final data = jsonDecode(res.body);
//         final u = Map<String, dynamic>.from(data['user'] ?? {});
//         if (u['avatarUrl'] != null &&
//             u['avatarUrl'].toString().startsWith('/')) {
//           u['avatarUrl'] = _absUrl(u['avatarUrl']);
//         }
//         if (mounted) setState(() => userData = u);
//       } else {
//         await _showErrorSnack(res.body, fallback: "Failed to fetch user");
//       }
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text("User load error: $e"),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   String _absUrl(String? maybeRelative) {
//     if (maybeRelative == null || maybeRelative.isEmpty) return '';
//     if (maybeRelative.startsWith('http')) return maybeRelative;

//     if (maybeRelative.startsWith('/uploads')) {
//       return "${ApiConfig.imageBaseUrl}$maybeRelative";
//     }
//     return "${ApiConfig.baseUrl}$maybeRelative";
//   }

//   Future<void> fetchTeamMembers(String token) async {
//     try {
//       final res = await http.get(
//         Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
//         headers: {"Authorization": "Bearer $token"},
//       );
//       if (res.statusCode == 200) {
//         final data = jsonDecode(res.body);
//         final List<dynamic> members = List<dynamic>.from(
//           data['teamMembers'] ?? [],
//         );
//         // normalize avatar URLs
//         for (final m in members) {
//           if (m['avatarUrl'] != null &&
//               m['avatarUrl'].toString().startsWith('/')) {
//             m['avatarUrl'] = _absUrl(m['avatarUrl']);
//           }
//         }

//         if (mounted) setState(() => teamMembers = members);
//       } else {
//         await _showErrorSnack(
//           res.body,
//           fallback: "Failed to fetch team members",
//         );
//       }
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text("Team load error: $e"),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   // ---------- OTP API HELPERS ----------
//   Future<Map<String, dynamic>> _registerInit(
//     Map<String, dynamic> data,
//     File? avatarFile,
//   ) async {
//     final prefs = await SharedPreferences.getInstance();
//     final token = _cleanToken(prefs.getString('auth_token'));
//     if (token.isEmpty) throw Exception("Not logged in");

//     final uri = Uri.parse("${ApiConfig.baseUrl}/user/register-init");
//     final req = http.MultipartRequest('POST', uri)
//       ..headers['Authorization'] = "Bearer $token";

//     data.forEach((k, v) {
//       if (v != null && v.toString().isNotEmpty) req.fields[k] = v.toString();
//     });

//     if (avatarFile != null) {
//       req.files.add(
//         await http.MultipartFile.fromPath('avatar', avatarFile.path),
//       );
//     }

//     final resp = await req.send();
//     final body = await resp.stream.bytesToString();
//     final json = jsonDecode(body);
//     if (resp.statusCode == 200 && json['success'] == true) {
//       return json; // {success, message, tempId, expiresInSec}
//     } else {
//       throw Exception(json['message'] ?? 'Failed to start registration');
//     }
//   }

//   Future<void> _registerVerify(String tempId, String email, String otp) async {
//     final prefs = await SharedPreferences.getInstance();
//     final token = _cleanToken(prefs.getString('auth_token'));
//     if (token.isEmpty) throw Exception("Not logged in");

//     final res = await http.post(
//       Uri.parse("${ApiConfig.baseUrl}/user/register-verify"),
//       headers: {
//         "Authorization": "Bearer $token",
//         "Content-Type": "application/json",
//       },
//       body: jsonEncode({"tempId": tempId, "email": email, "otp": otp}),
//     );

//     final data = jsonDecode(res.body);
//     if (res.statusCode != 201 || data['success'] != true) {
//       throw Exception(data['message'] ?? 'Verification failed');
//     }
//   }

//   Future<void> _registerResendOtp(String tempId, String email) async {
//     final prefs = await SharedPreferences.getInstance();
//     final token = _cleanToken(prefs.getString('auth_token'));
//     if (token.isEmpty) throw Exception("Not logged in");

//     final res = await http.post(
//       Uri.parse("${ApiConfig.baseUrl}/user/register-resend-otp"),
//       headers: {
//         "Authorization": "Bearer $token",
//         "Content-Type": "application/json",
//       },
//       body: jsonEncode({"tempId": tempId, "email": email}),
//     );

//     final data = jsonDecode(res.body);
//     if (res.statusCode != 200 || data['success'] != true) {
//       throw Exception(data['message'] ?? 'Resend failed');
//     }
//   }

//   // ---------- CRUD ----------
//   Future<void> deleteMember(String id) async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final token = _cleanToken(prefs.getString('auth_token'));
//       if (token.isEmpty) return;

//       final res = await http.delete(
//         Uri.parse("${ApiConfig.baseUrl}/user/team-members/$id"),
//         headers: {"Authorization": "Bearer $token"},
//       );

//       if (res.statusCode == 200) {
//         setState(() {
//           teamMembers.removeWhere((m) => m['_id'] == id);
//         });

//         SnackbarHelper.show(
//           context,
//           title: 'Success',
//           message: 'Member deleted successfully',
//           type: ContentType.success,
//         );
//       } else {
//         await _showErrorSnack(res.body, fallback: "Failed to delete member");
//       }
//     } catch (e) {
//       SnackbarHelper.show(
//         context,
//         title: 'Error',
//         message: "Delete error: $e",
//         type: ContentType.failure,
//       );
//     }
//   }

//   Future<void> updateMember(
//     String id,
//     Map<String, dynamic> updateData,
//     File? avatarFile,
//   ) async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final token = _cleanToken(prefs.getString('auth_token'));
//       if (token.isEmpty) return;

//       final uri = Uri.parse("${ApiConfig.baseUrl}/user/team-members/$id");
//       final req = http.MultipartRequest('PUT', uri)
//         ..headers['Authorization'] = "Bearer $token";

//       updateData.forEach((k, v) {
//         if (v != null) req.fields[k] = v.toString();
//       });
//       if (avatarFile != null) {
//         req.files.add(
//           await http.MultipartFile.fromPath('avatar', avatarFile.path),
//         );
//       }

//       final resp = await req.send();
//       final body = await resp.stream.bytesToString();

//       if (resp.statusCode == 200) {
//         SnackbarHelper.show(
//           context,
//           title: 'Success',
//           message: 'Member updated successfully',
//           type: ContentType.success,
//         );
//         await fetchTeamMembers(token);
//       } else {
//         SnackbarHelper.show(
//           context,
//           title: 'Error',
//           message: 'Failed to update member',
//           type: ContentType.failure,
//         );
//       }
//     } catch (e) {
//       if (!mounted) return;
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text("Update error: $e"),
//           backgroundColor: Colors.red,
//         ),
//       );
//     }
//   }

//   /// (Kept for compatibility; not used by the new inline flow.)
//   Future<void> addMember(Map<String, dynamic> newData, File? avatarFile) async {
//     try {
//       final init = await _registerInit(newData, avatarFile);
//       final tempId = init['tempId'] as String;
//       final expiresInSec = (init['expiresInSec'] as num?)?.toInt() ?? 600;

//       if (!mounted) return;
//       await _showOtpDialog(
//         email: newData['email'],
//         tempId: tempId,
//         expiresIn: Duration(seconds: expiresInSec),
//         onVerified: () async {
//           final prefs = await SharedPreferences.getInstance();
//           final token = _cleanToken(prefs.getString('auth_token'));
//           await fetchTeamMembers(token);
//           SnackbarHelper.show(
//             context,
//             title: 'Success',
//             message: 'Member added & verified.',
//             type: ContentType.success,
//           );
//         },
//       );
//     } catch (e) {
//       if (!mounted) return;
//       SnackbarHelper.show(
//         context,
//         title: 'Error',
//         message: e.toString(),
//         type: ContentType.failure,
//       );
//     }
//   }

//   // ---------- Delete Confirmation Dialog ----------
//   Future<void> _showDeleteConfirmationDialog(
//     String memberId,
//     String memberName,
//   ) async {
//     return showDialog(
//       context: context,
//       builder: (BuildContext context) {
//         return Dialog(
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(20.0),
//           ),
//           backgroundColor: const Color(0xFFFDF6EE),
//           child: Container(
//             padding: const EdgeInsets.all(24),
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Container(
//                   width: 80,
//                   height: 80,
//                   decoration: BoxDecoration(
//                     color: Colors.red.shade50,
//                     shape: BoxShape.circle,
//                   ),
//                   child: Icon(
//                     Icons.warning_rounded,
//                     size: 40,
//                     color: Colors.red.shade600,
//                   ),
//                 ),
//                 const SizedBox(height: 20),
//                 Text(
//                   'Delete Team Member',
//                   style: TextStyle(
//                     fontSize: 20,
//                     fontWeight: FontWeight.bold,
//                     color: Colors.red.shade700,
//                   ),
//                 ),
//                 const SizedBox(height: 12),
//                 Text(
//                   'Are you sure you want to delete "$memberName"?',
//                   textAlign: TextAlign.center,
//                   style: const TextStyle(fontSize: 16, color: Colors.brown),
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   'This action cannot be undone.',
//                   textAlign: TextAlign.center,
//                   style: TextStyle(
//                     fontSize: 14,
//                     color: Colors.red.shade600,
//                     fontWeight: FontWeight.w500,
//                   ),
//                 ),
//                 const SizedBox(height: 24),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: OutlinedButton(
//                         style: OutlinedButton.styleFrom(
//                           foregroundColor: Colors.brown,
//                           side: const BorderSide(color: Colors.brown),
//                           padding: const EdgeInsets.symmetric(vertical: 12),
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                         ),
//                         onPressed: () => Navigator.of(context).pop(),
//                         child: const Text(
//                           'Cancel',
//                           style: TextStyle(fontWeight: FontWeight.w600),
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 12),
//                     Expanded(
//                       child: ElevatedButton(
//                         style: ElevatedButton.styleFrom(
//                           backgroundColor: Colors.red.shade600,
//                           foregroundColor: Colors.white,
//                           padding: const EdgeInsets.symmetric(vertical: 12),
//                           shape: RoundedRectangleBorder(
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                           elevation: 2,
//                         ),
//                         onPressed: () {
//                           Navigator.of(context).pop();
//                           deleteMember(memberId);
//                         },
//                         child: const Row(
//                           mainAxisAlignment: MainAxisAlignment.center,
//                           children: [
//                             Icon(Icons.delete_outline, size: 18),
//                             SizedBox(width: 6),
//                             Text(
//                               'Delete',
//                               style: TextStyle(fontWeight: FontWeight.w600),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         );
//       },
//     );
//   }

//   void _startAutoScrollRow() {
//     _autoScrollTimer?.cancel();
//     if (!mounted) return;
//     // Don't scroll if few items or controller not attached yet
//     _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 30), (_) {
//       if (!_teamRowController.hasClients) return;
//       final max = _teamRowController.position.maxScrollExtent;
//       final min = _teamRowController.position.minScrollExtent;
//       var next = _teamRowController.offset + (0.6 * _autoDir); // speed

//       if (next >= max) {
//         next = max;
//         _autoDir = -1; // bounce
//       } else if (next <= min) {
//         next = min;
//         _autoDir = 1;
//       }
//       _teamRowController.jumpTo(next);
//     });
//   }

//   void _stopAutoScrollRow() {
//     _autoScrollTimer?.cancel();
//     _autoScrollTimer = null;
//   }

//   // ---------- UI ----------
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: BackgroundContainer(
//         child: SafeArea(
//           child: isLoading
//               ? const Center(
//                   child: CircularProgressIndicator(color: Colors.brown),
//                 )
//               : Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     ProfileHeader(
//                       avatarUrl: userData?['avatarUrl'],
//                       fullName: userData?['fullName'],
//                       role: formatUserRole(userData?['role']),
//                       showBackButton: true,
//                       onBack: () => Navigator.pop(context),
//                     ),
//                     const SizedBox(height: 10),
//                     Expanded(
//                       child: showAll
//                           ? _buildGridView(teamMembers)
//                           : _buildTeamRow(teamMembers),
//                     ),
//                     _buildViewAllButton(),
//                     const SizedBox(height: 20),
//                     _buildAddMemberButton(),
//                     const SizedBox(height: 25),
//                     CustomBottomNavBar(
//                       currentIndex: 4,
//                       onTap: (i) {},
//                       userRole: userData?['role'] ?? '',
//                     ),
//                   ],
//                 ),
//         ),
//       ),
//     );
//   }

//   Widget _buildTeamRow(List<dynamic> members) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 12),
//       child: SizedBox(
//         height: 140, // taller to fit card + badge cleanly
//         child: ListView.separated(
//           scrollDirection: Axis.horizontal,
//           itemCount: members.length,
//           separatorBuilder: (_, __) => const SizedBox(width: 14),
//           itemBuilder: (context, i) {
//             final m = members[i];
//             final avatar =
//                 (m['avatarUrl'] != null &&
//                     (m['avatarUrl'] as String).isNotEmpty)
//                 ? NetworkImage(m['avatarUrl'])
//                 : const AssetImage('assets/user.jpg') as ImageProvider;

//             return GestureDetector(
//               onTap: () => _showEditMemberDialog(m),
//               child: Container(
//                 width: 150,
//                 padding: const EdgeInsets.all(10),
//                 decoration: BoxDecoration(
//                   color: Colors.white,
//                   borderRadius: BorderRadius.circular(14),
//                   boxShadow: [
//                     BoxShadow(
//                       color: Colors.black.withOpacity(0.06),
//                       blurRadius: 8,
//                       offset: const Offset(0, 3),
//                     ),
//                   ],
//                   border: Border.all(color: Colors.brown.shade100),
//                 ),
//                 child: Column(
//                   mainAxisAlignment: MainAxisAlignment.center,
//                   children: [
//                     Stack(
//                       clipBehavior: Clip.none,
//                       children: [
//                         CircleAvatar(radius: 28, backgroundImage: avatar),
//                         Positioned(
//                           right: -2,
//                           bottom: -2,
//                           child: Container(
//                             padding: const EdgeInsets.symmetric(
//                               horizontal: 6,
//                               vertical: 2,
//                             ),
//                             decoration: BoxDecoration(
//                               color: Colors.white,
//                               borderRadius: BorderRadius.circular(10),
//                               border: Border.all(color: Colors.brown.shade200),
//                             ),
//                             child: _roleBadge(m['role']),
//                           ),
//                         ),
//                       ],
//                     ),
//                     const SizedBox(height: 8),
//                     Text(
//                       (m['fullName'] ?? '').toString(),
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: const TextStyle(
//                         fontSize: 13,
//                         fontWeight: FontWeight.w600,
//                         color: Colors.brown,
//                       ),
//                     ),
//                     const SizedBox(height: 2),
//                     Text(
//                       (m['email'] ?? '').toString(),
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: TextStyle(
//                         fontSize: 11,
//                         color: Colors.brown.shade400,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             );
//           },
//         ),
//       ),
//     );
//   }

//   Widget _roleBadge(dynamic roleRaw) {
//     final role = (roleRaw ?? '').toString().toUpperCase();
//     String text;
//     Color dot;
//     switch (role) {
//       case 'SUPER_ADMIN':
//         text = 'Super';
//         dot = Colors.redAccent;
//         break;
//       case 'ADMIN':
//         text = 'Admin';
//         dot = Colors.orangeAccent;
//         break;
//       case 'TEAM_MEMBER':
//         text = 'Team';
//         dot = Colors.green;
//         break;
//       case 'CLIENT':
//         text = 'Client';
//         dot = Colors.blueAccent;
//         break;
//       default:
//         text = role.isEmpty ? '—' : role;
//         dot = Colors.grey;
//     }
//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         Container(
//           width: 6,
//           height: 6,
//           decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
//         ),
//         const SizedBox(width: 4),
//         Text(
//           text,
//           style: const TextStyle(
//             fontSize: 10,
//             fontWeight: FontWeight.w600,
//             color: Colors.brown,
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildGridView(List<dynamic> members) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: GridView.builder(
//         itemCount: members.length,
//         gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
//           crossAxisCount: 2,
//           childAspectRatio: 0.9,
//           crossAxisSpacing: 16,
//           mainAxisSpacing: 16,
//         ),
//         itemBuilder: (context, i) {
//           final m = members[i];
//           return GestureDetector(
//             onTap: () => _showEditMemberDialog(m),
//             child: Column(
//               children: [
//                 CircleAvatar(
//                   radius: 40,
//                   backgroundImage:
//                       (m['avatarUrl'] != null &&
//                           (m['avatarUrl'] as String).isNotEmpty)
//                       ? NetworkImage(m['avatarUrl'])
//                       : const AssetImage('assets/user.jpg') as ImageProvider,
//                 ),
//                 const SizedBox(height: 8),
//                 Text(
//                   m['fullName'] ?? '',
//                   style: const TextStyle(
//                     fontSize: 13,
//                     fontWeight: FontWeight.w600,
//                     color: Colors.brown,
//                   ),
//                 ),
//               ],
//             ),
//           );
//         },
//       ),
//     );
//   }

//   Widget _buildViewAllButton() {
//     return Padding(
//       padding: const EdgeInsets.only(right: 16, top: 8),
//       child: Align(
//         alignment: Alignment.centerRight,
//         child: GestureDetector(
//           onTap: () => setState(() => showAll = !showAll),
//           child: Text(
//             showAll ? "View Less" : "View All",
//             style: const TextStyle(
//               color: Colors.blueAccent,
//               fontWeight: FontWeight.w500,
//               fontSize: 13,
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildAddMemberButton() {
//     return Center(
//       child: ElevatedButton.icon(
//         style: ElevatedButton.styleFrom(
//           backgroundColor: AppColors.primaryColor,
//           padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(12),
//           ),
//           elevation: 5,
//         ),
//         icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
//         label: const Text(
//           "Add Member",
//           style: TextStyle(
//             color: Colors.white,
//             fontWeight: FontWeight.bold,
//             fontSize: 16,
//           ),
//         ),
//         onPressed: () => _showAddMemberDialog(context),
//       ),
//     );
//   }

//   // ---------- Dialogs ----------
//   /// NEW: inline OTP flow inside the Add Member popup (no external OTP dialog)
//   // ---------- Dialogs ----------
//   // ---------- Dialogs ----------
//   void _showAddMemberDialog(BuildContext context) {
//     final fullNameController = TextEditingController();
//     final emailController = TextEditingController();
//     final phoneController = TextEditingController();
//     final cityController = TextEditingController();
//     final stateController = TextEditingController();
//     final passwordController = TextEditingController();
//     String role = "TEAM_MEMBER";
//     File? selectedImage;

//     // OTP stage state
//     String? tempId; // set after /register-init
//     int secondsLeft = 0;
//     bool canResend = false;
//     bool isSendingCode = false;
//     bool isVerifying = false;
//     bool emailVerified = false;
//     final otpController = TextEditingController();
//     _SimpleTicker? ticker;

//     // Inline banner (fixed at top of dialog)
//     String? bannerMsg;
//     ContentType? bannerType; // success / failure / warning
//     void showBanner(
//       String msg,
//       ContentType type,
//       void Function(void Function()) setStateDialog,
//     ) {
//       setStateDialog(() {
//         bannerMsg = msg;
//         bannerType = type;
//       });
//     }

//     String mmss(int s) {
//       final m = (s ~/ 60).toString().padLeft(2, '0');
//       final ss = (s % 60).toString().padLeft(2, '0');
//       return "$m:$ss";
//     }

//     void startTimer(int s, void Function(void Function()) setStateDialog) {
//       secondsLeft = s;
//       canResend = false;
//       ticker?.dispose();
//       ticker = _SimpleTicker((_) {
//         if (!mounted) return;
//         setStateDialog(() {
//           if (secondsLeft > 0) secondsLeft -= 1;
//           if (secondsLeft <= 0) canResend = true;
//         });
//       })..start();
//     }

//     showDialog(
//       context: context,
//       builder: (context) {
//         final maxHeight =
//             MediaQuery.of(context).size.height *
//             0.9; // roomy but not full-screen
//         final maxWidth = MediaQuery.of(context).size.width * 0.95;

//         return Dialog(
//           insetPadding: const EdgeInsets.all(16),
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(20),
//           ),
//           backgroundColor: const Color(0xFFFDF6EE),
//           child: StatefulBuilder(
//             builder: (context, setStateDialog) {
//               Future<void> sendCode() async {
//                 // Validate required fields for register-init
//                 final name = fullNameController.text.trim();
//                 final pwd = passwordController.text;
//                 final email = emailController.text.trim();

//                 if (name.isEmpty || pwd.isEmpty || email.isEmpty) {
//                   showBanner(
//                     "Please fill Full Name, Password and Email before verification.",
//                     ContentType.warning,
//                     setStateDialog,
//                   );
//                   return;
//                 }

//                 setStateDialog(() => isSendingCode = true);
//                 try {
//                   final data = {
//                     'fullName': name,
//                     'email': email,
//                     'phone': phoneController.text.trim(),
//                     'city': cityController.text.trim(),
//                     'state': stateController.text.trim(),
//                     'role': role,
//                     'password': pwd,
//                   };

//                   final init = await _registerInit(data, selectedImage);
//                   tempId = init['tempId'] as String?;
//                   final expiresInSec =
//                       (init['expiresInSec'] as num?)?.toInt() ?? 600;

//                   otpController.clear();
//                   startTimer(expiresInSec, setStateDialog);

//                   showBanner(
//                     "OTP sent to $email",
//                     ContentType.success,
//                     setStateDialog,
//                   );
//                 } catch (e) {
//                   showBanner(e.toString(), ContentType.failure, setStateDialog);
//                 } finally {
//                   setStateDialog(() => isSendingCode = false);
//                 }
//               }

//               Future<void> verifyCode() async {
//                 if (emailVerified) return;

//                 final code = otpController.text.trim();
//                 final email = emailController.text.trim();

//                 if (code.length != 6) {
//                   showBanner(
//                     "Enter the 6-digit code.",
//                     ContentType.warning,
//                     setStateDialog,
//                   );
//                   return;
//                 }
//                 if (tempId == null) return;

//                 setStateDialog(() => isVerifying = true);
//                 try {
//                   await _registerVerify(tempId!, email, code);

//                   emailVerified = true;
//                   ticker?.dispose();
//                   setStateDialog(() {});

//                   // Refresh members list; backend creates the user on verify
//                   final prefs = await SharedPreferences.getInstance();
//                   final token = _cleanToken(prefs.getString('auth_token'));
//                   await fetchTeamMembers(token);

//                   showBanner(
//                     "Member added & email verified.",
//                     ContentType.success,
//                     setStateDialog,
//                   );
//                 } catch (e) {
//                   showBanner(e.toString(), ContentType.failure, setStateDialog);
//                 } finally {
//                   setStateDialog(() => isVerifying = false);
//                 }
//               }

//               Future<void> resendCode() async {
//                 if (!canResend || tempId == null) return;
//                 try {
//                   await _registerResendOtp(
//                     tempId!,
//                     emailController.text.trim(),
//                   );
//                   startTimer(600, setStateDialog);
//                   showBanner(
//                     "OTP resent. Check your inbox.",
//                     ContentType.success,
//                     setStateDialog,
//                   );
//                 } catch (e) {
//                   showBanner(e.toString(), ContentType.failure, setStateDialog);
//                 }
//               }

//               // Success chip (fixed just under banner)
//               final successChip = AnimatedSwitcher(
//                 duration: const Duration(milliseconds: 250),
//                 child: emailVerified
//                     ? Container(
//                         key: const ValueKey('ok'),
//                         padding: const EdgeInsets.symmetric(
//                           vertical: 8,
//                           horizontal: 12,
//                         ),
//                         decoration: BoxDecoration(
//                           color: Colors.green.shade50,
//                           borderRadius: BorderRadius.circular(12),
//                           border: Border.all(color: Colors.green.shade200),
//                         ),
//                         child: Row(
//                           mainAxisSize: MainAxisSize.min,
//                           children: const [
//                             Icon(
//                               Icons.verified_rounded,
//                               color: Colors.green,
//                               size: 18,
//                             ),
//                             SizedBox(width: 8),
//                             Text(
//                               "Email verified",
//                               style: TextStyle(color: Colors.green),
//                             ),
//                           ],
//                         ),
//                       )
//                     : const SizedBox.shrink(),
//               );

//               // Inline top banner (ALWAYS VISIBLE; outside the scroll view)
//               Widget buildBanner() {
//                 if (bannerMsg == null || bannerType == null)
//                   return const SizedBox.shrink();
//                 Color bg, border;
//                 IconData icon;
//                 switch (bannerType!) {
//                   case ContentType.success:
//                     bg = Colors.green.shade50;
//                     border = Colors.green.shade200;
//                     icon = Icons.check_circle;
//                     break;
//                   case ContentType.failure:
//                     bg = Colors.red.shade50;
//                     border = Colors.red.shade200;
//                     icon = Icons.error_outline;
//                     break;
//                   case ContentType.warning:
//                   default:
//                     bg = Colors.orange.shade50;
//                     border = Colors.orange.shade200;
//                     icon = Icons.warning_amber_rounded;
//                 }
//                 return Container(
//                   margin: const EdgeInsets.only(bottom: 10),
//                   padding: const EdgeInsets.all(12),
//                   decoration: BoxDecoration(
//                     color: bg,
//                     border: Border.all(color: border),
//                     borderRadius: BorderRadius.circular(12),
//                   ),
//                   child: Row(
//                     children: [
//                       Icon(icon, size: 18),
//                       const SizedBox(width: 8),
//                       Expanded(
//                         child: Text(
//                           bannerMsg!,
//                           style: const TextStyle(fontWeight: FontWeight.w500),
//                         ),
//                       ),
//                       IconButton(
//                         padding: EdgeInsets.zero,
//                         constraints: const BoxConstraints(),
//                         onPressed: () => setStateDialog(() {
//                           bannerMsg = null;
//                           bannerType = null;
//                         }),
//                         icon: const Icon(Icons.close, size: 18),
//                       ),
//                     ],
//                   ),
//                 );
//               }

//               return ConstrainedBox(
//                 constraints: BoxConstraints(
//                   maxHeight: maxHeight,
//                   maxWidth: maxWidth,
//                 ),
//                 child: SizedBox(
//                   // make dialog content occupy height so header stays fixed
//                   height: maxHeight * 0.95,
//                   child: Column(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       // Header (fixed)
//                       Padding(
//                         padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
//                         child: Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             const Text(
//                               "Add New Member",
//                               style: TextStyle(
//                                 fontSize: 18,
//                                 fontWeight: FontWeight.bold,
//                                 color: AppColors.primaryColor,
//                               ),
//                             ),
//                             IconButton(
//                               icon: const Icon(
//                                 Icons.close,
//                                 color: Colors.brown,
//                               ),
//                               onPressed: () {
//                                 ticker?.dispose();
//                                 Navigator.pop(context);
//                               },
//                             ),
//                           ],
//                         ),
//                       ),
//                       const Padding(
//                         padding: EdgeInsets.symmetric(horizontal: 20),
//                         child: Divider(color: Colors.brown),
//                       ),

//                       // Fixed banner & chip
//                       Padding(
//                         padding: const EdgeInsets.symmetric(horizontal: 20),
//                         child: Column(
//                           crossAxisAlignment: CrossAxisAlignment.start,
//                           children: [
//                             const SizedBox(height: 6),
//                             buildBanner(),
//                             successChip,
//                             const SizedBox(height: 10),
//                           ],
//                         ),
//                       ),

//                       // Scrollable form area
//                       Expanded(
//                         child: Padding(
//                           padding: const EdgeInsets.symmetric(horizontal: 20),
//                           child: SingleChildScrollView(
//                             child: Column(
//                               mainAxisSize: MainAxisSize.min,
//                               children: [
//                                 // Photo
//                                 GestureDetector(
//                                   onTap: () async {
//                                     final picker = ImagePicker();
//                                     final picked = await picker.pickImage(
//                                       source: ImageSource.gallery,
//                                     );
//                                     if (picked != null) {
//                                       setStateDialog(
//                                         () => selectedImage = File(picked.path),
//                                       );
//                                     }
//                                   },
//                                   child: selectedImage == null
//                                       ? Container(
//                                           width: double.infinity,
//                                           height: 120,
//                                           decoration: BoxDecoration(
//                                             color: Colors.white,
//                                             borderRadius: BorderRadius.circular(
//                                               12,
//                                             ),
//                                             border: Border.all(
//                                               color: Colors.brown.shade200,
//                                             ),
//                                           ),
//                                           child: const Center(
//                                             child: Text(
//                                               "Select Member Photo",
//                                               style: TextStyle(
//                                                 color: Colors.brown,
//                                                 fontWeight: FontWeight.w500,
//                                               ),
//                                             ),
//                                           ),
//                                         )
//                                       : Stack(
//                                           children: [
//                                             Container(
//                                               width: double.infinity,
//                                               height: 120,
//                                               decoration: BoxDecoration(
//                                                 borderRadius:
//                                                     BorderRadius.circular(12),
//                                                 image: DecorationImage(
//                                                   image: FileImage(
//                                                     selectedImage!,
//                                                   ),
//                                                   fit: BoxFit.cover,
//                                                 ),
//                                               ),
//                                             ),
//                                             Positioned(
//                                               top: 6,
//                                               right: 6,
//                                               child: GestureDetector(
//                                                 onTap: () => setStateDialog(
//                                                   () => selectedImage = null,
//                                                 ),
//                                                 child: Container(
//                                                   decoration:
//                                                       const BoxDecoration(
//                                                         color: Colors.white,
//                                                         shape: BoxShape.circle,
//                                                       ),
//                                                   padding: const EdgeInsets.all(
//                                                     4,
//                                                   ),
//                                                   child: const Icon(
//                                                     Icons.close,
//                                                     color: Colors.brown,
//                                                     size: 20,
//                                                   ),
//                                                 ),
//                                               ),
//                                             ),
//                                           ],
//                                         ),
//                                 ),

//                                 const SizedBox(height: 16),

//                                 // Required BEFORE verification
//                                 _buildTextField(
//                                   fullNameController,
//                                   "Full Name",
//                                   Icons.person,
//                                 ),
//                                 _buildTextField(
//                                   passwordController,
//                                   "Password",
//                                   Icons.lock,
//                                   obscure: true,
//                                 ),

//                                 // Email + Send Code row
//                                 Row(
//                                   children: [
//                                     Expanded(
//                                       child: TextField(
//                                         controller: emailController,
//                                         readOnly: emailVerified,
//                                         decoration: InputDecoration(
//                                           prefixIcon: const Icon(
//                                             Icons.email,
//                                             color: Colors.brown,
//                                           ),
//                                           labelText: emailVerified
//                                               ? "Email (verified)"
//                                               : "Email",
//                                           labelStyle: const TextStyle(
//                                             color: Colors.brown,
//                                           ),
//                                           filled: true,
//                                           fillColor: emailVerified
//                                               ? Colors.brown.shade50
//                                               : Colors.white,
//                                           focusedBorder: OutlineInputBorder(
//                                             borderRadius: BorderRadius.circular(
//                                               12,
//                                             ),
//                                             borderSide: BorderSide(
//                                               color: AppColors.primaryColor,
//                                               width: 1.5,
//                                             ),
//                                           ),
//                                           border: OutlineInputBorder(
//                                             borderRadius: BorderRadius.circular(
//                                               12,
//                                             ),
//                                             borderSide: const BorderSide(
//                                               color: Colors.brown,
//                                             ),
//                                           ),
//                                         ),
//                                       ),
//                                     ),
//                                     const SizedBox(width: 10),
//                                     ElevatedButton(
//                                       style: ElevatedButton.styleFrom(
//                                         backgroundColor: AppColors.primaryColor,
//                                         padding: const EdgeInsets.symmetric(
//                                           horizontal: 14,
//                                           vertical: 14,
//                                         ),
//                                         shape: RoundedRectangleBorder(
//                                           borderRadius: BorderRadius.circular(
//                                             12,
//                                           ),
//                                         ),
//                                       ),
//                                       onPressed:
//                                           (emailVerified || isSendingCode)
//                                           ? null
//                                           : sendCode,
//                                       child: isSendingCode
//                                           ? const SizedBox(
//                                               width: 18,
//                                               height: 18,
//                                               child: CircularProgressIndicator(
//                                                 strokeWidth: 2,
//                                                 color: Colors.white,
//                                               ),
//                                             )
//                                           : const Text(
//                                               "Send Code",
//                                               style: TextStyle(
//                                                 color: Colors.white,
//                                               ),
//                                             ),
//                                     ),
//                                   ],
//                                 ),

//                                 // OTP Section
//                                 AnimatedSwitcher(
//                                   duration: const Duration(milliseconds: 300),
//                                   child: (tempId != null && !emailVerified)
//                                       ? Column(
//                                           key: const ValueKey('otpSection'),
//                                           children: [
//                                             const SizedBox(height: 14),
//                                             Container(
//                                               width: double.infinity,
//                                               padding: const EdgeInsets.all(12),
//                                               decoration: BoxDecoration(
//                                                 color: Colors.orange.shade50,
//                                                 border: Border.all(
//                                                   color: Colors.orange.shade200,
//                                                 ),
//                                                 borderRadius:
//                                                     BorderRadius.circular(12),
//                                               ),
//                                               child: Column(
//                                                 crossAxisAlignment:
//                                                     CrossAxisAlignment.start,
//                                                 children: [
//                                                   const Text(
//                                                     "Email Verification",
//                                                     style: TextStyle(
//                                                       color: Colors.brown,
//                                                       fontWeight:
//                                                           FontWeight.w700,
//                                                     ),
//                                                   ),
//                                                   Text(
//                                                     "Enter the 6-digit code sent to ${emailController.text.trim()}",
//                                                     style: const TextStyle(
//                                                       color: Colors.brown,
//                                                     ),
//                                                   ),
//                                                   const SizedBox(height: 10),
//                                                   TextField(
//                                                     controller: otpController,
//                                                     keyboardType:
//                                                         TextInputType.number,
//                                                     maxLength: 6,
//                                                     textAlign: TextAlign.center,
//                                                     decoration: InputDecoration(
//                                                       counterText: "",
//                                                       hintText: "Enter OTP",
//                                                       filled: true,
//                                                       fillColor: Colors.white,
//                                                       border: OutlineInputBorder(
//                                                         borderRadius:
//                                                             BorderRadius.circular(
//                                                               12,
//                                                             ),
//                                                       ),
//                                                       focusedBorder:
//                                                           OutlineInputBorder(
//                                                             borderRadius:
//                                                                 BorderRadius.circular(
//                                                                   12,
//                                                                 ),
//                                                             borderSide: BorderSide(
//                                                               color: AppColors
//                                                                   .primaryColor,
//                                                               width: 1.5,
//                                                             ),
//                                                           ),
//                                                     ),
//                                                     onSubmitted: (_) =>
//                                                         verifyCode(),
//                                                   ),
//                                                   const SizedBox(height: 8),
//                                                   Row(
//                                                     children: [
//                                                       Expanded(
//                                                         child: OutlinedButton.icon(
//                                                           onPressed: canResend
//                                                               ? resendCode
//                                                               : null,
//                                                           icon: const Icon(
//                                                             Icons.refresh,
//                                                           ),
//                                                           label: Text(
//                                                             canResend
//                                                                 ? "Resend Code"
//                                                                 : "Resend in ${mmss(secondsLeft)}",
//                                                           ),
//                                                           style: OutlinedButton.styleFrom(
//                                                             foregroundColor:
//                                                                 Colors.brown,
//                                                             side:
//                                                                 const BorderSide(
//                                                                   color: Colors
//                                                                       .brown,
//                                                                 ),
//                                                             padding:
//                                                                 const EdgeInsets.symmetric(
//                                                                   vertical: 12,
//                                                                 ),
//                                                             shape: RoundedRectangleBorder(
//                                                               borderRadius:
//                                                                   BorderRadius.circular(
//                                                                     12,
//                                                                   ),
//                                                             ),
//                                                           ),
//                                                         ),
//                                                       ),
//                                                       const SizedBox(width: 12),
//                                                       Expanded(
//                                                         child: ElevatedButton.icon(
//                                                           onPressed: isVerifying
//                                                               ? null
//                                                               : verifyCode,
//                                                           icon: isVerifying
//                                                               ? const SizedBox(
//                                                                   width: 18,
//                                                                   height: 18,
//                                                                   child: CircularProgressIndicator(
//                                                                     strokeWidth:
//                                                                         2,
//                                                                     color: Colors
//                                                                         .white,
//                                                                   ),
//                                                                 )
//                                                               : const Icon(
//                                                                   Icons
//                                                                       .verified_user,
//                                                                   color: Colors
//                                                                       .white,
//                                                                 ),
//                                                           label: const Text(
//                                                             "Verify",
//                                                             style: TextStyle(
//                                                               color:
//                                                                   Colors.white,
//                                                             ),
//                                                           ),
//                                                           style: ElevatedButton.styleFrom(
//                                                             backgroundColor:
//                                                                 AppColors
//                                                                     .primaryColor,
//                                                             padding:
//                                                                 const EdgeInsets.symmetric(
//                                                                   vertical: 12,
//                                                                 ),
//                                                             shape: RoundedRectangleBorder(
//                                                               borderRadius:
//                                                                   BorderRadius.circular(
//                                                                     12,
//                                                                   ),
//                                                             ),
//                                                           ),
//                                                         ),
//                                                       ),
//                                                     ],
//                                                   ),
//                                                 ],
//                                               ),
//                                             ),
//                                           ],
//                                         )
//                                       : const SizedBox.shrink(),
//                                 ),

//                                 const SizedBox(height: 18),

//                                 // Rest (enabled after verification)
//                                 _buildTextField(
//                                   phoneController,
//                                   "Phone",
//                                   Icons.phone,
//                                 ),
//                                 _buildTextField(
//                                   cityController,
//                                   "City",
//                                   Icons.location_city,
//                                 ),
//                                 _buildTextField(
//                                   stateController,
//                                   "State",
//                                   Icons.map,
//                                 ),
//                                 DropdownButtonFormField<String>(
//                                   value: role,
//                                   decoration: InputDecoration(
//                                     prefixIcon: const Icon(
//                                       Icons.work_outline,
//                                       color: Colors.brown,
//                                     ),
//                                     labelText: "Role",
//                                     border: OutlineInputBorder(
//                                       borderRadius: BorderRadius.circular(12),
//                                     ),
//                                     filled: true,
//                                     fillColor: Colors.white,
//                                   ),
//                                   items: const [
//                                     DropdownMenuItem(
//                                       value: "SUPER_ADMIN",
//                                       child: Text("Super Admin"),
//                                     ),
//                                     DropdownMenuItem(
//                                       value: "ADMIN",
//                                       child: Text("Admin"),
//                                     ),
//                                     DropdownMenuItem(
//                                       value: "TEAM_MEMBER",
//                                       child: Text("Team Member"),
//                                     ),
//                                     DropdownMenuItem(
//                                       value: "CLIENT",
//                                       child: Text("Client"),
//                                     ),
//                                   ],
//                                   onChanged: emailVerified
//                                       ? (v) => role = v!
//                                       : null,
//                                 ),
//                                 const SizedBox(height: 20),
//                               ],
//                             ),
//                           ),
//                         ),
//                       ),

//                       // Footer (fixed)
//                       Padding(
//                         padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
//                         child: Row(
//                           children: [
//                             Expanded(
//                               child: OutlinedButton(
//                                 onPressed: () {
//                                   ticker?.dispose();
//                                   Navigator.pop(context);
//                                 },
//                                 style: OutlinedButton.styleFrom(
//                                   foregroundColor: Colors.brown,
//                                   side: const BorderSide(color: Colors.brown),
//                                   padding: const EdgeInsets.symmetric(
//                                     vertical: 14,
//                                   ),
//                                   shape: RoundedRectangleBorder(
//                                     borderRadius: BorderRadius.circular(12),
//                                   ),
//                                 ),
//                                 child: const Text("Cancel"),
//                               ),
//                             ),
//                             const SizedBox(width: 12),
//                             Expanded(
//                               child: ElevatedButton.icon(
//                                 style: ElevatedButton.styleFrom(
//                                   backgroundColor: emailVerified
//                                       ? AppColors.primaryColor
//                                       : Colors.brown.shade300,
//                                   padding: const EdgeInsets.symmetric(
//                                     vertical: 14,
//                                   ),
//                                   shape: RoundedRectangleBorder(
//                                     borderRadius: BorderRadius.circular(12),
//                                   ),
//                                 ),
//                                 onPressed: !emailVerified
//                                     ? null
//                                     : () {
//                                         // Already created by backend on verify — just close.
//                                         ticker?.dispose();
//                                         Navigator.pop(context);
//                                       },
//                                 icon: const Icon(
//                                   Icons.check,
//                                   color: Colors.white,
//                                 ),
//                                 label: const Text(
//                                   "Finish",
//                                   style: TextStyle(color: Colors.white),
//                                 ),
//                               ),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               );
//             },
//           ),
//         );
//       },
//     ).then((_) {
//       ticker?.dispose();
//     });
//   }

//   void _showEditMemberDialog(dynamic member) {
//     final fullNameController = TextEditingController(text: member['fullName']);
//     final emailController = TextEditingController(text: member['email']);
//     final phoneController = TextEditingController(text: member['phone']);
//     final cityController = TextEditingController(text: member['city']);
//     final stateController = TextEditingController(text: member['state']);
//     final passwordController = TextEditingController();

//     String role = member['role'] ?? "TEAM_MEMBER";
//     File? selectedImage;

//     showDialog(
//       context: context,
//       builder: (context) {
//         return Dialog(
//           shape: RoundedRectangleBorder(
//             borderRadius: BorderRadius.circular(20),
//           ),
//           backgroundColor: const Color(0xFFFDF6EE),
//           insetPadding: const EdgeInsets.all(16),
//           child: StatefulBuilder(
//             builder: (context, setStateDialog) {
//               return Padding(
//                 padding: const EdgeInsets.all(20),
//                 child: SingleChildScrollView(
//                   child: Column(
//                     mainAxisSize: MainAxisSize.min,
//                     children: [
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           const Text(
//                             "Edit Member",
//                             style: TextStyle(
//                               fontSize: 18,
//                               fontWeight: FontWeight.bold,
//                               color: AppColors.primaryColor,
//                             ),
//                           ),
//                           IconButton(
//                             icon: const Icon(Icons.close, color: Colors.brown),
//                             onPressed: () => Navigator.pop(context),
//                           ),
//                         ],
//                       ),
//                       const Divider(color: Colors.brown),
//                       GestureDetector(
//                         onTap: () async {
//                           final picker = ImagePicker();
//                           final picked = await picker.pickImage(
//                             source: ImageSource.gallery,
//                           );
//                           if (picked != null) {
//                             setStateDialog(
//                               () => selectedImage = File(picked.path),
//                             );
//                           }
//                         },
//                         child: selectedImage == null
//                             ? CircleAvatar(
//                                 radius: 50,
//                                 backgroundImage:
//                                     (member['avatarUrl'] != null &&
//                                         (member['avatarUrl'] as String)
//                                             .isNotEmpty)
//                                     ? NetworkImage(member['avatarUrl'])
//                                     : const AssetImage('assets/user.jpg')
//                                           as ImageProvider,
//                               )
//                             : CircleAvatar(
//                                 radius: 50,
//                                 backgroundImage: FileImage(selectedImage!),
//                               ),
//                       ),
//                       const SizedBox(height: 16),
//                       _buildTextField(
//                         fullNameController,
//                         "Full Name",
//                         Icons.person,
//                       ),

//                       // EMAIL: read-only + disabled style, and NOT sent in update payload
//                       Padding(
//                         padding: const EdgeInsets.only(bottom: 12),
//                         child: TextField(
//                           controller: emailController,
//                           readOnly: true,
//                           decoration: InputDecoration(
//                             prefixIcon: const Icon(
//                               Icons.email,
//                               color: Colors.brown,
//                             ),
//                             labelText: "Email (read-only)",
//                             labelStyle: const TextStyle(color: Colors.brown),
//                             filled: true,
//                             fillColor: Colors.brown.shade50,
//                             focusedBorder: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(12),
//                               borderSide: BorderSide(
//                                 color: Colors.brown.shade300,
//                                 width: 1.5,
//                               ),
//                             ),
//                             border: OutlineInputBorder(
//                               borderRadius: BorderRadius.circular(12),
//                               borderSide: const BorderSide(color: Colors.brown),
//                             ),
//                           ),
//                         ),
//                       ),

//                       _buildTextField(phoneController, "Phone", Icons.phone),
//                       _buildTextField(
//                         cityController,
//                         "City",
//                         Icons.location_city,
//                       ),
//                       _buildTextField(stateController, "State", Icons.map),
//                       _buildTextField(
//                         passwordController,
//                         "New Password (optional)",
//                         Icons.lock,
//                         obscure: true,
//                       ),
//                       DropdownButtonFormField<String>(
//                         value: role,
//                         decoration: InputDecoration(
//                           prefixIcon: const Icon(
//                             Icons.work_outline,
//                             color: Colors.brown,
//                           ),
//                           labelText: "Role",
//                           border: OutlineInputBorder(
//                             borderRadius: BorderRadius.circular(12),
//                           ),
//                         ),
//                         items: const [
//                           DropdownMenuItem(
//                             value: "SUPER_ADMIN",
//                             child: Text("Super Admin"),
//                           ),
//                           DropdownMenuItem(
//                             value: "ADMIN",
//                             child: Text("Admin"),
//                           ),
//                           DropdownMenuItem(
//                             value: "TEAM_MEMBER",
//                             child: Text("Team Member"),
//                           ),
//                           DropdownMenuItem(
//                             value: "CLIENT",
//                             child: Text("Client"),
//                           ),
//                         ],
//                         onChanged: (v) => role = v!,
//                       ),
//                       const SizedBox(height: 20),
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           ElevatedButton.icon(
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: Colors.red,
//                             ),
//                             onPressed: () {
//                               Navigator.pop(context);
//                               _showDeleteConfirmationDialog(
//                                 member['_id'],
//                                 member['fullName'] ?? 'this member',
//                               );
//                             },
//                             icon: const Icon(
//                               Icons.delete_outline,
//                               color: Colors.white,
//                             ),
//                             label: const Text(
//                               "Delete",
//                               style: TextStyle(color: Colors.white),
//                             ),
//                           ),
//                           ElevatedButton.icon(
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: AppColors.primaryColor,
//                             ),
//                             onPressed: () {
//                               final data = {
//                                 'fullName': fullNameController.text.trim(),
//                                 // email intentionally NOT sent
//                                 'phone': phoneController.text.trim(),
//                                 'city': cityController.text.trim(),
//                                 'state': stateController.text.trim(),
//                                 'role': role,
//                               };
//                               if (passwordController.text.trim().isNotEmpty) {
//                                 data['password'] = passwordController.text
//                                     .trim();
//                               }
//                               Navigator.pop(context);
//                               updateMember(member['_id'], data, selectedImage);
//                             },
//                             icon: const Icon(Icons.check, color: Colors.white),
//                             label: const Text(
//                               "Update",
//                               style: TextStyle(color: Colors.white),
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               );
//             },
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildTextField(
//     TextEditingController controller,
//     String hint,
//     IconData icon, {
//     bool obscure = false,
//   }) {
//     return Padding(
//       padding: const EdgeInsets.only(bottom: 12),
//       child: TextField(
//         controller: controller,
//         obscureText: obscure,
//         decoration: InputDecoration(
//           prefixIcon: Icon(icon, color: Colors.brown),
//           labelText: hint,
//           labelStyle: const TextStyle(color: Colors.brown),
//           filled: true,
//           fillColor: Colors.white,
//           focusedBorder: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: BorderSide(color: AppColors.primaryColor, width: 1.5),
//           ),
//           border: OutlineInputBorder(
//             borderRadius: BorderRadius.circular(12),
//             borderSide: const BorderSide(color: Colors.brown),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildShimmerHeader() {
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 16),
//       child: Row(
//         children: [
//           Shimmer.fromColors(
//             baseColor: Colors.grey.shade300,
//             highlightColor: Colors.grey.shade100,
//             child: const CircleAvatar(radius: 25),
//           ),
//           const SizedBox(width: 12),
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Shimmer.fromColors(
//                   baseColor: Colors.grey.shade300,
//                   highlightColor: Colors.grey.shade100,
//                   child: Container(height: 16, width: 120, color: Colors.white),
//                 ),
//                 const SizedBox(height: 8),
//                 Shimmer.fromColors(
//                   baseColor: Colors.grey.shade300,
//                   highlightColor: Colors.grey.shade100,
//                   child: Container(height: 14, width: 180, color: Colors.white),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildShimmerSubCompanyList() {
//     return SizedBox(
//       height: 85,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         itemCount: 4,
//         itemBuilder: (_, i) => Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 8),
//           child: Column(
//             children: [
//               Shimmer.fromColors(
//                 baseColor: Colors.grey.shade300,
//                 highlightColor: Colors.grey.shade100,
//                 child: const CircleAvatar(radius: 25),
//               ),
//               const SizedBox(height: 5),
//               Shimmer.fromColors(
//                 baseColor: Colors.grey.shade300,
//                 highlightColor: Colors.grey.shade100,
//                 child: Container(height: 10, width: 50, color: Colors.white),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildShimmerClientStrip() {
//     return SizedBox(
//       height: 85,
//       child: ListView.builder(
//         scrollDirection: Axis.horizontal,
//         itemCount: 5,
//         itemBuilder: (_, i) => Padding(
//           padding: const EdgeInsets.symmetric(horizontal: 8),
//           child: Column(
//             children: [
//               Shimmer.fromColors(
//                 baseColor: Colors.grey.shade300,
//                 highlightColor: Colors.grey.shade100,
//                 child: const CircleAvatar(radius: 25),
//               ),
//               const SizedBox(height: 5),
//               Shimmer.fromColors(
//                 baseColor: Colors.grey.shade300,
//                 highlightColor: Colors.grey.shade100,
//                 child: Container(height: 10, width: 50, color: Colors.white),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }

//   // ---------- (Kept) OTP Dialog (unused by new flow, but still available) ----------
//   Future<void> _showOtpDialog({
//     required String email,
//     required String tempId,
//     required Duration expiresIn,
//     required VoidCallback onVerified,
//   }) async {
//     final otpController = TextEditingController();
//     int secondsLeft = expiresIn.inSeconds;
//     bool isVerifying = false;
//     bool canResend = false;

//     // simple ticker
//     late final _SimpleTicker ticker;
//     ticker = _SimpleTicker((elapsed) {
//       if (!mounted) return;
//       setState(() {
//         if (secondsLeft > 0) secondsLeft -= 1;
//         if (secondsLeft <= 0) canResend = true;
//       });
//     })..start();

//     await showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (ctx) {
//         return StatefulBuilder(
//           builder: (ctx, setStateDialog) {
//             Future<void> verify() async {
//               final code = otpController.text.trim();
//               if (code.length != 6) {
//                 SnackbarHelper.show(
//                   ctx,
//                   title: 'Invalid',
//                   message: 'Enter the 6-digit code.',
//                   type: ContentType.warning,
//                 );
//                 return;
//               }
//               setStateDialog(() => isVerifying = true);
//               try {
//                 await _registerVerify(tempId, email, code);
//                 Navigator.of(ctx).pop(); // close dialog
//                 ticker.dispose();
//                 onVerified();
//               } catch (e) {
//                 SnackbarHelper.show(
//                   ctx,
//                   title: 'Error',
//                   message: e.toString(),
//                   type: ContentType.failure,
//                 );
//               } finally {
//                 if (mounted) setStateDialog(() => isVerifying = false);
//               }
//             }

//             Future<void> resend() async {
//               if (!canResend) return;
//               try {
//                 await _registerResendOtp(tempId, email);
//                 setStateDialog(() {
//                   secondsLeft = 600;
//                   canResend = false;
//                 });
//               } catch (e) {
//                 SnackbarHelper.show(
//                   ctx,
//                   title: 'Error',
//                   message: e.toString(),
//                   type: ContentType.failure,
//                 );
//               }
//             }

//             String mmss(int s) {
//               final m = (s ~/ 60).toString().padLeft(2, '0');
//               final ss = (s % 60).toString().padLeft(2, '0');
//               return "$m:$ss";
//             }

//             return Dialog(
//               shape: RoundedRectangleBorder(
//                 borderRadius: BorderRadius.circular(20),
//               ),
//               backgroundColor: const Color(0xFFFDF6EE),
//               child: Padding(
//                 padding: const EdgeInsets.all(20),
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     const Icon(
//                       Icons.mark_email_read,
//                       size: 48,
//                       color: Colors.brown,
//                     ),
//                     const SizedBox(height: 10),
//                     const Text(
//                       "Email Verification",
//                       style: TextStyle(
//                         fontSize: 18,
//                         fontWeight: FontWeight.bold,
//                         color: Colors.brown,
//                       ),
//                     ),
//                     const SizedBox(height: 6),
//                     Text(
//                       "We sent a 6-digit code to\n$email",
//                       textAlign: TextAlign.center,
//                       style: const TextStyle(color: Colors.brown),
//                     ),
//                     const SizedBox(height: 16),

//                     // OTP input
//                     TextField(
//                       controller: otpController,
//                       keyboardType: TextInputType.number,
//                       maxLength: 6,
//                       textAlign: TextAlign.center,
//                       decoration: InputDecoration(
//                         counterText: "",
//                         hintText: "Enter OTP",
//                         filled: true,
//                         fillColor: Colors.white,
//                         border: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                         ),
//                         focusedBorder: OutlineInputBorder(
//                           borderRadius: BorderRadius.circular(12),
//                           borderSide: BorderSide(
//                             color: AppColors.primaryColor,
//                             width: 1.5,
//                           ),
//                         ),
//                       ),
//                       onSubmitted: (_) => verify(),
//                     ),

//                     const SizedBox(height: 8),
//                     Text(
//                       canResend
//                           ? "Code expired"
//                           : "Expires in ${mmss(secondsLeft)}",
//                       style: TextStyle(
//                         color: canResend ? Colors.red.shade600 : Colors.brown,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),

//                     const SizedBox(height: 16),
//                     Row(
//                       children: [
//                         Expanded(
//                           child: OutlinedButton.icon(
//                             onPressed: canResend ? resend : null,
//                             icon: const Icon(Icons.refresh),
//                             label: Text(
//                               canResend
//                                   ? "Resend Code"
//                                   : "Resend in ${mmss(secondsLeft)}",
//                             ),
//                             style: OutlinedButton.styleFrom(
//                               foregroundColor: Colors.brown,
//                               side: const BorderSide(color: Colors.brown),
//                               padding: const EdgeInsets.symmetric(vertical: 12),
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                             ),
//                           ),
//                         ),
//                         const SizedBox(width: 12),
//                         Expanded(
//                           child: ElevatedButton.icon(
//                             onPressed: isVerifying ? null : verify,
//                             icon: isVerifying
//                                 ? const SizedBox(
//                                     width: 18,
//                                     height: 18,
//                                     child: CircularProgressIndicator(
//                                       strokeWidth: 2,
//                                       color: Colors.white,
//                                     ),
//                                   )
//                                 : const Icon(
//                                     Icons.verified_user,
//                                     color: Colors.white,
//                                   ),
//                             label: const Text(
//                               "Verify",
//                               style: TextStyle(color: Colors.white),
//                             ),
//                             style: ElevatedButton.styleFrom(
//                               backgroundColor: AppColors.primaryColor,
//                               padding: const EdgeInsets.symmetric(vertical: 12),
//                               shape: RoundedRectangleBorder(
//                                 borderRadius: BorderRadius.circular(12),
//                               ),
//                             ),
//                           ),
//                         ),
//                       ],
//                     ),

//                     const SizedBox(height: 8),
//                     TextButton(
//                       onPressed: () {
//                         ticker.dispose();
//                         Navigator.of(ctx).pop();
//                       },
//                       child: const Text(
//                         "Cancel",
//                         style: TextStyle(color: Colors.brown),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//             );
//           },
//         );
//       },
//     );

//     if (ticker.isActive) ticker.dispose();
//   }
// }

// /// Lightweight 1-second ticker (no external deps)
// class _SimpleTicker {
//   final void Function(Duration elapsed) onTick;
//   bool _active = false;
//   Duration _elapsed = Duration.zero;

//   _SimpleTicker(this.onTick);

//   bool get isActive => _active;

//   void start() {
//     _active = true;
//     _loop();
//   }

//   Future<void> _loop() async {
//     while (_active) {
//       await Future.delayed(const Duration(seconds: 1));
//       if (!_active) break;
//       _elapsed += const Duration(seconds: 1);
//       onTick(_elapsed);
//     }
//   }

//   void dispose() {
//     _active = false;
//   }
// }
