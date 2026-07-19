import 'package:flutter/material.dart';
import '../models/chat_thread.dart';
import '../models/message.dart';
import '../services/database_service.dart';

class NewGroupScreen extends StatefulWidget {
  const NewGroupScreen({super.key});

  @override
  State<NewGroupScreen> createState() => _NewGroupScreenState();
}

class _NewGroupScreenState extends State<NewGroupScreen> {
  final DatabaseService _localDb = DatabaseService();
  List<ChatThread> _contacts = [];
  final List<String> _selectedUids = [];
  final TextEditingController _groupNameCtrl = TextEditingController();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _groupNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await _localDb.getConnectedThreads();
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    }
  }

  void _toggleSelect(String uid) {
    setState(() {
      if (_selectedUids.contains(uid)) {
        _selectedUids.remove(uid);
      } else {
        _selectedUids.add(uid);
      }
    });
  }

  Future<void> _createGroup() async {
    final name = _groupNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a group name'), backgroundColor: Colors.redAccent),
      );
      return;
    }
    if (_selectedUids.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one contact'), backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Create a mock group thread locally
    final groupUid = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final groupThread = ChatThread(
      contactUid: groupUid,
      contactPhone: name,
      connectionStatus: 'connected',
      isOnline: true,
      lastMessage: Message(
        id: 'welcome_${DateTime.now().millisecondsSinceEpoch}',
        senderUid: 'system',
        receiverUid: groupUid,
        senderPhone: 'System',
        receiverPhone: name,
        encryptedPayload: 'Group "$name" created successfully.',
        mediaType: 'text',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        status: 'read',
      ),
    );

    await _localDb.saveOrUpdateThread(groupThread);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group "$name" created successfully!'),
          backgroundColor: const Color(0xFFD8B48C),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1120),
      appBar: AppBar(
        title: const Text('New Group', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0E1120),
        actions: [
          TextButton(
            onPressed: _createGroup,
            child: const Text(
              'Create',
              style: TextStyle(
                color: Color(0xFFD8B48C),
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD8B48C)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _groupNameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.group_work_outlined, color: Color(0xFF8FA1AE)),
                      hintText: 'Enter group name...',
                      filled: true,
                      fillColor: const Color(0xFF171B30),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Select Contacts',
                      style: TextStyle(color: Color(0xFF8FA1AE), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                Expanded(
                  child: _contacts.isEmpty
                      ? const Center(
                          child: Text(
                            'No contacts available to add',
                            style: TextStyle(color: Color(0xFF8FA1AE)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _contacts.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                          itemBuilder: (ctx, i) {
                            final thread = _contacts[i];
                            final isSelected = _selectedUids.contains(thread.contactUid);
                            return CheckboxListTile(
                              activeColor: const Color(0xFFD8B48C),
                              checkColor: const Color(0xFF0E1120),
                              secondary: CircleAvatar(
                                backgroundColor: const Color(0xFFD8B48C),
                                child: Text(
                                  thread.contactPhone.isNotEmpty
                                      ? thread.contactPhone.substring(thread.contactPhone.length - 2)
                                      : '?',
                                  style: const TextStyle(color: Color(0xFF0E1120), fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(
                                thread.contactPhone,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              value: isSelected,
                              onChanged: (_) => _toggleSelect(thread.contactUid),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
