import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _userEmail;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get userEmail => _userEmail;

  // Replace this with your actual Flask backend IP
  final String _baseUrl = 'http://10.141.115.196:5000/api';

  AuthProvider() {
    _checkAuthStatus();
  }

  Future<void> _checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    _isAuthenticated = prefs.getBool('isAuthenticated') ?? false;
    _userEmail = prefs.getString('userEmail');

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isAuthenticated', true);
        await prefs.setString('userEmail', email);

        _isAuthenticated = true;
        _userEmail = email;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print("Login error: $e");
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signup(String email, String password, String name) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/signup'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'password': password,
          'name': name,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 201 && data['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isAuthenticated', true);
        await prefs.setString('userEmail', email);

        _isAuthenticated = true;
        _userEmail = email;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      if (kDebugMode) {
        print("Signup error: $e");
      }
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await http.post(Uri.parse('$_baseUrl/logout'));

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      _isAuthenticated = false;
      _userEmail = null;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print("Logout error: $e");
      }
    }
  }

  Future<void> setAuthenticated(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isAuthenticated', true);
    await prefs.setString('userEmail', email);
    _isAuthenticated = true;
    _userEmail = email;
    notifyListeners();
  }
}
