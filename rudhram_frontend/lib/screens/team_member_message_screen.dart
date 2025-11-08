import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:open_file/open_file.dart';
import '../services/open_any_file.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/api_config.dart';
import '../utils/constants.dart';
import '../screens/team_member_dashboard.dart';

/// Team Member message page:
/// - Chats list shows ONLY SUPER_ADMIN users
/// - Tabs: Chats, Rudhram (no Broadcast)
/// - User can delete ONLY their own messages (1:1 and group)
/// - No delete-entire-thread / clear-group options
class TeamMemberMessageScreen extends StatefulWidget {
  const TeamMemberMessageScreen({super.key});
  @override
  State<TeamMemberMessageScreen> createState() =>
      _TeamMemberMessageScreenState();
}

class _TeamMemberMessageScreenState extends State<TeamMemberMessageScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  // ---------- ROUTES (match your backend) ----------
  final String usersPath = "/user/users"; // GET (list members)
  String threadPath(String otherUserId) => "/message/$otherUserId"; // GET (1:1)
  final String postMessagePath = "/message"; // POST (send 1:1 or multi)
  final String deleteMessagePath = "/message"; // DELETE /message/:id
  final String inboxPath = "/message"; // GET all visible messages (for meta)
  final String groupListPath = "/message/group/rudhram"; // GET group feed
  final String postGroupPath = "/message/group"; // POST group message
  final String unreadPath = "/message/unread"; // GET unread counts
  // --------------------------------------------------

  // Common
  String? _authToken;
  Map<String, dynamic>? _me;
  String? _myId;
  String _myRole = "";
  bool _loadingUsers = true;
  List<dynamic> _users = [];

  // Unread counts
  final Map<String, int> _unreadDirect = {}; // partnerId -> unread count
  int _unreadGroup = 0; // Rudhram group unread total

  // Conversation meta (for ordering list by last activity)
  final Map<String, String> _lastTs = {}; // partnerId -> last message ISO

  // 1-to-1
  bool _loadingThread = false;
  String? _activeUserId;
  Map<String, List<dynamic>> _cachedThreads = {};
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _chatScroll = ScrollController();
  Timer? _pollTimer;

  // Group
  final TextEditingController _groupCtrl = TextEditingController();
  final ScrollController _groupScroll = ScrollController();
  List<dynamic> _groupMsgs = [];
  bool _loadingGroup = true;
  Timer? _groupPollTimer;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this); // Chats, Rudhram
    _tab.addListener(_handleTabChange);
    _bootstrap();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _groupPollTimer?.cancel();
    _msgCtrl.dispose();
    _groupCtrl.dispose();
    _chatScroll.dispose();
    _groupScroll.dispose();
    _tab.removeListener(_handleTabChange);
    _tab.dispose();
    super.dispose();
  }

  void _handleTabChange() {
    if (!_tab.indexIsChanging) {
      if (_tab.index == 1) {
        _startGroupPolling();
      } else {
        _groupPollTimer?.cancel();
      }
      setState(() {});
    }
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _authToken = prefs.getString("auth_token");
    final rawUser = prefs.getString("user");
    if (rawUser != null) {
      try {
        _me = jsonDecode(rawUser);
        _myId = (_me!["_id"] ?? _me!["id"])?.toString();
        _myRole = (_me!["role"] ?? "").toString();
      } catch (_) {}
    }
    await _fetchUsers();
    await _prefetchThreadMeta(); // last activity timestamps
    await _prefetchUnread(); // unread badges
    await _loadGroupMessages();
    _startGroupPolling();
  }

  // ---------------- USERS ----------------
  Future<void> _fetchUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}$usersPath"),
        headers: {"Authorization": "Bearer ${_authToken ?? ""}"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data is List) ? data : (data["data"] ?? []);
        // Filter to ONLY SUPER_ADMIN for team member view, and not me
        final onlyAdmins = List<dynamic>.from(list).where((u) {
          final role = (u["role"] ?? "").toString();
          final id = (u["_id"] ?? u["id"])?.toString();
          return role == "SUPER_ADMIN" && id != _myId;
        }).toList();
        setState(() => _users = onlyAdmins);
      } else {
        _toast("Failed to load users: ${res.statusCode}");
      }
    } catch (e) {
      _toast("Users error: $e");
    } finally {
      setState(() => _loadingUsers = false);
    }
  }

  /// Build last activity timestamps from inbox (for ordering).
  Future<void> _prefetchThreadMeta() async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}$inboxPath"),
        headers: {"Authorization": "Bearer ${_authToken ?? ""}"},
      );
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body);
      final list = (data["data"] ?? []) as List;
      _lastTs.clear();

      for (final raw in list) {
        final m = raw as Map;
        if ((m["channel"] ?? "direct") != "direct") continue;
        final sender = (m["sender"] ?? "").toString();

        String partner = "";
        if (sender == _myId) {
          final rec = m["receivers"];
          if (rec is List && rec.isNotEmpty) {
            final first = rec.first;
            partner = (first is Map)
                ? (first["_id"] ?? first["id"] ?? "").toString()
                : (rec.first ?? "").toString();
          } else if (rec is String) {
            partner = rec;
          }
        } else {
          partner = sender;
        }
        if (partner.isEmpty) continue;

        final ts = (m["createdAt"] ?? "").toString();
        if (!_lastTs.containsKey(partner)) {
          _lastTs[partner] = ts;
        } else {
          final prev = _lastTs[partner]!;
          if (_isAfter(ts, prev)) _lastTs[partner] = ts;
        }
      }
      setState(() {});
    } catch (_) {
      // ignore
    }
  }

  Future<void> _prefetchUnread() async {
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}$unreadPath"),
        headers: {"Authorization": "Bearer ${_authToken ?? ""}"},
      );
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body)["data"] ?? {};
      final direct = Map<String, dynamic>.from(data["direct"] ?? {});
      final group = Map<String, dynamic>.from(data["group"] ?? {});
      _unreadDirect
        ..clear()
        ..addAll(direct.map((k, v) => MapEntry(k, (v as num).toInt())));
      _unreadGroup = (group["RUDHRAM"] ?? 0) as int;

      setState(() {});
    } catch (_) {}
  }

  bool _isAfter(String a, String b) {
    try {
      return DateTime.parse(a).isAfter(DateTime.parse(b));
    } catch (_) {
      return false;
    }
  }

  // --------------- 1:1 THREADS ---------------
  Future<void> _openThread(String otherUserId, {bool force = false}) async {
    if (_activeUserId == otherUserId &&
        !force &&
        _cachedThreads[otherUserId] != null) {
      _scrollToBottomSoon();
      return;
    }
    setState(() {
      _activeUserId = otherUserId;
      _loadingThread = true;
    });

    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}${threadPath(otherUserId)}?markRead=1"),
        headers: {"Authorization": "Bearer ${_authToken ?? ""}"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data is List) ? data : (data["data"] ?? []);
        _cachedThreads[otherUserId] = List<dynamic>.from(list);
      } else {
        _toast("Load thread failed: ${res.statusCode}");
      }
      await _prefetchUnread();
    } catch (e) {
      _toast("Thread error: $e");
    } finally {
      setState(() => _loadingThread = false);
      _scrollToBottomSoon();
      _startPolling();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    if (_activeUserId == null) return;
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (_activeUserId != null) _openThread(_activeUserId!, force: true);
    });
  }

  // -------- send text OR files to direct --------
  Future<void> _sendDirect({List<File> files = const []}) async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty && files.isEmpty) return;
    if (_activeUserId == null) return;

    // optimistic insert
    final optimistic = {
      "_id": "local_${DateTime.now().millisecondsSinceEpoch}",
      "sender": {
        "_id": _myId,
        "fullName": _me?["fullName"],
        "avatarUrl": _me?["avatarUrl"],
      },
      "receivers": [_activeUserId],
      "message": text,
      "createdAt": DateTime.now().toIso8601String(),
      "kind": files.isEmpty ? "text" : "mixed",
      "attachments": files
          .map(
            (f) => {
              "url": "",
              "name": f.path.split("/").last,
              "mime": "",
              "size": f.lengthSync(),
            },
          )
          .toList(),
      "status": "sending",
      "readBy": [
        {"user": _myId, "readAt": DateTime.now().toIso8601String()},
      ],
    };

    setState(() {
      final list = _cachedThreads[_activeUserId!] ?? <dynamic>[];
      list.add(optimistic);
      _cachedThreads[_activeUserId!] = list;
      _msgCtrl.clear();
    });
    _scrollToBottomSoon();

    try {
      final uri = Uri.parse("${ApiConfig.baseUrl}$postMessagePath");
      final req = http.MultipartRequest("POST", uri);
      req.headers["Authorization"] = "Bearer ${_authToken ?? ""}";
      req.fields["message"] = text;
      req.fields["receivers"] = jsonEncode([_activeUserId]);

      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath("files", f.path));
      }

      final streamed = await req.send();
      final body = await streamed.stream.bytesToString();

      if (streamed.statusCode == 201 || streamed.statusCode == 200) {
        await _prefetchThreadMeta();
        await _openThread(_activeUserId!, force: true);
      } else {
        _toast("Send failed: ${streamed.statusCode}");
        _markLastAsFailed(_activeUserId!);
        debugPrint("sendDirect error body: $body");
      }
    } catch (e) {
      _toast("Send error: $e");
      _markLastAsFailed(_activeUserId!);
    }
  }

  void _markLastAsFailed(String userId) {
    final list = _cachedThreads[userId];
    if (list == null || list.isEmpty) return;
    final last = list.last;
    last["status"] = "failed";
    setState(() {});
  }

  // --------------- GROUP (Rudhram) ---------------
  Future<void> _loadGroupMessages() async {
    setState(() => _loadingGroup = true);
    try {
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}$groupListPath?markRead=1"),
        headers: {"Authorization": "Bearer ${_authToken ?? ""}"},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _groupMsgs = List.from(data["data"] ?? []));
        _scrollGroupSoon();
      } else {
        _toast("Group load failed: ${res.statusCode}");
      }
      await _prefetchUnread();
    } catch (e) {
      _toast("Group error: $e");
    } finally {
      setState(() => _loadingGroup = false);
    }
  }

  void _startGroupPolling() {
    _groupPollTimer?.cancel();
    _groupPollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      _loadGroupMessages();
    });
  }

  Future<void> _sendGroup({List<File> files = const []}) async {
    final text = _groupCtrl.text.trim();
    if (text.isEmpty && files.isEmpty) return;

    // optimistic
    final optimistic = {
      "_id": "local_grp_${DateTime.now().millisecondsSinceEpoch}",
      "sender": {
        "_id": _myId,
        "fullName": (_me?["fullName"] ?? _me?["email"] ?? "Me"),
        "avatarUrl": (_me?["avatarUrl"] ?? ""),
      },
      "message": text,
      "kind": files.isEmpty ? "text" : "mixed",
      "attachments": files
          .map(
            (f) => {
              "url": "",
              "name": f.path.split("/").last,
              "mime": "",
              "size": f.lengthSync(),
            },
          )
          .toList(),
      "channel": "group",
      "groupKey": "RUDHRAM",
      "createdAt": DateTime.now().toIso8601String(),
      "status": "sending",
      "readBy": [
        {"user": _myId, "readAt": DateTime.now().toIso8601String()},
      ],
    };

    setState(() {
      _groupMsgs.add(optimistic);
      _groupCtrl.clear();
    });
    _scrollGroupSoon();

    try {
      final uri = Uri.parse("${ApiConfig.baseUrl}$postGroupPath");
      final req = http.MultipartRequest("POST", uri);
      req.headers["Authorization"] = "Bearer ${_authToken ?? ""}";
      req.fields["message"] = text;
      for (final f in files) {
        req.files.add(await http.MultipartFile.fromPath("files", f.path));
      }
      final resp = await req.send();
      if (resp.statusCode == 201 || resp.statusCode == 200) {
        await _loadGroupMessages();
      } else {
        _toast("Group send failed: ${resp.statusCode}");
        _markLastGroupAsFailed();
      }
    } catch (e) {
      _toast("Group send error: $e");
      _markLastGroupAsFailed();
    }
  }

  void _markLastGroupAsFailed() {
    if (_groupMsgs.isEmpty) return;
    final last = _groupMsgs.last;
    last["status"] = "failed";
    setState(() {});
  }

  // ---------- deletes (single-only) ----------
  Future<void> _deleteSingle(String messageId) async {
    final ok = await _confirm(
      title: "Delete message?",
      message: "Are you sure you want to delete this message?",
      danger: true,
    );
    if (!ok) return;

    final res = await http.delete(
      Uri.parse("${ApiConfig.baseUrl}$deleteMessagePath/$messageId"),
      headers: {"Authorization": "Bearer ${_authToken ?? ""}"},
    );
    if (res.statusCode == 200) {
      final ok1 = _tryRemoveFromThread(messageId);
      final ok2 = _tryRemoveFromGroup(messageId);
      if (!ok1 && !ok2) {}
      setState(() {});
      await _prefetchThreadMeta();
      await _prefetchUnread();
    } else {
      _toast("Delete failed: ${res.statusCode}");
    }
  }

  bool _tryRemoveFromThread(String id) {
    if (_activeUserId == null) return false;
    final list = _cachedThreads[_activeUserId!];
    if (list == null) return false;
    final before = list.length;
    list.removeWhere((m) => (m["_id"] ?? "") == id);
    return list.length != before;
  }

  bool _tryRemoveFromGroup(String id) {
    final before = _groupMsgs.length;
    _groupMsgs.removeWhere((m) => (m["_id"] ?? "") == id);
    return _groupMsgs.length != before;
  }

  // ------------------------ UI ------------------------

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 820;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        title: const Text("Messages"),
        automaticallyImplyLeading: false,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const TeamMemberDashboard(), // <-- redirect to dashboard
              ),
            );
          },
        ),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(icon: Icon(Icons.chat_bubble_outline), text: "Chats"),
            Tab(icon: Icon(Icons.groups_outlined), text: "Rudhram"),
          ],
        ),
      ),

      body: TabBarView(
        controller: _tab,
        children: [_buildChatsTab(isWide), _buildGroupTab()],
      ),
    );
  }

  // ---------- Chats Tab ----------
  Widget _buildChatsTab(bool isWide) {
    if (_loadingUsers) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_users.isEmpty) {
      return const Center(child: Text("No admins found"));
    }

    if (isWide) {
      return Row(
        children: [
          SizedBox(width: 340, child: _buildUserList()),
          const VerticalDivider(width: 1),
          Expanded(child: _buildThreadArea()),
        ],
      );
    } else {
      if (_activeUserId == null) {
        return _buildUserList();
      } else {
        return _buildThreadArea(showBack: true);
      }
    }
  }

  // Sort admins: by lastTs desc, then by name
  List<dynamic> _sortedUsers() {
    final copy = List<dynamic>.from(_users);
    copy.sort((a, b) {
      final aid = (a["_id"] ?? a["id"] ?? "").toString();
      final bid = (b["_id"] ?? b["id"] ?? "").toString();
      final ats = _lastTs[aid] ?? "";
      final bts = _lastTs[bid] ?? "";
      if (ats.isNotEmpty && bts.isNotEmpty) {
        final after = _isAfter(ats, bts);
        if (after) return -1;
        if (ats != bts) return 1;
      } else if (ats.isNotEmpty) {
        return -1;
      } else if (bts.isNotEmpty) {
        return 1;
      }
      final an = (a["fullName"] ?? a["email"] ?? "").toString();
      final bn = (b["fullName"] ?? b["email"] ?? "").toString();
      return an.toLowerCase().compareTo(bn.toLowerCase());
    });
    return copy;
  }

  Widget _buildUserList() {
    final users = _sortedUsers();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          color: Colors.brown[50],
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: Colors.brown),
              const SizedBox(width: 8),
              Text(
                "Super Admin",
                style: TextStyle(
                  color: Colors.brown[800],
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: users.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final u = users[i];
              final id = (u["_id"] ?? u["id"])?.toString() ?? "";
              final name = (u["fullName"] ?? u["email"] ?? id).toString();
              final selected = _activeUserId == id;
              final count = _unreadDirect[id] ?? 0; // unread badge
              final last = _lastTs[id];

              return ListTile(
                selected: selected,
                selectedTileColor: AppColors.primaryColor.withOpacity(.08),
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _avatarSmall(u),
                    if (count > 0)
                      Positioned(
                        right: -4,
                        bottom: -2,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(.15),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Text(
                            "$count",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (last != null && last.isNotEmpty)
                      Text(
                        _fmtTime(last),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.brown[400],
                        ),
                      ),
                  ],
                ),
                subtitle: const Text("Super Admin"),
                onTap: () => _openThread(id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildThreadArea({bool showBack = false}) {
    final list = _activeUserId == null
        ? <dynamic>[]
        : (_cachedThreads[_activeUserId!] ?? <dynamic>[]);

    final partner = _users.firstWhere(
      (u) => (u["_id"] ?? u["id"])?.toString() == _activeUserId,
      orElse: () => {},
    );
    final partnerName = (partner["fullName"] ?? partner["email"] ?? "")
        .toString();

    if (_activeUserId == null) {
      return Center(
        child: Text(
          "Select a Super Admin to start chatting",
          style: TextStyle(color: Colors.brown[600]),
        ),
      );
    }

    // compact composer height guess (excluding safe padding)
    const composerBase = 50.0;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    return Column(
      children: [
        if (showBack)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            height: 48,
            color: Colors.brown[50],
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _activeUserId = null),
                ),
                _avatarSmall(partner),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    partnerName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loadingThread
              ? const Center(child: CircularProgressIndicator())
              : Container(
                  color: Colors.brown[50],
                  child: ListView.builder(
                    controller: _chatScroll,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      // include composer height + safe bottom once (no double SafeArea)
                      12 + composerBase + safeBottom,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final m = list[i] as Map;
                      final senderObj = m["sender"];
                      final senderId = (senderObj is Map)
                          ? (senderObj["_id"] ?? senderObj["id"])?.toString()
                          : (m["sender"] ?? "").toString();

                      final mine = senderId == _myId;
                      final text = (m["message"] ?? "").toString();
                      final ts = _fmtTime(m["createdAt"]);
                      final failed = (m["status"] == "failed");
                      final atts = List<Map>.from(m["attachments"] ?? const []);

                      final seen = mine
                          ? _isSeenByUser(m, _activeUserId)
                          : _isSeenByUser(m, _myId);

                      return GestureDetector(
                        onLongPress: () => _showMessageMenu(m, mine),
                        child: Align(
                          alignment: mine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 520),
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                              decoration: BoxDecoration(
                                color: mine
                                    ? AppColors.primaryColor
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: mine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "#${i + 1}",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: mine
                                          ? Colors.white70
                                          : Colors.brown[400],
                                    ),
                                  ),
                                  if (text.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      text,
                                      style: TextStyle(
                                        color: mine
                                            ? Colors.white
                                            : Colors.brown[900],
                                        fontSize: 15,
                                      ),
                                    ),
                                  ],
                                  if (atts.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    _attachmentsView(atts, mine),
                                  ],
                                  const SizedBox(height: 4),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        ts,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: mine
                                              ? Colors.white70
                                              : Colors.brown[400],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      if (mine)
                                        Icon(
                                          seen
                                              ? Icons.done_all_rounded
                                              : Icons.check_rounded,
                                          size: 16,
                                          color: seen
                                              ? Colors.lightBlueAccent
                                              : (mine
                                                    ? Colors.white70
                                                    : Colors.brown[400]),
                                        ),
                                      if (failed) ...[
                                        const SizedBox(width: 6),
                                        const Icon(
                                          Icons.error_outline,
                                          size: 14,
                                          color: Colors.red,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        _buildComposer(
          controller: _msgCtrl,
          hint: "Message $partnerName",
          onSend: () => _sendDirect(),
          extraActions: [
            IconButton(
              tooltip: "Image",
              onPressed: () async {
                final picker = ImagePicker();
                final x = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                );
                if (x != null) await _sendDirect(files: [File(x.path)]);
              },
              icon: const Icon(Icons.image_outlined),
              color: AppColors.primaryColor,
            ),
            IconButton(
              tooltip: "File",
              onPressed: () async {
                final res = await FilePicker.platform.pickFiles(
                  allowMultiple: true,
                );
                final files = (res?.files ?? [])
                    .where((f) => f.path != null)
                    .map((f) => File(f.path!))
                    .toList();
                if (files.isNotEmpty) await _sendDirect(files: files);
              },
              icon: const Icon(Icons.attach_file),
              color: AppColors.primaryColor,
            ),
          ],
          dense: true, // compact composer
        ),
      ],
    );
  }

  // ---------- Group (Rudhram) Tab ----------
  Widget _buildGroupTab() {
    // compact composer height guess (excluding safe padding)
    const composerBase = 50.0;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          color: Colors.brown[50],
          child: Row(
            children: [
              const Icon(Icons.groups_outlined, color: Colors.brown),
              const SizedBox(width: 8),
              Text(
                "Rudhram Group (everyone can chat)",
                style: TextStyle(
                  color: Colors.brown[800],
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              if (_unreadGroup > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    "$_unreadGroup",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loadingGroup
              ? const Center(child: CircularProgressIndicator())
              : Container(
                  color: Colors.brown[50],
                  child: ListView.builder(
                    controller: _groupScroll,
                    padding: EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      // include composer height + safe bottom once
                      12 + composerBase + safeBottom,
                    ),
                    itemCount: _groupMsgs.length,
                    itemBuilder: (_, i) {
                      final m = _groupMsgs[i] as Map;
                      final senderObj = m["sender"];
                      final senderId = (senderObj is Map)
                          ? (senderObj["_id"] ?? senderObj["id"])?.toString()
                          : (m["sender"] ?? "").toString();
                      final mine = senderId == _myId;

                      final rawName = (senderObj is Map)
                          ? (senderObj["fullName"] ?? senderObj["email"] ?? "")
                                .toString()
                          : "";
                      final displayName = rawName.isNotEmpty
                          ? (mine ? "$rawName (You)" : rawName)
                          : (mine ? "You" : "Member");

                      final text = (m["message"] ?? "").toString();
                      final ts = _fmtTime(m["createdAt"]);
                      final failed = (m["status"] == "failed");
                      final atts = List<Map>.from(m["attachments"] ?? const []);

                      // For group read receipts: if my message has >1 readBy entries,
                      // consider it seen by at least one other.
                      final readBy = List.from(m["readBy"] ?? const []);
                      final seen = mine ? (readBy.length > 1) : false;

                      return GestureDetector(
                        onLongPress: () => _showMessageMenu(m, mine),
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: mine
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              if (!mine)
                                _avatarSmall(
                                  senderObj is Map ? senderObj : null,
                                ),
                              if (!mine) const SizedBox(width: 8),
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 520,
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      9,
                                      12,
                                      9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: mine
                                          ? AppColors.primaryColor
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(.05),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: mine
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          displayName,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: mine
                                                ? Colors.white70
                                                : Colors.brown[600],
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        Text(
                                          "#${i + 1}",
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: mine
                                                ? Colors.white70
                                                : Colors.brown[400],
                                          ),
                                        ),
                                        if (text.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            text,
                                            style: TextStyle(
                                              color: mine
                                                  ? Colors.white
                                                  : Colors.brown[900],
                                              fontSize: 15,
                                            ),
                                          ),
                                        ],
                                        if (atts.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          _attachmentsView(atts, mine),
                                        ],
                                        const SizedBox(height: 4),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              ts,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: mine
                                                    ? Colors.white70
                                                    : Colors.brown[400],
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            if (mine)
                                              Icon(
                                                seen
                                                    ? Icons.done_all_rounded
                                                    : Icons.check_rounded,
                                                size: 16,
                                                color: seen
                                                    ? Colors.lightBlueAccent
                                                    : (mine
                                                          ? Colors.white70
                                                          : Colors.brown[400]),
                                              ),
                                            if (failed) ...[
                                              const SizedBox(width: 6),
                                              const Icon(
                                                Icons.error_outline,
                                                size: 14,
                                                color: Colors.red,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (mine) const SizedBox(width: 8),
                              if (mine)
                                _avatarSmall(
                                  senderObj is Map ? senderObj : _me,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
        _buildComposer(
          controller: _groupCtrl,
          hint: "Message Rudhram group",
          onSend: () => _sendGroup(),
          extraActions: [
            IconButton(
              tooltip: "Image",
              onPressed: () async {
                final picker = ImagePicker();
                final x = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                );
                if (x != null) await _sendGroup(files: [File(x.path)]);
              },
              icon: const Icon(Icons.image_outlined),
              color: AppColors.primaryColor,
            ),
            IconButton(
              tooltip: "File",
              onPressed: () async {
                final res = await FilePicker.platform.pickFiles(
                  allowMultiple: true,
                );
                final files = (res?.files ?? [])
                    .where((f) => f.path != null)
                    .map((f) => File(f.path!))
                    .toList();
                if (files.isNotEmpty) await _sendGroup(files: files);
              },
              icon: const Icon(Icons.attach_file),
              color: AppColors.primaryColor,
            ),
          ],
          dense: true, // compact composer
        ),
      ],
    );
  }

  // ---------- Compact composer (no SafeArea double-count) ----------
  Widget _buildComposer({
    required TextEditingController controller,
    required String hint,
    required VoidCallback? onSend,
    List<Widget> extraActions = const [],
    bool dense = false,
  }) {
    // Safe inset from gesture/navigation bar (we will apply manually)
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;

    // sizes for dense vs normal
    final vPad = dense ? 6.0 : 10.0;
    final hPad = 10.0;
    final tfHPad = dense ? 10.0 : 12.0;
    final tfVPad = dense ? 8.0 : 10.0;
    final iconSz = dense ? 20.0 : 24.0;
    final sendPad = dense ? 6.0 : 8.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.brown[200]!)),
      ),
      // apply bottomInset ONCE here; no SafeArea wrapper -> no double padding
      padding: EdgeInsets.fromLTRB(hPad, vPad, hPad, sendPad + bottomInset),
      child: Row(
        children: [
          ...extraActions.map(
            (w) => IconTheme.merge(
              data: IconThemeData(size: iconSz),
              child: w,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4, // compact
              decoration: InputDecoration(
                hintText: hint,
                filled: true,
                fillColor: Colors.brown[50],
                contentPadding: EdgeInsets.symmetric(
                  horizontal: tfHPad,
                  vertical: tfVPad,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: AppColors.primaryColor.withOpacity(.5),
                  ),
                ),
              ),
              onSubmitted: (_) => onSend?.call(),
            ),
          ),
          const SizedBox(width: 6),
          IconButton(
            icon: const Icon(Icons.send),
            iconSize: iconSz,
            color: AppColors.primaryColor,
            onPressed: onSend,
            tooltip: "Send",
          ),
        ],
      ),
    );
  }

  Widget _attachmentsView(List<Map> atts, bool mine) {
    return Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: atts.map((a) {
        final url = (a["url"] ?? "").toString();
        final name = (a["name"] ?? "file").toString();
        final mime = (a["mime"] ?? "").toString();

        final isImage =
            mime.startsWith("image/") ||
            name.toLowerCase().endsWith(".jpg") ||
            name.toLowerCase().endsWith(".jpeg") ||
            name.toLowerCase().endsWith(".png") ||
            name.toLowerCase().endsWith(".gif") ||
            name.toLowerCase().endsWith(".webp");

        if (isImage && url.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: GestureDetector(
              onTap: () => _openAttachment(url, suggestedName: name),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  _absoluteUrl(url),
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: InkWell(
            onTap: () => _openAttachment(url, suggestedName: name),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: mine ? Colors.white24 : Colors.brown[100],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.insert_drive_file, size: 18),
                  const SizedBox(width: 6),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 240),
                    child: Text(
                      name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mine ? Colors.white : Colors.black87,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _openAttachment(String url, {String? suggestedName}) async {
    try {
      if (url.isEmpty) return;
      final abs = _absoluteUrl(url);
      await OpenAnyFile.openFromUrl(abs, suggestedName: suggestedName);
    } catch (e) {
      try {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          await OpenFile.open(url);
        }
      } catch (_) {}
    }
  }

  String _absoluteUrl(String url) {
    if (url.startsWith('http')) return url;
    if (url.startsWith('/uploads')) return "${ApiConfig.imageBaseUrl}$url";
    return "${ApiConfig.baseUrl}$url";
  }

  // Avatars
  Widget _avatarSmall(Map? user) {
    final url = (user?["avatarUrl"] ?? "").toString();
    final name = (user?["fullName"] ?? user?["email"] ?? "").toString();
    final letter = name.isNotEmpty ? name[0].toUpperCase() : "V";
    final image = _avatarImage(url);
    return CircleAvatar(
      radius: 18,
      backgroundColor: Colors.brown[100],
      backgroundImage: image,
      child: image == null
          ? Text(
              letter,
              style: const TextStyle(
                color: Colors.brown,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
    );
  }

  ImageProvider? _avatarImage(String url) {
    if (url.isEmpty) return null;
    if (url.startsWith('http')) return NetworkImage(url);
    if (url.startsWith('/uploads')) {
      return NetworkImage("${ApiConfig.imageBaseUrl}$url");
    }
    return NetworkImage("${ApiConfig.baseUrl}$url");
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  void _scrollGroupSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_groupScroll.hasClients) return;
      _groupScroll.animateTo(
        _groupScroll.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    });
  }

  String _fmtTime(dynamic iso) {
    if (iso == null) return "";
    try {
      final d = DateTime.parse(iso.toString()).toLocal();
      final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final mm = d.minute.toString().padLeft(2, '0');
      final am = d.hour >= 12 ? "PM" : "AM";
      return "$hh:$mm $am";
    } catch (_) {
      return "";
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // Bottom sheet (single delete) — only allow if it's my own message
  void _showMessageMenu(Map msg, bool mine) {
    final id = (msg["_id"] ?? "").toString();
    final canDelete = mine; // Team member: only own messages
    if (!canDelete || id.isEmpty) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: 22,
              ),
              title: const Text("Delete message"),
              onTap: () async {
                Navigator.pop(context);
                await _deleteSingle(id);
              },
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  // Read receipts helpers
  bool _isSeenByUser(Map msg, String? userId) {
    if (userId == null) return false;
    final list = List.from(msg["readBy"] ?? const []);
    for (final rb in list) {
      if (rb is Map) {
        final u = (rb["user"] ?? "").toString();
        if (u == userId) return true;
      }
    }
    return false;
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            child: const Text("Cancel"),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: danger
                  ? Colors.red.shade600
                  : AppColors.primaryColor,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Yes, continue"),
          ),
        ],
      ),
    );
    return ok == true;
  }
}
