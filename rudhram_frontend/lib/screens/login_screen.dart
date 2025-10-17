import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rudhram_frontend/screens/home_screen.dart';
import '../widgets/custom_textfield.dart';
import '../widgets/background_container.dart';
import '../utils/constants.dart';
import '../utils/api_config.dart';
import 'package:awesome_snackbar_content/awesome_snackbar_content.dart';
import '../utils/snackbar_helper.dart';
import 'package:rudhram_frontend/screens/teammember_home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;

  Future<void> loginUser() async {
    final username = usernameController.text.trim();
    final password = passwordController.text.trim();

    // Input validation
    if (username.isEmpty || password.isEmpty) {
      SnackbarHelper.show(
        context,
        title: 'Missing Info',
        message: 'Please enter both username and password.',
        type: ContentType.warning,
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/user/login"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"fullName": username, "password": password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data["success"] == true) {
        // Store user info & token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("auth_token", data["token"] ?? "");
        await prefs.setString("user", jsonEncode(data["user"]));

        final userRole = data["user"]["role"];

        SnackbarHelper.show(
          context,
          title: 'Login Successful 🎉',
          message: 'Welcome back, ${data["user"]["fullName"]}!',
          type: ContentType.success,
        );

        await Future.delayed(const Duration(seconds: 1));

        if (userRole == "SUPER_ADMIN") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        } else if (userRole == "TEAM_MEMBER") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TeamMemberHomeScreen()),
          );
        } else {
          SnackbarHelper.show(
            context,
            title: 'Access Denied ❌',
            message: 'Your role is not authorized to access this app.',
            type: ContentType.failure,
          );
        }
      } else {
        SnackbarHelper.show(
          context,
          title: 'Login Failed ⚠️',
          message: data["message"] ?? "Invalid username or password.",
          type: ContentType.failure,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: BackgroundContainer(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.08),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.08),
              Image.asset('assets/logo.png', height: size.height * 0.18),
              const SizedBox(height: 20),
              Text(
                'Welcome',
                style: TextStyle(
                  color: AppColors.primaryColor,
                  fontSize: size.width * 0.07,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 30),
              CustomTextField(
                controller: usernameController,
                hintText: 'Username',
                icon: Icons.person_outline,
              ),
              const SizedBox(height: 15),
              CustomTextField(
                controller: passwordController,
                hintText: 'Password',
                icon: Icons.lock_outline,
                isPassword: true,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isLoading ? null : loginUser,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Login Now',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'To reset password contact admin',
                style: TextStyle(color: Colors.red, fontSize: 12),
              ),
              SizedBox(height: size.height * 0.1),
            ],
          ),
        ),
      ),
    );
  }
}
