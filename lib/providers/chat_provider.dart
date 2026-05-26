import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../services/tts_service.dart';

class ChatMessage {
  final int? id;
  final String message;
  final bool isUser;
  final DateTime timestamp;
  final String? disease;
  final String? precautions;
  final List<String>? symptoms;

  ChatMessage({
    this.id,
    required this.message,
    required this.isUser,
    required this.timestamp,
    this.disease,
    this.precautions,
    this.symptoms,
  });

  Map<String, dynamic> toJson() {
    return {
      'message': message,
      'is_user': isUser,
      'disease': disease,
      'precautions': precautions,
      'symptoms': symptoms,
    };
  }

  static ChatMessage fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'],
      message: map['message'],
      isUser: map['is_user'] == true || map['is_user'] == 1,
      timestamp: map['timestamp'] != null
          ? DateTime.parse(map['timestamp'])
          : DateTime.now(),
      disease: map['disease'],
      precautions: map['precautions'],
      symptoms: map['symptoms'] != null
          ? List<String>.from(map['symptoms'] is String ? jsonDecode(map['symptoms']) : map['symptoms'])
          : null,
    );
  }
}

class ChatProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isRecording = false;
  int? _currentConversationId;
  String? _userEmail;

  List<ChatMessage> _messages = [];
  List<Map<String, dynamic>> _conversations = [];

  final String baseUrl = 'http://10.99.143.196:5000/api';

  List<ChatMessage> get messages => _messages;
  List<Map<String, dynamic>> get conversations => _conversations;
  bool get isLoading => _isLoading;
  bool get isRecording => _isRecording;
  int? get currentConversationId => _currentConversationId;

  String? get currentConversationTitle {
    if (_currentConversationId == null) return null;
    final conv = _conversations.firstWhere(
      (c) => c['id'] == _currentConversationId,
      orElse: () => {},
    );
    return conv['title'];
  }

  void setUserEmail(String? email) {
    if (_userEmail != email) {
      _userEmail = email;
      if (email != null) {
        loadConversations();
      } else {
        _conversations = [];
        _messages = [];
        _currentConversationId = null;
        notifyListeners();
      }
    }
  }

  // ---------------- CONVERSATION MANAGEMENT ----------------

  Future<void> loadConversations() async {
    if (_userEmail == null) return;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/conversations?email=$_userEmail'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          _conversations = List<Map<String, dynamic>>.from(data['conversations']);
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint("Error loading conversations: $e");
    }
  }

  Future<int?> startNewConversation({String? title}) async {
    if (_userEmail == null) return null;

    _isLoading = true;
    notifyListeners();

    try {
      title ??= "नवीन संभाषण - ${DateTime.now().toString().substring(0, 16)}";
      final response = await http.post(
        Uri.parse('$baseUrl/conversations'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _userEmail,
          'title': title,
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        _currentConversationId = data['id'];
        _messages = [];

        // Add initial assistant message
        final initialText = 'तुम्हाला आज कसे वाटते? कृपया तुमची लक्षणे किंवा तक्रारी सांगा.';
        await addMessageToBackend(ChatMessage(
          message: initialText,
          isUser: false,
          timestamp: DateTime.now(),
        ));

        await loadConversations();
        return _currentConversationId;
      }
    } catch (e) {
      debugPrint("Error starting conversation: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return null;
  }

  Future<void> loadConversationMessages(int conversationId) async {
    if (_userEmail == null) return;

    _isLoading = true;
    _currentConversationId = conversationId;
    _messages = [];
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/conversations/$conversationId/messages?email=$_userEmail'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List rawMsgs = data['messages'];
          _messages = rawMsgs.map((m) => ChatMessage.fromMap(m)).toList();
        }
      }
    } catch (e) {
      debugPrint("Error loading messages: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteConversation(int conversationId) async {
    if (_userEmail == null) return;

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/conversations/$conversationId?email=$_userEmail'),
      );

      if (response.statusCode == 200) {
        if (_currentConversationId == conversationId) {
          _currentConversationId = null;
          _messages = [];
        }
        await loadConversations();
      }
    } catch (e) {
      debugPrint("Error deleting conversation: $e");
    }
  }

  Future<void> updateConversationTitle(int conversationId, String title) async {
    // Note: You might need to add a backend route for this, 
    // but for now we'll just implement it locally or assume the backend handles it via another POST.
  }

  // ---------------- MESSAGE HANDLING ----------------

  Future<void> addMessageToBackend(ChatMessage message) async {
    if (_currentConversationId == null || _userEmail == null) return;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/conversations/$_currentConversationId/messages'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'email': _userEmail,
          ...message.toJson(),
        }),
      );

      if (response.statusCode == 201) {
        _messages.add(message);
        notifyListeners();

        if (!message.isUser) {
          TtsService.instance.speak(message.message);
        }
      }
    } catch (e) {
      debugPrint("Error adding message: $e");
    }
  }

  Future<Map<String, dynamic>?> sendTextMessage(String text, String language, {bool noMoreSymptoms = false}) async {
    if (text.trim().isEmpty || _currentConversationId == null) return null;

    _isLoading = true;
    notifyListeners();

    final userMsg = ChatMessage(
      message: text,
      isUser: true,
      timestamp: DateTime.now(),
    );

    await addMessageToBackend(userMsg);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'text': text, 
          'language': language, 
          'conversation_id': _currentConversationId,
          'no_more_symptoms': noMoreSymptoms,
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['follow_up_needed'] == true) {
          return data;
        }

        if (data['success'] == true) {
          final List rawSymptoms = (data['symptoms_detected'] as List?) ?? [];
          final symptomsDetected = rawSymptoms.map((s) => s.toString()).toList();
          final precautionsList = (data['precautions_marathi'] as List?) ?? [];

          final responseText = '''
निदान: ${data['disease_marathi'] ?? 'नाही'}

सापडलेली लक्षणे: ${symptomsDetected.isNotEmpty ? symptomsDetected.join(', ') : 'कोणतीही लक्षणे नोंदली नाहीत'}

खबरदारी:
${precautionsList.map((p) => '• $p').join('\n')}
''';

          final botMsg = ChatMessage(
            message: responseText.trim(),
            isUser: false,
            timestamp: DateTime.now(),
            disease: data['disease_marathi'],
            precautions: precautionsList.join('\n'),
            symptoms: symptomsDetected,
          );

          await addMessageToBackend(botMsg);
        } else {
          final errorMsg = ChatMessage(
            message: data['error_marathi'] ?? 'माफ करा, काही त्रुटी आली.',
            isUser: false,
            timestamp: DateTime.now(),
          );
          await addMessageToBackend(errorMsg);
        }
        return data;
      }
    } catch (e) {
      debugPrint("Prediction error: $e");
    } finally {
      _isLoading = false;
      await loadConversations();
      notifyListeners();
    }
    return null;
  }

  void clearChat() {
    _messages = [];
    notifyListeners();
  }

  void setRecording(bool recording) {
    _isRecording = recording;
    notifyListeners();
  }
}
