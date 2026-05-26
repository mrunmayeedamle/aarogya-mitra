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
    if (data == null) return;

    // FOLLOW-UP SYMPTOMS — show checkbox dialog, don't add any message
    if (data['follow_up_needed'] == true) {
      final suggestedSymptoms = List<String>.from(data['suggested_symptoms'] ?? []);
      final detectedSymptoms = List<String>.from(data['detected_symptoms'] ?? []);
      if (suggestedSymptoms.isNotEmpty) {
        showFollowUpDialog(suggestedSymptoms, detectedSymptoms);
      }
      return;
    }

    // AMBIGUOUS — show disease picker dialog, don't add any message yet
    if (data['ambiguous'] == true) {
      final predictions = List<dynamic>.from(data['top_predictions'] ?? []);
      if (predictions.isNotEmpty) {
        showAmbiguousPredictionDialog(predictions);
      }
      return;
    }

    // NORMAL PATH — ChatProvider.sendTextMessage already built & saved the
    // bot message, so nothing extra to do here. The Consumer rebuilds the list.
  }

  // Called only from the ambiguous dialog after the user picks a disease.
  // ChatProvider handled the user message already; we just add the bot reply.
  Future<void> _handleSelectedDisease(Map<String, dynamic> prediction) async {
    final disease = prediction['disease'] as String? ?? '';
    final probability =
    (((prediction['probability'] ?? 0.0) as num) * 100).toStringAsFixed(0);
    final precautions = List<String>.from(prediction['precautions'] ?? []);

    final precautionsText = precautions.isNotEmpty
        ? precautions.map((p) => '• $p').join('\n')
        : '• डॉक्टरांचा सल्ला घ्या';

    final botMessage = '''
तुमच्या निवडीवर आधारित संभाव्य आजार:

🩺 $disease

विश्वास पातळी: $probability%

काळजी:
$precautionsText
''';

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    // addMessageToBackend saves to DB + appends to _messages + notifies listeners
    await chatProvider.addMessageToBackend(
      ChatMessage(
        message: botMessage.trim(),
        isUser: false,
        timestamp: DateTime.now(),
        disease: disease,
        precautions: precautions.join('\n'),
      ),
    );
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
            builder: (context, setDialogState) {
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
                                setDialogState(() {
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
                final finalSymptoms = [...initialSymptoms, ...selectedSymptoms];
                resendWithFollowUp(finalSymptoms);
              },
              child: const Text('सुरू ठेवा', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void showAmbiguousPredictionDialog(List<dynamic> predictions) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'संभाव्य आजार',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('तुमच्या लक्षणांवर आधारित संभाव्य आजार:'),
                const SizedBox(height: 20),
                ...predictions.map((prediction) {
                  final disease = prediction['disease'];
                  final probability =
                  (((prediction['probability'] ?? 0.0) as num) * 100)
                      .toStringAsFixed(0);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context); // dismiss dialog first
                          _handleSelectedDisease(prediction); // then add bot message
                        },
                        child: Text(
                          '$disease ($probability%)',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                }).toList(),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('कृपया अधिक स्पष्ट लक्षणे द्या.'),
                      ),
                    );
                  },
                  child: const Text('वरीलपैकी काहीही नाही'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> resendWithFollowUp(List<String> finalSymptoms, {bool noMore = false}) async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final combinedText = finalSymptoms.join(', ');
    final data = await chatProvider.sendTextMessage(
      combinedText,
      'marathi',
      noMoreSymptoms: noMore,
    );
    _handlePredictionResult(data);
  }

  @override
  void dispose() {
    _textController.dispose();
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
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      final data = await Provider.of<ChatProvider>(
                        context,
                        listen: false,
                      ).sendTextMessage(text, 'marathi');
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