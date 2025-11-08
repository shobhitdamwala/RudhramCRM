import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/api_config.dart';
import '../utils/constants.dart';

class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  List<dynamic> notifications = [];
  bool loading = true;
  bool error = false;

  @override
  void initState() {
    super.initState();
    fetchNotifications();
  }

  Future<void> fetchNotifications() async {
    setState(() {
      loading = true;
      error = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final deviceToken = prefs.getString('device_token'); // saved at login

      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/notifications"),
        headers: {
          "Authorization": "Bearer $token",
          if (deviceToken != null && deviceToken.isNotEmpty)
            "x-device-token": deviceToken,
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = List<Map<String, dynamic>>.from(data['data'] ?? []);
        // newest first
        list.sort((a, b) =>
            DateTime.tryParse(b['createdAt'] ?? '')!
                .compareTo(DateTime.tryParse(a['createdAt'] ?? '')!));
        setState(() => notifications = list);
      } else {
        error = true;
      }
    } catch (_) {
      error = true;
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> removeNotification(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final deviceToken = prefs.getString('device_token');

      final res = await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/user/notifications/$id"),
        headers: {
          "Authorization": "Bearer $token",
          if (deviceToken != null && deviceToken.isNotEmpty)
            "x-device-token": deviceToken,
        },
      );

      if (res.statusCode == 200) {
        setState(() {
          notifications.removeWhere((n) => n['_id'] == id);
        });
      } else {
        _showSnack("Failed to delete notification");
      }
    } catch (e) {
      _showSnack("Delete failed");
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  // ---------- UI HELPERS ----------

  String _formatRelative(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return DateFormat('dd MMM, yyyy').format(dt);
    }

  String _sectionTitle(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);

    if (target == today) return 'Today';
    if (target == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('EEEE, dd MMM').format(dt); // e.g. Monday, 02 Dec
  }

  IconData _iconForType(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'task':
      case 'task_assigned':
      case 'task_assigned_update':
      case 'task_deadline':
        return Icons.checklist_rounded;
      case 'meeting':
        return Icons.event_available_rounded;
      case 'lead_converted':
        return Icons.person_add_alt_1_rounded;
      case 'alert':
        return Icons.warning_amber_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _colorForType(String? type) {
    switch ((type ?? '').toLowerCase()) {
      case 'task':
      case 'task_assigned':
      case 'task_assigned_update':
      case 'task_deadline':
        return Colors.indigo;
      case 'meeting':
        return Colors.teal;
      case 'lead_converted':
        return Colors.orange;
      case 'alert':
        return Colors.redAccent;
      default:
        return AppColors.primaryColor;
    }
  }

  Map<String, List<Map<String, dynamic>>> _groupByDay(
      List<Map<String, dynamic>> list) {
    final map = <String, List<Map<String, dynamic>>>{};
    for (final n in list) {
      final created = DateTime.tryParse(n['createdAt'] ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final key = _sectionTitle(created);
      map.putIfAbsent(key, () => []).add(n);
    }
    return map;
  }

  // ---------- BUILD ----------

  @override
  Widget build(BuildContext context) {
    final bgGradTop = AppColors.backgroundGradientStart;
    final bgGradBottom = AppColors.backgroundGradientEnd ?? Colors.white;

    return Scaffold(
      extendBody: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          "Notifications",
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        foregroundColor: const Color.fromARGB(255, 255, 255, 255),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [bgGradTop, bgGradBottom],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: loading
              ? const _SkeletonList()
              : error
                  ? _ErrorState(onRetry: fetchNotifications)
                  : notifications.isEmpty
                      ? const _EmptyState()
                      : RefreshIndicator(
                          color: AppColors.primaryColor,
                          onRefresh: fetchNotifications,
                          child: _NotificationListView(
                            notifications: notifications,
                            iconForType: _iconForType,
                            colorForType: _colorForType,
                            formatRelative: _formatRelative,
                            groupByDay: _groupByDay,
                            onDelete: removeNotification,
                          ),
                        ),
        ),
      ),
    );
  }
}

// ---------------- Reusable Widgets ----------------

class _NotificationListView extends StatelessWidget {
  const _NotificationListView({
    required this.notifications,
    required this.iconForType,
    required this.colorForType,
    required this.formatRelative,
    required this.groupByDay,
    required this.onDelete,
  });

  final List<dynamic> notifications;
  final IconData Function(String? type) iconForType;
  final Color Function(String? type) colorForType;
  final String Function(DateTime dt) formatRelative;
  final Map<String, List<Map<String, dynamic>>> Function(
      List<Map<String, dynamic>>) groupByDay;
  final Future<void> Function(String id) onDelete;

  @override
  Widget build(BuildContext context) {
    // Convert to strong-typed maps
    final list =
        notifications.map((e) => Map<String, dynamic>.from(e)).toList();

    final grouped = groupByDay(list);

    final sectionKeys = grouped.keys.toList()
      ..sort((a, b) {
        // Keep "Today" then "Yesterday" then older
        final order = {"Today": 0, "Yesterday": 1};
        final ai = order[a] ?? 2;
        final bi = order[b] ?? 2;
        return ai.compareTo(bi);
      });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: sectionKeys.length,
      itemBuilder: (_, idx) {
        final key = sectionKeys[idx];
        final items = grouped[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                key,
                style: const TextStyle(
                  color: Colors.brown,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            ...items.map(
              (n) => _NotificationCard(
                n: n,
                icon: iconForType(n['type']),
                color: colorForType(n['type']),
                relative: formatRelative(
                  DateTime.tryParse(n['createdAt'] ?? '') ??
                      DateTime.fromMillisecondsSinceEpoch(0),
                ),
                onDelete: () => onDelete(n['_id'].toString()),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.n,
    required this.icon,
    required this.color,
    required this.relative,
    required this.onDelete,
  });

  final Map<String, dynamic> n;
  final IconData icon;
  final Color color;
  final String relative;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = (n['title'] ?? '').toString();
    final msg = (n['message'] ?? '').toString();
    final type = (n['type'] ?? '').toString();
    final unread = !(n['isRead'] == true);

    return Dismissible(
      key: ValueKey(n['_id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: Colors.red.shade500,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => onDelete(),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border(
            left: BorderSide(
              color: color.withOpacity(.8),
              width: 4,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Leading icon badge
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 12),

              // Texts
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: Colors.brown,
                            ),
                          ),
                        ),
                        // unread dot
                        if (unread)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6, right: 4),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                        // delete icon (compact)
                        IconButton(
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.close, size: 18, color: Colors.black45),
                          onPressed: onDelete,
                          tooltip: "Delete",
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      msg,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black87,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Meta row: type chip + time
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: color.withOpacity(.10),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: color.withOpacity(.35)),
                          ),
                          child: Text(
                            (type.isEmpty ? "GENERAL" : type).toUpperCase(),
                            style: TextStyle(
                              fontSize: 10.5,
                              letterSpacing: .6,
                              fontWeight: FontWeight.w700,
                              color: color,
                            ),
                          ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 14, color: Colors.black45),
                            const SizedBox(width: 4),
                            Text(
                              relative,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none_rounded,
                size: 72, color: Colors.brown.withOpacity(.35)),
            const SizedBox(height: 12),
            const Text(
              "No Notifications",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.brown,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "You’re all caught up. When something new happens, it’ll show up here.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 72, color: Colors.red.shade300),
            const SizedBox(height: 12),
            const Text(
              "Couldn’t load notifications",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.brown,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              "Please check your connection and try again.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();

  @override
  Widget build(BuildContext context) {
    // Simple lightweight shimmer-ish effect without extra packages
    Widget bar() => Container(
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.6),
            borderRadius: BorderRadius.circular(6),
          ),
        );

    Widget tile() => Container(
          height: 92,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.8),
            borderRadius: BorderRadius.circular(16),
          ),
        );

    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: 8,
      itemBuilder: (_, i) {
        if (i == 0 || i == 3 || i == 6) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: bar(),
          );
        }
        return tile();
      },
    );
  }
}
