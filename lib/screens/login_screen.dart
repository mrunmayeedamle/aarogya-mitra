import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _ageController = TextEditingController();

  String? _selectedGender;

  bool _isLogin = true;

  final String baseUrl = 'http://10.99.143.196:5000/api';

  Future<void> sendVerificationEmail(
      String userEmail,
      String token,
      ) async {

    final verificationLink =
        'http://10.99.143.196:5000/api/verify-email/$token';

    final url =
    Uri.parse('https://api.emailjs.com/api/v1.0/email/send');

    final body = {
      'service_id': 'service_xzkuy6g',
      'template_id': 'template_fgopr06',
      'user_id': '8Sfx9WXi3K4f1N75W',

      'template_params': {
        'email': userEmail,
        'verification_link': verificationLink,
      }
    };

    try {

      final response = await http.post(
        url,

        headers: {
          'origin': 'http://localhost',
          'Content-Type': 'application/json',
        },

        body: jsonEncode(body),
      );

      debugPrint(
          "📧 EmailJS STATUS: ${response.statusCode}");

      debugPrint(
          "📧 EmailJS RESPONSE: ${response.body}");

    } catch (e) {

      debugPrint(
          "❌ EmailJS ERROR: $e");
    }
  }



  Future<void> _handleAuth(BuildContext context) async {
    debugPrint(
        "🚀 AUTH BUTTON CLICKED! Mode: ${_isLogin ? 'Login' : 'Signup'}");

    if (!_formKey.currentState!.validate()) {
      debugPrint("❌ Form validation failed");
      return;
    }

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();
    final age = int.tryParse(_ageController.text.trim()) ?? 0;
    final gender = _selectedGender;

    final url = _isLogin ? '$baseUrl/login' : '$baseUrl/signup';

    final body = _isLogin
        ? {
            'email': email,
            'password': password,
          }
        : {
            'name': name,
            'email': email,
            'password': password,
            'age': age,
            'gender': gender,
          };

    debugPrint("📡 Sending request to: $url");

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint("📤 Status Code: ${response.statusCode}");
      debugPrint("📄 Response: ${response.body}");

      if (!mounted) return;

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        // LOGIN
        if (_isLogin) {
          final authProvider = Provider.of<AuthProvider>(
            context,
            listen: false,
          );

          await authProvider.setAuthenticated(email);
        } else {
          // SIGNUP
          final token = data['verification_token'];

          await sendVerificationEmail(
            email,
            token,
          );
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message'] ?? 'यशस्वी ✅',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['message'] ?? 'त्रुटी आली',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'सर्व्हरशी संपर्क नाही: $e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 24.0,
            vertical: 60.0,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.local_hospital,
                  size: 80,
                  color: Colors.green.shade700,
                ),
                const SizedBox(height: 16),
                const Text(
                  'आरोग्यमित्र',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 32),
                // ✅ EMAIL
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'ईमेल',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (v) => v!.isEmpty ? 'ईमेल आवश्यक' : null,
                ),
                const SizedBox(height: 16),
                // ✅ PASSWORD
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'पासवर्ड',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'पासवर्ड आवश्यक';
                    }

                    if (!_isLogin && v.length < 6) {
                      return 'पासवर्ड ६ अक्षरी हवा';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // ✅ SIGNUP ONLY FIELDS
                if (!_isLogin) ...[
                  // NAME
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: 'नाव',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (v) => v!.isEmpty ? 'नाव आवश्यक' : null,
                  ),
                  const SizedBox(height: 16),
                  // AGE
                  TextFormField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'वय',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (v) => v!.isEmpty ? 'वय आवश्यक' : null,
                  ),
                  const SizedBox(height: 16),
                  // GENDER
                  DropdownButtonFormField<String>(
                    value: _selectedGender,
                    decoration: InputDecoration(
                      labelText: 'लिंग',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Male',
                        child: Text('पुरुष'),
                      ),
                      DropdownMenuItem(
                        value: 'Female',
                        child: Text('महिला'),
                      ),
                      DropdownMenuItem(
                        value: 'Other',
                        child: Text('इतर'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedGender = value;
                      });
                    },
                    validator: (v) => v == null ? 'लिंग निवडा' : null,
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: authProvider.isLoading
                      ? null
                      : () => _handleAuth(context),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 55),
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: authProvider.isLoading
                      ? const CircularProgressIndicator(
                          color: Colors.white,
                        )
                      : Text(
                          _isLogin ? 'लॉगिन' : 'नोंदणी करा',
                        ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isLogin = !_isLogin;
                    });
                  },
                  child: Text(
                    _isLogin
                        ? 'नवीन वापरकर्ता? नोंदणी करा'
                        : 'आधीच खाते आहे? लॉगिन करा',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
