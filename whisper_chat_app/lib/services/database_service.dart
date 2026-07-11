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
        .where((t) => t.isConnected)
        .toList()
      ..sort((a, b) {
        final aT = a.lastMessage?.timestamp ?? 0;
        final bT = b.lastMessage?.timestamp ?? 0;
        return bT.compareTo(aT);
      });
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

  Future<void> deleteThread(String contactUid) async {
    final box = await _getThreadsBox();
    await box.delete(contactUid);
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
