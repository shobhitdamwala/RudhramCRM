// full corrected AddEditTaskScreen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class AddEditTaskScreen extends StatefulWidget {
  final Map<String, dynamic>? task;
  const AddEditTaskScreen({Key? key, this.task}) : super(key: key);

  @override
  State<AddEditTaskScreen> createState() => _AddEditTaskScreenState();
}

class _AddEditTaskScreenState extends State<AddEditTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descriptionCtrl = TextEditingController();

  /// Selected services (each item normalized)
  List<Map<String, dynamic>> _selectedServices = [];

  DateTime? _deadline;

  String? _selectedClientId;
  Map<String, dynamic>? _selectedClient;

  String? _selectedStatus;
  String? _selectedPriority;

  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> teamMembers = [];
  List<Map<String, dynamic>> clientServices = [];
  List<String> clientSubCompanies = [];

  bool isLoading = false;
  bool isEditing = false;

  @override
  void initState() {
    super.initState();
    isEditing = widget.task != null;
    // If editing, prepare initial values first (title/desc/status/priority/deadline/selected services)
    if (isEditing) _prepareEditingState();

    // Fetch remote lists. After clients are fetched we will re-link selected client and chosen services.
    _fetchClients();
    _fetchTeamMembers();
  }

  void _prepareEditingState() {
    _titleCtrl.text = widget.task?['title'] ?? '';
    _descriptionCtrl.text = widget.task?['description'] ?? '';
    _selectedStatus = widget.task?['status'];
    _selectedPriority = widget.task?['priority'];
    _deadline = widget.task?['deadline'] != null
        ? DateTime.tryParse(widget.task!['deadline'].toString())
        : null;

    // Normalize chosenServices from the task (but client meta may still be missing until clients fetched)
    if (widget.task?['chosenServices'] != null) {
      final chosen = List<dynamic>.from(widget.task!['chosenServices']);
      final List<Map<String, dynamic>> normalized = [];
      for (var cs in chosen) {
        try {
          final serviceId =
              (cs['serviceId'] ??
                      cs['_id'] ??
                      cs['id'] ??
                      cs['service']?['_id'])
                  .toString();
          final title =
              (cs['title'] ??
                      cs['service']?['title'] ??
                      cs['serviceTitle'] ??
                      (cs['service'] != null ? cs['service']['title'] : '') ??
                      '')
                  .toString();
          final subCompanyId =
              (cs['subCompanyId'] ?? cs['service']?['subCompanyId'])
                  ?.toString();
          final selectedOfferings = List<String>.from(
            cs['selectedOfferings'] ?? cs['offerings'] ?? [],
          );
          final assignedTeamMembers =
              (cs['assignedTeamMembers'] ?? cs['assignedTo'] ?? [])
                  .map<String>((e) => e.toString())
                  .toList();

          normalized.add({
            'serviceId': serviceId,
            'title': title,
            'subCompanyId': subCompanyId,
            'subCompanyName': (cs['subCompanyName'] ?? '')?.toString(),
            'selectedOfferings': selectedOfferings,
            'assignedTeamMembers': assignedTeamMembers,
          });
        } catch (_) {
          // skip malformed entries
        }
      }

      // dedupe by serviceId
      final Map<String, Map<String, dynamic>> uniq = {};
      for (var s in normalized) {
        uniq[s['serviceId'].toString()] = s;
      }
      _selectedServices = uniq.values.toList();
    }

    if (widget.task?['client'] != null) {
      // store id so we can re-link after clients fetched
      _selectedClientId =
          (widget.task!['client']['_id'] ??
                  widget.task!['client']['id'] ??
                  widget.task!['client'])
              .toString();
      // keep the lightweight client object temporarily (we'll replace it with fetched client data once available)
      _selectedClient = Map<String, dynamic>.from(widget.task!['client']);
    }
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ')
        ? token.substring('Bearer '.length).trim()
        : token.trim();
  }

  Future<void> _fetchClients() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/client/getclient"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final raw = List<dynamic>.from(data['data'] ?? []);
        // normalize clients to Map<String, dynamic>
        clients = raw
            .map<Map<String, dynamic>>(
              (c) => Map<String, dynamic>.from(c as Map),
            )
            .toList();

        // If we are editing and have a client id from the task, replace the temporary _selectedClient
        // with the one fetched from the server so we get the client's meta (chosenServices/subCompanyNames).
        if (isEditing && _selectedClientId != null) {
          try {
            final found = clients.firstWhere(
              (c) =>
                  (c['_id']?.toString() ?? c['id']?.toString()) ==
                  _selectedClientId.toString(),
              orElse: () => <String, dynamic>{},
            );
            if (found.isNotEmpty) {
              _selectedClient = found;
              // update dependent fields (clientServices, sub companies) now that we have meta
              _updateClientDependentFields();
            }
          } catch (_) {
            // ignore if not found; UI will let user pick
          }
        }

        if (mounted) setState(() {});
      }
    } catch (e) {
      // ignore for now; network errors don't block the UI
    }
  }

  Future<void> _fetchTeamMembers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));
      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/user/team-members"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final raw = List<dynamic>.from(data['teamMembers'] ?? []);
        teamMembers = raw
            .map<Map<String, dynamic>>(
              (m) => Map<String, dynamic>.from(m as Map),
            )
            .toList();
        if (mounted) setState(() {});
      }
    } catch (e) {
      // ignore
    }
  }

  /// When user selects a client, load clientServices and sub companies (normalize & dedupe)
  void _updateClientDependentFields() {
    if (_selectedClient == null) return;

    final meta = _selectedClient!['meta'] ?? {};
    final rawServices = List<dynamic>.from(meta['chosenServices'] ?? []);
    final normalizedServices = <Map<String, dynamic>>[];

    for (var s in rawServices) {
      try {
        final id = (s['_id'] ?? s['serviceId'] ?? s['id']).toString();
        final title =
            (s['title'] ?? s['serviceTitle'] ?? s['service']?['title'] ?? '')
                .toString();
        final subCompanyId =
            (s['subCompanyId'] ?? s['service']?['subCompanyId'])?.toString();
        final selectedOfferings = List<String>.from(
          s['selectedOfferings'] ?? s['offerings'] ?? [],
        );
        normalizedServices.add({
          '_id': id,
          'title': title,
          'subCompanyId': subCompanyId,
          'selectedOfferings': selectedOfferings,
          // keep any other fields you may need
        });
      } catch (_) {
        // skip malformed
      }
    }

    // dedupe clientServices by _id
    final Map<String, Map<String, dynamic>> uniq = {};
    for (var s in normalizedServices) uniq[s['_id'].toString()] = s;
    clientServices = uniq.values.toList();

    // normalize sub companies to string list
    clientSubCompanies = (meta['subCompanyNames'] != null)
        ? List<String>.from(meta['subCompanyNames'].map((e) => e.toString()))
        : [];

    // If creating (not editing) clear previous selections; if editing keep intersection
    if (!isEditing) {
      _selectedServices = [];
    } else {
      final currentServiceIds = clientServices
          .map((s) => s['_id'].toString())
          .toSet();

      // Keep only selected services that still belong to this client's available services
      _selectedServices = _selectedServices
          .where((s) => currentServiceIds.contains(s['serviceId'].toString()))
          .toList();

      // For any selected service that exists in clientServices, update subCompanyName & selectedOfferings
      final Map<String, Map<String, dynamic>> clientServiceMap = {
        for (var s in clientServices) s['_id'].toString(): s,
      };
      for (var i = 0; i < _selectedServices.length; i++) {
        final sid = _selectedServices[i]['serviceId'].toString();
        if (clientServiceMap.containsKey(sid)) {
          final cs = clientServiceMap[sid]!;
          _selectedServices[i]['selectedOfferings'] = List<String>.from(
            cs['selectedOfferings'] ?? [],
          );
          _selectedServices[i]['subCompanyId'] =
              cs['subCompanyId']?.toString() ??
              _selectedServices[i]['subCompanyId'];
          // set subCompanyName using helper
          _selectedServices[i]['subCompanyName'] = _getSubCompanyName(
            _selectedServices[i]['subCompanyId']?.toString(),
          );
        }
      }
    }

    if (mounted) setState(() {});
  }

  /// Show modal to assign team members for a service.
  /// returns:
  /// - null => cancelled
  /// - [] => explicit remove
  /// - List<String> => selected user ids
  Future<List<String>?> _showAssignMembersModal(
    String serviceId,
    String serviceTitle,
  ) {
    final Set<String> tempSelected = {};
    final Map<String, dynamic> existing = _selectedServices.firstWhere(
      (s) => s['serviceId'].toString() == serviceId.toString(),
      orElse: () => <String, dynamic>{},
    );
    if (existing.isNotEmpty) {
      final assigned = List<dynamic>.from(
        existing['assignedTeamMembers'] ?? [],
      );
      tempSelected.addAll(assigned.map((e) => e.toString()));
    }

    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            "Assign Team Members",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade900,
                            ),
                          ),
                        ),
                        Text(
                          serviceTitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 320),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: teamMembers.length,
                        itemBuilder: (context, idx) {
                          final tm = teamMembers[idx];
                          final id = tm['_id'].toString();
                          final name =
                              (tm['fullName'] ?? tm['name'] ?? 'Unnamed')
                                  .toString();
                          final selected = tempSelected.contains(id);
                          return CheckboxListTile(
                            title: Text(name),
                            value: selected,
                            onChanged: (v) {
                              setModalState(() {
                                if (v == true)
                                  tempSelected.add(id);
                                else
                                  tempSelected.remove(id);
                              });
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (existing.isNotEmpty)
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(
                                  ctx,
                                ).pop(<String>[]); // explicit remove
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.red.shade300),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              child: Text(
                                "Remove Service",
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ),
                        if (existing.isNotEmpty) const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(null),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              "Cancel",
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: tempSelected.isEmpty
                                ? null
                                : () => Navigator.of(
                                    ctx,
                                  ).pop(tempSelected.toList()),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primaryColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                "Save (${tempSelected.length})",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Handler when user taps on a service card
  Future<void> _onServiceCardTap(Map<String, dynamic> service) async {
    final serviceId = (service['_id'] ?? service['serviceId']).toString();
    final result = await _showAssignMembersModal(
      serviceId,
      service['title']?.toString() ?? '',
    );

    if (result == null) {
      // user cancelled modal => do nothing
      return;
    }

    // explicit remove
    if (result.isEmpty) {
      setState(() {
        _selectedServices.removeWhere(
          (s) => s['serviceId'].toString() == serviceId,
        );
      });
      return;
    }

    // Build the selected service entry (normalized)
    final entry = {
      'serviceId': serviceId,
      'title': service['title']?.toString() ?? '',
      'subCompanyId': (service['subCompanyId'] ?? '')?.toString(),
      'subCompanyName': _getSubCompanyName(service['subCompanyId']?.toString()),
      'selectedOfferings': List<String>.from(
        service['selectedOfferings'] ?? service['offerings'] ?? [],
      ),
      'assignedTeamMembers': result.map((e) => e.toString()).toList(),
    };

    // Replace existing with same serviceId (prevents duplicates)
    setState(() {
      _selectedServices.removeWhere(
        (s) => s['serviceId'].toString() == serviceId,
      );
      _selectedServices.add(Map<String, dynamic>.from(entry));
    });
  }

  void _removeSelectedService(String serviceId) {
    setState(() {
      _selectedServices.removeWhere(
        (s) => s['serviceId'].toString() == serviceId.toString(),
      );
    });
  }

  /// toggle team member inside a selected service card's FilterChip
  void _toggleServiceTeamMember(String serviceId, String teamMemberId) {
    setState(() {
      final idx = _selectedServices.indexWhere(
        (s) => s['serviceId'].toString() == serviceId.toString(),
      );
      if (idx == -1) return;
      final service = Map<String, dynamic>.from(_selectedServices[idx]);
      final List<String> assignedMembers = List<String>.from(
        service['assignedTeamMembers'] ?? [],
      );
      if (assignedMembers.contains(teamMemberId)) {
        assignedMembers.remove(teamMemberId);
      } else {
        assignedMembers.add(teamMemberId);
      }
      service['assignedTeamMembers'] = assignedMembers;
      _selectedServices[idx] = service;
    });
  }

  bool _isServiceTeamMemberSelected(String serviceId, String teamMemberId) {
    final service = _selectedServices.firstWhere(
      (s) => s['serviceId'].toString() == serviceId.toString(),
      orElse: () => {'assignedTeamMembers': []},
    );
    final assignedMembers = List<String>.from(
      service['assignedTeamMembers'] ?? [],
    );
    return assignedMembers.contains(teamMemberId);
  }

  String _getSubCompanyName(String? subCompanyId) {
    if (subCompanyId == null) return '';
    if (_selectedClient == null) return '';
    final meta = _selectedClient!['meta'] ?? {};
    final subCompanyIds = List<dynamic>.from(
      meta['subCompanyIds'] ?? [],
    ).map((e) => e.toString()).toList();
    final subCompanyNames = List<dynamic>.from(
      meta['subCompanyNames'] ?? [],
    ).map((e) => e.toString()).toList();
    final index = subCompanyIds.indexOf(subCompanyId.toString());
    return index != -1 ? subCompanyNames[index] : '';
  }

  bool _isServiceSelected(Map<String, dynamic> service) {
    final sid = (service['_id'] ?? service['serviceId']).toString();
    return _selectedServices.any((s) => s['serviceId'].toString() == sid);
  }

  List<Widget> _buildServiceSelectionWidgets() {
    return clientServices.map<Widget>((service) {
      final isSelected = _isServiceSelected(service);
      final offerings = List<String>.from(
        service['selectedOfferings'] ?? service['offerings'] ?? [],
      );
      final subCompanyName = _getSubCompanyName(
        (service['subCompanyId'] ?? '').toString(),
      );
      final serviceIdStr = (service['_id'] ?? service['serviceId']).toString();

      return Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        elevation: 0,
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? AppColors.primaryColor : Colors.grey.shade300,
            width: isSelected ? 1.8 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => _onServiceCardTap(service),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primaryColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primaryColor
                              : Colors.grey.shade400,
                          width: 1.6,
                        ),
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              size: 14,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service['title']?.toString() ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: isSelected
                                  ? AppColors.primaryColor
                                  : Colors.grey.shade900,
                            ),
                          ),
                          if (subCompanyName.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                subCompanyName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isSelected
                                      ? AppColors.primaryColor.withOpacity(0.85)
                                      : Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (offerings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Included Offerings:",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: offerings.map<Widget>((offering) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.primaryColor.withOpacity(
                                    0.15,
                                  ),
                                ),
                              ),
                              child: Text(
                                offering.toString(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ],

                // Show assigned members inline only when selected (and allow quick toggle chips)
                if (isSelected) ...[
                  const SizedBox(height: 12),
                  Divider(color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Text(
                    "Assigned Team Members:",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: teamMembers.map<Widget>((tm) {
                        final isMemberSelected = _isServiceTeamMemberSelected(
                          serviceIdStr,
                          tm['_id'].toString(),
                        );
                        return FilterChip(
                          label: Text(
                            tm['fullName']?.toString() ??
                                tm['name']?.toString() ??
                                'Unnamed',
                            style: TextStyle(
                              color: isMemberSelected
                                  ? Colors.white
                                  : Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          selected: isMemberSelected,
                          onSelected: (selected) {
                            // toggle in-place; keep service in list
                            _toggleServiceTeamMember(
                              serviceIdStr,
                              tm['_id'].toString(),
                            );
                          },
                          selectedColor: AppColors.primaryColor,
                          checkmarkColor: Colors.white,
                          backgroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: Colors.grey.shade300),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildSelectedServicesSummary() {
    return _selectedServices.map<Widget>((service) {
      final assignedMembers = List<String>.from(
        service['assignedTeamMembers'] ?? [],
      );
      final assignedMemberNames = teamMembers
          .where((tm) => assignedMembers.contains(tm['_id'].toString()))
          .map(
            (tm) =>
                tm['fullName']?.toString() ??
                tm['name']?.toString() ??
                'Unnamed',
          )
          .toList();

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primaryColor.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: AppColors.primaryColor,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service['title']?.toString() ?? '',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Colors.black87,
                        ),
                      ),
                      if (service['subCompanyName'] != null &&
                          service['subCompanyName'].toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            service['subCompanyName'].toString(),
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () =>
                      _removeSelectedService(service['serviceId'].toString()),
                  icon: Icon(Icons.close, color: Colors.grey.shade500),
                  iconSize: 20,
                  tooltip: 'Remove Service',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),

            if (assignedMemberNames.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.group,
                          color: Colors.green.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "Assigned:",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: assignedMemberNames.map<Widget>((name) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.person,
                                size: 12,
                                color: Colors.green.shade700,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                name,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green.shade900,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],

            if (service['selectedOfferings'] != null &&
                (service['selectedOfferings'] as List).isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Selected Offerings:",
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: (service['selectedOfferings'] as List)
                          .map<Widget>((offering) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppColors.primaryColor.withOpacity(
                                    0.12,
                                  ),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check,
                                    size: 12,
                                    color: AppColors.primaryColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    offering.toString(),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.primaryColor,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );
    }).toList();
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    // each selected service must have at least one assigned member
    for (var s in _selectedServices) {
      final assigned = List<String>.from(s['assignedTeamMembers'] ?? []);
      if (assigned.isEmpty) {
        SnackbarHelper.show(
          context,
          title: 'Assign Team',
          message:
              'Please assign at least one team member for "${s['title'] ?? 'selected service'}".',
          type: ContentType.failure,
        );
        return;
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final token = _cleanToken(prefs.getString('auth_token'));

    // build assignedTo as unique union
    final Set<String> assignedToSet = {};
    for (var s in _selectedServices) {
      final assigned = List<String>.from(s['assignedTeamMembers'] ?? []);
      for (var a in assigned) assignedToSet.add(a.toString());
    }

    final body = {
      "title": _titleCtrl.text.trim(),
      "description": _descriptionCtrl.text.trim(),
      "client": _selectedClientId,
      // send chosenServices array with assignedTeamMembers inside each service
      "chosenServices": _selectedServices,
      "assignedTo": assignedToSet.toList(),
      "status": _selectedStatus,
      "priority": _selectedPriority,
      "deadline": _deadline?.toIso8601String(),
    };

    setState(() => isLoading = true);

    final url = isEditing
        ? Uri.parse("${ApiConfig.baseUrl}/task/${widget.task!['_id']}")
        : Uri.parse("${ApiConfig.baseUrl}/task/addtask");

    try {
      final res = await (isEditing
          ? http.put(
              url,
              headers: {
                "Authorization": "Bearer $token",
                "Content-Type": "application/json",
              },
              body: jsonEncode(body),
            )
          : http.post(
              url,
              headers: {
                "Authorization": "Bearer $token",
                "Content-Type": "application/json",
              },
              body: jsonEncode(body),
            ));

      setState(() => isLoading = false);

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (!mounted) return;
        SnackbarHelper.show(
          context,
          title: 'Success',
          message: isEditing
              ? 'Task updated successfully'
              : 'Task created successfully',
          type: ContentType.success,
        );
        Navigator.pop(context, true);
      } else {
        final err = jsonDecode(res.body);
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: err['message'] ?? 'Failed to save task',
          type: ContentType.failure,
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      SnackbarHelper.show(
        context,
        title: 'Error',
        message: 'Network error',
        type: ContentType.failure,
      );
    }
  }

  List<Widget> _buildSubCompanyWidgets() {
    return clientSubCompanies.map<Widget>((s) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business, color: AppColors.primaryColor, size: 16),
            const SizedBox(width: 8),
            Text(
              s.toString(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Edit Task" : "Create New Task"),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),

      // sticky button in bottomNavigationBar
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _saveTask,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            isEditing ? "Update Task" : "Create Task",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),

      body: isLoading && !isEditing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionHeader(
                      "Basic Information",
                      Icons.info_outline,
                    ),
                    const SizedBox(height: 12),
                    _buildTextField(_titleCtrl, "Task Title", Icons.title),
                    _buildTextField(
                      _descriptionCtrl,
                      "Task Description",
                      Icons.description,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 18),
                    _buildSectionHeader("Client Information", Icons.person),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedClientId,
                      decoration: _inputDecoration(
                        "Select Client",
                        Icons.person_outline,
                      ),
                      items: clients
                          .map<DropdownMenuItem<String>>(
                            (c) => DropdownMenuItem<String>(
                              value: c['_id']?.toString(),
                              child: Text(
                                c['name'].toString(),
                                style: const TextStyle(fontSize: 14),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedClientId = value;
                          _selectedClient = clients.firstWhere(
                            (c) => c['_id']?.toString() == value,
                            orElse: () => <String, dynamic>{},
                          );
                          // if we didn't find proper map, keep as empty map -> avoid null
                          if ((_selectedClient ?? {}).isEmpty) {
                            _selectedClient = null;
                          }
                          _updateClientDependentFields();
                        });
                      },
                      validator: (val) =>
                          val == null ? 'Please select a client' : null,
                    ),
                    if (clientSubCompanies.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.business,
                                  color: AppColors.primaryColor,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Client's Sub Companies",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade800,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _buildSubCompanyWidgets(),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (clientServices.isNotEmpty) ...[
                      const SizedBox(height: 26),
                      _buildSectionHeader(
                        "Service Selection",
                        Icons.design_services,
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Available Services",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Tap a service to select it and assign team members (required).",
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 12),
                            ..._buildServiceSelectionWidgets(),
                          ],
                        ),
                      ),
                    ],
                    if (_selectedServices.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppColors.primaryColor.withOpacity(0.14),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: AppColors.primaryColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  "Selected Services (${_selectedServices.length})",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primaryColor,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ..._buildSelectedServicesSummary(),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    _buildSectionHeader("Task Details", Icons.settings),
                    const SizedBox(height: 12),
                    Column(
                      children: [
                        _buildStatusDropdown(),
                        const SizedBox(height: 12),
                        _buildPriorityDropdown(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDeadlinePicker(),
                    const SizedBox(height: 80), // space for sticky button
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.primaryColor.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: AppColors.primaryColor, size: 20),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: _inputDecoration(label, icon),
        validator: (val) =>
            val == null || val.trim().isEmpty ? '$label is required' : null,
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: Colors.grey.shade600),
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey.shade600),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
      ),
    );
  }

  Widget _buildStatusDropdown() {
    final statuses = ['open', 'in_progress', 'review', 'done', 'blocked'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Status",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedStatus,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.flag, color: Colors.grey.shade600),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
            ),
          ),
          items: statuses
              .map<DropdownMenuItem<String>>(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    s.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedStatus = v),
          validator: (val) => val == null ? 'Please select status' : null,
        ),
      ],
    );
  }

  Widget _buildPriorityDropdown() {
    final priorities = ['low', 'medium', 'high'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Priority",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedPriority,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.priority_high, color: Colors.grey.shade600),
            filled: true,
            fillColor: Colors.grey.shade50,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade400),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
            ),
          ),
          items: priorities
              .map<DropdownMenuItem<String>>(
                (s) => DropdownMenuItem(
                  value: s,
                  child: Text(
                    s.toUpperCase(),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _selectedPriority = v),
          validator: (val) => val == null ? 'Please select priority' : null,
        ),
      ],
    );
  }

  Widget _buildDeadlinePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Deadline",
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: Colors.grey.shade800,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _deadline ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) setState(() => _deadline = picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              prefixIcon: Icon(
                Icons.calendar_today,
                color: Colors.grey.shade600,
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade400),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.primaryColor, width: 2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _deadline == null
                      ? "Select deadline date"
                      : _deadline!.toLocal().toString().split(' ')[0],
                  style: TextStyle(
                    color: _deadline == null
                        ? Colors.grey.shade600
                        : Colors.black87,
                    fontSize: 14,
                  ),
                ),
                Icon(
                  Icons.calendar_today,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
