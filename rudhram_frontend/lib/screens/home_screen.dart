import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:rudhram_frontend/screens/active_lead_screen.dart';
import 'package:rudhram_frontend/utils/snackbar_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../widgets/background_container.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import '../utils/api_config.dart';
import '../utils/custom_bottom_nav.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/profile_header.dart';

import 'package:rudhram_frontend/screens/sub_company_info_screen.dart';
import 'package:rudhram_frontend/screens/team_member_details_screen.dart';
import 'package:rudhram_frontend/screens/lead_list_screen.dart';
import 'package:rudhram_frontend/screens/onboard_lead_screen.dart';
import '../screens/meeting_details_screen.dart'; // <- needed for navigation to meeting details

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? userData;
  List<dynamic> subCompanies = [];
  List<dynamic> teamMembers = [];
  bool isLoading = true;

  // Calendar / events state
  List<dynamic> allMeetings = [];
  List<dynamic> allTasks = [];
  Map<String, List<dynamic>> meetingsByDate = {}; // key: 'yyyy-MM-dd'
  Map<String, List<dynamic>> tasksByDate = {};
  DateTime calendarMonth = DateTime.now(); // currently displayed month

  @override
  void initState() {
    super.initState();
    fetchAllData();
  }

  Future<void> fetchAllData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        SnackbarHelper.show(
          context,
          title: "Not Logged In",
          message: "Please log in again.",
          type: ContentType.warning,
        );
        return;
      }

      // request user + lists and also fetch meetings/tasks for calendar
      await Future.wait([
        fetchUser(token),
        fetchSubCompanies(token),
        fetchTeamMembers(token),
        _fetchMeetingsAndTasks(token), // new: populate calendar events
      ]);
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: "Error",
        message: "Failed to fetch data: $e",
        type: ContentType.failure,
      );
    } finally {
      setState(() => isLoading = false);
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

  Future<void> fetchSubCompanies(String token) async {
    final response = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() => subCompanies = data['data']);
    }
  }

  Future<void> fetchTeamMembers(String token) async {
    final response = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
      headers: {"Authorization": "Bearer $token"},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        teamMembers = (data['teamMembers'] as List).map((m) {
          final member = Map<String, dynamic>.from(m);
          final avatarUrl = member['avatarUrl']?.toString() ?? '';
          if (avatarUrl.startsWith('/uploads')) {
            member['avatarUrl'] = "${ApiConfig.imageBaseUrl}$avatarUrl";
          }
          return member;
        }).toList();
      });
    }
  }

  /// -----------------------------
  /// Calendar: fetch meetings & tasks
  /// -----------------------------
  Future<void> _fetchMeetingsAndTasks(String token) async {
    // fetch meetings
    try {
      final mRes = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/meeting/getmeeting"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (mRes.statusCode == 200) {
        final data = jsonDecode(mRes.body);
        setState(() {
          allMeetings = List<dynamic>.from(data['data'] ?? []);
        });
      }
    } catch (e) {
      // ignore but optionally show snack
    }

    // fetch tasks
    try {
      final tRes = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/task/gettask"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (tRes.statusCode == 200) {
        final data = jsonDecode(tRes.body);
        setState(() {
          allTasks = List<dynamic>.from(data['data'] ?? []);
        });
      }
    } catch (e) {
      // ignore
    }

    // build date maps
    _buildDateMaps();
  }

  void _buildDateMaps() {
    final Map<String, List<dynamic>> mMap = {};
    final Map<String, List<dynamic>> tMap = {};
    final formatter = DateFormat('yyyy-MM-dd');

    for (final m in allMeetings) {
      try {
        final s = m['startTime']?.toString();
        if (s == null || s.isEmpty) continue;
        final dt = DateTime.parse(s).toLocal();
        final key = formatter.format(dt);
        mMap.putIfAbsent(key, () => []).add(m);
      } catch (_) {}
    }

    for (final t in allTasks) {
      try {
        final d = t['deadline']?.toString();
        if (d == null || d.isEmpty) continue;
        final dt = DateTime.parse(d).toLocal();
        final key = formatter.format(dt);
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

  // Move calendar forward/back a month
  void _changeMonth(int delta) {
    setState(() {
      calendarMonth = DateTime(calendarMonth.year, calendarMonth.month + delta, 1);
    });
  }

  // Show bottom sheet with details for that date
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
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              children: [
                // --- Header Bar ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF8B5E3C), Color(0xFFD2B48C)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('EEEE, dd MMM yyyy').format(date),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),

                // --- Scrollable Content ---
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Meetings Section
                        Row(
                          children: const [
                            Icon(Icons.video_call_rounded, color: Colors.brown),
                            SizedBox(width: 8),
                            Text(
                              "Meetings",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (meetings.isEmpty)
                          const Text(
                            "No meetings for this date",
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          ...meetings.map((m) {
                            final title = m['title'] ?? '-';
                            final start = _safeParseLocal(m['startTime']);
                            final end = _safeParseLocal(m['endTime']);
                            final timeLabel = (start != null && end != null)
                                ? '${DateFormat('h:mm a').format(start)} — ${DateFormat('h:mm a').format(end)}'
                                : '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFFFAF3),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 5,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                leading: const CircleAvatar(
                                  backgroundColor: Color(0xFFB87333),
                                  child: Icon(Icons.event_note, color: Colors.white),
                                ),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.brown,
                                  ),
                                ),
                                subtitle: Text(timeLabel, style: const TextStyle(color: Colors.black54)),
                                trailing: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryColor,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () {
                                    Navigator.pop(context);
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MeetingDetailsScreen(meeting: m),
                                      ),
                                    );
                                  },
                                  child: const Text('Details'),
                                ),
                              ),
                            );
                          }),

                        const SizedBox(height: 20),
                        const Divider(thickness: 1, color: Color(0xFFE0CDA9)),
                        const SizedBox(height: 10),

                        // Tasks Section
                        Row(
                          children: const [
                            Icon(Icons.task_rounded, color: Colors.brown),
                            SizedBox(width: 8),
                            Text(
                              "Tasks",
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (tasks.isEmpty)
                          const Text(
                            "No tasks for this date",
                            style: TextStyle(color: Colors.grey),
                          )
                        else
                          ...tasks.map((t) {
                            final title = t['title'] ?? '-';
                            final desc = t['description'] ?? '';
                            final status = t['status'] ?? '';
                            final priority = t['priority'] ?? '';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDFBF8),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
                                    blurRadius: 5,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                leading: const CircleAvatar(
                                  backgroundColor: Colors.brown,
                                  child: Icon(Icons.assignment, color: Colors.white),
                                ),
                                title: Text(
                                  title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Colors.brown,
                                  ),
                                ),
                                subtitle: Text(
                                  "$desc\nStatus: $status  •  Priority: $priority",
                                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                                ),
                                isThreeLine: true,
                                trailing: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.brown,
                                    side: const BorderSide(color: Colors.brown),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () {
                                    showDialog(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                        title: Text(
                                          title,
                                          style: const TextStyle(
                                            color: Colors.brown,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        content: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('Description: $desc'),
                                            const SizedBox(height: 8),
                                            Text('Status: $status'),
                                            const SizedBox(height: 8),
                                            Text('Priority: $priority'),
                                            const SizedBox(height: 8),
                                            Text(
                                              'Assigned To: ${(t['assignedTo'] ?? []).map((a) => a['fullName']).join(', ')}',
                                            ),
                                          ],
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Close', style: TextStyle(color: Colors.brown)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                  child: const Text('View'),
                                ),
                              ),
                            );
                          }),
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

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            /// 🔹 User Header
                            ProfileHeader(
                              avatarUrl: userData?['avatarUrl'],
                              fullName: userData?['fullName'],
                              role: userData?['role'] ?? '',
                              onNotification: () {
                                // handle notification icon tap
                                print("🔔 Notification tapped");
                              },
                            ),

                            const SizedBox(height: 15),

                            /// 🔹 Meeting Card (Static)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      "Meeting with client 03.00 PM",
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.brown,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            /// 🔹 Subcompany List
                            if (subCompanies.isNotEmpty)
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  // Calculate width dynamically to show exactly 6 items
                                  final double itemWidth =
                                      (constraints.maxWidth - 5 * 10) / 6;

                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      top: 4.0,
                                      bottom: 4.0,
                                    ),
                                    child: Wrap(
                                      spacing: 10,
                                      runSpacing: 10,
                                      alignment: WrapAlignment.center,
                                      children: List.generate(subCompanies.length, (
                                        index,
                                      ) {
                                        final sub = subCompanies[index];
                                        return GestureDetector(
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    SubCompanyInfoScreen(
                                                      subCompanyId:
                                                          sub['_id'],
                                                    ),
                                              ),
                                            );
                                          },

                                          child: SizedBox(
                                            width: itemWidth,
                                            child: Column(
                                              children: [
                                                Container(
                                                  width: itemWidth * 1.4,
                                                  height: itemWidth * 1.4,
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.white,
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(0.08),
                                                        blurRadius: 4,
                                                        offset: const Offset(
                                                          0,
                                                          2,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: ClipOval(
                                                    child:
                                                        sub['logoUrl'] != null
                                                        ? Image.network(
                                                            sub['logoUrl'],
                                                            fit: BoxFit.cover,
                                                            errorBuilder:
                                                                (
                                                                  _,
                                                                  __,
                                                                  ___,
                                                                ) => const Icon(
                                                                  Icons
                                                                      .image_not_supported,
                                                                  color: Colors
                                                                      .grey,
                                                                ),
                                                          )
                                                        : const Icon(
                                                            Icons.business,
                                                            color: Colors.brown,
                                                          ),
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  sub['name'] ?? '',
                                                  textAlign: TextAlign.center,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.brown,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }),
                                    ),
                                  );
                                },
                              ),

                            const SizedBox(height: 15),

                            // -------------------------
                            // Dynamic Calendar widget
                            // -------------------------
                            _buildCalendar(),

                            const SizedBox(height: 20),

                            /// 🔹 Static Stats
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              const LeadListScreen(),
                                        ),
                                      );
                                    },
                                    child: const _StatCard(
                                      title: "Leads",
                                      value: "150",
                                      icon: Icons.star_border,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const OnboardLeadScreen(),
                                        ),
                                      );
                                    },
                                    child: const _StatCard(
                                      title: "Onboard",
                                      value: "25",
                                      icon: Icons.star_border,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const ActiveLeadScreen(),
                                        ),
                                      );
                                    },
                                    child: const _StatCard(
                                      title: "Active",
                                      value: "10",
                                      icon: Icons.star_border,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 30),

                            /// 🔹 Team Members
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: const [
                                Text(
                                  "Team Members",
                                  style: TextStyle(
                                    color: Colors.brown,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                Text(
                                  "View All",
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _buildTeamRow(),
                            const SizedBox(height: 5),
                          ],
                        ),
                      ),
                    ),

                    CustomBottomNavBar(
                      currentIndex: 0, // you can set the active tab index
                      onTap: (index) {
                        // Handle navigation here
                        print("Tapped on $index");
                      },
                      userRole: userData?['role'] ?? '',
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Calendar widget (responsive + dynamic markers)
  Widget _buildCalendar() {
    final monthStart = DateTime(calendarMonth.year, calendarMonth.month, 1);
    final firstWeekday = monthStart.weekday % 7; // make Sunday = 0
    final daysInMonth = DateUtils.getDaysInMonth(calendarMonth.year, calendarMonth.month);
    final totalTiles = firstWeekday + daysInMonth;
    final weeks = (totalTiles / 7).ceil();

    final dayFormatter = DateFormat('yyyy-MM-dd');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0,2))],
      ),
      child: Column(
        children: [
          // header with month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left, color: Colors.brown)),
              Text(DateFormat('MMMM yyyy').format(calendarMonth), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.brown)),
              IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right, color: Colors.brown)),
            ],
          ),
          const SizedBox(height: 8),
          // weekday labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'].map((d) =>
              Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 12, color: Colors.grey))))).toList(),
          ),
          const SizedBox(height: 8),

          // days grid
          Column(
            children: List.generate(weeks, (weekIndex) {
              return Row(
                children: List.generate(7, (weekdayIndex) {
                  final tileIndex = weekIndex * 7 + weekdayIndex;
                  final dayNumber = tileIndex - firstWeekday + 1;
                  final bool inMonth = dayNumber >= 1 && dayNumber <= daysInMonth;
                  if (!inMonth) {
                    return Expanded(child: SizedBox(height: 48));
                  }

                  final date = DateTime(calendarMonth.year, calendarMonth.month, dayNumber);
                  final key = dayFormatter.format(date);
                  final hasMeeting = (meetingsByDate[key] ?? []).isNotEmpty;
                  final hasTask = (tasksByDate[key] ?? []).isNotEmpty;

                  return Expanded(
                    child: InkWell(
                      onTap: () => _showDateDetails(date),
                      child: Container(
                        height: 56,
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                        decoration: BoxDecoration(
                          color: DateFormat('yyyy-MM-dd').format(DateTime.now()) == key
                              ? AppColors.primaryColor.withOpacity(0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNumber',
                              style: TextStyle(
                                fontSize: 14,
                                color: DateFormat('yyyy-MM-dd').format(DateTime.now()) == key ? AppColors.primaryColor : Colors.brown,
                                fontWeight: DateFormat('yyyy-MM-dd').format(DateTime.now()) == key ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 6),
                            // markers row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (hasMeeting)
                                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.red)),
                                if (hasMeeting && hasTask) const SizedBox(width: 6),
                                if (hasTask)
                                  Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.blue)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// Team members row (unchanged)
  Widget _buildTeamRow() {
    if (teamMembers.isEmpty) {
      return const Text(
        "No team members found.",
        style: TextStyle(color: Colors.grey),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: teamMembers.map((m) {
          final String avatarUrl = (m['avatarUrl'] ?? '').toString();
          final String id = m['_id'] ?? '';
          final String fullName = m['fullName'] ?? '';

          final imageProvider = avatarUrl.isNotEmpty
              ? NetworkImage(avatarUrl)
              : const AssetImage('assets/user.jpg') as ImageProvider;

          return GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TeamMemberDetailsScreen(teamMemberId: id),
                ),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.brown[100],
                    backgroundImage: imageProvider,
                    child: avatarUrl.isEmpty
                        ? const Icon(
                            Icons.person,
                            color: Colors.brown,
                            size: 30,
                          )
                        : null,
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 55,
                    child: Text(
                      fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.brown,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Bottom Navbar (unchanged)
  Widget _buildBottomNavBar() {
    final List<Map<String, dynamic>> items = [
      {'icon': Icons.home_outlined},
      {'icon': Icons.task_alt_outlined},
      {'icon': Icons.grid_view_rounded},
      {'icon': Icons.groups_2_outlined},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ...items.take(2).map((item) => _buildSquareIcon(item['icon'])),
          _buildCenterCircleIcon(Icons.bolt_outlined),
          ...items.skip(2).map((item) => _buildSquareIcon(item['icon'])),
        ],
      ),
    );
  }

  Widget _buildSquareIcon(IconData icon) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: const Color(0xFFF5E6D3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: Colors.brown, size: 32),
    );
  }

  Widget _buildCenterCircleIcon(IconData icon) {
    return Container(
      width: 68,
      height: 68,
      decoration: const BoxDecoration(
        color: Color(0xFFF5E6D3),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: AppColors.primaryColor, size: 38),
    );
  }
}

/// Stat card widget (Static) - unchanged
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: AppColors.primaryColor, size: 30),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: AppColors.primaryColor,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              title,
              style: const TextStyle(color: Colors.brown, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
