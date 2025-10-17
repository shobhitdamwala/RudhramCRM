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

      // ✅ Correct route: /api/v1/user + /me (NOT /user/me again)
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
        // Use updatedAt as cache key if present
        final cacheKey = (u['updatedAt'] ?? DateTime.now().toIso8601String()).toString();
        if (avatar.isNotEmpty && avatar.startsWith('/')) {
          u['avatarUrl'] = _absUrl(avatar, cacheKey: cacheKey);
        } else if (avatar.isNotEmpty) {
          // External absolute URL — still attach cache buster to avoid stale cache
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

  /// -------- EDIT PROFILE DIALOG (with live avatar preview) --------
  Future<void> _editProfileDialog() async {
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
              final picked = await ImagePicker().pickImage(
                source: ImageSource.gallery,
                imageQuality: 85, // smaller upload size
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

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Edit Profile",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SingleChildScrollView(
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: saving ? null : pickImage,
                      child: CircleAvatar(
                        radius: 45,
                        backgroundColor: Colors.brown[100],
                        backgroundImage: tempAvatarFile != null
                            ? FileImage(tempAvatarFile!)
                            : (currentAvatarUrl.isNotEmpty
                                ? NetworkImage(currentAvatarUrl) as ImageProvider
                                : null),
                        child: (tempAvatarFile == null && currentAvatarUrl.isEmpty)
                            ? const Icon(Icons.camera_alt, color: Colors.brown, size: 32)
                            : null,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: "Full Name"),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailController,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: "Email"),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: phoneController,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: "Phone"),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passwordController,
                      enabled: !saving,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: "New Password"),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.brown)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown[700],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: saving ? null : onSave,
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("Save"),
                ),
              ],
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
        request.files.add(await http.MultipartFile.fromPath('avatar', avatarFile.path));
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
        // Prefer server response; otherwise refetch
        if (decoded != null && decoded['superAdmin'] != null) {
          final updated = Map<String, dynamic>.from(decoded['superAdmin']);
          // Rebuild avatar with cache buster so UI refreshes instantly
          final rawAvatar = (updated['avatarUrl'] ?? '').toString();
          final cacheKey = (updated['updatedAt'] ??
                  DateTime.now().toIso8601String())
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
          message: (decoded?['message'] ?? "Profile updated successfully").toString(),
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

  String _formatRole(dynamic role) {
    final r = (role ?? '').toString().toUpperCase();
    if (r == 'SUPER_ADMIN') return "Super Admin";
    if (r == 'ADMIN') return "Admin";
    if (r == 'USER') return "Team Member";
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
    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.brown))
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Column(
                          children: [
                            const SizedBox(height: 10),
                            Center(
                              child: GestureDetector(
                                onTap: _editProfileDialog,
                                child: CircleAvatar(
                                  radius: 55,
                                  backgroundColor: Colors.brown[100],
                                  backgroundImage: (userData?['avatarUrl'] != null &&
                                          (userData!['avatarUrl'] as String).isNotEmpty)
                                      ? NetworkImage(userData!['avatarUrl'])
                                      : null,
                                  child: (userData?['avatarUrl'] == null ||
                                          (userData!['avatarUrl'] as String).isEmpty)
                                      ? const Icon(Icons.person, color: Colors.brown, size: 60)
                                      : null,
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
                              style: const TextStyle(fontSize: 14, color: Colors.grey),
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
                                IconButton(
                                  onPressed: _editProfileDialog,
                                  icon: const Icon(Icons.edit_outlined, color: Colors.brown),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _buildDetailCard(Icons.person_outline, "Full Name", userData?['fullName']),
                            _buildDetailCard(Icons.email_outlined, "Email", userData?['email']),
                            _buildDetailCard(Icons.phone_outlined, "Phone", userData?['phone']),
                            _buildDetailCard(Icons.admin_panel_settings_outlined, "Role",
                                _formatRole(userData?['role'])),
                            _buildDetailCard(Icons.calendar_today_outlined, "Joined On",
                                _formatDate(userData?['createdAt'])),
                            const SizedBox(height: 30),
                            Center(
                              child: ElevatedButton.icon(
                                onPressed: _logout,
                                icon: const Icon(Icons.logout, color: Colors.white),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.brown[800],
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
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
                    CustomBottomNavBar(currentIndex: 4, onTap: (index) {},userRole: userData?['role'] ?? '',),
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
                Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
}
