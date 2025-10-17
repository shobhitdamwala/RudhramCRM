import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/custom_bottom_nav.dart';
import '../widgets/background_container.dart';
import '../utils/api_config.dart';

class SubCompanyInfoScreen extends StatefulWidget {
  final String subCompanyId;
  
  const SubCompanyInfoScreen({Key? key, required this.subCompanyId})
    : super(key: key);

    

  @override
  State<SubCompanyInfoScreen> createState() => _SubCompanyInfoScreenState();
}

class _SubCompanyInfoScreenState extends State<SubCompanyInfoScreen> {
  bool _loading = true;
  String? _error;

  Map<String, dynamic>? _subCompany;
  List<dynamic> _clients = [];
  Map<String, dynamic>? userData;
  int? _selectedClientIndex;

  // 🆕 Track only assigned clients
  Set<String> _assignedClientIds = {};

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      final url = Uri.parse(
        "${ApiConfig.baseUrl}/subcompany/${widget.subCompanyId}/details",
      );
      final res = await http.get(
        url,
        headers: {
          if (token != null) "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      if (res.statusCode != 200) {
        setState(() {
          _error = "Failed to load details (${res.statusCode}).";
          _loading = false;
        });
        return;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final clients = List.from(body['clients'] ?? []);

      // 🆕 Build assigned client set (if needed, use field like isAssigned or validate through API)
      _assignedClientIds = clients
          .map((c) => (c['_id'] ?? c['id'] ?? '').toString())
          .where((id) => id.isNotEmpty)
          .toSet();

      setState(() {
        _subCompany = body['subCompany'] as Map<String, dynamic>?;
        _clients = clients;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Something went wrong.";
        _loading = false;
      });
    }
  }

  Map<String, dynamic>? get _selectedClient =>
      (_selectedClientIndex != null &&
          _selectedClientIndex! >= 0 &&
          _selectedClientIndex! < _clients.length)
      ? _clients[_selectedClientIndex!] as Map<String, dynamic>
      : null;

  List<Map<String, dynamic>> _teamForSelectedClient() {
    final client = _selectedClient;
    if (client == null) return [];
    final tasks = (client['tasks'] ?? []) as List<dynamic>;

    final Map<String, Map<String, dynamic>> byUser = {};
    for (final t in tasks) {
      final assignees = (t['assignedTo'] ?? []) as List<dynamic>;
      for (final a in assignees) {
        final userId = (a['userId'] ?? '').toString();
        if (userId.isEmpty) continue;
        final prev = byUser[userId];
        final int progress = (a['progress'] is num)
            ? (a['progress'] as num).toInt()
            : 0;
        if (prev == null || progress > (prev['progress'] ?? 0)) {
          byUser[userId] = {
            'userId': userId,
            'fullName': a['fullName'],
            'avatarUrl': a['avatarUrl'],
            'progress': progress,
            'assignmentStatus': a['assignmentStatus'],
          };
        }
      }
    }
    return byUser.values.toList();
  }

  Color _statusDot(String status) {
    final s = (status).toLowerCase();
    if (s.contains('done') || s.contains('complete')) return Colors.green;
    if (s.contains('progress') || s.contains('in_progress')) return Colors.blue;
    if (s.contains('block')) return Colors.red;
    if (s.contains('review')) return Colors.orange;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBody: true,
      body: BackgroundContainer(
        child: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.brown),
                )
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
                    const SizedBox(height: 8),
                    _buildClientStripOrSelected(),
                    Expanded(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_selectedClient != null) ...[
                              const SizedBox(height: 10),
                              _buildTeamStrip(),
                              const SizedBox(height: 16),
                              _buildFullWidthBox(
                                child: _buildClientDetailsBoxContent(),
                              ),
                              const SizedBox(height: 16),
                              _buildFullWidthBox(
                                child: _buildServicesBoxContent(),
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
    final sc = _subCompany;
    if (sc == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.brown[100],
            backgroundImage:
                (sc['logoUrl'] != null && (sc['logoUrl'] as String).isNotEmpty)
                ? NetworkImage(sc['logoUrl'])
                : null,
            child: (sc['logoUrl'] == null || (sc['logoUrl'] as String).isEmpty)
                ? Text(
                    (sc['name'] ?? 'S')[0].toString().toUpperCase(),
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
                  sc['name'] ?? '',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown,
                  ),
                ),
                Text(
                  sc['description'] ?? '',
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientStripOrSelected() {
    if (_selectedClientIndex == null) {
      if (_clients.isEmpty) {
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
            itemCount: _clients.length,
            itemBuilder: (context, i) {
              final client = _clients[i] as Map<String, dynamic>;
              final id = (client['_id'] ?? client['id'] ?? '').toString();
              final name = (client['name'] ?? '') as String;
              final logoUrl = client['logoUrl'] as String?;
              final isActive = _assignedClientIds.contains(id);

              return GestureDetector(
                onTap: isActive
                    ? () => setState(() => _selectedClientIndex = i)
                    : null,
                child: Opacity(
                  opacity: isActive ? 1.0 : 0.3,
                  child: SizedBox(
                    width: 60,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.brown[200],
                          backgroundImage:
                              (logoUrl != null && logoUrl.isNotEmpty)
                              ? NetworkImage(logoUrl)
                              : null,
                          child: (logoUrl == null || logoUrl.isEmpty)
                              ? Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
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
      final name = (client['name'] ?? '') as String;
      final logoUrl = client['logoUrl'] as String?;
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
                backgroundImage: (logoUrl != null && logoUrl.isNotEmpty)
                    ? NetworkImage(logoUrl)
                    : null,
                child: (logoUrl == null || logoUrl.isEmpty)
                    ? Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.brown,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      (client['meta']?['businessCategory'] ?? '').toString(),
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_drop_down, color: Colors.brown),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildTeamStrip() {
    final members = _teamForSelectedClient();
    if (members.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Text(
          "No team members assigned.",
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SizedBox(
        height: 85,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          scrollDirection: Axis.horizontal,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemCount: members.length,
          itemBuilder: (context, i) {
            final m = members[i];
            final name = (m['fullName'] ?? '') as String;
            final avatar = (m['avatarUrl'] ?? '') as String;
            final img = (avatar.isNotEmpty && !avatar.startsWith('http'))
                ? "${ApiConfig.imageBaseUrl}$avatar"
                : avatar;

            return SizedBox(
              width: 60,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Colors.brown[200],
                    backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                    child: img.isEmpty
                        ? Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildClientDetailsBoxContent() {
    final c = _selectedClient!;
    final businessName = (c['businessName'] ?? '').toString();
    final category = (c['meta']?['businessCategory'] ?? '').toString();

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
        if (category.isNotEmpty) Text(category),
      ],
    );
  }

  Widget _buildServicesBoxContent() {
    final c = _selectedClient!;
    final services = List.from(c['meta']?['chosenServices'] ?? []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Services",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 8),
        if (services.isEmpty)
          const Text(
            "No services assigned.",
            style: TextStyle(color: Colors.grey),
          )
        else
          ...services.map((s) {
            final Map<String, dynamic> svc = Map<String, dynamic>.from(s);
            final title = (svc['title'] ?? '').toString();
            final offerings = List.from(svc['offerings'] ?? []);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (offerings.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: offerings.take(4).map<Widget>((o) {
                          return Text(
                            "• ${o.toString()}",
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black87,
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
      ],
    );
  }

  Widget _buildWorkStatusBoxContent() {
    final c = _selectedClient!;
    final tasks = List.from(c['tasks'] ?? []);

    Color getStatusColor(String status) {
      switch (status) {
        case 'done':
          return Colors.green;
        case 'in_progress':
          return Colors.blue;
        case 'review':
          return Colors.orange;
        case 'blocked':
          return Colors.red;
        default:
          return Colors.grey;
      }
    }

    String getReadableStatus(String status) {
      switch (status) {
        case 'done':
          return 'Done';
        case 'in_progress':
          return 'In Progress';
        case 'review':
          return 'In Review';
        case 'blocked':
          return 'Blocked';
        case 'not_started':
          return 'Not Started';
        default:
          return status;
      }
    }

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
          ...tasks.map((t) {
            final Map<String, dynamic> task = Map<String, dynamic>.from(t);
            final title = (task['title'] ?? '').toString();
            final assignees = List.from(task['assignedTo'] ?? []);

            return Column(
              children: assignees.map<Widget>((a) {
                final Map<String, dynamic> asg = Map<String, dynamic>.from(a);
                final assigneeName = (asg['fullName'] ?? '').toString();
                final status = (asg['assignmentStatus'] ?? '').toString();
                final progress = (asg['progress'] is num)
                    ? (asg['progress'] as num).toDouble()
                    : 0.0;

                final statusColor = getStatusColor(status);
                final readableStatus = getReadableStatus(status);

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
                          Text(
                            assigneeName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.brown,
                            ),
                          ),
                          const SizedBox(width: 8),
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
                            readableStatus,
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
            );
          }).toList(),
      ],
    );
  }

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
}
