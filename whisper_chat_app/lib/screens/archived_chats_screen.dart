import 'package:flutter/material.dart';
import '../models/chat_thread.dart';
import '../services/database_service.dart';
import 'chat_screen.dart';

class ArchivedChatsScreen extends StatefulWidget {
  const ArchivedChatsScreen({super.key});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  final DatabaseService _localDb = DatabaseService();
  List<ChatThread> _archived = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArchived();
  }

  Future<void> _loadArchived() async {
    final archived = await _localDb.getArchivedThreads();
    if (mounted) {
      setState(() {
        _archived = archived;
        _isLoading = false;
      });
    }
  }

  Future<void> _unarchiveChat(String uid) async {
    await _localDb.toggleArchiveThread(uid);
    await _loadArchived();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chat unarchived successfully'),
          backgroundColor: Color(0xFFD8B48C),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1120),
      appBar: AppBar(
        title: const Text('Archived Chats', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0E1120),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD8B48C)))
          : _archived.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.archive_outlined, size: 52, color: Color(0xFF8FA1AE)),
                      SizedBox(height: 16),
                      Text('No archived chats', style: TextStyle(color: Color(0xFF8FA1AE))),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: _archived.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (ctx, i) {
                    final thread = _archived[i];
                    return Dismissible(
                      key: Key(thread.contactUid),
                      background: Container(
                        color: const Color(0xFFD8B48C),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.unarchive, color: Color(0xFF0E1120)),
                      ),
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) => _unarchiveChat(thread.contactUid),
                      child: ListTile(
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
                          thread.lastMessage?.encryptedPayload ?? 'No messages',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF8FA1AE), fontSize: 12),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.unarchive, color: Color(0xFF8FA1AE)),
                          onPressed: () => _unarchiveChat(thread.contactUid),
                          tooltip: 'Unarchive',
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => ChatScreen(thread: thread)),
                          ).then((_) => _loadArchived());
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
