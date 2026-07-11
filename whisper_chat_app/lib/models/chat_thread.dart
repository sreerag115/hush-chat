import 'message.dart';

/// connectionStatus values:
///   'pending_sent'     - Alice sent Bob a friend request, waiting for Bob
///   'pending_received' - Bob has received Alice's request, needs to accept
///   'connected'        - Both accepted, full E2EE chat and calls enabled
class ChatThread {
  final String contactUid;
  final String contactPhone;
  final String contactPublicKey; // Base64 Curve25519 public key, empty if not yet connected
  final String connectionStatus;
  final Message? lastMessage;
  final int unreadCount;
  final bool isOnline;
  final int lastSeen;

  ChatThread({
    required this.contactUid,
    required this.contactPhone,
    this.contactPublicKey = '',
    required this.connectionStatus,
    this.lastMessage,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastSeen = 0,
  });

  bool get isConnected => connectionStatus == 'connected';
  bool get isPendingSent => connectionStatus == 'pending_sent';
  bool get isPendingReceived => connectionStatus == 'pending_received';

  ChatThread copyWith({
    String? contactUid,
    String? contactPhone,
    String? contactPublicKey,
    String? connectionStatus,
    Message? lastMessage,
    int? unreadCount,
    bool? isOnline,
    int? lastSeen,
  }) {
    return ChatThread(
      contactUid: contactUid ?? this.contactUid,
      contactPhone: contactPhone ?? this.contactPhone,
      contactPublicKey: contactPublicKey ?? this.contactPublicKey,
      connectionStatus: connectionStatus ?? this.connectionStatus,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'contactUid': contactUid,
      'contactPhone': contactPhone,
      'contactPublicKey': contactPublicKey,
      'connectionStatus': connectionStatus,
      'lastMessage': lastMessage?.toMap(),
      'unreadCount': unreadCount,
      'isOnline': isOnline,
      'lastSeen': lastSeen,
    };
  }

  factory ChatThread.fromMap(Map<dynamic, dynamic> map) {
    return ChatThread(
      contactUid: map['contactUid'] as String,
      contactPhone: map['contactPhone'] as String,
      contactPublicKey: map['contactPublicKey'] as String? ?? '',
      connectionStatus: map['connectionStatus'] as String,
      lastMessage: map['lastMessage'] != null
          ? Message.fromMap(map['lastMessage'] as Map<dynamic, dynamic>)
          : null,
      unreadCount: map['unreadCount'] as int? ?? 0,
      isOnline: map['isOnline'] as bool? ?? false,
      lastSeen: map['lastSeen'] as int? ?? 0,
    );
  }
}
