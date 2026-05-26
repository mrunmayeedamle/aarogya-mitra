import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import 'profile_screen.dart';
import 'conversation_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int? _selectedConversationId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ChatProvider>(context, listen: false).loadConversations();
    });
  }

  Future<void> _confirmDelete(BuildContext context, ChatProvider chatProvider, int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('संभाषण हटवायचे?'),
        content: const Text('तुम्हाला नक्की हे संभाषण काढून टाकायचे आहे का?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('रद्द करा'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('हटवा', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await chatProvider.deleteConversation(id);
      setState(() {
        _selectedConversationId = null;
      });
    }
  }

  Future<void> _confirmLogout(BuildContext context, AuthProvider authProvider) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('लॉगआउट करायचे?'),
        content: const Text('तुम्हाला नक्की लॉगआउट करायचे आहे का?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('रद्द करा'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('लॉगआउट', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await authProvider.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFFE8F5E9),
      appBar: AppBar(
        title: const Text(
          'आरोग्यमित्र',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.green.shade700,
        elevation: 0,
        actions: [
          if (_selectedConversationId != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white),
              onPressed: () => _confirmDelete(context, chatProvider, _selectedConversationId!),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmLogout(context, authProvider),
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.green.shade700),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person, color: Colors.green),
                  ),
                  SizedBox(width: 16),
                  Text(
                    'आरोग्यमित्र',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person),
              title: const Text('प्रोफाइल'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('लॉगआउट'),
              onTap: () {
                Navigator.pop(context);
                _confirmLogout(context, authProvider);
              },
            ),
          ],
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_selectedConversationId != null) setState(() => _selectedConversationId = null);
        },
        child: Column(
          children: [
            // Horizontal "tabs" for conversations
            if (chatProvider.conversations.isNotEmpty)
              Container(
                height: 72,
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: chatProvider.conversations.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final conv = chatProvider.conversations[index];
                    final isSelected = _selectedConversationId == conv['id'];
                    final title = conv['title'] ?? 'संभाषण ${index + 1}';
                    final last = conv['lastMessage'] ?? '';
                    
                    return GestureDetector(
                      onTap: () {
                        if (_selectedConversationId != null) {
                          setState(() => _selectedConversationId = null);
                        } else {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationScreen(conversationId: conv['id'])));
                        }
                      },
                      onLongPress: () => setState(() => _selectedConversationId = conv['id']),
                      child: Chip(
                        backgroundColor: isSelected ? Colors.green.shade100 : Colors.white,
                        onDeleted: isSelected ? () => _confirmDelete(context, chatProvider, conv['id']) : null,
                        deleteIconColor: Colors.red,
                        side: isSelected ? BorderSide(color: Colors.green.shade700, width: 2) : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        label: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            if (last.isNotEmpty)
                              SizedBox(
                                width: 100,
                                child: Text(last, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

            // Main body: vertical list
            Expanded(
              child: chatProvider.conversations.isEmpty
                  ? const Center(child: Text('अजून कोणत्याही संभाषणाची नोंद नाही.\nनवीन संभाषण सुरू करण्यासाठी मायक्रोफोनवर टॅप करा.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: chatProvider.conversations.length,
                      itemBuilder: (context, index) {
                        final conv = chatProvider.conversations[index];
                        final isSelected = _selectedConversationId == conv['id'];
                        return Card(
                          elevation: isSelected ? 4 : 2,
                          color: isSelected ? Colors.green.shade50 : Colors.white,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: isSelected ? BorderSide(color: Colors.green.shade700, width: 2) : BorderSide.none,
                          ),
                          child: ListTile(
                            title: Text(conv['title'] ?? 'संभाषण ${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(conv['lastMessage'] ?? 'संभाषण पहा...', maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () {
                              if (_selectedConversationId != null) {
                                setState(() => _selectedConversationId = null);
                              } else {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationScreen(conversationId: conv['id'])));
                              }
                            },
                            onLongPress: () => setState(() => _selectedConversationId = conv['id']),
                            trailing: isSelected
                                ? IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _confirmDelete(context, chatProvider, conv['id']))
                                : const Icon(Icons.chevron_right, color: Colors.grey),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        elevation: 6,
        backgroundColor: Colors.green.shade700,
        onPressed: () async {
          final chatProv = Provider.of<ChatProvider>(context, listen: false);
          final newId = await chatProv.startNewConversation();
          if (newId != null) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => ConversationScreen(conversationId: newId)));
          }
        },
        child: const Icon(Icons.mic, size: 36, color: Colors.white),
      ),
    );
  }
}
