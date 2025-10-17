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
  bool showAll = false;

  @override
  void initState() {
    super.initState();
    fetchAllData();
  }

  // ---------- Helpers ----------
  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
  }

  String _absUrl(String? maybeRelative) {
    if (maybeRelative == null || maybeRelative.isEmpty) return '';
    if (maybeRelative.startsWith('http')) return maybeRelative;

    if (maybeRelative.startsWith('/uploads')) {
      // 🟢 Use image base URL
      return "${ApiConfig.imageBaseUrl}$maybeRelative";
    }

    // Default
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

  // ---------- Fetch All ----------
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
      // surface error
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

  Future<void> fetchTeamMembers(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> members = List<dynamic>.from(
          data['teamMembers'] ?? [],
        );
        // normalize avatar URLs
        for (final m in members) {
          if (m['avatarUrl'] != null &&
              m['avatarUrl'].toString().startsWith('/')) {
            m['avatarUrl'] = _absUrl(m['avatarUrl']);
            print("Member avatar fixed URL: ${m['avatarUrl']}");
          }
        }

        if (mounted) setState(() => teamMembers = members);
      } else {
        await _showErrorSnack(
          res.body,
          fallback: "Failed to fetch team members",
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Team load error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ---------- CRUD ----------
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
        // ✅ Remove from local list to update UI instantly
        setState(() {
          teamMembers.removeWhere((m) => m['_id'] == id);
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
      final body = await resp.stream.bytesToString();

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

  Future<void> addMember(Map<String, dynamic> newData, File? avatarFile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      if (token.isEmpty) return;

      // NOTE: if your route is different, change path here (e.g. /auth/register)
      final uri = Uri.parse("${ApiConfig.baseUrl}/user/register");

      final req = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = "Bearer $token";

      newData.forEach((k, v) {
        if (v != null) req.fields[k] = v.toString();
      });

      if (avatarFile != null) {
        req.files.add(
          await http.MultipartFile.fromPath('avatar', avatarFile.path),
        );
      }

      final resp = await req.send();
      final body = await resp.stream.bytesToString();

      if (resp.statusCode == 201 || resp.statusCode == 200) {
        if (!mounted) return;
        SnackbarHelper.show(
          context,
          title: 'Success',
          message: 'Member added successfully',
          type: ContentType.success,
        );
        await fetchTeamMembers(token);
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to add member',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Add error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final displayed = showAll ? teamMembers : teamMembers.take(6).toList();

    return Scaffold(
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
                      role: userData?['role'],
                      showBackButton: true,
                      onBack: () => Navigator.pop(context),
                    ),

                    const SizedBox(height: 10),
                    Expanded(
                      child: showAll
                          ? _buildGridView(displayed)
                          : _buildTeamRow(displayed),
                    ),
                    _buildViewAllButton(),
                    const SizedBox(height: 20),
                    _buildAddMemberButton(),
                    const SizedBox(height: 25),
                    CustomBottomNavBar(currentIndex: 4, onTap: (i) {},userRole: userData?['role'] ?? '',),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundImage:
                    (userData?['avatarUrl'] != null &&
                        (userData!['avatarUrl'] as String).isNotEmpty)
                    ? NetworkImage(userData!['avatarUrl'])
                    : const AssetImage('assets/user.jpg') as ImageProvider,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userData?['fullName'] ?? 'Hi...',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.brown,
                    ),
                  ),
                  Text(
                    userData?['role'] ?? '',
                    style: const TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.brown),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamRow(List<dynamic> members) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SizedBox(
        height: 110,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: members.length,
          separatorBuilder: (_, __) => const SizedBox(width: 16),
          itemBuilder: (context, i) {
            final m = members[i];
            return GestureDetector(
              onTap: () => _showEditMemberDialog(m),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundImage:
                        (m['avatarUrl'] != null &&
                            (m['avatarUrl'] as String).isNotEmpty)
                        ? NetworkImage(m['avatarUrl'])
                        : const AssetImage('assets/user.jpg') as ImageProvider,
                  ),

                  const SizedBox(height: 6),
                  Text(
                    m['fullName'] ?? '',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.brown,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGridView(List<dynamic> members) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        itemCount: members.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 0.9,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemBuilder: (context, i) {
          final m = members[i];
          return GestureDetector(
            onTap: () => _showEditMemberDialog(m),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundImage:
                      (m['avatarUrl'] != null &&
                          (m['avatarUrl'] as String).isNotEmpty)
                      ? NetworkImage(m['avatarUrl'])
                      : const AssetImage('assets/user.jpg') as ImageProvider,
                ),
                const SizedBox(height: 8),
                Text(
                  m['fullName'] ?? '',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.brown,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildViewAllButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 16, top: 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: GestureDetector(
          onTap: () => setState(() => showAll = !showAll),
          child: Text(
            showAll ? "View Less" : "View All",
            style: const TextStyle(
              color: Colors.blueAccent,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddMemberButton() {
    return Center(
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 5,
        ),
        icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
        label: const Text(
          "Add Member",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        onPressed: () => _showAddMemberDialog(context),
      ),
    );
  }

  // ---------- Dialogs ----------
  void _showAddMemberDialog(BuildContext context) {
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final cityController = TextEditingController();
    final stateController = TextEditingController();
    final passwordController = TextEditingController();
    String role = "TEAM_MEMBER";
    File? selectedImage;

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: const Color(0xFFFDF6EE),
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
                            "Add New Member",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.brown,
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
                            ? Container(
                                width: double.infinity,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
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
                                      borderRadius: BorderRadius.circular(12),
                                      image: DecorationImage(
                                        image: FileImage(selectedImage!),
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
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(4),
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
                      _buildTextField(emailController, "Email", Icons.email),
                      _buildTextField(phoneController, "Phone", Icons.phone),
                      _buildTextField(
                        cityController,
                        "City",
                        Icons.location_city,
                      ),
                      _buildTextField(stateController, "State", Icons.map),
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
                      const SizedBox(height: 12),
                      _buildTextField(
                        passwordController,
                        "Password",
                        Icons.lock,
                        obscure: true,
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                        ),
                        onPressed: () {
                          final data = {
                            'fullName': fullNameController.text.trim(),
                            'email': emailController.text.trim(),
                            'phone': phoneController.text.trim(),
                            'city': cityController.text.trim(),
                            'state': stateController.text.trim(),
                            'role': role,
                            'password': passwordController.text,
                          };
                          Navigator.pop(context);
                          addMember(data, selectedImage);
                        },
                        icon: const Icon(Icons.check, color: Colors.white),
                        label: const Text(
                          "Submit",
                          style: TextStyle(color: Colors.white),
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
    );
  }

  void _showEditMemberDialog(dynamic member) {
    final fullNameController = TextEditingController(text: member['fullName']);
    final emailController = TextEditingController(text: member['email']);
    final phoneController = TextEditingController(text: member['phone']);
    final cityController = TextEditingController(text: member['city']);
    final stateController = TextEditingController(text: member['state']);
    final passwordController = TextEditingController(); // 👈 ADD THIS

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
                              color: Colors.brown,
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
                      _buildTextField(emailController, "Email", Icons.email),
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
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              deleteMember(member['_id']);
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
                              final data = {
                                'fullName': fullNameController.text.trim(),
                                'email': emailController.text.trim(),
                                'phone': phoneController.text.trim(),
                                'city': cityController.text.trim(),
                                'state': stateController.text.trim(),
                                'role': role,
                              };
                              if (passwordController.text.trim().isNotEmpty) {
                                data['password'] = passwordController.text
                                    .trim();
                              }
                              Navigator.pop(context);
                              updateMember(member['_id'], data, selectedImage);
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
    TextEditingController controller,
    String hint,
    IconData icon, {
    bool obscure = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
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
  Widget _buildShimmerHeader() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Shimmer.fromColors(
          baseColor: Colors.grey.shade300,
          highlightColor: Colors.grey.shade100,
          child: const CircleAvatar(radius: 25),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(
                  height: 16,
                  width: 120,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Container(
                  height: 14,
                  width: 180,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildShimmerSubCompanyList() {
  return SizedBox(
    height: 85,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 4,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: const CircleAvatar(radius: 25),
            ),
            const SizedBox(height: 5),
            Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(
                height: 10,
                width: 50,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _buildShimmerClientStrip() {
  return SizedBox(
    height: 85,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: 5,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          children: [
            Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: const CircleAvatar(radius: 25),
            ),
            const SizedBox(height: 5),
            Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Container(
                height: 10,
                width: 50,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

}
