import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../services/tts_service.dart';

class ChatMessage {
  final String message;
  final bool isUser;
  final DateTime timestamp;
  final String? disease;
  final String? precautions;
  final List<String>? symptoms;

  ChatMessage({
    required this.message,
    required this.isUser,
    required this.timestamp,
    this.disease,
    this.precautions,
    this.symptoms,
  });

  Map<String, dynamic> toMap(int conversationId) {
    return {
      'conversation_id': conversationId,
      'message': message,
      'is_user': isUser ? 1 : 0,
      'timestamp': timestamp.toIso8601String(),
      'disease': disease,
      'precautions': precautions,
      'symptoms': symptoms != null ? jsonEncode(symptoms) : null,
    };
  }

  static ChatMessage fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      message: map['message'],
      isUser: map['is_user'] == 1,
      timestamp: DateTime.parse(map['timestamp']),
      disease: map['disease'],
      precautions: map['precautions'],
      symptoms: map['symptoms'] != null
          ? List<String>.from(jsonDecode(map['symptoms']))
          : null,
    );
  }
}

class ChatProvider with ChangeNotifier {
  Database? _db;
  bool _isLoading = false;
  bool _isRecording = false;
  int? _currentConversationId;

  List<ChatMessage> _messages = [];
  List<Map<String, dynamic>> _conversations = [];

  // expose current conversation id/title to UI
  int? get currentConversationId => _currentConversationId;
  String? get currentConversationTitle {
    if (_currentConversationId == null) return null;
    final conv = _conversations
        .firstWhere((c) => c['id'] == _currentConversationId, orElse: () => {});
    return conv['title'];
  }

  final String baseUrl =
      'http://10.141.90.209:5000/api'; // update IP if needed

  List<ChatMessage> get messages => _messages;
  List<Map<String, dynamic>> get conversations => _conversations;
  bool get isLoading => _isLoading;
  bool get isRecording => _isRecording;

  // ---------------- DATABASE SETUP ----------------

  Future<void> initDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final path = join(docsDir.path, 'chats.db');

    // open the DB
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE conversations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT,
            created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            conversation_id INTEGER,
            message TEXT,
            is_user INTEGER,
            timestamp TEXT,
            disease TEXT,
            precautions TEXT,
            symptoms TEXT
          )
        ''');
      },
    );

    // Ensure last_message column exists (adds it for older DBs)
    final cols = await db.rawQuery("PRAGMA table_info(conversations)");
    final hasLastMessage = cols.any((c) => c['name'] == 'last_message');
    if (!hasLastMessage) {
      await db
          .execute("ALTER TABLE conversations ADD COLUMN last_message TEXT");
    }

    _db = db;

    await loadConversations();
  }

  // ---------------- CONVERSATION MANAGEMENT ----------------

  Future<void> loadConversations() async {
    if (_db == null) await initDatabase();
    final rows = await _db!.query('conversations', orderBy: 'id DESC');

    // Normalize keys so UI can use 'lastMessage'
    _conversations = rows.map((r) {
      return {
        'id': r['id'],
        'title': r['title'],
        'created_at': r['created_at'],
        'lastMessage': r['last_message'],
      };
    }).toList();

    notifyListeners();
  }

  Future<int> startNewConversation({String? title}) async {
    if (_db == null) await initDatabase();
    title ??= "नवीन संभाषण - ${DateTime.now().toString().substring(0, 16)}";
    final id = await _db!.insert('conversations', {
      'title': title,
      'created_at': DateTime.now().toIso8601String(),
      'last_message': null,
    });

    _currentConversationId = id;
    _messages = [];

    // Insert a placeholder assistant message (Marathi) and persist it
    final placeholderText =
        'तुम्हाला आज कसे वाटते? कृपया तुमची लक्षणे किंवा तक्रारी सांगा.';
    final placeholder = ChatMessage(
      message: placeholderText,
      isUser: false,
      timestamp: DateTime.now(),
    );

    // persist the placeholder message
    await _db!.insert('messages', placeholder.toMap(id));
    // update last_message for conversation
    await _db!.update(
      'conversations',
      {'last_message': placeholderText},
      where: 'id = ?',
      whereArgs: [id],
    );

    // refresh in-memory lists and notify UI
    _messages = [placeholder];
    await loadConversations();
    notifyListeners();

    // speak placeholder (if TTS enabled) — safe to call without awaiting
    try {
      // import of TtsService may or may not exist in this file; if present it will speak
      // if not present this call will be ignored (wrap in try to be safe)
      // If you want TTS, ensure `import '../services/tts_service.dart';` is present at top
      // and TtsService is initialized elsewhere.
      TtsService.instance.speak(placeholderText);
    } catch (_) {}

    return id;
  }

  Future<void> loadConversationMessages(int conversationId) async {
    if (_db == null) await initDatabase();
    final result = await _db!.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'id ASC',
    );
    _messages = result.map(ChatMessage.fromMap).toList();
    _currentConversationId = conversationId;
    notifyListeners();
  }

  Future<void> deleteConversation(int conversationId) async {
    if (_db == null) await initDatabase();
    await _db!.delete('messages',
        where: 'conversation_id = ?', whereArgs: [conversationId]);
    await _db!
        .delete('conversations', where: 'id = ?', whereArgs: [conversationId]);
    await loadConversations();
  }

  // ---------------- MESSAGE HANDLING ----------------

  void addMessage(ChatMessage message) async {
    _messages.add(message);

    if (_db != null && _currentConversationId != null) {
      await _db!.insert('messages', message.toMap(_currentConversationId!));

      // update last_message in conversations table
      await _db!.update(
        'conversations',
        {'last_message': message.message},
        where: 'id = ?',
        whereArgs: [_currentConversationId],
      );

      // If conversation still has default title, try to generate a better one.
      final rows = await _db!.query('conversations',
          columns: ['title'],
          where: 'id = ?',
          whereArgs: [_currentConversationId]);
      final currentTitle =
          rows.isNotEmpty ? rows.first['title'] as String? : null;
      if (currentTitle != null && currentTitle.startsWith('नवीन संभाषण')) {
        String newTitle = _generateTitleFromMessage(message);
        await _db!.update('conversations', {'title': newTitle},
            where: 'id = ?', whereArgs: [_currentConversationId]);
      }

      // refresh conversation list so UI shows updated lastMessage
      await loadConversations();
    }

    // Speak assistant reply (only when message is from assistant)
    if (!message.isUser) {
      // Use a safety limit to avoid extremely long reads
      final toSpeak = message.message.length > 800
          ? '${message.message.substring(0, 780)}...'
          : message.message;
      TtsService.instance.speak(toSpeak);
    }

    notifyListeners();
  }

  String _generateTitleFromMessage(ChatMessage m) {
    if (m.disease != null && m.disease!.trim().isNotEmpty) {
      return 'निदान: ${m.disease}';
    }
    // prefer first user message summary
    final text = m.message.trim();
    if (text.isEmpty) {
      return 'संभाषण ${DateTime.now().toString().substring(0, 16)}';
    }
    // take up to first 6 words, strip newlines
    final cleaned = text.replaceAll(RegExp(r'\s+'), ' ').replaceAll('\n', ' ');
    final words = cleaned.split(' ');
    final take = words.take(6).join(' ');
    return take.length <= 40 ? take : '${take.substring(0, 37)}...';
  }

  Future<void> updateConversationTitle(int conversationId, String title) async {
    if (_db == null) await initDatabase();
    await _db!.update('conversations', {'title': title},
        where: 'id = ?', whereArgs: [conversationId]);
    await loadConversations();
    notifyListeners();
  }

  // ---------------- LOADING STATE ----------------

  void clearChat() {
    _messages.clear();
    notifyListeners();
  }

  void setRecording(bool recording) {
    _isRecording = recording;
    notifyListeners();
  }

  // ---------------- BACKEND COMMUNICATION ----------------

  Future<void> sendTextMessage(String text, String language) async {
    if (text.trim().isEmpty) return;

    _isLoading = true;
    notifyListeners();

    addMessage(ChatMessage(
      message: text,
      isUser: true,
      timestamp: DateTime.now(),
    ));

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'text': text, 'language': language}),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true) {
          final List<dynamic> rawSymptoms =
              (data['symptoms_detected'] as List?) ?? [];
          final List<String> symptomsDetected =
              rawSymptoms.map((s) => s.toString()).toList();
          final precautionsList = (data['precautions_marathi'] as List?) ?? [];

          final responseText = '''
निदान: ${data['disease_marathi'] ?? 'नाही'}

सापडलेली लक्षणे: ${symptomsDetected.isNotEmpty ? symptomsDetected.join(', ') : 'कोणतीही लक्षणे नोंदली नाहीत'}

खबरदारी:
${precautionsList.map((p) => '• $p').join('\n')}
''';

          addMessage(ChatMessage(
            message: responseText.trim(),
            isUser: false,
            timestamp: DateTime.now(),
            disease: data['disease_marathi'],
            precautions: precautionsList.join('\n'),
            symptoms: symptomsDetected,
          ));
        } else {
          addMessage(ChatMessage(
            message: data['error_marathi'] ??
                'माफ करा, काही त्रुटी आली. कृपया पुन्हा प्रयत्न करा.',
            isUser: false,
            timestamp: DateTime.now(),
          ));
        }
      } else {
        throw Exception('API returned status code: ${response.statusCode}');
      }
    } on TimeoutException catch (e) {
      addMessage(ChatMessage(
        message:
            'सर्व्हरशी संपर्क करताना वेळ संपला. कृपया सर्व्हर चालू आहे आणि नेटवर्क कनेक्शन तपासा.\nत्रुटी: $e',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    } catch (e) {
      addMessage(ChatMessage(
        message:
            'सर्व्हरशी संपर्क करताना समस्या आली. कृपया पुन्हा प्रयत्न करा.\nत्रुटी: $e',
        isUser: false,
        timestamp: DateTime.now(),
      ));
    }

    _isLoading = false;
    notifyListeners();
  }
}
