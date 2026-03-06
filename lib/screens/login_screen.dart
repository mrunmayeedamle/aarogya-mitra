import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = true;

  // 🔹 Update this IP address to match your Flask backend IP
  final String baseUrl = 'http://10.141.115.196:5000/api';

  Future<void> _handleAuth(BuildContext context) async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final name = _nameController.text.trim();

    final url = _isLogin ? '$baseUrl/login' : '$baseUrl/signup';
    final body = _isLogin
        ? {'email': email, 'password': password}
        : {'name': name, 'email': email, 'password': password};

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        // ✅ Successful login or signup
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        await authProvider.setAuthenticated(email);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'यशस्वी ✅')),
        );
      } else {
        // ❌ Error message from backend
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'त्रुटी आली')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('सर्व्हरशी संपर्क साधता आला नाही ❌')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'आरोग्यमित्र',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'तुमचा मराठी आरोग्य सहाय्यक',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
              if (!_isLogin)
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'नाव',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'कृपया नाव प्रविष्ट करा'
                      : null,
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'ईमेल',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? 'कृपया ईमेल प्रविष्ट करा'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'पासवर्ड',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'कृपया पासवर्ड प्रविष्ट करा';
                  }
                  if (value.length < 6) {
                    return 'पासवर्ड ६ वर्णांपेक्षा जास्त असावा';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: authProvider.isLoading
                    ? null
                    : () async => _handleAuth(context),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: authProvider.isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(_isLogin ? 'लॉगिन' : 'नोंदणी करा'),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => setState(() => _isLogin = !_isLogin),
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
    );
  }
}
