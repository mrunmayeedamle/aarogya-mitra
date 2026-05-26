import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/voice_recorder_stt.dart';
import '../services/tts_service.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, this.conversationId});

  final int? conversationId;

  @override
  _ConversationScreenState createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      if (widget.conversationId != null) {
        chatProvider.loadConversationMessages(widget.conversationId!);
      }
    });
  }

  void _handlePredictionResult(Map<String, dynamic>? data) {
    if (data != null && data['follow_up_needed'] == true) {
      List<String> suggestedSymptoms = List<String>.from(data['suggested_symptoms'] ?? []);
      List<String> detectedSymptoms = List<String>.from(data['detected_symptoms'] ?? []);
      
      if (suggestedSymptoms.isNotEmpty) {
        showFollowUpDialog(suggestedSymptoms, detectedSymptoms);
      }
    }
  }

  void showFollowUpDialog(List<String> suggestedSymptoms, List<String> initialSymptoms) {
    List<String> selectedSymptoms = [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('कृपया आणखी लक्षणे निवडा'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('तुमच्या निदानासाठी अधिक माहिती हवी आहे:'),
                    const SizedBox(height: 10),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: suggestedSymptoms.map((symptom) {
                            return CheckboxListTile(
                              title: Text(symptom),
                              value: selectedSymptoms.contains(symptom),
                              onChanged: (bool? value) {
                                setState(() {
                                  if (value == true) {
                                    selectedSymptoms.add(symptom);
                                  } else {
                                    selectedSymptoms.remove(symptom);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Send original symptoms but tell backend we have no more
                resendWithFollowUp(initialSymptoms, noMore: true);
              },
              child: const Text('इतर काही नाही', style: TextStyle(color: Colors.red)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('रद्द करा'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () {
                Navigator.of(context).pop();
                List<String> finalSymptoms = [...initialSymptoms, ...selectedSymptoms];
                resendWithFollowUp(finalSymptoms);
              },
              child: const Text('सुरू ठेवा', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> resendWithFollowUp(List<String> finalSymptoms, {bool noMore = false}) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    // Join symptoms with commas - backend extract_symptoms will pick these up
    final combinedText = finalSymptoms.join(', ');
    final data = await chatProvider.sendTextMessage(
      combinedText, 
      'marathi', 
      noMoreSymptoms: noMore
    );
    _handlePredictionResult(data);
  }

  @override
  void dispose() {
    _textController.dispose();
    // Stop TTS when leaving the screen
    TtsService.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final currentTitle = chatProvider.currentConversationTitle ?? 'नवीन संभाषण';
    
    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      appBar: AppBar(
        title: Text(
          currentTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.green.shade700,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              Provider.of<ChatProvider>(context, listen: false).clearChat();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<ChatProvider>(
              builder: (context, chatProvider, child) {
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: chatProvider.messages.length,
                  itemBuilder: (context, index) {
                    final message = chatProvider.messages[index];
                    return ChatBubble(message: message);
                  },
                );
              },
            ),
          ),
          if (chatProvider.isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(color: Colors.green),
                  SizedBox(width: 16),
                  Text('आरोग्यमित्र विचार करत आहे...'),
                ],
              ),
            ),
          _buildInputArea(context),
        ],
      ),
    );
  }

  Widget _buildInputArea(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        children: [
          VoiceRecorderSTT(
            onResult: (data) => _handlePredictionResult(data),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: 'किंवा तुमची लक्षणे इथे टाइप करा...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: Colors.green.shade700,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () async {
                    final text = _textController.text.trim();
                    if (text.isNotEmpty) {
                      final data = await Provider.of<ChatProvider>(context, listen: false)
                          .sendTextMessage(text, 'marathi');
                      _textController.clear();
                      _handlePredictionResult(data);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
