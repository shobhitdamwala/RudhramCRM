import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class MeetingDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> meeting;
  const MeetingDetailsScreen({Key? key, required this.meeting}) : super(key: key);

  @override
  State<MeetingDetailsScreen> createState() => _MeetingDetailsScreenState();
}

class _MeetingDetailsScreenState extends State<MeetingDetailsScreen> {
  String? subCompanyName;
  bool isLoadingSubCompany = false;

  @override
  void initState() {
    super.initState();
    _fetchSubCompanyName();
  }

  Future<void> _fetchSubCompanyName() async {
    if (widget.meeting['subCompany'] == null ||
        widget.meeting['subCompany'].toString().isEmpty) return;

    setState(() => isLoadingSubCompany = true);
    try {
      final res = await http.get(Uri.parse("${ApiConfig.baseUrl}/subcompany/getsubcompany"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['data'] as List);
        final match = list.firstWhere(
          (item) => item['_id'] == widget.meeting['subCompany'],
          orElse: () => null,
        );
        if (match != null && mounted) {
          setState(() => subCompanyName = match['name']);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackbarHelper.show(
          context,
          title: 'Error',
          message: 'Failed to load Sub Company name',
          type: ContentType.failure,
        );
      }
    } finally {
      if (mounted) setState(() => isLoadingSubCompany = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meeting = widget.meeting;
    final start = DateTime.tryParse(meeting['startTime'] ?? '');
    final end = DateTime.tryParse(meeting['endTime'] ?? '');
    final dtFormat = DateFormat('EEE, dd MMM yyyy · h:mm a');

    final organizerName = (meeting['organizer'] is Map)
        ? (meeting['organizer']?['fullName']?.toString() ?? '')
        : (meeting['organizer']?.toString() ?? '');

    final leadName = (meeting['lead'] is Map)
        ? (meeting['lead']?['name']?.toString() ?? '')
        : (meeting['lead']?.toString() ?? '');

    final clientName = (meeting['client'] is Map)
        ? (meeting['client']?['name']?.toString() ?? '')
        : (meeting['client']?.toString() ?? '');

    final participantsNames = (meeting['participants'] is List)
        ? (meeting['participants'] as List)
            .map((p) => p is Map
                ? (p['fullName']?.toString() ?? '')
                : p.toString())
            .join(', ')
        : '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Meeting Details'),
        backgroundColor: AppColors.primaryColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📌 Header
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 3,
              color: const Color.fromARGB(255, 255, 255, 255),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meeting['title']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.brown,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meeting['agenda']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 📅 Date and Time
            _infoRow(Icons.calendar_today_outlined, 'Start',
                start != null ? dtFormat.format(start.toLocal()) : ''),
            _infoRow(Icons.calendar_today, 'End',
                end != null ? dtFormat.format(end.toLocal()) : ''),
            const Divider(height: 20),

            // 🏢 Organizer & Company
            _infoRow(
              Icons.business_outlined,
              'Sub Company',
              isLoadingSubCompany
                  ? 'Loading...'
                  : (subCompanyName ?? 'Not Found'),
            ),
            _infoRow(Icons.person_outline, 'Organizer', organizerName),
            _infoRow(Icons.people_outline, 'Participants', participantsNames),
            const Divider(height: 20),

            // 🧭 Lead / Client
            _infoRow(Icons.person_search_outlined, 'Lead', leadName),
            _infoRow(Icons.person_outline, 'Client', clientName),
            const Divider(height: 20),

            // 📍 Location
            _infoRow(Icons.place_outlined, 'Location',
                meeting['location']?.toString() ?? ''),
            _infoRow(Icons.link, 'Meeting Link',
                meeting['meetingLink']?.toString() ?? ''),
            _infoRow(Icons.notes_outlined, 'Notes',
                meeting['notes']?.toString() ?? ''),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.brown, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.brown,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
