import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_thread.dart';
import '../models/message.dart';
import 'crypto_service.dart';
import 'database_service.dart';
import 'package:flutter/widgets.dart';
import 'secure_storage_service.dart';
import 'notification_service.dart';

class FirebaseService extends ChangeNotifier with WidgetsBindingObserver {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  // Lazy getters — only accessed after Firebase.initializeApp() completes
  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFirestore get _db => FirebaseFirestore.instance;

  final CryptoService _crypto = CryptoService();
  final DatabaseService _localDb = DatabaseService();
  final SecureStorageService _secure = SecureStorageService();

  // Active Firestore listeners
  final Map<String, StreamSubscription<QuerySnapshot>> _messageListeners = {};
  final Map<String, StreamSubscription<DocumentSnapshot>> _presenceListeners = {};
  StreamSubscription<QuerySnapshot>? _requestListener;

  User? get currentUser => _auth.currentUser;
  String? get myUid => _auth.currentUser?.uid;

  String? activeChatUid;
  bool _observerInitialized = false;

  void initLifecycleObserver() {
    if (_observerInitialized) return;
    WidgetsBinding.instance.addObserver(this);
    _observerInitialized = true;
    setPresence(true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setPresence(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      setPresence(false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PHONE AUTH
  // ─────────────────────────────────────────────────────────────────────────

  Future<String> sendOtp(
    String phoneNumber, {
    required void Function(String verificationId) onCodeSent,
    required void Function(FirebaseAuthException e) onError,
  }) async {
    String vId = '';
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) => onError(e),
      codeSent: (String verificationId, int? resendToken) {
        vId = verificationId;
        onCodeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
    return vId;
  }

  Future<UserCredential> verifyOtp(String verificationId, String otp) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: otp,
    );
    return await _auth.signInWithCredential(credential);
  }

  Future<void> registerProfile({
    required String phoneNumber,
    required String publicKeyBase64,
  }) async {
    final uid = myUid;
    if (uid == null) throw Exception('Not authenticated');

    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'phoneNumber': phoneNumber,
      'publicKey': publicKeyBase64,
      'isOnline': true,
      'lastSeen': FieldValue.serverTimestamp(),
      'registeredAt': FieldValue.serverTimestamp(),
    });

    await _secure.savePhoneNumber(phoneNumber);
    await _secure.saveUid(uid);
  }

  Future<void> updateProfileName(String displayName) async {
    final uid = myUid;
    if (uid == null) return;
    await _db.collection('users').doc(uid).update({
      'displayName': displayName,
    });
    await _secure.saveDisplayName(displayName);
    notifyListeners();
  }

  Future<void> setPresence(bool isOnline) async {
    if (myUid == null) return;
    try {
      await _db.collection('users').doc(myUid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error updating presence: $e');
    }
  }

  void listenToPresence(String contactUid, {required void Function(bool isOnline, int lastSeen) onUpdate}) {
    _presenceListeners[contactUid]?.cancel();
    _presenceListeners[contactUid] = _db.collection('users').doc(contactUid).snapshots().listen((doc) {
      if (doc.exists) {
        final data = doc.data();
        if (data != null) {
          final isOnline = data['isOnline'] as bool? ?? false;
          final lastSeenTs = data['lastSeen'];
          int lastSeen = 0;
          if (lastSeenTs is Timestamp) {
            lastSeen = lastSeenTs.millisecondsSinceEpoch;
          } else if (lastSeenTs is int) {
            lastSeen = lastSeenTs;
          }
          _localDb.updateThreadPresence(contactUid, isOnline, lastSeen);
          onUpdate(isOnline, lastSeen);
          notifyListeners();
        }
      }
    });
  }

  void stopListeningToPresence(String contactUid) {
    _presenceListeners[contactUid]?.cancel();
    _presenceListeners.remove(contactUid);
  }

  Future<void> markMessagesAsReadInFirestore(String contactUid) async {
    final uid = myUid;
    if (uid == null) return;
    final connectionId = _buildConnectionId(uid, contactUid);
    final snap = await _db
        .collection('conversations')
        .doc(connectionId)
        .collection('messages')
        .where('receiverUid', isEqualTo: uid)
        .where('status', isNotEqualTo: 'read')
        .get();

    for (final doc in snap.docs) {
      await doc.reference.update({'status': 'read'});
    }
  }

  Future<void> signOut() async {
    await setPresence(false);
    _messageListeners.forEach((_, sub) => sub.cancel());
    _messageListeners.clear();
    _requestListener?.cancel();
    await _auth.signOut();
    await _secure.clearAll();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // USER LOOKUP
  // ─────────────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> findUserByPhone(String phoneNumber) async {
    final normalized = phoneNumber.trim().replaceAll(' ', '');
    final snap = await _db
        .collection('users')
        .where('phoneNumber', isEqualTo: normalized)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return null;
    return snap.docs.first.data();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // FRIEND REQUESTS
  // ─────────────────────────────────────────────────────────────────────────

  Future<String?> sendFriendRequest(String toPhoneNumber) async {
    final toUser = await findUserByPhone(toPhoneNumber);
    if (toUser == null) return 'User not found. Ask them to register first.';

    final toUid = toUser['uid'] as String;
    if (toUid == myUid) return 'You cannot add yourself.';

    final existing = await _db
        .collection('friend_requests')
        .where('fromUid', isEqualTo: myUid)
        .where('toUid', isEqualTo: toUid)
        .get();

    if (existing.docs.isNotEmpty) {
      return 'You already sent a request to this number.';
    }

    final reverse = await _db
        .collection('friend_requests')
        .where('fromUid', isEqualTo: toUid)
        .where('toUid', isEqualTo: myUid)
        .get();

    if (reverse.docs.isNotEmpty) {
      await acceptFriendRequest(toUid, reverse.docs.first.id);
      return null;
    }

    final myPhone = await _secure.getPhoneNumber() ?? '';
    final myPublicKey = await _secure.getPublicKey() ?? '';

    await _db.collection('friend_requests').add({
      'fromUid': myUid,
      'fromPhone': myPhone,
      'fromPublicKey': myPublicKey,
      'toUid': toUid,
      'toPhone': toUser['phoneNumber'],
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _localDb.saveOrUpdateThread(ChatThread(
      contactUid: toUid,
      contactPhone: toUser['phoneNumber'] as String,
      contactPublicKey: toUser['publicKey'] as String,
      connectionStatus: 'pending_sent',
    ));

    return null;
  }

  Future<void> acceptFriendRequest(String fromUid, String requestDocId) async {
    final myPublicKey = await _secure.getPublicKey() ?? '';
    final myPhone = await _secure.getPhoneNumber() ?? '';

    await _db.collection('friend_requests').doc(requestDocId).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
    });

    final connectionId = _buildConnectionId(myUid!, fromUid);
    final fromUserDoc = await _db.collection('users').doc(fromUid).get();
    final fromData = fromUserDoc.data()!;

    await _db.collection('connections').doc(connectionId).set({
      'members': [myUid, fromUid],
      'memberPhones': [myPhone, fromData['phoneNumber']],
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(myUid).collection('contacts').doc(fromUid).set({
      'uid': fromUid,
      'phone': fromData['phoneNumber'],
      'publicKey': fromData['publicKey'],
      'connectedAt': FieldValue.serverTimestamp(),
    });

    await _db.collection('users').doc(fromUid).collection('contacts').doc(myUid).set({
      'uid': myUid,
      'phone': myPhone,
      'publicKey': myPublicKey,
      'connectedAt': FieldValue.serverTimestamp(),
    });

    await _localDb.saveOrUpdateThread(ChatThread(
      contactUid: fromUid,
      contactPhone: fromData['phoneNumber'] as String,
      contactPublicKey: fromData['publicKey'] as String,
      connectionStatus: 'connected',
    ));

    notifyListeners();
  }

  Future<void> declineFriendRequest(String requestDocId) async {
    await _db.collection('friend_requests').doc(requestDocId).delete();
  }

  void listenForFriendRequests(
      void Function(List<Map<String, dynamic>> requests) onUpdate) {
    _requestListener?.cancel();
    _requestListener = _db
        .collection('friend_requests')
        .where('toUid', isEqualTo: myUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      final requests = snap.docs.map((doc) {
        final data = doc.data();
        data['docId'] = doc.id;
        return data;
      }).toList();
      onUpdate(requests);
    });
  }

  Future<void> syncContacts() async {
    final snap = await _db
        .collection('users')
        .doc(myUid)
        .collection('contacts')
        .get();

    for (final doc in snap.docs) {
      final data = doc.data();
      final existingThread = await _localDb.getThread(data['uid'] as String);
      if (existingThread == null || !existingThread.isConnected) {
        await _localDb.saveOrUpdateThread(ChatThread(
          contactUid: data['uid'] as String,
          contactPhone: data['phone'] as String,
          contactPublicKey: data['publicKey'] as String,
          connectionStatus: 'connected',
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // E2EE MESSAGING (INLINE SECURE TEXT & AUDIO)
  // ─────────────────────────────────────────────────────────────────────────

  /// Send E2EE Message. For voice notes, we read the local audio file,
  /// encrypt the binary bytes, and store the resulting Base64 string directly in the doc.
  Future<Message?> sendMessage({
    required String toUid,
    required String text,
    required String mediaType,
    File? audioFile,
  }) async {
    final thread = await _localDb.getThread(toUid);
    if (thread == null || !thread.isConnected) return null;

    final privKeyStr = await _secure.getPrivateKey();
    final pubKeyStr = await _secure.getPublicKey();
    if (privKeyStr == null || pubKeyStr == null) return null;

    final localKeyPair = await _crypto.reconstructKeyPair(privKeyStr, pubKeyStr);

    String rawPayloadToEncrypt = text;

    if (mediaType == 'audio' && audioFile != null) {
      // 1. Read local audio file bytes
      final audioBytes = await audioFile.readAsBytes();
      // 2. Convert raw bytes to Base64 first so we can encrypt it as a clean UTF-8 string
      rawPayloadToEncrypt = base64Encode(audioBytes);
    }

    // Encrypt the payload using the recipient's public key
    final encryptedPayload = await _crypto.encrypt(
      plaintext: rawPayloadToEncrypt,
      remoteUsername: toUid,
      remotePublicKeyBase64: thread.contactPublicKey,
      localKeyPair: localKeyPair,
    );

    final msgId = const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final myPhone = await _secure.getPhoneNumber() ?? '';
    final connectionId = _buildConnectionId(myUid!, toUid);

    // Save to Firestore (fully E2EE)
    final msgData = {
      'id': msgId,
      'senderUid': myUid,
      'receiverUid': toUid,
      'senderPhone': myPhone,
      'receiverPhone': thread.contactPhone,
      'encryptedPayload': encryptedPayload,
      'mediaType': mediaType,
      'timestamp': timestamp,
      'status': 'sent',
    };

    await _db
        .collection('conversations')
        .doc(connectionId)
        .collection('messages')
        .doc(msgId)
        .set(msgData);

    // Save locally
    final localMsg = Message(
      id: msgId,
      senderUid: myUid!,
      receiverUid: toUid,
      senderPhone: myPhone,
      receiverPhone: thread.contactPhone,
      encryptedPayload: text, // For audio, stores placeholder '[Voice Note]'. Hive is already encrypted.
      mediaType: mediaType,
      mediaUrl: mediaType == 'audio' && audioFile != null ? audioFile.path : null, // Keep local path in local cache
      timestamp: timestamp,
      status: 'sent',
    );

    await _localDb.saveMessage(toUid, localMsg);
    return localMsg;
  }

  /// Listen for incoming Firestore E2EE messages
  void listenForMessages(
    String contactUid, {
    required void Function(Message message) onMessage,
  }) {
    _messageListeners[contactUid]?.cancel();
    final connectionId = _buildConnectionId(myUid!, contactUid);

    _messageListeners[contactUid] = _db
        .collection('conversations')
        .doc(connectionId)
        .collection('messages')
        .orderBy('timestamp')
        .snapshots()
        .listen((snap) async {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          final senderUid = data['senderUid'] as String;

          if (senderUid == myUid) continue;

          // Check if message is already stored locally
          final existing = await _localDb.getMessages(contactUid);
          final alreadySaved = existing.any((m) => m.id == data['id']);
          if (alreadySaved) continue;

          final thread = await _localDb.getThread(contactUid);
          if (thread == null) continue;

          final privKeyStr = await _secure.getPrivateKey();
          final pubKeyStr = await _secure.getPublicKey();
          if (privKeyStr == null || pubKeyStr == null) continue;

          final localKeyPair = await _crypto.reconstructKeyPair(privKeyStr, pubKeyStr);

          // Decrypt payload (which contains either raw text or Base64 audio bytes)
          final decrypted = await _crypto.decrypt(
            encryptedBase64: data['encryptedPayload'] as String,
            remoteUsername: contactUid,
            remotePublicKeyBase64: thread.contactPublicKey,
            localKeyPair: localKeyPair,
          );

          String? cachedLocalAudioPath;
          String displayPayloadText = decrypted;

          if (data['mediaType'] == 'audio') {
            displayPayloadText = '[Voice Note]';
            try {
              // Convert the decrypted Base64 string back into audio binary bytes
              final audioBytes = base64Decode(decrypted);

              // Save the bytes to a local m4a file in the cache directory
              final tempDir = await getTemporaryDirectory();
              final outFile = File('${tempDir.path}/rec_${data['id']}_${DateTime.now().millisecondsSinceEpoch}.m4a');
              await outFile.writeAsBytes(audioBytes);
              cachedLocalAudioPath = outFile.path;
            } catch (e) {
              debugPrint("Error writing inline voice note to file: $e");
              displayPayloadText = '[Error: Decrypting voice note failed]';
            }
          }

          final statusToSet = (activeChatUid == contactUid) ? 'read' : 'delivered';
          try {
            await change.doc.reference.update({'status': statusToSet});
          } catch (e) {
            debugPrint("Error updating msg status: $e");
          }

          final msg = Message(
            id: data['id'] as String,
            senderUid: senderUid,
            receiverUid: myUid!,
            senderPhone: data['senderPhone'] as String? ?? '',
            receiverPhone: data['receiverPhone'] as String? ?? '',
            encryptedPayload: displayPayloadText,
            mediaType: data['mediaType'] as String,
            mediaUrl: cachedLocalAudioPath, // Store local audio path in local DB
            timestamp: data['timestamp'] as int,
            status: statusToSet,
          );

          await _localDb.saveMessage(contactUid, msg);
          onMessage(msg);

          if (activeChatUid != contactUid) {
            await NotificationService().showManualNotification(
              id: msg.id.hashCode,
              title: msg.senderPhone.isNotEmpty ? msg.senderPhone : 'New Message',
              body: msg.mediaType == 'audio' ? '🎤 Voice Note' : msg.encryptedPayload,
            );
          }
        } else if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data()!;
          final senderUid = data['senderUid'] as String;

          if (senderUid == myUid) {
            final newStatus = data['status'] as String? ?? 'sent';
            await _localDb.updateMessageStatus(contactUid, data['id'] as String, newStatus);
            final updatedMsg = Message(
              id: data['id'] as String,
              senderUid: senderUid,
              receiverUid: data['receiverUid'] as String? ?? '',
              senderPhone: data['senderPhone'] as String? ?? '',
              receiverPhone: data['receiverPhone'] as String? ?? '',
              encryptedPayload: '',
              mediaType: data['mediaType'] as String? ?? 'text',
              timestamp: data['timestamp'] as int? ?? 0,
              status: newStatus,
            );
            onMessage(updatedMsg);
          }
        }
      }
    });
  }

  void stopListeningForMessages(String contactUid) {
    _messageListeners[contactUid]?.cancel();
    _messageListeners.remove(contactUid);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WebRTC SIGNALING via Firestore
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> sendSignal(String toUid, Map<String, dynamic> payload) async {
    await _db
        .collection('calls')
        .doc('${myUid}_to_$toUid')
        .collection('signals')
        .add({
      ...payload,
      'from': myUid,
      'to': toUid,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  StreamSubscription listenForSignals(
      void Function(Map<String, dynamic> signal) onSignal) {
    return _db
        .collection('calls')
        .doc('${_db.collection("_").parent?.id ?? ""}_to_${myUid}')
        .collection('signals')
        .where('to', isEqualTo: myUid)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          onSignal(data);
          change.doc.reference.delete();
        }
      }
    });
  }

  String _buildConnectionId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return '${sorted[0]}_${sorted[1]}';
  }
}
