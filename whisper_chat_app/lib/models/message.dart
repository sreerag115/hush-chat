import 'dart:convert';

class Message {
  final String id;
  final String senderUid;    // Firebase User UID
  final String receiverUid;  // Firebase User UID
  final String senderPhone;
  final String receiverPhone;
  final String encryptedPayload; // AES-GCM encrypted (Base64), or decrypted text stored locally
  final String mediaType;        // 'text' or 'audio'
  final String? mediaUrl;        // For E2EE voice notes: URL#mediaKey
  final int timestamp;
  final String status;           // 'sending', 'sent', 'delivered', 'read'
  final bool isStarred;

  Message({
    required this.id,
    required this.senderUid,
    required this.receiverUid,
    required this.senderPhone,
    required this.receiverPhone,
    required this.encryptedPayload,
    required this.mediaType,
    this.mediaUrl,
    required this.timestamp,
    required this.status,
    this.isStarred = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'senderUid': senderUid,
      'receiverUid': receiverUid,
      'senderPhone': senderPhone,
      'receiverPhone': receiverPhone,
      'encryptedPayload': encryptedPayload,
      'mediaType': mediaType,
      'mediaUrl': mediaUrl,
      'timestamp': timestamp,
      'status': status,
      'isStarred': isStarred,
    };
  }

  factory Message.fromMap(Map<dynamic, dynamic> map) {
    return Message(
      id: map['id'] as String,
      senderUid: map['senderUid'] as String,
      receiverUid: map['receiverUid'] as String,
      senderPhone: map['senderPhone'] as String? ?? '',
      receiverPhone: map['receiverPhone'] as String? ?? '',
      encryptedPayload: map['encryptedPayload'] as String,
      mediaType: map['mediaType'] as String,
      mediaUrl: map['mediaUrl'] as String?,
      timestamp: map['timestamp'] as int,
      status: map['status'] as String,
      isStarred: map['isStarred'] as bool? ?? false,
    );
  }

  String toJson() => json.encode(toMap());
  factory Message.fromJson(String source) => Message.fromMap(json.decode(source) as Map<String, dynamic>);
}
