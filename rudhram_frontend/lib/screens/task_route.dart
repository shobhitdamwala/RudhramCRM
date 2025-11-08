import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_config.dart';
import '../utils/constants.dart';
import '../utils/snackbar_helper.dart';
import 'task_details_screen.dart';
import '../utils/snackbar_helper.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';

class TaskRoute extends StatefulWidget {
  const TaskRoute({super.key});

  @override
  State<TaskRoute> createState() => _TaskRouteState();
}

class _TaskRouteState extends State<TaskRoute> {
  Map<String, dynamic>? task;
  bool loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final taskId = ModalRoute.of(context)?.settings.arguments?.toString();
    if (taskId != null && loading) _load(taskId);
  }

  String _cleanToken(String? token) {
    if (token == null) return '';
    return token.startsWith('Bearer ') ? token.substring(7).trim() : token.trim();
    }

  Future<void> _load(String taskId) async {
    setState(() => loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = _cleanToken(prefs.getString('auth_token'));

      final res = await http.get(
        Uri.parse("${ApiConfig.baseUrl}/task/$taskId"),
        headers: {"Authorization": "Bearer $token"},
      );

      if (res.statusCode == 200) {
        final body = jsonDecode(res.body);
        setState(() => task = Map<String, dynamic>.from(body['data'] ?? {}));
      } else {
        SnackbarHelper.show(context, title: 'Error', message: 'Failed to load task', type: ContentType.failure);
      }
    } catch (e) {
      SnackbarHelper.show(context, title: 'Error', message: 'Task load error: $e', type: ContentType.failure);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.brown)),
      );
    }
    if (task == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Task')),
        body: const Center(child: Text('Task not found')),
      );
    }
    return TaskDetailsScreen(task: task!);
  }
}
