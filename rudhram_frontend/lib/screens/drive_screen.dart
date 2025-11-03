import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import '../widgets/background_container.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import '../utils/custom_bottom_nav.dart';
import '../widgets/profile_header.dart';

class DriveScreen extends StatefulWidget {
  const DriveScreen({super.key});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

enum ViewMode { list, grid }

enum SortBy { nameAsc, nameDesc, recent }

class _DriveScreenState extends State<DriveScreen> {
  bool loading = true;
  int _selectedIndex = 2;

  Map<String, dynamic>? userData;

  String? _currentSubCompanyId;
  String? _currentParentFolderId;
  final List<Map<String, dynamic>> _breadcrumbs = [];

  List<dynamic> _items = [];
  List<dynamic> _filtered = [];

  // UI state
  ViewMode _view = ViewMode.list;
  SortBy _sort = SortBy.recent;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _searchCtrl.addListener(_applyFilters);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));
    if (token.isNotEmpty) {
      await fetchUser(token);
    }
    await _fetchSubCompanies();
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
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

  // ==================== Fetch User ====================
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

  // ================= FETCH APIs =================
  Future<void> _fetchSubCompanies() async {
    setState(() => loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        _items = body['data'] ?? [];
        _applyFilters();
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to load SubCompanies',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: e.toString(),
        type: ContentType.failure,
      );
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _fetchFolders(
    String subCompanyId, {
    String? parentFolderId,
  }) async {
    setState(() => loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final uri = Uri.parse(
        "${ApiConfig.baseUrl}/drive/getdrivefolder?subCompany=$subCompanyId${parentFolderId != null ? "&parentFolder=$parentFolderId" : ""}",
      );
      final res = await http.get(
        uri,
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        _items = body['data'] ?? [];
        _applyFilters();
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to load folders',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: e.toString(),
        type: ContentType.failure,
      );
    } finally {
      setState(() => loading = false);
    }
  }

  // ================= CRUD =================
  Future<void> _addFolderOrLink({
    required String subCompany,
    required String name,
    required String type, // folder | link
    String? parentFolder,
    String? externalLink,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final body = {
        "subCompany": subCompany,
        "name": name,
        "type": type,
        if (parentFolder != null) "parentFolder": parentFolder,
        if (externalLink != null) "externalLink": externalLink,
      };
      final res = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/drive/adddrivefolder"),
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
        body: jsonEncode(body),
      );
      if (res.statusCode == 201) {
        SnackbarHelper.show(
          context,
          title: 'Success',
          message: 'Created Successfully',
          type: ContentType.success,
        );
        _fetchFolders(
          _currentSubCompanyId!,
          parentFolderId: _currentParentFolderId,
        );
      } else {
        final msg = jsonDecode(res.body)['message'] ?? 'Failed';
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: msg,
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: e.toString(),
        type: ContentType.failure,
      );
    }
  }

  Future<void> _deleteFolder(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final res = await http.delete(
        Uri.parse("${ApiConfig.baseUrl}/drive/$id"),
        headers: {"Authorization": "Bearer $token"},
      );
      if (res.statusCode == 200) {
        setState(() {
          _items.removeWhere((e) => e['_id'] == id);
          _applyFilters();
        });
        SnackbarHelper.show(
          context,
          title: 'Deleted',
          message: 'Item deleted',
          type: ContentType.success,
        );
      } else {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to delete',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: e.toString(),
        type: ContentType.failure,
      );
    }
  }

  // ================= Navigation =================
  void _openSubCompany(Map<String, dynamic> subCompany) {
    _currentSubCompanyId = subCompany['_id'];
    _currentParentFolderId = null;
    _breadcrumbs
      ..clear()
      ..add({'name': subCompany['name'], 'id': null});
    _fetchFolders(_currentSubCompanyId!);
  }

  void _openFolder(Map<String, dynamic> folder) {
    _currentParentFolderId = folder['_id'];
    _breadcrumbs.add({'name': folder['name'], 'id': folder['_id']});
    _fetchFolders(
      _currentSubCompanyId!,
      parentFolderId: _currentParentFolderId,
    );
  }

  void _goBack() {
    if (_breadcrumbs.isEmpty) return;
    _breadcrumbs.removeLast();
    if (_breadcrumbs.isEmpty) {
      _currentSubCompanyId = null;
      _currentParentFolderId = null;
      _fetchSubCompanies();
    } else {
      _currentParentFolderId = _breadcrumbs.last['id'];
      _fetchFolders(
        _currentSubCompanyId!,
        parentFolderId: _currentParentFolderId,
      );
    }
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Could not open link',
          type: ContentType.failure,
        );
      }
    }
  }

  // ================= Filters / Sort / View =================
  void _applyFilters() {
    final q = _searchCtrl.text.trim().toLowerCase();
    List<dynamic> out = List<dynamic>.from(_items);

    if (q.isNotEmpty) {
      out = out.where((it) {
        final name = (it['name'] ?? it['title'] ?? '').toString().toLowerCase();
        final link = (it['externalLink'] ?? '').toString().toLowerCase();
        final comp = (it['company'] ?? it['subCompany'] ?? '')
            .toString()
            .toLowerCase();
        return name.contains(q) || link.contains(q) || comp.contains(q);
      }).toList();
    }

    // sort
    out.sort((a, b) {
      final an = (a['name'] ?? '').toString().toLowerCase();
      final bn = (b['name'] ?? '').toString().toLowerCase();
      final ac = DateTime.tryParse(a['createdAt'] ?? '') ?? DateTime(2000);
      final bc = DateTime.tryParse(b['createdAt'] ?? '') ?? DateTime(2000);

      switch (_sort) {
        case SortBy.nameAsc:
          return an.compareTo(bn);
        case SortBy.nameDesc:
          return bn.compareTo(an);
        case SortBy.recent:
          return bc.compareTo(ac);
      }
    });

    setState(() => _filtered = out);
  }

  // ================= UI Pieces =================
  Widget _breadcrumbBar() {
    final crumbs = _breadcrumbs.map((e) => e['name'] as String).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, color: Colors.brown, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 6,
                children: [
                  if (crumbs.isEmpty)
                    const Chip(
                      label: Text("Drive"),
                      backgroundColor: Colors.transparent,
                    ),
                  for (int i = 0; i < crumbs.length; i++)
                    GestureDetector(
                      onTap: i == crumbs.length - 1
                          ? null
                          : () {
                              setState(() {
                                _breadcrumbs.removeRange(
                                  i + 1,
                                  _breadcrumbs.length,
                                );
                                _currentParentFolderId =
                                    _breadcrumbs.last['id'];
                              });
                              if (_breadcrumbs.isEmpty) {
                                _currentSubCompanyId = null;
                                _fetchSubCompanies();
                              } else {
                                _fetchFolders(
                                  _currentSubCompanyId!,
                                  parentFolderId: _currentParentFolderId,
                                );
                              }
                            },
                      child: Chip(
                        label: Text(crumbs[i]),
                        elevation: 0,
                        side: BorderSide(color: Colors.brown.withOpacity(0.2)),
                        backgroundColor: i == crumbs.length - 1
                            ? Colors.brown.withOpacity(0.06)
                            : Colors.white,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.brown),
            onPressed: () {
              if (_currentSubCompanyId == null) {
                _fetchSubCompanies();
              } else {
                _fetchFolders(
                  _currentSubCompanyId!,
                  parentFolderId: _currentParentFolderId,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _toolbar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          // search
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  hintText: "Search folders or links",
                  prefixIcon: Icon(Icons.search_rounded),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // sort
          PopupMenuButton<SortBy>(
            tooltip: 'Sort',
            onSelected: (val) {
              setState(() => _sort = val);
              _applyFilters();
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: SortBy.recent, child: Text('Recent')),
              PopupMenuItem(value: SortBy.nameAsc, child: Text('Name A–Z')),
              PopupMenuItem(value: SortBy.nameDesc, child: Text('Name Z–A')),
            ],
            child: _roundIcon(Icons.sort_rounded),
          ),
          const SizedBox(width: 8),
          // view toggle
          InkWell(
            onTap: () => setState(
              () => _view = _view == ViewMode.list
                  ? ViewMode.grid
                  : ViewMode.list,
            ),
            child: _roundIcon(
              _view == ViewMode.list
                  ? Icons.grid_view_rounded
                  : Icons.view_list_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.brown),
    );
  }

  // section header
  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.brown,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Container(height: 1, color: Colors.brown.withOpacity(0.15)),
          ),
        ],
      ),
    );
  }

  // list / grid content
  Widget _content() {
    final isRoot = _currentSubCompanyId == null;

    if (isRoot) {
      return _view == ViewMode.list ? _companyList() : _companyGrid();
    }

    // inside a company: separate folders & links
    final folders = _filtered
        .where((e) => (e['type'] ?? 'folder') == 'folder')
        .toList();
    final links = _filtered.where((e) => e['type'] == 'link').toList();

    if (_filtered.isEmpty) {
      return const Center(
        child: Text(
          'No items found',
          style: TextStyle(
            color: Colors.brown,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _view == ViewMode.list
          ? ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                if (folders.isNotEmpty) _sectionTitle("Folders"),
                ...folders.map(_folderTile).toList(),
                if (links.isNotEmpty) _sectionTitle("Links"),
                ...links.map(_linkTile).toList(),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 120),
              children: [
                if (folders.isNotEmpty) _sectionTitle("Folders"),
                _folderGrid(folders),
                if (links.isNotEmpty) _sectionTitle("Links"),
                _linkGrid(links),
              ],
            ),
    );
  }

  // ======= Companies =======
  Widget _companyList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      itemCount: _filtered.length,
      itemBuilder: (_, i) {
        final c = _filtered[i];
        return _card(
          ListTile(
            leading: const Icon(
              Icons.folder_special_rounded,
              color: Colors.orange,
              size: 28,
            ),
            title: Text(c['name'] ?? '', style: _titleStyle()),
            trailing: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.brown,
            ),
            onTap: () => _openSubCompany(c),
          ),
        );
      },
    );
  }

  Widget _companyGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
      itemCount: _filtered.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemBuilder: (_, i) {
        final c = _filtered[i];
        return _card(
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openSubCompany(c),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.folder_special_rounded,
                    color: Colors.orange,
                    size: 32,
                  ),
                  const Spacer(),
                  Text(
                    c['name'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ======= Folders (list + grid) =======
  Widget _folderTile(dynamic m) {
    return _card(
      ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: const Icon(
          Icons.folder_rounded,
          color: Colors.orange,
          size: 28,
        ),
        title: Text(m['name'] ?? '', style: _titleStyle()),
        subtitle: const Text(
          'Folder',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
        trailing: _menuFor(m, isLink: false),
        onTap: () => _openFolder(m),
      ),
    );
  }

  Widget _folderGrid(List items) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (_, i) {
        final m = items[i];
        return _card(
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openFolder(m),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.folder_rounded,
                    color: Colors.orange,
                    size: 32,
                  ),
                  const Spacer(),
                  Text(
                    m['name'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle(),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Folder',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ======= Links (list + grid) =======
  Widget _linkTile(dynamic m) {
    return _card(
      ListTile(
        contentPadding: const EdgeInsets.all(14),
        leading: const Icon(Icons.link_rounded, color: Colors.blue, size: 28),
        title: Text(m['name'] ?? '', style: _titleStyle()),
        subtitle: Text(
          m['externalLink'] ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _menuFor(m, isLink: true),
        onTap: () => _openLink(m['externalLink'] ?? ''),
      ),
    );
  }

  Widget _linkGrid(List items) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.35,
      ),
      itemBuilder: (_, i) {
        final m = items[i];
        return _card(
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openLink(m['externalLink'] ?? ''),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.link_rounded, color: Colors.blue, size: 32),
                  const Spacer(),
                  Text(
                    m['name'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _titleStyle(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    m['externalLink'] ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Card wrapper
  Widget _card(Widget child) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  TextStyle _titleStyle() => const TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: Colors.brown,
  );

  // Context menu
  Widget _menuFor(dynamic m, {required bool isLink}) {
    return PopupMenuButton<String>(
      onSelected: (val) {
        if (val == 'open' && isLink) _openLink(m['externalLink'] ?? '');
        if (val == 'delete') _deleteFolder(m['_id']);
      },
      itemBuilder: (_) => [
        if (isLink)
          const PopupMenuItem(
            value: 'open',
            child: Row(
              children: [
                Icon(Icons.open_in_new_rounded, size: 18),
                SizedBox(width: 8),
                Text('Open Link'),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_rounded, size: 18, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete'),
            ],
          ),
        ),
      ],
    );
  }

  // ================= Add Bottom Sheet =================
  void _showAddBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final nameCtrl = TextEditingController();
        final linkCtrl = TextEditingController();
        String type = 'folder';

        return StatefulBuilder(
          builder: (ctx, setLocal) {
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;
            return AnimatedPadding(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.only(bottom: bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 16,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 44,
                        height: 5,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(100),
                        ),
                      ),
                      const Text(
                        "Add to Drive",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: Colors.brown,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // segmented selector
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _segBtn(
                              ctx,
                              label: "Folder",
                              icon: Icons.create_new_folder_rounded,
                              selected: type == 'folder',
                              onTap: () => setLocal(() => type = 'folder'),
                            ),
                            _segBtn(
                              ctx,
                              label: "Link",
                              icon: Icons.add_link_rounded,
                              selected: type == 'link',
                              onTap: () => setLocal(() => type = 'link'),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 14),
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          prefixIcon: Icon(Icons.title_rounded),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (type == 'link') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: linkCtrl,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(
                            labelText: 'Drive URL',
                            prefixIcon: Icon(Icons.link_rounded),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final name = nameCtrl.text.trim();
                            final url = linkCtrl.text.trim();
                            if (name.isEmpty) {
                              SnackbarHelper.show(
                                context,
                                title: "Name",
                                message: "Please enter a name",
                                type: ContentType.warning,
                              );
                              return;
                            }
                            if (type == 'link' &&
                                (url.isEmpty || !_looksLikeUrl(url))) {
                              SnackbarHelper.show(
                                context,
                                title: "Link",
                                message: "Please paste a valid URL",
                                type: ContentType.warning,
                              );
                              return;
                            }
                            Navigator.pop(ctx);
                            _addFolderOrLink(
                              subCompany: _currentSubCompanyId!,
                              name: name,
                              type: type,
                              parentFolder: _currentParentFolderId,
                              externalLink: type == 'link' ? url : null,
                            );
                          },
                          icon: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                          ),
                          label: Text(
                            type == 'folder' ? "Create Folder" : "Add Link",
                            style: const TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryColor,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _segBtn(
    BuildContext ctx, {
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : Colors.brown,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.brown,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _looksLikeUrl(String s) {
    final uri = Uri.tryParse(s);
    return uri != null && (uri.isScheme("http") || uri.isScheme("https"));
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    final isRoot = _currentSubCompanyId == null;
    final currentLocation = isRoot
        ? "Drive"
        : _breadcrumbs.map((e) => e['name']).join(' / ');

    return Scaffold(
      extendBody: true,
      body: BackgroundContainer(
        child: SafeArea(
          child: Column(
            children: [
              // Fixed ProfileHeader with proper user data
              ProfileHeader(
                avatarUrl: userData?['avatarUrl'],
                fullName: userData?['fullName'], // Show actual user name
                 role: formatUserRole(userData?['role']), // Show actual user role
                showBackButton: _breadcrumbs.isNotEmpty,
                onBack: _goBack,
              ),

              // Current location indicator
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
        
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        currentLocation,
                        style: const TextStyle(
                          fontSize: 20,
                          color: Colors.brown,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),

              if (!isRoot) _breadcrumbBar(),
              _toolbar(),

              Expanded(
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.brown),
                      )
                    : RefreshIndicator(
                        onRefresh: isRoot
                            ? _fetchSubCompanies
                            : () => _fetchFolders(
                                _currentSubCompanyId!,
                                parentFolderId: _currentParentFolderId,
                              ),
                        child: _content(),
                      ),
              ),
            ],
          ),
        ),
      ),

      floatingActionButton: _currentSubCompanyId != null
          ? Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: FloatingActionButton.extended(
                backgroundColor: AppColors.primaryColor,
                onPressed: _showAddBottomSheet,
                icon: const Icon(Icons.add_rounded, color: Colors.white),
                label: const Text('Add', style: TextStyle(color: Colors.white)),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,

      bottomNavigationBar: SafeArea(
        child: CustomBottomNavBar(
          currentIndex: _selectedIndex,
          onTap: (index) => setState(() => _selectedIndex = index),
          userRole: userData?['role'] ?? '',
        ),
      ),
    );
  }
}
