import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../providers/chat_provider.dart';

class VoiceRecorderSTT extends StatefulWidget {
  final Function(Map<String, dynamic>?)? onResult;
  const VoiceRecorderSTT({super.key, this.onResult});

  @override
  _VoiceRecorderSTTState createState() => _VoiceRecorderSTTState();
}

class _VoiceRecorderSTTState extends State<VoiceRecorderSTT> {
  final AudioRecorder _record = AudioRecorder();
  bool _isRecording = false;
  bool _hasPermission = false;
  String? _audioPath;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    try {
      await _record.hasPermission();
    } catch (e) {
      print('Error initializing recorder: $e');
    }
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      final result = await Permission.microphone.request();
      setState(() {
        _hasPermission = result.isGranted;
      });
    } else {
      setState(() {
        _hasPermission = true;
      });
    }
  }

  Future<void> _startRecording() async {
    if (!_hasPermission) {
      await _checkPermissions();
      if (!_hasPermission) {
        _showMessage('मायक्रोफोन परवानगी आवश्यक आहे');
        return;
      }
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _audioPath = '${tempDir.path}/recording_$timestamp.wav';

      await _record.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: _audioPath!,
      );

      setState(() {
        _isRecording = true;
      });

      Provider.of<ChatProvider>(context, listen: false).setRecording(true);
      _showMessage('रेकॉर्डिंग सुरू झाले आहे... मराठीत बोला');
    } catch (e) {
      print('Error starting recording: $e');
      _showMessage('रेकॉर्डिंग सुरू करण्यात त्रुटी');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _record.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true;
      });

      Provider.of<ChatProvider>(context, listen: false).setRecording(false);
      _showMessage('रेकॉर्डिंग थांबले आहे... प्रक्रिया करत आहे');

      if (path != null && await File(path).exists()) {
        await _convertSpeechToText(path);
      } else {
        _showMessage('ऑडिओ फाइल सापडली नाही');
        setState(() => _isProcessing = false);
      }
    } catch (e) {
      print('Error stopping recording: $e');
      _showMessage('रेकॉर्डिंग थांबवण्यात त्रुटी');
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _convertSpeechToText(String audioPath) async {
    try {
      _showMessage('ध्वनी मजकुरात रूपांतरित करत आहे...');

      final recognizedText = await _sendToBackendSTT(audioPath);

      if (recognizedText.isEmpty) {
        _showMessage('STT सेवा उपलब्ध नाही. सिम्युलेटेड वापरत आहे.');
        _useSimulatedText();
      } else {
        _processVoiceInput(recognizedText);
      }
    } catch (e) {
      print('STT Error: $e');
      _showMessage('ध्वनी प्रक्रिया अयशस्वी. सिम्युलेटेड वापरत आहे.');
      _useSimulatedText();
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  Future<String> _sendToBackendSTT(String audioPath) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    try {
      final audioFile = File(audioPath);
      final audioBytes = await audioFile.readAsBytes();

      final response = await http
          .post(
            Uri.parse('${chatProvider.baseUrl}/speech-to-text'),
            headers: {'Content-Type': 'application/octet-stream'},
            body: audioBytes,
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['text'] ?? '';
      }
      return '';
    } catch (e) {
      print('Backend STT error: $e');
      return '';
    }
  }

  void _useSimulatedText() {
    final List<String> sampleSymptoms = [
      'मला ताप आणि डोकेदुखी आहे',
      'माझ्याकडे खोकला आणि सर्दी झाली आहे',
      'मला उलट्या आणि अतिसार होत आहेत',
      'माझे अंग दुखत आहे आणि थकवा येतो',
      'मला घसादुखी आणि ताप आहे',
      'मला खोकला सर्दी आणि शरीर दुखत आहे',
      'मला ताप आहे आणि अंग दुखत आहे',
      'मला डोकेदुखी आणि थकवा येतो'
    ];

    final randomIndex = DateTime.now().millisecond % sampleSymptoms.length;
    final randomSymptom = sampleSymptoms[randomIndex];

    _processVoiceInput(randomSymptom);
  }

  Future<void> _processVoiceInput(String text) async {
    _showMessage('ऐकले: $text');

    final data = await Provider.of<ChatProvider>(context, listen: false)
        .sendTextMessage(text, 'marathi');
    
    if (widget.onResult != null) {
      widget.onResult!(data);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  void dispose() {
    _record.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_isRecording)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.mic, color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Text(
                  'रेकॉर्डिंग चालू आहे...',
                  style: TextStyle(
                    color: Colors.red[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ),

        if (_isProcessing)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'ध्वनी प्रक्रिया करत आहे...',
                  style: TextStyle(
                    color: Colors.blue[800],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

        Container(
          decoration: BoxDecoration(
            color: _isRecording
                ? Colors.red
                : (_isProcessing ? Colors.blue : Colors.green),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            icon: _isProcessing
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: Colors.white,
                    size: 28,
                  ),
            onPressed: _isProcessing
                ? null
                : (_isRecording ? _stopRecording : _startRecording),
          ),
        ),

        Text(
          _isProcessing
              ? 'प्रक्रिया करत आहे'
              : _isRecording
                  ? 'रेकॉर्डिंग चालू आहे'
                  : 'बोलण्यासाठी टॅप करा',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
