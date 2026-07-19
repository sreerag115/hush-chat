import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/firebase_service.dart';
import '../services/secure_storage_service.dart';
import '../services/database_service.dart';
import 'login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SecureStorageService _secure = SecureStorageService();
  final DatabaseService _localDb = DatabaseService();

  String _displayName = 'User';
  String _phoneNumber = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final name = await _secure.getDisplayName() ?? 'User';
    final phone = await _secure.getPhoneNumber() ?? '';
    if (mounted) {
      setState(() {
        _displayName = name;
        _phoneNumber = phone;
        _isLoading = false;
      });
    }
  }

  void _showChangeNameDialog() {
    final ctrl = TextEditingController(text: _displayName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF171B30),
        title: const Text('Change Display Name', style: TextStyle(fontFamily: 'serif', color: Colors.white)),
        content: TextField(
          controller: ctrl,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter your name...',
          ),
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
                await _loadProfile();
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
    final firebase = Provider.of<FirebaseService>(context, listen: false);
    await firebase.signOut();
    await _localDb.clearDatabase();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1120),
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontFamily: 'serif', fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0E1120),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD8B48C)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Profile Section
                Card(
                  color: const Color(0xFF171B30),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.white.withOpacity(0.05)),
                  ),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 36,
                          backgroundColor: const Color(0xFFD8B48C),
                          child: Text(
                            _displayName.isNotEmpty ? _displayName.substring(0, 1).toUpperCase() : 'U',
                            style: const TextStyle(fontSize: 28, color: Color(0xFF0E1120), fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _displayName,
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _phoneNumber,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF8FA1AE)),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Color(0xFFD8B48C)),
                          onPressed: _showChangeNameDialog,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Settings List Items
                _buildSettingTile(Icons.person_outline, 'Account Info', 'Privacy, security, change number'),
                _buildSettingTile(Icons.chat_outlined, 'Chat Settings', 'Theme, wallpaper, chat history'),
                _buildSettingTile(Icons.notifications_none, 'Notifications', 'Message, group & call tones'),
                _buildSettingTile(Icons.data_usage_outlined, 'Storage and Data', 'Network usage, auto-download'),
                _buildSettingTile(Icons.help_outline, 'Help & Feedback', 'FAQ, contact support, policy'),
                
                const SizedBox(height: 32),
                const Divider(color: Colors.white10),
                const SizedBox(height: 16),

                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text('Log Out & Clear Local Data', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  subtitle: const Text('Deletes E2EE keys and all messaging history locally', style: TextStyle(color: Colors.white30, fontSize: 12)),
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF171B30),
                        title: const Text('Log Out', style: TextStyle(fontFamily: 'serif', color: Colors.white)),
                        content: const Text(
                          'Are you sure you want to log out? All your local E2EE messages and keys will be permanently deleted.',
                          style: TextStyle(color: Colors.white70),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8FA1AE))),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _handleLogout();
                            },
                            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildSettingTile(IconData icon, String title, String subtitle) {
    return ListTile(
      leading: Icon(icon, color: const Color(0xFF8FA1AE)),
      title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFF49566B), fontSize: 12)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF49566B)),
      onTap: () {
        if (title == 'Account Info') {
          _showChangeNameDialog();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$title details coming soon!'),
              backgroundColor: const Color(0xFFD8B48C),
            ),
          );
        }
      },
    );
  }
}
