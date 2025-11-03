import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiClient {
  // 🔧 Set this to your Node API base URL
  static const String baseUrl = ApiClientBase.baseUrl;
}

class ApiClientBase {
  static const String baseUrl = 'http://192.168.1.20:9000/api/v1'; // <-- change
}

Future<String?> _getJwt() async {
  final sp = await SharedPreferences.getInstance();
  // You are saving it as "auth_token" in your LoginScreen, so keep that
  return sp.getString('auth_token');
}

Future<http.Response> apiPost(String path, Map<String, dynamic> body) async {
  final token = await _getJwt();
  final uri = Uri.parse('${ApiClient.baseUrl}$path');
  return http.post(
    uri,
    headers: {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(body),
  );
}

Future<http.Response> apiDelete(String path, Map<String, dynamic> body) async {
  final token = await _getJwt();
  final req = http.Request('DELETE', Uri.parse('${ApiClient.baseUrl}$path'));
  req.headers.addAll({
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  });
  req.body = jsonEncode(body);
  final streamed = await req.send();
  return http.Response.fromStream(streamed);
}
