import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_config.dart';
import '../utils/constants.dart';
import '../utils/snackbar_helper.dart';
import '../widgets/background_container.dart';
import '../widgets/profile_header.dart';
import '../utils/custom_bottom_nav.dart';
import '../screens/meeting_details_screen.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import 'package:share_plus/share_plus.dart';


/// ------------------------------
/// MEETING SCREEN (List + CRUD)
/// ------------------------------
class MeetingScreen extends StatefulWidget {
  const MeetingScreen({Key? key}) : super(key: key);

  @override
  State<MeetingScreen> createState() => _MeetingScreenState();
}

class _MeetingScreenState extends State<MeetingScreen> {
  final DateFormat _dtf = DateFormat('EEE, dd MMM · h:mm a');

  Map<String, dynamic>? userData;
  List<dynamic> meetings = [];
  bool isLoading = true;
  int _currentIndex = 3; // adapt to your nav mapping

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      if (token.isEmpty) return;
      await _fetchUser(token);
      await fetchMeetings();
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

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
      return "${ApiConfig.imageBaseUrl}$maybeRelative";
    }
    return "${ApiConfig.baseUrl}$maybeRelative";
  }

  Future<void> _fetchUser(String token) async {
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
      }
    } catch (_) {}
  }
  Future<void> fetchMeetings() async {
    setState(() => isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/meeting/getmeeting"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => meetings = List<dynamic>.from(data['data'] ?? []));
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to load meetings',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Load error: $e',
        type: ContentType.failure,
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deleteMeeting(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final res = await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/meeting/$id"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        setState(() => meetings.removeWhere((m) => m['_id'] == id));
        SnackbarHelper.show(
          context,
          title: 'Deleted',
          message: 'Meeting deleted',
          type: ContentType.success,
        );
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to delete meeting',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Delete error: $e',
        type: ContentType.failure,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              ProfileHeader(
                avatarUrl: userData?['avatarUrl'],
                fullName: userData?['fullName'],
                role: userData?['role'] ?? '',
                onNotification: () {},
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Meetings',
                        style: TextStyle(
                          color: AppColors.primaryColor,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.brown),
                      onPressed: fetchMeetings,
                      tooltip: 'Refresh',
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        final created = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddEditMeetingScreen(
                              currentUserId: userData?['_id'],
                            ),
                          ),
                        );
                        if (created == true) fetchMeetings();
                      },
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: const Text(
                        'New',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.brown),
                      )
                    : meetings.isEmpty
                    ? const Center(
                        child: Text(
                          'No meetings found',
                          style: TextStyle(color: Colors.brown),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: fetchMeetings,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: meetings.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) =>
                              _buildMeetingTile(meetings[i]),
                        ),
                      ),
              ),
              // Bottom spacing so it never clashes with system navbar
              const SizedBox(height: 6),
              CustomBottomNavBar(currentIndex: _currentIndex, onTap: (i) {},userRole: userData?['role'] ?? '',),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 90.0),
        child: FloatingActionButton.extended(
          backgroundColor: AppColors.primaryColor,
          onPressed: () async {
            final created = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    AddEditMeetingScreen(currentUserId: userData?['_id']),
              ),
            );
            if (created == true) fetchMeetings();
          },
          icon: const Icon(Icons.event_available, color: Colors.white),
          label: const Text(
            'Add Meeting',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildMeetingTile(dynamic m) {
    final start = _safeParse(m['startTime']);
    final end = _safeParse(m['endTime']);
    final withName = (m['meetingWithType'] == 'lead')
        ? (m['lead']?['name'] ?? 'Lead')
        : (m['client']?['name'] ?? 'Client');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.event_note, color: Colors.brown),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Row (Title + Share Icon)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          m['title'] ?? '-',
                          style: const TextStyle(
                            color: Colors.brown,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share, color: Colors.brown),
                        tooltip: 'Share meeting',
                        onPressed: () {
                          final shareText =
                              '''
📅 *${m['title'] ?? 'Meeting'}*
🕒 ${m['startTime'] ?? ''} - ${m['endTime'] ?? ''}
📍 ${m['location'] ?? 'Online'}
🔗 ${m['meetingLink'] ?? ''}
${m['meetingPassword'] != null && m['meetingPassword'].toString().isNotEmpty ? '🔒 Password: ${m['meetingPassword']}' : ''}
''';
                          Share.share(shareText, subject: 'Meeting Details');
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.schedule, size: 14, color: Colors.brown),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          start != null && end != null
                              ? '${_dtf.format(start)} — ${DateFormat('h:mm a').format(end)}'
                              : '-',
                          style: const TextStyle(fontSize: 12),
                          softWrap: true,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 14,
                        color: Colors.brown,
                      ),
                      const SizedBox(width: 6),
                      Text(withName, style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                  if ((m['location'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.place_outlined,
                          size: 14,
                          color: Colors.brown,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            m['location'],
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Right-side menu button (optional)
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'view') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MeetingDetailsScreen(meeting: m),
                    ),
                  );
                } else if (v == 'edit') {
                  final updated = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddEditMeetingScreen(
                        meeting: m,
                        currentUserId: userData?['_id'],
                      ),
                    ),
                  );
                  if (updated == true) fetchMeetings();
                } else if (v == 'delete') {
                  deleteMeeting(m['_id']);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'view', child: Text('View Details')),
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  DateTime? _safeParse(dynamic v) {
    try {
      if (v == null) return null;
      return DateTime.parse(v.toString()).toLocal();
    } catch (_) {
      return null;
    }
  }
}

/// ----------------------------------
/// ADD / EDIT MEETING SCREEN (Form)
/// ----------------------------------
class AddEditMeetingScreen extends StatefulWidget {
  final Map<String, dynamic>? meeting;
  final String? currentUserId; // default organizer

  const AddEditMeetingScreen({Key? key, this.meeting, this.currentUserId})
    : super(key: key);

  @override
  State<AddEditMeetingScreen> createState() => _AddEditMeetingScreenState();
}

class _AddEditMeetingScreenState extends State<AddEditMeetingScreen> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _agendaCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _meetingLinkCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  DateTime? _start;
  DateTime? _end;

  String? _selectedSubCompanyId;
  String? _selectedOrganizerId;
  String? _selectedLeadId;
  String? _selectedClientId;
  final List<String> _selectedParticipants = [];

  // data sources
  List<dynamic> subCompanies = [];
  List<dynamic> teamMembers = [];
  List<dynamic> leads = [];
  List<dynamic> clients = [];

  bool isLoading = false;
  bool isEditing = false;

  @override
  void initState() {
    super.initState();
    isEditing = widget.meeting != null;
    _bootstrap();
    if (isEditing) _fillFromMeeting(widget.meeting!);
  }

  Future<void> _bootstrap() async {
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _fetchSubCompanies(),
        _fetchTeamMembers(),
        _fetchLeads(),
        _fetchClients(),
      ]);
      if (!isEditing) {
        _selectedOrganizerId = widget.currentUserId; // default organizer
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _fillFromMeeting(Map<String, dynamic> m) {
    _titleCtrl.text = m['title'] ?? '';
    _agendaCtrl.text = m['agenda'] ?? '';
    _locationCtrl.text = m['location'] ?? '';
    _meetingLinkCtrl.text = m['meetingLink'] ?? '';
    _passwordCtrl.text = m['meetingPassword'] ?? '';
    _notesCtrl.text = m['notes'] ?? '';
    _start = m['startTime'] != null
        ? DateTime.parse(m['startTime']).toLocal()
        : null;
    _end = m['endTime'] != null ? DateTime.parse(m['endTime']).toLocal() : null;

    _selectedSubCompanyId = m['subCompany'] is Map
        ? m['subCompany']['_id']
        : m['subCompany'];
    _selectedOrganizerId = m['organizer'] is Map
        ? m['organizer']['_id']
        : m['organizer'];
    _selectedLeadId = m['lead'] is Map ? m['lead']['_id'] : m['lead'];
    _selectedClientId = m['client'] is Map ? m['client']['_id'] : m['client'];

    if (m['participants'] != null) {
      for (final p in (m['participants'] as List)) {
        final id = p is Map ? p['_id'] : p;
        if (id != null) _selectedParticipants.add(id);
      }
    }
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
  }

  Future<void> _fetchSubCompanies() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => subCompanies = List<dynamic>.from(data['data'] ?? []));
    }
  }

  Future<void> _fetchTeamMembers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(
        () => teamMembers = List<dynamic>.from(data['teamMembers'] ?? []),
      );
    }
  }

  Future<void> _fetchLeads() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/lead/getlead"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => leads = List<dynamic>.from(data['data'] ?? []));
    }
  }

  Future<void> _fetchClients() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    final res = await http.get(
      Uri.parse("${ApiConfig.baseUrl}/client/getclient"),
      headers: {"Authorization": "Bearer $token"},
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      setState(() => clients = List<dynamic>.from(data['data'] ?? []));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // backend requires either lead or client
    if (_selectedLeadId == null && _selectedClientId == null) {
      SnackbarHelper.show(
        context,
        title: 'Validation',
        message: 'Select a Lead or a Client',
        type: ContentType.warning,
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));

    final body = {
      'title': _titleCtrl.text.trim(),
      'agenda': _agendaCtrl.text.trim(),
      'subCompany': _selectedSubCompanyId,
      'organizer': _selectedOrganizerId,
      'participants': _selectedParticipants,
      'lead': _selectedLeadId,
      'client': _selectedClientId,
      'startTime': _start?.toUtc().toIso8601String(),
      'endTime': _end?.toUtc().toIso8601String(),
      'location': _locationCtrl.text.trim(),
      'meetingLink': _meetingLinkCtrl.text.trim(),
      'meetingPassword': _passwordCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
    }..removeWhere((k, v) => v == null || (v is String && v.isEmpty));

    setState(() => isLoading = true);

    final isEditing = widget.meeting != null;
    final url = isEditing
        ? Uri.parse("${ApiConfig.baseUrl}/meeting/${widget.meeting!['_id']}")
        : Uri.parse("${ApiConfig.baseUrl}/meeting/addmeeting");

    late http.Response res;
    try {
      if (isEditing) {
        res = await http.put(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        );
      } else {
        res = await http.post(
          url,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        );
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!mounted) return;
        SnackbarHelper.show(
          context,
          title: 'Success',
          message: isEditing ? 'Meeting updated' : 'Meeting created',
          type: ContentType.success,
        );
        Navigator.pop(context, true);
      } else {
        final err = jsonDecode(res.body);
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: err['message'] ?? 'Save failed',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Save error: $e',
        type: ContentType.failure,
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.meeting == null ? 'Add Meeting' : 'Edit Meeting'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _textField(
                      _titleCtrl,
                      'Title',
                      Icons.title,
                      required: true,
                    ),
                    _textField(
                      _agendaCtrl,
                      'Agenda',
                      Icons.summarize,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),

                    // SubCompany
                    _labeled(
                      'Sub Company',
                      DropdownButtonFormField<String>(
                        value:
                            subCompanies.any(
                              (s) => s['_id'] == _selectedSubCompanyId,
                            )
                            ? _selectedSubCompanyId
                            : null,
                        isExpanded: true,
                        decoration: _decor(
                          'Select Sub Company',
                          Icons.business,
                        ),
                        items: subCompanies
                            .map(
                              (s) => DropdownMenuItem<String>(
                                value: s['_id'],
                                child: Text(
                                  s['name'] ?? '-',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedSubCompanyId = v),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Organizer
                    _labeled(
                      'Organizer',
                      DropdownButtonFormField<String>(
                        value:
                            teamMembers.any(
                              (u) => u['_id'] == _selectedOrganizerId,
                            )
                            ? _selectedOrganizerId
                            : null,
                        isExpanded: true,
                        decoration: _decor(
                          'Select Organizer',
                          Icons.badge_outlined,
                        ),
                        items: teamMembers
                            .map(
                              (u) => DropdownMenuItem<String>(
                                value: u['_id'],
                                child: Text(
                                  u['fullName'] ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedOrganizerId = v),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Participants chips (multi-select)
                    const Text(
                      'Participants',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.brown,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: _box(),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: teamMembers.map((tm) {
                          final id = tm['_id'];
                          final selected = _selectedParticipants.contains(id);
                          return FilterChip(
                            label: Text(tm['fullName'] ?? ''),
                            selected: selected,
                            onSelected: (val) {
                              setState(() {
                                if (val) {
                                  _selectedParticipants.add(id);
                                } else {
                                  _selectedParticipants.remove(id);
                                }
                              });
                            },
                            selectedColor: AppColors.primaryColor.withOpacity(
                              0.2,
                            ),
                            checkmarkColor: AppColors.primaryColor,
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Lead / Client (mutually exclusive)
                    Row(
                      children: [
                        Expanded(
                          child: _labeled(
                            'Lead (optional)',
                            DropdownButtonFormField<String>(
                              value:
                                  leads.any((l) => l['_id'] == _selectedLeadId)
                                  ? _selectedLeadId
                                  : null,
                              isExpanded: true,
                              decoration: _decor(
                                'Select Lead',
                                Icons.person_search_outlined,
                              ),
                              items: leads
                                  .map(
                                    (l) => DropdownMenuItem<String>(
                                      value: l['_id'],
                                      child: Text(
                                        l['name'] ?? '',
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _selectedLeadId = v;
                                if (v != null)
                                  _selectedClientId =
                                      null; // only one of them allowed
                              }),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _labeled(
                            'Client (optional)',
                            DropdownButtonFormField<String>(
                              value:
                                  clients.any(
                                    (c) => c['_id'] == _selectedClientId,
                                  )
                                  ? _selectedClientId
                                  : null,
                              isExpanded: true,
                              decoration: _decor(
                                'Select Client',
                                Icons.person_outline,
                              ),
                              items: clients
                                  .map(
                                    (c) => DropdownMenuItem<String>(
                                      value: c['_id'],
                                      child: Text(
                                        c['name'] ?? '',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setState(() {
                                _selectedClientId = v;
                                if (v != null)
                                  _selectedLeadId =
                                      null; // only one of them allowed
                              }),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // Start & End
                    Row(
                      children: [
                        Expanded(child: _dateTimePicker('Start', true)),
                        const SizedBox(width: 10),
                        Expanded(child: _dateTimePicker('End', false)),
                      ],
                    ),

                    const SizedBox(height: 12),

                    _textField(_locationCtrl, 'Location', Icons.place_outlined),
                    _textField(_meetingLinkCtrl, 'Meeting Link', Icons.link),

                    // ✅ Meeting Password (with visibility toggle)
                    const Text(
                      'Meeting Password (optional)',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.brown,
                      ),
                    ),
                    const SizedBox(height: 6),

                    StatefulBuilder(
                      builder: (context, setStatePassword) {
                        bool isVisible = false;
                        return TextFormField(
                          controller: _passwordCtrl, // ✅ use global controller
                          obscureText: !isVisible,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(
                              Icons.lock_outline,
                              color: Colors.brown,
                            ),
                            labelText: 'Meeting Password',
                            filled: true,
                            fillColor: Colors.white,
                            suffixIcon: IconButton(
                              icon: Icon(
                                isVisible
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.brown,
                              ),
                              onPressed: () {
                                setStatePassword(() {
                                  isVisible = !isVisible;
                                });
                              },
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: AppColors.primaryColor,
                                width: 1.5,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),

                    _textField(_notesCtrl, 'Notes', Icons.notes, maxLines: 3),
                    const SizedBox(height: 20),

                    Center(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 14,
                          ),
                        ),
                        onPressed: isLoading ? null : _save,
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: Text(
                          widget.meeting == null
                              ? 'Add Meeting'
                              : 'Update Meeting',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------------- UI helpers ----------------
  InputDecoration _decor(String label, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.brown),
      labelText: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primaryColor, width: 1.5),
      ),
    );
  }

  BoxDecoration _box() => BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: Colors.brown.shade300),
  );

  Widget _labeled(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.brown,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  Widget _textField(
    TextEditingController c,
    String label,
    IconData icon, {
    int maxLines = 1,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: c,
        maxLines: maxLines,
        decoration: _decor(label, icon),
        validator: (v) {
          if (!required) return null;
          if (v == null || v.trim().isEmpty) return '$label is required';
          return null;
        },
      ),
    );
  }

  Widget _dateTimePicker(String label, bool isStart) {
    final value = isStart ? _start : _end;
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final pickedDate = await showDatePicker(
          context: context,
          initialDate: value ?? now,
          firstDate: DateTime(now.year - 1),
          lastDate: DateTime(now.year + 2),
        );
        if (pickedDate == null) return;
        final pickedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value ?? now),
        );
        if (pickedTime == null) return;
        final dt = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        setState(() {
          if (isStart) {
            _start = dt;
            if (_end == null || (_end!.isBefore(_start!))) {
              _end = _start!.add(const Duration(hours: 1));
            }
          } else {
            _end = dt;
          }
        });
      },
      child: InputDecorator(
        decoration: _decor(label, Icons.calendar_today),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value == null
                    ? 'Pick $label'
                    : DateFormat('EEE, dd MMM · h:mm a').format(value),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.calendar_today, color: Colors.brown),
          ],
        ),
      ),
    );
  }
}
