import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_thread.dart';
import '../services/crypto_service.dart';
import '../services/database_service.dart';
import '../services/firebase_service.dart';
import 'chat_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late TabController _tabController;

  final DatabaseService _localDb = DatabaseService();

  List<ChatThread> _chats = [];
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String _myPhone = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();

    // Listen for incoming friend requests in real-time
    final firebase = Provider.of<FirebaseService>(context, listen: false);
    firebase.listenForFriendRequests((requests) {
      if (mounted) {
        setState(() => _requests = requests);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final firebase = Provider.of<FirebaseService>(context, listen: false);
    final phone = firebase.currentUser?.phoneNumber ?? '';

    final chats = await _localDb.getConnectedThreads();

    if (mounted) {
      setState(() {
        _chats = chats;
        _myPhone = phone;
        _isLoading = false;
      });
    }
  }

  void _showAddContactDialog() {
    final ctrl = TextEditingController(text: '+91');
    bool _searching = false;
    String? _error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: const Text('Add Contact'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter their phone number (with country code). If they are registered on WhisperChat, a friend request will be sent.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_add),
                    labelText: 'Phone Number',
                    hintText: '+91 98765 43210',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                ],
                if (_searching) ...[
                  const SizedBox(height: 16),
                  const LinearProgressIndicator(),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: _searching
                    ? null
                    : () async {
                        final phone = ctrl.text.trim();
                        if (phone.length < 8) return;

                        setS(() {
                          _searching = true;
                          _error = null;
                        });

                        final firebase = Provider.of<FirebaseService>(context, listen: false);
                        final error = await firebase.sendFriendRequest(phone);

                        setS(() => _searching = false);

                        if (error != null) {
                          setS(() => _error = error);
                        } else {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Friend request sent to $phone!'),
                              backgroundColor: Colors.teal,
                            ),
                          );
                          _loadData();
                        }
                      },
                child: const Text('Send Request'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleLogout() async {
    await Provider.of<FirebaseService>(context, listen: false).signOut();
    await _localDb.clearDatabase();
    CryptoService().clearCache();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            const Text('WhisperChat'),
            Text(
              _myPhone,
              style: TextStyle(fontSize: 11, color: theme.colorScheme.secondary),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: theme.colorScheme.primary,
          tabs: [
            const Tab(text: 'Chats'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Requests'),
                  if (_requests.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_requests.length}',
                        style: const TextStyle(fontSize: 10, color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'logout') {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign Out'),
                    content: const Text(
                      'Signing out will delete all your local messages and E2EE keys. Your account will remain active on WhisperChat.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _handleLogout();
                        },
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'logout', child: Text('Sign Out')),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChatsTab(theme),
                _buildRequestsTab(theme),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        backgroundColor: theme.colorScheme.primary,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  Widget _buildChatsTab(ThemeData theme) {
    if (_chats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 52, color: Colors.white12),
            const SizedBox(height: 16),
            const Text('No chats yet', style: TextStyle(color: Colors.white38)),
            const SizedBox(height: 8),
            const Text(
              'Tap the + button to add a contact by phone number.',
              style: TextStyle(fontSize: 12, color: Colors.white24),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        itemCount: _chats.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
        itemBuilder: (ctx, i) {
          final thread = _chats[i];
          final lastMsg = thread.lastMessage;
          final isAudio = lastMsg?.mediaType == 'audio';

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.15),
                  child: Text(
                    thread.contactPhone.isNotEmpty
                        ? thread.contactPhone.substring(
                            thread.contactPhone.length - 2)
                        : '?',
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: thread.isOnline ? Colors.teal : Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                    ),
                  ),
                ),
              ],
            ),
            title: Text(
              thread.contactPhone,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            subtitle: Row(
              children: [
                if (isAudio) ...[
                  const Icon(Icons.mic, size: 13, color: Colors.teal),
                  const SizedBox(width: 4),
                  const Text('Voice Note', style: TextStyle(color: Colors.teal, fontSize: 12)),
                ] else ...[
                  Expanded(
                    child: Text(
                      lastMsg?.encryptedPayload ?? 'Tap to start chatting',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ),
                ],
              ],
            ),
            trailing: thread.unreadCount > 0
                ? Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${thread.unreadCount}',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                  )
                : null,
            onTap: () async {
              await _localDb.markMessagesAsRead(thread.contactUid);
              _loadData();
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ChatScreen(thread: thread)),
                ).then((_) => _loadData());
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildRequestsTab(ThemeData theme) {
    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 52, color: Colors.white12),
            SizedBox(height: 16),
            Text('No pending requests', style: TextStyle(color: Colors.white38)),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _requests.length,
      itemBuilder: (ctx, i) {
        final req = _requests[i];
        final phone = req['fromPhone'] as String;
        final docId = req['docId'] as String;
        final fromUid = req['fromUid'] as String;

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.secondary.withOpacity(0.15),
                  child: Icon(Icons.person, color: theme.colorScheme.secondary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(phone,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                      const Text('Wants to connect securely with you',
                          style: TextStyle(fontSize: 11, color: Colors.white54)),
                    ],
                  ),
                ),
                // Decline
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    final firebase = Provider.of<FirebaseService>(context, listen: false);
                    await firebase.declineFriendRequest(docId);
                  },
                ),
                // Accept
                ElevatedButton(
                  onPressed: () async {
                    final firebase = Provider.of<FirebaseService>(context, listen: false);
                    await firebase.acceptFriendRequest(fromUid, docId);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Now connected with $phone!'),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Accept', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
