import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_thread.dart';
import '../services/crypto_service.dart';
import '../services/database_service.dart';
import '../services/firebase_service.dart';
import 'chat_screen.dart';
import 'login_screen.dart';
import '../services/secure_storage_service.dart';
import 'contacts_screen.dart';
import 'new_group_screen.dart';
import 'archived_chats_screen.dart';
import 'starred_messages_screen.dart';
import 'settings_screen.dart';

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
  String _displayName = 'User';

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
    final secure = SecureStorageService();
    final name = await secure.getDisplayName() ?? 'User';

    final chats = await _localDb.getConnectedThreads();

    if (mounted) {
      setState(() {
        _chats = chats;
        _myPhone = phone;
        _displayName = name;
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

  void _showProfileEditorDialog() async {
    final secure = SecureStorageService();
    final currentName = await secure.getDisplayName() ?? 'User';
    final ctrl = TextEditingController(text: currentName);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B30),
        title: const Text('Edit Profile Name', style: TextStyle(fontFamily: 'serif', color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Specify a name so others can identify you.',
              style: TextStyle(color: Color(0xFF8FA1AE), fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Display Name',
                hintText: 'Enter your name...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8FA1AE))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD8B48C),
              foregroundColor: const Color(0xFF0E1120),
              elevation: 0,
            ),
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isNotEmpty) {
                final firebase = Provider.of<FirebaseService>(context, listen: false);
                await firebase.updateProfileName(newName);
                _loadData();
              }
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
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
      backgroundColor: const Color(0xFF0E1120),
      drawer: _buildDrawer(theme),
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFFD8B48C)),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Column(
          children: [
            const Text(
              'WhisperChat',
              style: TextStyle(
                fontFamily: 'serif',
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              _myPhone,
              style: const TextStyle(fontSize: 11, color: Color(0xFF8FA1AE)),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFD8B48C),
          labelColor: const Color(0xFFD8B48C),
          unselectedLabelColor: const Color(0xFF8FA1AE),
          indicatorSize: TabBarIndicatorSize.tab,
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: const BoxDecoration(
                        color: Color(0xFFD8B48C),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${_requests.length}',
                        style: const TextStyle(fontSize: 10, color: Color(0xFF0E1120), fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD8B48C)))
          : TabBarView(
              controller: _tabController,
              children: [
                _buildChatsTab(theme),
                _buildRequestsTab(theme),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddContactDialog,
        backgroundColor: const Color(0xFFD8B48C),
        foregroundColor: const Color(0xFF0E1120),
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    return Drawer(
      backgroundColor: const Color(0xFF0E1120),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drawer Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/images/logo.png',
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName,
                          style: const TextStyle(
                            fontFamily: 'serif',
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 2),
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(context);
                            _showProfileEditorDialog();
                          },
                          child: Row(
                            children: [
                              Text(
                                _myPhone,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF8FA1AE),
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(
                                Icons.edit_outlined,
                                size: 14,
                                color: Color(0xFFD8B48C),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.white10, height: 1),
            const SizedBox(height: 12),
            // Menu Items
            _buildDrawerItem(
              Icons.group_outlined,
              'New Group',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const NewGroupScreen()));
              },
            ),
            _buildDrawerItem(
              Icons.contacts_outlined,
              'Contacts',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen()));
              },
            ),
            _buildDrawerItem(
              Icons.archive_outlined,
              'Archived Chats',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchivedChatsScreen())).then((_) => _loadData());
              },
            ),
            _buildDrawerItem(
              Icons.star_outline,
              'Starred Messages',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const StarredMessagesScreen()));
              },
            ),
            _buildDrawerItem(
              Icons.settings_outlined,
              'Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => _loadData());
              },
            ),
            _buildDrawerItem(Icons.lock_outline, 'Privacy & Security'),
            _buildDrawerItem(Icons.help_outline, 'Help & Support'),
            _buildDrawerItem(Icons.info_outline, 'About WhisperChat'),
            const Spacer(),
            const Divider(color: Colors.white10, height: 1),
            _buildDrawerItem(
              Icons.logout,
              'Log Out',
              textColor: const Color(0xFFD8B48C),
              iconColor: const Color(0xFFD8B48C),
              onTap: () {
                Navigator.pop(context); // Close Drawer
                _confirmSignOut();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, {Color? textColor, Color? iconColor, VoidCallback? onTap}) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? const Color(0xFF8FA1AE), size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap ?? () {},
      horizontalTitleGap: 8,
    );
  }

  void _confirmSignOut() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B30),
        title: const Text('Sign Out', style: TextStyle(fontFamily: 'serif')),
        content: const Text(
          'Signing out will delete all your local messages and E2EE keys. Your account will remain active on WhisperChat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8FA1AE))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD8B48C),
              foregroundColor: const Color(0xFF0E1120),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              _handleLogout();
            },
            child: const Text('Sign Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildChatsTab(ThemeData theme) {
    if (_chats.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 52, color: Color(0xFF8FA1AE)),
            SizedBox(height: 16),
            Text('No chats yet', style: TextStyle(color: Color(0xFF8FA1AE))),
            SizedBox(height: 8),
            Text(
              'Tap the + button to add a contact by phone number.',
              style: TextStyle(fontSize: 12, color: Color(0xFF49566B)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      color: const Color(0xFFD8B48C),
      backgroundColor: const Color(0xFF171B30),
      child: ListView.separated(
        itemCount: _chats.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
        itemBuilder: (ctx, i) {
          final thread = _chats[i];
          final lastMsg = thread.lastMessage;
          final isAudio = lastMsg?.mediaType == 'audio';

          return Dismissible(
            key: Key(thread.contactUid),
            background: Container(
              color: const Color(0xFFD8B48C),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 20),
              child: const Icon(Icons.archive, color: Color(0xFF0E1120)),
            ),
            direction: DismissDirection.startToEnd,
            onDismissed: (direction) async {
              await _localDb.toggleArchiveThread(thread.contactUid);
              _loadData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Chat archived'),
                    backgroundColor: Color(0xFFD8B48C),
                  ),
                );
              }
            },
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: Stack(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: const Color(0xFFD8B48C),
                    child: Text(
                      thread.contactPhone.isNotEmpty
                          ? thread.contactPhone.substring(
                              thread.contactPhone.length - 2)
                          : '?',
                      style: const TextStyle(
                        color: Color(0xFF0E1120),
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
                        color: thread.isOnline ? const Color(0xFFD8B48C) : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.scaffoldBackgroundColor, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      thread.contactPhone,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.white),
                    ),
                  ),
                  if (thread.isPinned) ...[
                    const Icon(Icons.push_pin, color: Color(0xFFD8B48C), size: 14),
                  ],
                ],
              ),
              subtitle: Row(
                children: [
                  if (isAudio) ...[
                    const Icon(Icons.mic, size: 13, color: Color(0xFFD8B48C)),
                    const SizedBox(width: 4),
                    const Text('Voice Note', style: TextStyle(color: Color(0xFFD8B48C), fontSize: 12)),
                  ] else ...[
                    Expanded(
                      child: Text(
                        lastMsg?.encryptedPayload ?? 'Tap to start chatting',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8FA1AE)),
                      ),
                    ),
                  ],
                ],
              ),
              trailing: thread.unreadCount > 0
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD8B48C),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${thread.unreadCount}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF0E1120),
                          fontWeight: FontWeight.bold,
                        ),
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
              onLongPress: () => _showChatOptions(thread),
            ),
          );
        },
      ),
    );
  }

  void _showChatOptions(ChatThread thread) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF171B30),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                thread.isPinned ? Icons.pin_end : Icons.push_pin,
                color: const Color(0xFFD8B48C),
              ),
              title: Text(
                thread.isPinned ? 'Unpin Chat' : 'Pin Chat to Top',
                style: const TextStyle(color: Colors.white),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _localDb.togglePinThread(thread.contactUid);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined, color: Color(0xFF8FA1AE)),
              title: const Text('Archive Chat', style: TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(ctx);
                await _localDb.toggleArchiveThread(thread.contactUid);
                _loadData();
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete Chat', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(ctx);
                _confirmDeleteChat(thread.contactUid);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteChat(String contactUid) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B30),
        title: const Text('Delete Chat', style: TextStyle(fontFamily: 'serif', color: Colors.white)),
        content: const Text('Are you sure you want to delete this chat? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8FA1AE))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(ctx);
              await _localDb.deleteThread(contactUid);
              _loadData();
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsTab(ThemeData theme) {
    if (_requests.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 52, color: Color(0xFF8FA1AE)),
            SizedBox(height: 16),
            Text('No pending requests', style: TextStyle(color: Color(0xFF8FA1AE))),
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
          color: const Color(0xFF171B30),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFD8B48C),
                  child: Text(
                    phone.isNotEmpty ? phone.substring(phone.length - 2) : '?',
                    style: const TextStyle(color: Color(0xFF0E1120), fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(phone, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white)),
                      const Text('Wants to connect securely with you', style: TextStyle(fontSize: 11, color: Color(0xFF8FA1AE))),
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
                const SizedBox(width: 8),
                // Accept
                ElevatedButton(
                  onPressed: () async {
                    final firebase = Provider.of<FirebaseService>(context, listen: false);
                    await firebase.acceptFriendRequest(fromUid, docId);
                    _loadData();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Now connected with $phone!'),
                        backgroundColor: const Color(0xFFD8B48C),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD8B48C),
                    foregroundColor: const Color(0xFF0E1120),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: const Text('Accept', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
