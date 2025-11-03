import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';
import '../utils/custom_bottom_nav.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? userData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUser();
  }

  // Build absolute image URL & optionally append cache-buster
  String _absUrl(String? path, {String? cacheKey}) {
    if (path == null || path.isEmpty) return '';
    String url = path;
    if (!url.startsWith('http')) {
      if (url.startsWith('/uploads')) {
        url = "${ApiConfig.imageBaseUrl}$url";
      } else if (url.startsWith('/')) {
        url = "${ApiConfig.baseUrl}$url";
      } else {
        url = "${ApiConfig.baseUrl}/$url";
      }
    }
    if (cacheKey != null && cacheKey.isNotEmpty) {
      url += (url.contains('?') ? '&' : '?') + 't=$cacheKey';
    }
    return url;
  }

  Future<void> _fetchUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) return;

      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/me"),
        headers: {
          "Authorization": "Bearer $token",
          "Accept": "application/json",
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final u = Map<String, dynamic>.from(data['user'] ?? {});
        final avatar = (u['avatarUrl'] ?? '').toString();
        final cacheKey = (u['updatedAt'] ?? DateTime.now().toIso8601String())
            .toString();
        if (avatar.isNotEmpty && avatar.startsWith('/')) {
          u['avatarUrl'] = _absUrl(avatar, cacheKey: cacheKey);
        } else if (avatar.isNotEmpty) {
          u['avatarUrl'] = _absUrl(avatar, cacheKey: cacheKey);
        }
        if (mounted) setState(() => userData = u);
      } else {
        throw Exception("Fetch failed (${res.statusCode})");
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Failed to fetch profile: $e",
        type: ContentType.failure,
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// -------- EDIT PROFILE DIALOG (beautiful & professional) --------
  Future<void> _editProfileDialog() async {
    // Guard: only SUPER_ADMIN can edit
    if (!_isEditableRole) return;
    if (userData == null) return;

    final nameController = TextEditingController(text: userData?['fullName']);
    final emailController = TextEditingController(text: userData?['email']);
    final phoneController = TextEditingController(text: userData?['phone']);
    final passwordController = TextEditingController();

    File? tempAvatarFile;
    bool saving = false;

    await showDialog(
      context: context,
      barrierDismissible: !saving,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            Future<void> pickImage() async {
              if (saving) return;
              final picked = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                imageQuality: 85,
              );
              if (picked != null) {
                setLocalState(() {
                  tempAvatarFile = File(picked.path);
                });
              }
            }

            Future<void> onSave() async {
              if (saving) return;
              setLocalState(() => saving = true);

              final ok = await _updateProfile(
                nameController.text.trim(),
                emailController.text.trim(),
                phoneController.text.trim(),
                passwordController.text,
                tempAvatarFile,
              );

              setLocalState(() => saving = false);

              if (ok && mounted) {
                Navigator.pop(context); // close only on success
              }
            }

            final currentAvatarUrl = (userData?['avatarUrl'] ?? '').toString();

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFB87333), Color(0xFFD1A574)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.manage_accounts,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              "Edit Profile",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: saving
                                ? null
                                : () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: 'Close',
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            // Avatar with edit badge
                            Stack(
                              children: [
                                CircleAvatar(
                                  radius: 48,
                                  backgroundColor: const Color(0xFFF5E6D3),
                                  backgroundImage: tempAvatarFile != null
                                      ? FileImage(tempAvatarFile!)
                                      : (currentAvatarUrl.isNotEmpty
                                            ? NetworkImage(currentAvatarUrl)
                                                  as ImageProvider
                                            : null),
                                  child:
                                      (tempAvatarFile == null &&
                                          currentAvatarUrl.isEmpty)
                                      ? const Icon(
                                          Icons.person,
                                          color: Colors.brown,
                                          size: 48,
                                        )
                                      : null,
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: InkWell(
                                    onTap: pickImage,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryColor,
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.2,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(8),
                                      child: const Icon(
                                        Icons.edit,
                                        color: Colors.white,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            _prettyField(
                              controller: nameController,
                              label: "Full Name",
                              icon: Icons.person_outline,
                              enabled: !saving,
                            ),
                            _prettyField(
                              controller: emailController,
                              label: "Email",
                              icon: Icons.email_outlined,
                              keyboardType: TextInputType.emailAddress,
                              enabled: !saving,
                            ),
                            _prettyField(
                              controller: phoneController,
                              label: "Phone",
                              icon: Icons.phone_outlined,
                              keyboardType: TextInputType.phone,
                              enabled: !saving,
                            ),
                            _prettyField(
                              controller: passwordController,
                              label: "New Password (optional)",
                              icon: Icons.lock_outline,
                              obscure: true,
                              enabled: !saving,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Actions
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving
                                  ? null
                                  : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFB87333),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                "Cancel",
                                style: TextStyle(
                                  color: Color(0xFFB87333),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: saving ? null : onSave,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryColor,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      "Save Changes",
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
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
        );
      },
    );
  }

  /// Returns true if update succeeded (used by dialog)
  Future<bool> _updateProfile(
    String name,
    String email,
    String phone,
    String password, [
    File? avatarFile,
  ]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final id = userData?['_id'];
      if (token == null || id == null) {
        SnackbarHelper.show(
          context,
          title: "Error",
          message: "Not authenticated.",
          type: ContentType.failure,
        );
        return false;
      }

      final uri = Uri.parse("${ApiConfig.baseUrl}/user/superadmin/$id");
      final request = http.MultipartRequest('PUT', uri);
      request.headers['Authorization'] = "Bearer $token";

      if (name.isNotEmpty) request.fields['fullName'] = name;
      if (email.isNotEmpty) request.fields['email'] = email;
      if (phone.isNotEmpty) request.fields['phone'] = phone;
      if (password.isNotEmpty) request.fields['password'] = password;

      if (avatarFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath('avatar', avatarFile.path),
        );
      }

      final res = await request.send();
      final responseData = await res.stream.bytesToString();

      Map<String, dynamic>? decoded;
      try {
        decoded = jsonDecode(responseData);
      } catch (_) {
        decoded = null;
      }

      if (res.statusCode == 200) {
        if (decoded != null && decoded['superAdmin'] != null) {
          final updated = Map<String, dynamic>.from(decoded['superAdmin']);
          final rawAvatar = (updated['avatarUrl'] ?? '').toString();
          final cacheKey =
              (updated['updatedAt'] ?? DateTime.now().toIso8601String())
                  .toString();

          if (rawAvatar.isNotEmpty) {
            updated['avatarUrl'] = _absUrl(rawAvatar, cacheKey: cacheKey);
          }

          if (mounted) {
            setState(() {
              userData = {...?userData, ...updated};
            });
          }
        } else {
          await _fetchUser();
        }

        SnackbarHelper.show(
          context,
          title: "Updated",
          message: (decoded?['message'] ?? "Profile updated successfully")
              .toString(),
          type: ContentType.success,
        );
        return true;
      } else {
        final msg = (decoded?['message'] ?? responseData).toString();
        SnackbarHelper.show(
          context,
          title: "Failed",
          message: msg,
          type: ContentType.failure,
        );
        return false;
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Error updating profile: $e",
        type: ContentType.failure,
      );
      return false;
    }
  }

  // ---- Role helpers ----
  bool get _isEditableRole {
    final r = (userData?['role'] ?? '').toString().toUpperCase();
    return r == 'SUPER_ADMIN';
  }

  String _formatRole(dynamic role) {
    final r = (role ?? '').toString().toUpperCase();
    if (r == 'SUPER_ADMIN') return "Super Admin";
    if (r == 'ADMIN') return "Admin";
    if (r == 'TEAM_MEMBER' || r == 'USER') return "Team Member";
    if (r == 'CLIENT') return "Client";
    return r;
  }

  String _formatDate(dynamic date) {
    if (date == null) return "—";
    try {
      final d = DateTime.parse(date.toString());
      return "${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}";
    } catch (_) {
      return date.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _isEditableRole;
    final String roleUpper = (userData?['role'] ?? '').toString().toUpperCase();
    final int bottomIndex = roleUpper == 'TEAM_MEMBER' ? 3 : 4;

    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.brown),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            // Avatar (tap only for SUPER_ADMIN)
                            Center(
                              child: GestureDetector(
                                onTap: canEdit ? _editProfileDialog : null,
                                child: Stack(
                                  children: [
                                    CircleAvatar(
                                      radius: 55,
                                      backgroundColor: Colors.brown[100],
                                      backgroundImage:
                                          (userData?['avatarUrl'] != null &&
                                              (userData!['avatarUrl'] as String)
                                                  .isNotEmpty)
                                          ? NetworkImage(userData!['avatarUrl'])
                                          : null,
                                      child:
                                          (userData?['avatarUrl'] == null ||
                                              (userData!['avatarUrl'] as String)
                                                  .isEmpty)
                                          ? const Icon(
                                              Icons.person,
                                              color: Colors.brown,
                                              size: 60,
                                            )
                                          : null,
                                    ),
                                    if (canEdit)
                                      Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryColor,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.2,
                                                ),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          padding: const EdgeInsets.all(6),
                                          child: const Icon(
                                            Icons.edit,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 15),
                            Text(
                              (userData?['fullName'] ?? '—').toString(),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              _formatRole(userData?['role']),
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 25),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "Profile Details",
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.brown,
                                  ),
                                ),
                                if (canEdit)
                                  IconButton(
                                    onPressed: _editProfileDialog,
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      color: Colors.brown,
                                    ),
                                    tooltip: 'Edit Profile',
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            _buildDetailCard(
                              Icons.person_outline,
                              "Full Name",
                              userData?['fullName'],
                            ),
                            _buildDetailCard(
                              Icons.email_outlined,
                              "Email",
                              userData?['email'],
                            ),
                            _buildDetailCard(
                              Icons.phone_outlined,
                              "Phone",
                              userData?['phone'],
                            ),
                            _buildDetailCard(
                              Icons.admin_panel_settings_outlined,
                              "Role",
                              _formatRole(userData?['role']),
                            ),
                            _buildDetailCard(
                              Icons.calendar_today_outlined,
                              "Joined On",
                              _formatDate(userData?['createdAt']),
                            ),

                            const SizedBox(height: 30),
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: _logout,
                                icon: const Icon(
                                  Icons.logout,
                                  color: Colors.white,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 28,
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                label: const Text(
                                  "Logout",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    CustomBottomNavBar(
                      currentIndex: bottomIndex,
                      onTap: (index) {},
                      userRole: userData?['role'] ?? '',
                    ),
                   ],
                ),
        ),
      ),
    );
  }

  Widget _buildDetailCard(IconData icon, String label, dynamic value) {
    final val = (value ?? '').toString().trim();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF5E6D3),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.brown),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  val.isEmpty ? "—" : val,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.brown,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Pretty input used inside dialog
  Widget _prettyField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    bool enabled = true,
    TextInputType? keyboardType,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        enabled: enabled,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: Colors.brown),
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 14,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.brown),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primaryColor, width: 1.6),
          ),
        ),
      ),
    );
  }
}
