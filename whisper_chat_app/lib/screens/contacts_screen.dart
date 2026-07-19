import 'package:flutter/material.dart';
import '../models/chat_thread.dart';
import '../services/database_service.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final DatabaseService _localDb = DatabaseService();
  List<ChatThread> _contacts = [];
  List<ChatThread> _filtered = [];
  bool _isLoading = true;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    final contacts = await _localDb.getConnectedThreads();
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _filtered = contacts;
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = _contacts.where((t) {
        return t.contactPhone.toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1120),
      appBar: AppBar(
        title: const Text('Contacts', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0E1120),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD8B48C)))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF8FA1AE)),
                      hintText: 'Search contacts...',
                      filled: true,
                      fillColor: const Color(0xFF171B30),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _filtered.isEmpty
                      ? const Center(
                          child: Text(
                            'No contacts found',
                            style: TextStyle(color: Color(0xFF8FA1AE)),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                          itemBuilder: (ctx, i) {
                            final thread = _filtered[i];
                            return ListTile(
                              leading: CircleAvatar(
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
                              subtitle: Text(
                                thread.isOnline ? 'Online' : 'Offline',
                                style: TextStyle(
                                  color: thread.isOnline ? const Color(0xFFD8B48C) : const Color(0xFF8FA1AE),
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => ChatScreen(thread: thread)),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
