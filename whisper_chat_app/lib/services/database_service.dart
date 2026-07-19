import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';
import '../models/chat_thread.dart';
import 'secure_storage_service.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  final SecureStorageService _secureStorage = SecureStorageService();

  bool _isInitialized = false;
  List<int>? _encryptionKey;

  static const String _threadsBoxName = 'chat_threads';

  Future<void> init() async {
    if (_isInitialized) return;
    await Hive.initFlutter();
    _encryptionKey = await _secureStorage.getOrCreateHiveEncryptionKey();
    _isInitialized = true;
  }

  Future<Box<T>> _openEncryptedBox<T>(String name) async {
    await init();
    return await Hive.openBox<T>(
      name,
      encryptionCipher: HiveAesCipher(_encryptionKey!),
    );
  }

  Future<Box<Map>> _getThreadsBox() async =>
      _openEncryptedBox<Map>(_threadsBoxName);

  Future<Box<Map>> _getMessagesBox(String contactUid) async =>
      _openEncryptedBox<Map>('messages_$contactUid');

  // --- Threads ---

  Future<List<ChatThread>> getConnectedThreads() async {
    final box = await _getThreadsBox();
    return box.values
        .map((d) => ChatThread.fromMap(d))
        .where((t) => t.isConnected && !t.isArchived)
        .toList()
      ..sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        final aT = a.lastMessage?.timestamp ?? 0;
        final bT = b.lastMessage?.timestamp ?? 0;
        return bT.compareTo(aT);
      });
  }

  Future<List<ChatThread>> getArchivedThreads() async {
    final box = await _getThreadsBox();
    return box.values
        .map((d) => ChatThread.fromMap(d))
        .where((t) => t.isConnected && t.isArchived)
        .toList()
      ..sort((a, b) {
        final aT = a.lastMessage?.timestamp ?? 0;
        final bT = b.lastMessage?.timestamp ?? 0;
        return bT.compareTo(aT);
      });
  }

  Future<void> toggleArchiveThread(String contactUid) async {
    final thread = await getThread(contactUid);
    if (thread != null) {
      final updated = thread.copyWith(isArchived: !thread.isArchived);
      await saveOrUpdateThread(updated);
    }
  }

  Future<void> togglePinThread(String contactUid) async {
    final thread = await getThread(contactUid);
    if (thread != null) {
      final updated = thread.copyWith(isPinned: !thread.isPinned);
      await saveOrUpdateThread(updated);
    }
  }

  Future<List<ChatThread>> getPendingReceivedThreads() async {
    final box = await _getThreadsBox();
    return box.values
        .map((d) => ChatThread.fromMap(d))
        .where((t) => t.isPendingReceived)
        .toList();
  }

  Future<List<ChatThread>> getPendingSentThreads() async {
    final box = await _getThreadsBox();
    return box.values
        .map((d) => ChatThread.fromMap(d))
        .where((t) => t.isPendingSent)
        .toList();
  }

  Future<void> saveOrUpdateThread(ChatThread thread) async {
    final box = await _getThreadsBox();
    await box.put(thread.contactUid, thread.toMap());
  }

  Future<ChatThread?> getThread(String contactUid) async {
    final box = await _getThreadsBox();
    final data = box.get(contactUid);
    if (data == null) return null;
    return ChatThread.fromMap(data);
  }

  Future<void> updateThreadPresence(String contactUid, bool isOnline, int lastSeen) async {
    final thread = await getThread(contactUid);
    if (thread != null) {
      await saveOrUpdateThread(thread.copyWith(isOnline: isOnline, lastSeen: lastSeen));
    }
  }

  Future<void> updateMessageStatus(String contactUid, String messageId, String newStatus) async {
    final box = await _getMessagesBox(contactUid);
    final data = box.get(messageId);
    if (data != null) {
      final msg = Message.fromMap(data);
      if (msg.status != newStatus) {
        final updated = Message(
          id: msg.id,
          senderUid: msg.senderUid,
          receiverUid: msg.receiverUid,
          senderPhone: msg.senderPhone,
          receiverPhone: msg.receiverPhone,
          encryptedPayload: msg.encryptedPayload,
          mediaType: msg.mediaType,
          mediaUrl: msg.mediaUrl,
          timestamp: msg.timestamp,
          status: newStatus,
          isStarred: msg.isStarred,
        );
        await box.put(messageId, updated.toMap());

        // Update thread last message if applicable
        final thread = await getThread(contactUid);
        if (thread != null && thread.lastMessage?.id == messageId) {
          await saveOrUpdateThread(thread.copyWith(lastMessage: updated));
        }
      }
    }
  }

  Future<void> deleteThread(String contactUid) async {
    final box = await _getThreadsBox();
    await box.delete(contactUid);
  }

  Future<void> toggleStarMessage(String contactUid, String messageId) async {
    final box = await _getMessagesBox(contactUid);
    final data = box.get(messageId);
    if (data != null) {
      final msg = Message.fromMap(data);
      final updated = Message(
        id: msg.id,
        senderUid: msg.senderUid,
        receiverUid: msg.receiverUid,
        senderPhone: msg.senderPhone,
        receiverPhone: msg.receiverPhone,
        encryptedPayload: msg.encryptedPayload,
        mediaType: msg.mediaType,
        mediaUrl: msg.mediaUrl,
        timestamp: msg.timestamp,
        status: msg.status,
        isStarred: !msg.isStarred,
      );
      await box.put(messageId, updated.toMap());
    }
  }

  Future<List<Message>> getStarredMessages() async {
    final threadsBox = await _getThreadsBox();
    final List<Message> starred = [];
    for (final threadMap in threadsBox.values) {
      final thread = ChatThread.fromMap(threadMap);
      final msgBox = await _getMessagesBox(thread.contactUid);
      for (final msgMap in msgBox.values) {
        final msg = Message.fromMap(msgMap);
        if (msg.isStarred) {
          starred.add(msg);
        }
      }
    }
    starred.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return starred;
  }

  // --- Messages ---

  Future<List<Message>> getMessages(String contactUid) async {
    final box = await _getMessagesBox(contactUid);
    return box.values
        .map((d) => Message.fromMap(d))
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  }

  Future<void> saveMessage(String contactUid, Message message) async {
    final box = await _getMessagesBox(contactUid);
    await box.put(message.id, message.toMap());

    final thread = await getThread(contactUid);
    if (thread != null) {
      final myUid = await _secureStorage.getUid();
      final isIncoming = message.senderUid != myUid;
      final unread = isIncoming && message.status != 'read'
          ? thread.unreadCount + 1
          : thread.unreadCount;

      await saveOrUpdateThread(thread.copyWith(
        lastMessage: message,
        unreadCount: unread,
      ));
    }
  }

  Future<void> markMessagesAsRead(String contactUid) async {
    final box = await _getMessagesBox(contactUid);
    final myUid = await _secureStorage.getUid();

    for (var key in box.keys) {
      final data = box.get(key);
      if (data != null) {
        final msg = Message.fromMap(data);
        if (msg.senderUid != myUid && msg.status != 'read') {
          final updated = Message(
            id: msg.id,
            senderUid: msg.senderUid,
            receiverUid: msg.receiverUid,
            senderPhone: msg.senderPhone,
            receiverPhone: msg.receiverPhone,
            encryptedPayload: msg.encryptedPayload,
            mediaType: msg.mediaType,
            mediaUrl: msg.mediaUrl,
            timestamp: msg.timestamp,
            status: 'read',
          );
          await box.put(key, updated.toMap());
        }
      }
    }

    final thread = await getThread(contactUid);
    if (thread != null) {
      await saveOrUpdateThread(thread.copyWith(unreadCount: 0));
    }
  }

  Future<void> clearDatabase() async {
    await init();
    await Hive.deleteFromDisk();
    _isInitialized = false;
  }
}
