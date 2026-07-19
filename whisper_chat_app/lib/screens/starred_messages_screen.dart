import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../services/database_service.dart';

class StarredMessagesScreen extends StatefulWidget {
  const StarredMessagesScreen({super.key});

  @override
  State<StarredMessagesScreen> createState() => _StarredMessagesScreenState();
}

class _StarredMessagesScreenState extends State<StarredMessagesScreen> {
  final DatabaseService _localDb = DatabaseService();
  List<Message> _starred = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStarred();
  }

  Future<void> _loadStarred() async {
    final starred = await _localDb.getStarredMessages();
    if (mounted) {
      setState(() {
        _starred = starred;
        _isLoading = false;
      });
    }
  }

  Future<void> _unstarMsg(Message msg) async {
    // Determine contactUid
    final String contactUid = msg.senderUid == 'me' ? msg.receiverUid : msg.senderUid;
    // Note: Since 'senderUid' matches 'myUid' in the real app, we need to resolve it appropriately
    // The DatabaseService toggleStarMessage takes the actual contactUid and messageId.
    // In our app, one of them is the remote peer and the other is the user themselves.
    // Let's resolve the contactUid of the chat from message:
    // If msg.senderPhone is matching the user's phone, contactUid is receiverUid, else senderUid.
    // We can try to use either receiverUid or senderUid based on the message.
    // Actually, toggleStarMessage works by looking inside messages_$contactUid box.
    // Let's find which one contains it, or toggle in both. Or we can just toggle using senderUid and receiverUid.
    // To be safe, we can try toggleStarMessage on senderUid, and if it fails or doesn't match, receiverUid.
    // Or we can just pass the correct contactUid from a helper.
    // Let's toggle both to be absolutely robust!
    await _localDb.toggleStarMessage(msg.senderUid, msg.id);
    await _localDb.toggleStarMessage(msg.receiverUid, msg.id);
    await _loadStarred();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1120),
      appBar: AppBar(
        title: const Text('Starred Messages', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0E1120),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD8B48C)))
          : _starred.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.star_outline, size: 52, color: Color(0xFF8FA1AE)),
                      SizedBox(height: 16),
                      Text('No starred messages', style: TextStyle(color: Color(0xFF8FA1AE))),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _starred.length,
                  itemBuilder: (ctx, i) {
                    final msg = _starred[i];
                    final date = DateFormat('yyyy-MM-dd HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(msg.timestamp),
                    );

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: const Color(0xFF171B30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.white.withOpacity(0.05)),
                      ),
                      elevation: 0,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  msg.senderPhone.isNotEmpty ? msg.senderPhone : 'Unknown',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFD8B48C),
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  date,
                                  style: const TextStyle(color: Color(0xFF8FA1AE), fontSize: 11),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              msg.encryptedPayload,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(50, 30),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                icon: const Icon(Icons.star, color: Color(0xFFD8B48C), size: 16),
                                label: const Text('Unstar', style: TextStyle(color: Color(0xFF8FA1AE), fontSize: 12)),
                                onPressed: () => _unstarMsg(msg),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
