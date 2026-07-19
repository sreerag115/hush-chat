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
import '../services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final DatabaseService _localDb = DatabaseService();

  int _currentIndex = 0; // 0: Chats, 1: Calls, 2: Groups, 3: Profile

  List<ChatThread> _chats = [];
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String _myPhone = '';
  String _displayName = 'User';

  @override
  void initState() {
    super.initState();
    _loadData();

    // Init notifications & lifecycle presence observer
    NotificationService().init();

    final firebase = Provider.of<FirebaseService>(context, listen: false);
    firebase.initLifecycleObserver();

    // Listen for incoming friend requests in real-time
    firebase.listenForFriendRequests((requests) {
      if (mounted) {
        setState(() => _requests = requests);
      }
    });
  }

  Future<void> _loadData() async {
    final firebase = Provider.of<FirebaseService>(context, listen: false);
    final phone = firebase.currentUser?.phoneNumber ?? '';
    final secure = SecureStorageService();
    final name = await secure.getDisplayName() ?? 'User';

    final chats = await _localDb.getConnectedThreads();

    for (final thread in chats) {
      firebase.listenToPresence(
        thread.contactUid,
        onUpdate: (isOnline, lastSeen) {
          if (mounted) {
            _localDb.getConnectedThreads().then((updatedChats) {
              if (mounted) setState(() => _chats = updatedChats);
            });
          }
        },
      );
    }

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
    bool searching = false;
    String? error;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            backgroundColor: const Color(0xFF171B30),
            title: const Text('Add Contact', style: TextStyle(fontFamily: 'serif', color: Colors.white)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter their phone number (with country code). If registered on WhisperChat, a friend request will be sent.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8FA1AE)),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ctrl,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    labelStyle: const TextStyle(color: Color(0xFF8FA1AE)),
                    hintText: '+919876543210',
                    hintStyle: const TextStyle(color: Colors.white30),
                    errorText: error,
                    filled: true,
                    fillColor: const Color(0xFF0E1120),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                if (searching)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFFD8B48C))),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF8FA1AE))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD8B48C), foregroundColor: const Color(0xFF0E1120)),
                onPressed: searching
                    ? null
                    : () async {
                        final phone = ctrl.text.trim();
                        if (phone.isEmpty) return;
                        setS(() {
                          searching = true;
                          error = null;
                        });

                        final firebase = Provider.of<FirebaseService>(context, listen: false);
                        final result = await firebase.sendFriendRequest(phone);

                        if (!ctx.mounted) return;

                        if (result != null) {
                          setS(() {
                            searching = false;
                            error = result;
                          });
                        } else {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Friend request sent to $phone!'),
                              backgroundColor: const Color(0xFFD8B48C),
                            ),
                          );
                          _loadData();
                        }
                      },
                child: const Text('Send Request', style: TextStyle(fontWeight: FontWeight.bold)),
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

  void _showQrCodeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Center(
          child: Text('My QR Code', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold, color: Colors.white)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(Icons.qr_code_2, size: 160, color: Color(0xFF0E1120)),
                  const SizedBox(height: 8),
                  Text(
                    _displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0E1120), fontSize: 16),
                  ),
                  Text(
                    _myPhone,
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Scan this code to instantly connect on WhisperChat.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF8FA1AE), fontSize: 12),
            ),
          ],
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Color(0xFFD8B48C), fontWeight: FontWeight.bold)),
            ),
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

  String _getTabTitle() {
    switch (_currentIndex) {
      case 0:
        return 'Chats';
      case 1:
        return 'Calls';
      case 2:
        return 'Groups';
      case 3:
        return 'Profile';
      default:
        return 'Chats';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1120),
      drawer: _buildDrawer(theme),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E1120),
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu, color: Color(0xFFD8B48C)),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(
          _getTabTitle(),
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            fontFamily: 'serif',
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2, color: Color(0xFFD8B48C), size: 24),
            onPressed: _showQrCodeDialog,
            tooltip: 'My QR Code',
          ),
          IconButton(
            icon: const Icon(Icons.person_add_alt_1, color: Color(0xFFD8B48C), size: 24),
            onPressed: _showAddContactDialog,
            tooltip: 'Add Contact',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD8B48C)))
          : IndexedStack(
              index: _currentIndex,
              children: [
                _buildChatsTab(theme),
                _buildCallsTab(theme),
                _buildGroupsTab(theme),
                _buildProfileTab(theme),
              ],
            ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BOTTOM NAVIGATION BAR (Matching Mockup with Pill Highlight)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomNavigationBar() {
    return Container(
      height: 72,
      decoration: const BoxDecoration(
        color: Color(0xFF141722),
        border: Border(top: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(0, Icons.chat_bubble, 'Chats'),
          _buildNavItem(1, Icons.call, 'Calls'),
          _buildNavItem(2, Icons.group, 'Groups'),
          _buildNavItem(3, Icons.person, 'Profile'),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFD8B48C) : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              size: 22,
              color: isSelected ? const Color(0xFF0E1120) : const Color(0xFF8FA1AE),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? const Color(0xFFD8B48C) : const Color(0xFF8FA1AE),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 0: CHATS VIEW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChatsTab(ThemeData theme) {
    return Column(
      children: [
        if (_requests.isNotEmpty) _buildRequestsBanner(),
        Expanded(
          child: _chats.isEmpty
              ? const Center(
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
                )
              : RefreshIndicator(
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
                                      ? thread.contactPhone.substring(thread.contactPhone.length - 2)
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
                ),
        ),
      ],
    );
  }

  Widget _buildRequestsBanner() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF171B30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD8B48C).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_add_outlined, color: Color(0xFFD8B48C)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_requests.length} Pending Friend Request(s)',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD8B48C),
              foregroundColor: const Color(0xFF0E1120),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen()));
            },
            child: const Text('View', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 1: CALLS VIEW
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCallsTab(ThemeData theme) {
    if (_chats.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.phone_missed_outlined, size: 52, color: Color(0xFF8FA1AE)),
            SizedBox(height: 16),
            Text('No call history', style: TextStyle(color: Color(0xFF8FA1AE))),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _chats.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
      itemBuilder: (ctx, i) {
        final thread = _chats[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFFD8B48C),
            child: Text(
              thread.contactPhone.isNotEmpty ? thread.contactPhone.substring(thread.contactPhone.length - 2) : '?',
              style: const TextStyle(color: Color(0xFF0E1120), fontWeight: FontWeight.bold),
            ),
          ),
          title: Text(thread.contactPhone, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          subtitle: Row(
            children: [
              const Icon(Icons.call_made, size: 12, color: Color(0xFFD8B48C)),
              const SizedBox(width: 4),
              Text(
                thread.isOnline ? 'Online • Ready to Call' : 'Offline',
                style: TextStyle(color: thread.isOnline ? const Color(0xFFD8B48C) : const Color(0xFF8FA1AE), fontSize: 12),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.phone, color: Color(0xFFD8B48C)),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(thread: thread)));
                },
                tooltip: 'Voice Call',
              ),
              IconButton(
                icon: const Icon(Icons.videocam, color: Color(0xFFD8B48C)),
                onPressed: () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(thread: thread)));
                },
                tooltip: 'Video Call',
              ),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 2: GROUPS VIEW (Replaces Contacts)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildGroupsTab(ThemeData theme) {
    final groups = _chats.where((t) => t.contactUid.startsWith('group_')).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF171B30),
              foregroundColor: const Color(0xFFD8B48C),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: const Color(0xFFD8B48C).withOpacity(0.3))),
            ),
            icon: const Icon(Icons.group_add, color: Color(0xFFD8B48C)),
            label: const Text('Create New Group', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const NewGroupScreen())).then((_) => _loadData());
            },
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.groups_outlined, size: 52, color: Color(0xFF8FA1AE)),
                      SizedBox(height: 16),
                      Text('No groups created yet', style: TextStyle(color: Color(0xFF8FA1AE))),
                      SizedBox(height: 8),
                      Text(
                        'Tap "Create New Group" above to start a group chat.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF49566B)),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  itemCount: groups.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                  itemBuilder: (ctx, i) {
                    final thread = groups[i];
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFD8B48C),
                        child: Icon(Icons.group, color: Color(0xFF0E1120)),
                      ),
                      title: Text(thread.contactPhone, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        thread.lastMessage?.encryptedPayload ?? 'Group created',
                        style: const TextStyle(color: Color(0xFF8FA1AE), fontSize: 12),
                      ),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(thread: thread)));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: PROFILE VIEW
  // ─────────────────────────────────────────────────────────────────────────

  // ─────────────────────────────────────────────────────────────────────────
  // TAB 3: PROFILE VIEW (Matching User Mockup Cards & Preserving Settings / QR)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProfileTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        const SizedBox(height: 10),
        // Centered Avatar with Golden Border Ring & Floating Pencil Badge
        Center(
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Color(0xFFD8B48C),
                  shape: BoxShape.circle,
                ),
                child: CircleAvatar(
                  radius: 52,
                  backgroundColor: const Color(0xFF0E1120),
                  child: Text(
                    _displayName.isNotEmpty ? _displayName.substring(0, 1).toUpperCase() : 'U',
                    style: const TextStyle(fontSize: 42, color: Color(0xFFD8B48C), fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Positioned(
                bottom: 2,
                right: 2,
                child: GestureDetector(
                  onTap: _showProfileEditorDialog,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8B48C),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF0E1120), width: 3),
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 16,
                      color: Color(0xFF0E1120),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // User Name & Edit Pencil
        Center(
          child: GestureDetector(
            onTap: _showProfileEditorDialog,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.edit, color: Color(0xFFD8B48C), size: 18),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),

        // Subtitle (Phone number / Account ID)
        Center(
          child: Text(
            _myPhone,
            style: const TextStyle(fontSize: 14, color: Color(0xFF8FA1AE)),
          ),
        ),
        const SizedBox(height: 12),

        // Online Badge
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: const Text(
              'Online',
              style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 28),

        // Cards Section matching mockup
        _buildProfileCard(
          icon: Icons.person,
          label: 'Display Name',
          value: _displayName,
          onTap: _showProfileEditorDialog,
        ),
        _buildProfileCard(
          icon: Icons.phone,
          label: 'Phone Number',
          value: _myPhone,
        ),
        _buildProfileCard(
          icon: Icons.qr_code_2,
          label: 'My QR Code',
          value: 'Tap to view & share contact QR code',
          onTap: _showQrCodeDialog,
        ),
        _buildProfileCard(
          icon: Icons.settings,
          label: 'Settings',
          value: 'Privacy, security, data usage & preferences',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())).then((_) => _loadData()),
        ),
        _buildProfileCard(
          icon: Icons.archive,
          label: 'Archived Chats',
          value: 'View and unarchive saved conversations',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ArchivedChatsScreen())).then((_) => _loadData()),
        ),
        _buildProfileCard(
          icon: Icons.star,
          label: 'Starred Messages',
          value: 'View bookmarked messages across chats',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StarredMessagesScreen())),
        ),
        _buildProfileCard(
          icon: Icons.calendar_today,
          label: 'Joined',
          value: 'July 12, 2026',
        ),
        const SizedBox(height: 12),
        _buildProfileCard(
          icon: Icons.logout,
          label: 'Account Action',
          value: 'Log Out & Clear Local Keys',
          iconColor: Colors.redAccent,
          valueColor: Colors.redAccent,
          onTap: _handleLogout,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildProfileCard({
    required IconData icon,
    required String label,
    required String value,
    VoidCallback? onTap,
    Color? iconColor,
    Color? valueColor,
  }) {
    final effectiveIconColor = iconColor ?? const Color(0xFFD8B48C);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF141722),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.white.withOpacity(0.04)),
      ),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: effectiveIconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: effectiveIconColor, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8FA1AE),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 15,
                        color: valueColor ?? Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: Color(0xFF49566B), size: 20),
            ],
          ),
        ),
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

  Widget _buildDrawer(ThemeData theme) {
    return Drawer(
      backgroundColor: const Color(0xFF0E1120),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            const Spacer(),
            const Divider(color: Colors.white10, height: 1),
            _buildDrawerItem(
              Icons.logout,
              'Log Out',
              textColor: const Color(0xFFD8B48C),
              iconColor: const Color(0xFFD8B48C),
              onTap: () {
                Navigator.pop(context);
                _handleLogout();
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
}
