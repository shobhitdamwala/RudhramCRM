import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

import '../utils/api_config.dart';
import '../utils/constants.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/background_container.dart';
import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';
import '../screens/meeting_details_screen.dart';
import '../screens/teammember_home_screen.dart';

class TeamMemberDashboard extends StatefulWidget {
  const TeamMemberDashboard({super.key});

  @override
  State<TeamMemberDashboard> createState() => _TeamMemberDashboardState();
}

class _TeamMemberDashboardState extends State<TeamMemberDashboard> {
  Map<String, dynamic>? userData;
  List<Map<String, dynamic>> teamMembers = [];
  List<dynamic> allMeetings = [];
  List<dynamic> allTasks = [];
  int _recentVisible = 3;

  // events grouped by yyyy-MM-dd
  Map<String, List<dynamic>> meetingsByDate = {};
  Map<String, List<dynamic>> tasksByDate = {};

  DateTime calendarMonth = DateTime.now();
  bool isLoading = true;
  List<dynamic> recentTasks = [];
  List<dynamic> deadlineTasks = [];
  


  @override
  void initState() {
    super.initState();
    _loadAll();
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

  Future<void> _loadAll() async {
    try {
      setState(() => isLoading = true);
   

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        SnackbarHelper.show(
          context,
          title: 'Not logged in',
          message: 'Please log in again',
          type: ContentType.warning,
        );
        return;
      }

      await _fetchUser(token);
      await Future.wait([
        _fetchTeamMembers(token),
        _fetchMeetings(token),
        _fetchTasks(token),
      ]);

      _buildDateMaps();
      _prepareRecentAndDeadlines();
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Failed to load data: $e',
        type: ContentType.failure,
      );
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _fetchUser(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/me"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final u = Map<String, dynamic>.from(body['user'] ?? {});
        if (u['avatarUrl'] != null &&
            u['avatarUrl'].toString().startsWith('/')) {
          u['avatarUrl'] = _absUrl(u['avatarUrl']);
        }
        if (mounted) setState(() => userData = u);
      } else {
        await _showErrorSnack(res.body, fallback: 'Failed to fetch user');
      }
    } catch (_) {}
  }

  Future<void> _fetchTeamMembers(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final raw = List<dynamic>.from(body['teamMembers'] ?? []);
        teamMembers = raw
            .map<Map<String, dynamic>>(
              (m) => Map<String, dynamic>.from(m as Map),
            )
            .toList();
        for (var m in teamMembers) {
          final a = m['avatarUrl']?.toString() ?? '';
          if (a.startsWith('/uploads')) {
            m['avatarUrl'] = "${ApiConfig.imageBaseUrl}$a";
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _fetchMeetings(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/meeting/getmeeting"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        final raw = List<dynamic>.from(body['data'] ?? []);
        final myId = (userData?['_id'] ?? userData?['id'])?.toString();
        allMeetings = raw.where((m) {
          try {
            final participants = List<dynamic>.from(m['participants'] ?? []);
            if (myId != null && myId.isNotEmpty) {
              for (var p in participants) {
                if (p == null) continue;
                if (p is String && p == myId) return true;
                if (p is Map &&
                    ((p['_id']?.toString() ?? p['id']?.toString()) == myId)) {
                  return true;
                }
              }
              final organizer = m['organizer'];
              if (organizer != null &&
                  ((organizer is String && organizer == myId) ||
                      (organizer is Map &&
                          ((organizer['_id']?.toString() ??
                                  organizer['id']?.toString()) ==
                              myId)))) {
                return true;
              }
            }
            return false;
          } catch (_) {
            return false;
          }
        }).toList();
      }
    } catch (_) {}
  }

  Future<void> _fetchTasks(String token) async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/task/mytasks"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        allTasks = List<dynamic>.from(body['data'] ?? []);
      } else {
        final res2 = await http.get(
          Uri.parse("${ApiConfig.baseUrl}/task/gettask"),
          headers: {"Authorization": "Bearer $token"},
        );
        if (res2.statusCode == 200) {
          final body = jsonDecode(res2.body);
          final raw = List<dynamic>.from(body['data'] ?? []);
          final myId = (userData?['_id'] ?? userData?['id'])?.toString();
          if (myId != null && myId.isNotEmpty) {
            allTasks = raw.where((t) {
              try {
                final assignedTo = List<dynamic>.from(t['assignedTo'] ?? []);
                for (var a in assignedTo) {
                  if (a == null) continue;
                  if (a is String && a == myId) return true;
                  if (a is Map &&
                      ((a['_id']?.toString() ?? a['id']?.toString()) == myId)) {
                    return true;
                  }
                }
                final chosen = List<dynamic>.from(t['chosenServices'] ?? []);
                for (var s in chosen) {
                  final at = List<dynamic>.from(
                    s['assignedTeamMembers'] ?? s['assignedTo'] ?? [],
                  );
                  for (var a in at) {
                    if (a == null) continue;
                    if (a is String && a == myId) return true;
                    if (a is Map &&
                        ((a['_id']?.toString() ?? a['id']?.toString()) == myId))
                      return true;
                  }
                }
                return false;
              } catch (_) {
                return false;
              }
            }).toList();
          } else {
            allTasks = raw;
          }
        }
      }
    } catch (_) {}
  }

  void _buildDateMaps() {
    final Map<String, List<dynamic>> mMap = {};
    final Map<String, List<dynamic>> tMap = {};
    final fmt = DateFormat('yyyy-MM-dd');

    for (final m in allMeetings) {
      try {
        final start = m['startTime']?.toString();
        if (start == null) continue;
        final dt = DateTime.parse(start).toLocal();
        final key = fmt.format(dt);
        mMap.putIfAbsent(key, () => []).add(m);
      } catch (_) {}
    }

    for (final t in allTasks) {
      try {
        final d = t['deadline']?.toString();
        if (d == null) continue;
        final dt = DateTime.parse(d).toLocal();
        final key = fmt.format(dt);
        tMap.putIfAbsent(key, () => []).add(t);
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        meetingsByDate = mMap;
        tasksByDate = tMap;
      });
    }
  }

 void _prepareRecentAndDeadlines() {
  // recent tasks (sorted newest first)
  final sorted = List<dynamic>.from(allTasks);
  sorted.sort((a, b) {
    final aT = DateTime.tryParse(a['updatedAt']?.toString() ?? a['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bT = DateTime.tryParse(b['updatedAt']?.toString() ?? b['createdAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return bT.compareTo(aT);
  });

  recentTasks = sorted;                      // ← keep ALL
  _recentVisible = recentTasks.isEmpty
      ? 0
      : (recentTasks.length < 3 ? recentTasks.length : 3); // reset to 3

  // deadlines within 3 days (unchanged)
  final now = DateTime.now();
  final upcoming = allTasks.where((t) {
    try {
      final d = DateTime.parse(t['deadline'].toString()).toLocal();
      final diff = d.difference(now);
      return diff.inDays >= 0 && diff.inDays <= 3;
    } catch (_) {
      return false;
    }
  }).toList();

  if (mounted) setState(() => deadlineTasks = upcoming);
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
    String fallback = 'Request failed',
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

  String _memberNameFrom(dynamic a) {
    try {
      if (a == null) return '';
      if (a is Map) {
        return (a['fullName'] ?? a['name'] ?? a['_id'] ?? a['id'] ?? '')
            .toString();
      }
      final sid = a.toString();
      final found = teamMembers.firstWhere(
        (m) => (m['_id']?.toString() == sid || m['id']?.toString() == sid),
        orElse: () => {},
      );
      if (found.isNotEmpty) {
        return (found['fullName'] ?? found['name'] ?? sid).toString();
      }
      return sid;
    } catch (_) {
      return a.toString();
    }
  }

  // calendar navigation
  void _changeMonth(int delta) {
    setState(() {
      calendarMonth = DateTime(
        calendarMonth.year,
        calendarMonth.month + delta,
        1,
      );
    });
  }

  // show bottomsheet for a date
  void _showDateDetails(DateTime date) {
    final key = DateFormat('yyyy-MM-dd').format(date);
    final meetings = meetingsByDate[key] ?? [];
    final tasks = tasksByDate[key] ?? [];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.45,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primaryColor,
                          AppColors.primaryColor.withOpacity(0.85),
                        ],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('EEEE, dd MMM yyyy').format(date),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(
                                Icons.video_call_rounded,
                                color: Colors.brown,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Meetings',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.brown,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (meetings.isEmpty)
                            const Text(
                              'No meetings on this date',
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            ...meetings.map((m) {
                              final title = m['title'] ?? m['agenda'] ?? '-';
                              final start = _safeParseLocal(m['startTime']);
                              final end = _safeParseLocal(m['endTime']);
                              final timeLabel = (start != null && end != null)
                                  ? '${DateFormat('h:mm a').format(start)} — ${DateFormat('h:mm a').format(end)}'
                                  : '';
                              final participants = List<dynamic>.from(
                                m['participants'] ?? [],
                              );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryColor,
                                    child: const Icon(
                                      Icons.event_note,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.brown,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (timeLabel.isNotEmpty)
                                        Text(
                                          timeLabel,
                                          style: const TextStyle(
                                            color: Colors.black54,
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Participants: ${participants.map((p) => _memberNameFrom(p)).join(', ')}',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: ElevatedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              MeetingDetailsScreen(meeting: m),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('Details'),
                                  ),
                                ),
                              );
                            }),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 8),
                          Row(
                            children: const [
                              Icon(Icons.task_alt_rounded, color: Colors.brown),
                              SizedBox(width: 8),
                              Text(
                                'Tasks',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.brown,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (tasks.isEmpty)
                            const Text(
                              'No tasks on this date',
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            ...tasks.map((t) {
                              final title = t['title'] ?? '-';
                              final desc = (t['description'] ?? '').toString();
                              final status = t['status'] ?? '';
                              final priority = t['priority'] ?? '';
                              final myId = (userData?['_id'] ?? userData?['id'])
                                  ?.toString();
                              final chosen = List<dynamic>.from(
                                t['chosenServices'] ?? [],
                              );
                              final assignedServicesForMe =
                                  (myId != null && myId.isNotEmpty)
                                  ? chosen.where((s) {
                                      final at = List<dynamic>.from(
                                        s['assignedTeamMembers'] ??
                                            s['assignedTo'] ??
                                            [],
                                      );
                                      for (var a in at) {
                                        if (a == null) continue;
                                        if (a is String && a == myId) {
                                          return true;
                                        }
                                        if (a is Map &&
                                            ((a['_id']?.toString() ??
                                                    a['id']?.toString()) ==
                                                myId)) {
                                          return true;
                                        }
                                      }
                                      return false;
                                    }).toList()
                                  : chosen;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.shade200,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.04),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: AppColors.primaryColor,
                                    child: const Icon(
                                      Icons.assignment,
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(
                                    title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.brown,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        desc,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.black54,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Status: $status  •  Priority: $priority',
                                        style: const TextStyle(
                                          color: Colors.black54,
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (assignedServicesForMe.isNotEmpty)
                                        const SizedBox(height: 8),
                                      if (assignedServicesForMe.isNotEmpty)
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 6,
                                          children: assignedServicesForMe
                                              .map<Widget>((s) {
                                                final stitle =
                                                    s['title'] ??
                                                    s['serviceTitle'] ??
                                                    '-';
                                                return Chip(
                                                  label: Text(
                                                    stitle.toString(),
                                                  ),
                                                  backgroundColor:
                                                      Colors.grey[100],
                                                );
                                              })
                                              .toList(),
                                        ),
                                    ],
                                  ),
                                  isThreeLine: true,
                                  trailing: OutlinedButton(
                                    onPressed: () {
                                      Navigator.pop(context);
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const TeamMemberHomeScreen(),
                                        ),
                                      );
                                    },
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: AppColors.primaryColor,
                                      ),
                                      foregroundColor: AppColors.primaryColor,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Text('View'),
                                  ),
                                ),
                              );
                            }),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  DateTime? _safeParseLocal(dynamic v) {
    try {
      if (v == null) return null;
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }

  /// ===================== CALENDAR UI (overflow-safe, aesthetic) =====================
  Widget _buildCalendar() {
    final monthStart = DateTime(calendarMonth.year, calendarMonth.month, 1);
    final firstWeekday = monthStart.weekday % 7; // Sunday = 0
    final daysInMonth = DateUtils.getDaysInMonth(
      calendarMonth.year,
      calendarMonth.month,
    );
    final totalTiles = firstWeekday + daysInMonth;
    final weeks = (totalTiles / 7).ceil();
    final fmt = DateFormat('yyyy-MM-dd');

    final now = DateTime.now();
    bool isSameDay(DateTime a, DateTime b) =>
        a.year == b.year && a.month == b.month && a.day == b.day;

    final screenW = MediaQuery.of(context).size.width;
    final isWide = screenW >= 720;
    final cellH = isWide ? 72.0 : 68.0;

    Widget weekdayLabel(String d) => Expanded(
      child: Center(
        child: Text(
          d,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF8A7E72),
            letterSpacing: .2,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );

    // Header
    Widget header = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFE6D9), Color(0xFFFFF4ED)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left, color: Color(0xFF6E594A)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  DateFormat('MMMM').format(calendarMonth),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6E594A),
                  ),
                ),
                Text(
                  '${calendarMonth.year}  •  ${DateUtils.getDaysInMonth(calendarMonth.year, calendarMonth.month)} days',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9C8E82),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right, color: Color(0xFF6E594A)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () {
              setState(() {
                calendarMonth = DateTime(now.year, now.month, 1);
              });
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: AppColors.primaryColor.withOpacity(.25),
                ),
              ),
              backgroundColor: AppColors.primaryColor.withOpacity(.06),
            ),
            icon: const Icon(Icons.today, size: 18),
            label: const Text(
              'Today',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    // Body with AnimatedSwitcher
    Widget monthBody = AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final offsetAnim = Tween<Offset>(
          begin: const Offset(0, .06),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: offsetAnim, child: child),
        );
      },
      child: Column(
        key: ValueKey('${calendarMonth.year}-${calendarMonth.month}'),
        children: [
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: const [
              'Sun',
              'Mon',
              'Tue',
              'Wed',
              'Thu',
              'Fri',
              'Sat',
            ].map((d) => weekdayLabel(d)).toList(),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFAF6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFF0E6DF)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              children: List.generate(weeks, (wi) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: List.generate(7, (xi) {
                      final tileIndex = wi * 7 + xi;
                      final dayNumber = tileIndex - firstWeekday + 1;
                      final inMonth =
                          dayNumber >= 1 && dayNumber <= daysInMonth;

                      if (!inMonth) {
                        return const Expanded(child: SizedBox(height: 56));
                      }

                      final date = DateTime(
                        calendarMonth.year,
                        calendarMonth.month,
                        dayNumber,
                      );
                      final key = DateFormat('yyyy-MM-dd').format(date);
                      final hasMeeting = (meetingsByDate[key] ?? []).isNotEmpty;
                      final hasTask = (tasksByDate[key] ?? []).isNotEmpty;
                      final isToday = isSameDay(date, now);

                      final mCount = (meetingsByDate[key] ?? []).length;
                      final tCount = (tasksByDate[key] ?? []).length;

                      return Expanded(
                        child: _DayCell(
                          height: cellH,
                          dayNumber: dayNumber,
                          isToday: isToday,
                          hasMeeting: hasMeeting,
                          hasTask: hasTask,
                          meetingsCount: mCount,
                          tasksCount: tCount,
                          onTap: () => _showDateDetails(date),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );

    // Legend
    Widget legend = const Padding(
      padding: EdgeInsets.fromLTRB(8, 0, 8, 12),
      child: Row(
        children: [
          _Legend(kind: 'Meetings', color: Colors.red),
          SizedBox(width: 16),
          _Legend(kind: 'Tasks', color: Colors.blue),
        ],
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9DED6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: [header, monthBody, legend]),
    );
  }

 Widget _buildRecentActivity() {
  if (recentTasks.isEmpty) return const SizedBox.shrink();

  final visible = recentTasks.take(_recentVisible).toList();
  final canShowMore = _recentVisible < recentTasks.length;
  final canShowLess = recentTasks.length > 3 && !canShowMore; // fully expanded

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Recent Tasks',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.brown,
        ),
      ),
      const SizedBox(height: 8),

      // render only visible tasks
      ...visible.map((t) {
        final title = t['title'] ?? '-';
        final status = t['status'] ?? '';
        final progress = t['progress'] ?? 0;
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primaryColor,
              child: const Icon(Icons.assignment, color: Colors.white),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.brown,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text('Status: $status • $progress%'),
            onTap: () {
              DateTime? d;
              try {
                d = DateTime.parse(t['deadline'].toString()).toLocal();
              } catch (_) {}
              if (d != null) _showDateDetails(d);
            },
          ),
        );
      }),

      // controls
      if (canShowMore || canShowLess) ...[
        const SizedBox(height: 4),
        Center(
          child: TextButton(
            onPressed: () {
              setState(() {
                if (canShowMore) {
                  _recentVisible =
                      (_recentVisible + 5).clamp(0, recentTasks.length);
                } else {
                  _recentVisible = 3; // collapse back to first 3
                }
              });
            },
            child: Text(
              canShowMore ? 'View more' : 'View less',
              style: TextStyle(
                color: AppColors.primaryColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    ],
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: AppColors.primaryColor,
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProfileHeader(
                              avatarUrl: userData?['avatarUrl'],
                              fullName: userData?['fullName'],
                              role: formatUserRole(userData?['role']),
                              onNotification: () {},
                            ),
                            const SizedBox(height: 16),
                            if (deadlineTasks.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primaryColor,
                                      AppColors.primaryColor.withOpacity(0.85),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.primaryColor.withOpacity(
                                        0.12,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.notifications_active,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'You have ${deadlineTasks.length} upcoming task${deadlineTasks.length > 1 ? 's' : ''}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () =>
                                          setState(() => deadlineTasks = []),
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            _buildCalendar(),
                            const SizedBox(height: 16),
                            _buildRecentActivity(),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ),
                    ),
                    CustomBottomNavBar(
                      currentIndex: 0,
                      onTap: (i) {},
                      userRole: userData?['role'] ?? '',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// Legend item (small dot + label)
class _Legend extends StatelessWidget {
  final String kind;
  final Color color;
  const _Legend({required this.kind, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          kind,
          style: const TextStyle(fontSize: 12, color: Color(0xFF7B6D61)),
        ),
      ],
    );
  }
}

/// Single day cell (overflow-safe & animated)
class _DayCell extends StatefulWidget {
  final double height;
  final int dayNumber;
  final bool isToday;
  final bool hasMeeting;
  final bool hasTask;
  final int meetingsCount;
  final int tasksCount;
  final VoidCallback onTap;

  const _DayCell({
    required this.height,
    required this.dayNumber,
    required this.isToday,
    required this.hasMeeting,
    required this.hasTask,
    required this.meetingsCount,
    required this.tasksCount,
    required this.onTap,
  });

  @override
  State<_DayCell> createState() => _DayCellState();
}

class _DayCellState extends State<_DayCell>
    with SingleTickerProviderStateMixin {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    final bg = widget.isToday
        ? AppColors.primaryColor.withOpacity(0.10)
        : Colors.transparent;

    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = .96),
      onTapCancel: () => setState(() => _scale = 1),
      onTapUp: (_) => setState(() => _scale = 1),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        child: Container(
          height: widget.height,
          // reduced horizontal margin -> avoids overflow in 7 columns
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${widget.dayNumber}',
                style: TextStyle(
                  fontSize: 14,
                  color: widget.isToday
                      ? AppColors.primaryColor
                      : const Color(0xFF6E594A),
                  fontWeight: widget.isToday
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4), // was 6
              // This makes the badges shrink if needed so no overflow happens
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.hasMeeting)
                        _badge(count: widget.meetingsCount, color: Colors.red),
                      if (widget.hasMeeting && widget.hasTask)
                        const SizedBox(width: 6),
                      if (widget.hasTask)
                        _badge(count: widget.tasksCount, color: Colors.blue),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badge({required int count, required Color color}) {
    return AnimatedOpacity(
      opacity: 1,
      duration: const Duration(milliseconds: 160),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 56, maxHeight: 20),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 1.5,
          ), // was 2
          decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(.45)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6.5,
                height: 6.5, // slightly smaller dot
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10, // was 10.5
                  color: _darken(color),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _darken(Color c, [double amount = .2]) {
    final hsl = HSLColor.fromColor(c);
    final l = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }
}
