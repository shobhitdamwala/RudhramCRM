import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import '../utils/custom_bottom_nav.dart';
import 'package:shimmer/shimmer.dart';

class TeamMemberDetailsScreen extends StatefulWidget {
  final String teamMemberId;
  const TeamMemberDetailsScreen({Key? key, required this.teamMemberId})
    : super(key: key);

  @override
  State<TeamMemberDetailsScreen> createState() =>
      _TeamMemberDetailsScreenState();
}

class _TeamMemberDetailsScreenState extends State<TeamMemberDetailsScreen> {
  bool _loading = true;
  String? _error;
Map<String, dynamic>? userData;
  Map<String, dynamic>? _teamMember;

  // All items from list APIs
  List<dynamic> _allSubCompanies = [];
  List<dynamic> _allClients = [];

  // From details API (what this member actually works on)
  Set<String> _memberSubCompanyIds = {};
  Set<String> _memberClientIds = {};
  Map<String, List<dynamic>> _tasksByClientId = {};

  int? _selectedClientIndex;
  String? _selectedSubCompanyId;

  @override
  void initState() {
    super.initState();
    _fetchAll();
  }

  Future<void> _fetchAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final headers = {
        if (token != null) "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      };

      // 1) Team member details
      final detRes = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/${widget.teamMemberId}/details"),
        headers: headers,
      );
      if (detRes.statusCode != 200) {
        throw Exception("Details load failed (${detRes.statusCode})");
      }
      final det = jsonDecode(detRes.body) as Map<String, dynamic>;

      _teamMember = Map<String, dynamic>.from(det['teamMember'] ?? {});

      // derive subcompany IDs the member works on
      final List<dynamic> memberSC = List<dynamic>.from(
        det['subCompanies'] ?? [],
      );
      _memberSubCompanyIds = memberSC
          .map((e) => (e is Map ? (e['_id'] ?? e['id'] ?? '').toString() : ''))
          .where((s) => s.isNotEmpty)
          .toSet();

      // derive client IDs + build tasks map
      final List<dynamic> memberClients = List<dynamic>.from(
        det['clients'] ?? [],
      );
      _memberClientIds = {};
      _tasksByClientId.clear();
      for (final c in memberClients) {
        if (c is Map) {
          final id = (c['_id'] ?? c['id'] ?? '').toString();
          if (id.isNotEmpty) {
            _memberClientIds.add(id);
            _tasksByClientId[id] = List<dynamic>.from(c['tasks'] ?? []);
          }
        }
      }

      // 2) All subcompanies
      final scRes = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"),
        headers: headers,
      );
      if (scRes.statusCode == 200) {
        final body = jsonDecode(scRes.body);
        _allSubCompanies = List<dynamic>.from(
          body['data'] ?? body['subCompanies'] ?? [],
        );
      }

      // 3) All clients
      final clRes = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/client/getclient"),
        headers: headers,
      );
      if (clRes.statusCode == 200) {
        final body = jsonDecode(clRes.body);
        _allClients = List<dynamic>.from(body['data'] ?? body['clients'] ?? []);
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = "Failed to load: $e";
        _loading = false;
      });
    }
  }

  // ---- Data helpers ---------------------------------------------------------

  List<Map<String, dynamic>> get _filteredClients {
    final all = _allClients.map<Map<String, dynamic>>((e) {
      return Map<String, dynamic>.from(e as Map);
    }).toList();

    if (_selectedSubCompanyId == null) return all;

    return all.where((c) {
      final direct = (c['subCompanyIds'] ?? []);
      final fromMeta =
          (c['meta'] != null ? c['meta']['subCompanyIds'] : []) ?? [];
      final List<String> ids = [
        ...List.from(direct),
        ...List.from(fromMeta),
      ].map((x) => x.toString()).toList();

      return ids.contains(_selectedSubCompanyId);
    }).toList();
  }

  Map<String, dynamic>? get _selectedClient =>
      (_selectedClientIndex != null &&
          _selectedClientIndex! >= 0 &&
          _selectedClientIndex! < _filteredClients.length)
      ? _filteredClients[_selectedClientIndex!]
      : null;

  Color _statusDot(String status) {
    final s = status.toLowerCase();
    if (s.contains('done')) return Colors.green;
    if (s.contains('progress') || s.contains('in_progress')) return Colors.blue;
    if (s.contains('block')) return Colors.red;
    if (s.contains('review')) return Colors.orange;
    return Colors.grey;
  }

  // ---- UI -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: BackgroundContainer(
        child: SafeArea(
          child: _loading
              ? _buildLoadingShimmer()
              : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    _buildHeader(),
                    const SizedBox(height: 25),
                    _buildSubCompanyStrip(),
                    const SizedBox(height: 8),
                    _buildClientStripOrSelected(),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedClient != null) ...[
                              const SizedBox(height: 16),
                              _buildFullWidthBox(
                                child: _buildClientDetailsBoxContent(),
                              ),
                              const SizedBox(height: 16),
                              _buildFullWidthBox(
                                child: _buildWorkStatusBoxContent(),
                              ),
                              const SizedBox(height: 24),
                            ] else ...[
                              const SizedBox(height: 20),
                              _buildSkeletonBox(),
                              const SizedBox(height: 16),
                              _buildSkeletonBox(),
                              const SizedBox(height: 24),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: CustomBottomNavBar(currentIndex: 6, onTap: (index) {},userRole: userData?['role'] ?? '',),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final tm = _teamMember;
    if (tm == null) return const SizedBox.shrink();

    final avatar = (tm['avatarUrl'] ?? '').toString();
    final img = (avatar.isNotEmpty && !avatar.startsWith('http'))
        ? "${ApiConfig.imageBaseUrl}$avatar"
        : avatar;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.brown[100],
            backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
            child: img.isEmpty
                ? Text(
                    (tm['fullName'] ?? 'U')[0].toString().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.brown,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tm['fullName'] ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                  ),
                ),
                Text(
                  tm['email'] ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubCompanyStrip() {
    if (_allSubCompanies.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 85,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        scrollDirection: Axis.horizontal,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: _allSubCompanies.length,
        itemBuilder: (context, i) {
          final sc = _allSubCompanies[i] as Map<String, dynamic>;
          final id = (sc['_id'] ?? sc['id'] ?? '').toString();
          final isActive = _memberSubCompanyIds.contains(id);
          final selected = id == _selectedSubCompanyId;

          return GestureDetector(
            onTap: isActive
                ? () {
                    setState(() {
                      _selectedClientIndex = null;
                      _selectedSubCompanyId = selected ? null : id;
                    });
                  }
                : null, // 👈 disabled if not active
            child: Opacity(
              opacity: isActive ? 1.0 : 0.3,
              child: _buildChip(sc['name'], sc['logoUrl'], selected),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChip(String? name, String? logoUrl, bool selected) {
    return SizedBox(
      width: 50,
      child: Column(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: selected ? Colors.brown : Colors.brown[200],
            backgroundImage: (logoUrl != null && logoUrl.isNotEmpty)
                ? NetworkImage(logoUrl)
                : null,
            child: (logoUrl == null || logoUrl.isEmpty)
                ? Text(
                    name != null && name.isNotEmpty
                        ? name[0].toUpperCase()
                        : '',
                    style: const TextStyle(color: Colors.white),
                  )
                : null,
          ),
          const SizedBox(height: 4),
          Text(
            name ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: selected ? Colors.brown : Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientStripOrSelected() {
    if (_selectedClientIndex == null) {
      if (_filteredClients.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: const Text(
            "No clients found.",
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: Colors.brown.withOpacity(0.05),
        child: SizedBox(
          height: 85,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            scrollDirection: Axis.horizontal,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemCount: _filteredClients.length,
            itemBuilder: (context, i) {
              final client = _filteredClients[i];
              final id = (client['_id'] ?? client['id'] ?? '').toString();
              final name = (client['name'] ?? '').toString();
              final isActive = _memberClientIds.contains(id);

              return GestureDetector(
                onTap: isActive
                    ? () => setState(() => _selectedClientIndex = i)
                    : null, // 👈 disabled if not assigned
                child: Opacity(
                  opacity: isActive ? 1.0 : 0.4,
                  child: SizedBox(
                    width: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.brown[200],
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    } else {
      final client = _selectedClient!;
      final name = (client['name'] ?? '').toString();
      return GestureDetector(
        onTap: () => setState(() => _selectedClientIndex = null),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.brown.withOpacity(0.05),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.brown[200],
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                    fontSize: 14,
                  ),
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.brown),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildClientDetailsBoxContent() {
    final c = _selectedClient!;
    final id = (c['_id'] ?? c['id'] ?? '').toString();
    final businessName = (c['businessName'] ?? '').toString();
    final tasksCount = (_tasksByClientId[id] ?? const []).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          businessName.isNotEmpty ? businessName : (c['name'] ?? ''),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        Text("Total Tasks: $tasksCount", style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildWorkStatusBoxContent() {
    final c = _selectedClient!;
    final id = (c['_id'] ?? c['id'] ?? '').toString();
    final tasks = List<Map<String, dynamic>>.from(
      (_tasksByClientId[id] ?? const []).map(
        (e) => Map<String, dynamic>.from(e as Map),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Work Status",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 10),
        if (tasks.isEmpty)
          const Text("No tasks assigned.", style: TextStyle(color: Colors.grey))
        else
          ...tasks.map((task) {
            final title = (task['title'] ?? '').toString();
            final status = (task['assignmentStatus'] ?? '').toString();
            final progress = (task['progress'] is num)
                ? (task['progress'] as num).toDouble()
                : 0.0;
            final statusColor = _statusDot(status);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        status.toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: (progress.clamp(0.0, 100.0)) / 100.0,
                          minHeight: 10,
                          backgroundColor: Colors.brown.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            statusColor,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          "${progress.toInt()}%",
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  // ---- Skeletons / Shimmer --------------------------------------------------

  Widget _buildSkeletonBox() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: double.infinity,
        height: 100,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFullWidthBox({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildLoadingShimmer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        _buildShimmerHeader(),
        const SizedBox(height: 12),
        _buildShimmerSubCompanyList(),
        const SizedBox(height: 12),
        _buildShimmerClientStrip(),
        const SizedBox(height: 20),
        _buildSkeletonBox(),
        const SizedBox(height: 16),
        _buildSkeletonBox(),
      ],
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
                  child: Container(height: 16, width: 120, color: Colors.white),
                ),
                const SizedBox(height: 8),
                Shimmer.fromColors(
                  baseColor: Colors.grey.shade300,
                  highlightColor: Colors.grey.shade100,
                  child: Container(height: 14, width: 180, color: Colors.white),
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
                child: Container(height: 10, width: 50, color: Colors.white),
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
                child: Container(height: 10, width: 50, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
