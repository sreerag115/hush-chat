import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_thread.dart';
import '../models/message.dart';
import '../services/audio_service.dart';
import '../services/database_service.dart';
import '../services/firebase_service.dart';
import '../services/webrtc_service.dart';

class ChatScreen extends StatefulWidget {
  final ChatThread thread;
  const ChatScreen({super.key, required this.thread});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final DatabaseService _localDb = DatabaseService();
  final AudioService _audio = AudioService();

  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  List<Message> _messages = [];
  bool _isRecording = false;

  final Map<String, String> _cachedVoiceNotes = {};
  String? _playingMsgId;
  Duration _playPos = Duration.zero;
  Duration _playDur = Duration.zero;

  @override
  void initState() {
    super.initState();
    _loadMessages();

    // Listen for new real-time messages from Firebase
    final firebase = Provider.of<FirebaseService>(context, listen: false);
    firebase.listenForMessages(
      widget.thread.contactUid,
      onMessage: (msg) {
        _loadMessages();
      },
    );

    // Audio playback listeners
    _audio.player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _playPos = p);
    });
    _audio.player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _playDur = d);
    });
    _audio.player.onPlayerComplete.listen((_) {
      if (mounted) setState(() {
        _playingMsgId = null;
        _playPos = Duration.zero;
      });
    });
  }

  @override
  void dispose() {
    final firebase = Provider.of<FirebaseService>(context, listen: false);
    firebase.stopListeningForMessages(widget.thread.contactUid);
    _audio.stopAudio();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final msgs = await _localDb.getMessages(widget.thread.contactUid);
    if (mounted) {
      setState(() => _messages = msgs);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Text Message ────────────────────────────────────────────────────────

  Future<void> _sendText() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final firebase = Provider.of<FirebaseService>(context, listen: false);
    await firebase.sendMessage(
      toUid: widget.thread.contactUid,
      text: text,
      mediaType: 'text',
    );
    _loadMessages();
  }

  // ── Voice Notes (disabled — requires Firebase Storage paid plan) ──────────

  void _voiceNoteComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.mic_off, color: Colors.white70, size: 16),
            SizedBox(width: 8),
            Text('Voice notes coming soon (requires Storage upgrade)'),
          ],
        ),
        backgroundColor: const Color(0xFF1E293B),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _playVoiceNote(Message msg) async {
    final localPath = msg.mediaUrl;
    if (localPath == null || !File(localPath).existsSync()) {
      _showSnack('Voice note file not found locally');
      return;
    }

    if (_playingMsgId == msg.id) {
      await _audio.pauseAudio();
      if (mounted) setState(() => _playingMsgId = null);
      return;
    }

    if (mounted) {
      setState(() {
        _playingMsgId = msg.id;
        _playPos = Duration.zero;
        _playDur = Duration.zero;
      });
    }

    try {
      await _audio.playAudio(localPath);
    } catch (e) {
      if (mounted) setState(() => _playingMsgId = null);
      _showSnack('Could not play voice note');
    }
  }

  // ── Calls ────────────────────────────────────────────────────────────────

  Future<void> _call(bool video) async {
    final webrtc = Provider.of<WebRtcService>(context, listen: false);
    await webrtc.makeCall(widget.thread.contactUid, widget.thread.contactPhone, video);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firebase = Provider.of<FirebaseService>(context, listen: false);
    final myUid = firebase.myUid ?? '';

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.12),
              child: Text(
                widget.thread.contactPhone.length >= 2
                    ? widget.thread.contactPhone.substring(
                        widget.thread.contactPhone.length - 2)
                    : '?',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.thread.contactPhone,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  Text(
                    widget.thread.isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.thread.isOnline ? Colors.teal : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.phone),
            onPressed: () => _call(false),
            tooltip: 'Voice Call',
          ),
          IconButton(
            icon: const Icon(Icons.videocam),
            onPressed: () => _call(true),
            tooltip: 'Video Call',
          ),
        ],
      ),
      body: Column(
        children: [
          // E2EE banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            color: Colors.teal.withOpacity(0.07),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, size: 11, color: theme.colorScheme.secondary),
                const SizedBox(width: 6),
                const Text(
                  'Messages are End-to-End Encrypted',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),

          // Messages
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (ctx, i) => _buildMessageBubble(_messages[i], myUid, theme),
            ),
          ),

          // Input bar
          _buildInputBar(theme),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Message msg, String myUid, ThemeData theme) {
    final isMe = msg.senderUid == myUid;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? theme.colorScheme.primary.withOpacity(0.85)
              : const Color(0xFF1E293B),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Message body
            if (msg.mediaType == 'audio') ...[
              _buildVoiceNotePlayer(msg, isMe, theme),
            ] else ...[
              Text(msg.encryptedPayload,
                  style: const TextStyle(color: Colors.white, fontSize: 14)),
            ],
            const SizedBox(height: 4),
            // Timestamp + status
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  DateFormat('HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(msg.timestamp)),
                  style: const TextStyle(fontSize: 10, color: Colors.white38),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    msg.status == 'read' ? Icons.done_all : Icons.done,
                    size: 13,
                    color: msg.status == 'read' ? Colors.cyan : Colors.white30,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceNotePlayer(Message msg, bool isMe, ThemeData theme) {
    final isPlaying = _playingMsgId == msg.id;
    final progress = _playDur.inMilliseconds > 0
        ? _playPos.inMilliseconds / _playDur.inMilliseconds
        : 0.0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          icon: Icon(
            isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: isMe ? Colors.white : theme.colorScheme.secondary,
            size: 36,
          ),
          onPressed: () => _playVoiceNote(msg),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Voice Note',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isMe ? Colors.white70 : theme.colorScheme.secondary,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: isPlaying ? progress : 0,
                  minHeight: 3,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isMe ? Colors.white70 : theme.colorScheme.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInputBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 20, top: 8),
      color: const Color(0xFF0F172A),
      child: Row(
        children: [
          // Text input
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(24),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: _isRecording
                  ? Row(
                      children: const [
                        Icon(Icons.fiber_manual_record, color: Colors.redAccent, size: 14),
                        SizedBox(width: 8),
                        Text('Recording...', style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _msgCtrl,
                            minLines: 1,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              hintText: 'Type a secure message...',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 10),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.send, color: theme.colorScheme.primary),
                          onPressed: _sendText,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(width: 8),
          // Mic button (disabled — voice notes require Firebase Storage)
          GestureDetector(
            onTap: _voiceNoteComingSoon,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withOpacity(0.4),
              ),
              child: const Icon(
                Icons.mic,
                color: Colors.white54,
                size: 22,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
