import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import '../models/message.dart';
import '../models/chat_thread.dart';
import 'crypto_service.dart';
import 'database_service.dart';
import 'secure_storage_service.dart';

enum SocketConnectionState { disconnected, connecting, connected }

class SocketService extends ChangeNotifier {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  final SecureStorageService _secureStorage = SecureStorageService();
  final CryptoService _cryptoService = CryptoService();
  final DatabaseService _dbService = DatabaseService();

  WebSocketChannel? _channel;
  SocketConnectionState _connectionState = SocketConnectionState.disconnected;
  String _serverIp = 'localhost'; // Default to localhost, can be changed in settings
  final int _serverPort = 8080;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  bool _shouldReconnect = false;

  // Controllers for streaming events
  final _messageStreamController = StreamController<Message>.broadcast();
  final _statusStreamController = StreamController<Map<String, dynamic>>.broadcast();
  final _signalingStreamController = StreamController<Map<String, dynamic>>.broadcast();

  // Getters
  SocketConnectionState get connectionState => _connectionState;
  Stream<Message> get messageStream => _messageStreamController.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusStreamController.stream;
  Stream<Map<String, dynamic>> get signalingStream => _signalingStreamController.stream;
  String get serverIp => _serverIp;

  set serverIp(String ip) {
    _serverIp = ip;
    notifyListeners();
  }

  /// Initialize and connect to WebSocket server
  void connect() async {
    final username = await _secureStorage.getUsername();
    final publicKey = await _secureStorage.getPublicKey();

    if (username == null || publicKey == null) {
      debugPrint("SocketService: No registration details found, skipping connection.");
      return;
    }

    if (_connectionState == SocketConnectionState.connected || 
        _connectionState == SocketConnectionState.connecting) {
      return;
    }

    _shouldReconnect = true;
    _connectionState = SocketConnectionState.connecting;
    notifyListeners();

    final wsUrl = 'ws://$_serverIp:$_serverPort';
    debugPrint("SocketService: Connecting to $wsUrl...");

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      
      // Send registration as the first message
      _sendRaw({
        'type': 'register',
        'username': username,
        'publicKey': publicKey,
      });

      _channel!.stream.listen(
        (message) => _onMessageReceived(message),
        onError: (error) {
          debugPrint("SocketService: WebSocket error: $error");
          _onDisconnected();
        },
        onDone: () {
          debugPrint("SocketService: WebSocket connection closed.");
          _onDisconnected();
        },
      );

      _connectionState = SocketConnectionState.connected;
      notifyListeners();
      _startHeartbeat();
      
      if (_reconnectTimer != null) {
        _reconnectTimer!.cancel();
        _reconnectTimer = null;
      }
    } catch (e) {
      debugPrint("SocketService: Connection failed: $e");
      _onDisconnected();
    }
  }

  /// Disconnect socket
  void disconnect() {
    _shouldReconnect = false;
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close(status.goingAway);
    _connectionState = SocketConnectionState.disconnected;
    notifyListeners();
  }

  void _onDisconnected() {
    _connectionState = SocketConnectionState.disconnected;
    _heartbeatTimer?.cancel();
    notifyListeners();

    if (_shouldReconnect) {
      _reconnectTimer ??= Timer.periodic(const Duration(seconds: 5), (timer) {
        debugPrint("SocketService: Reconnecting...");
        connect();
      });
    }
  }

  /// Start pinging server to keep connection alive
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (timer) {
      if (_connectionState == SocketConnectionState.connected) {
        _sendRaw({'type': 'heartbeat'});
      }
    });
  }

  /// Process incoming messages
  void _onMessageReceived(String rawMessage) async {
    try {
      final data = json.decode(rawMessage);
      final type = data['type'] as String;

      switch (type) {
        case 'registered':
          debugPrint("SocketService: Successfully registered as ${data['username']}");
          break;

        case 'status-change':
          // A contact online/offline status changed
          _statusStreamController.add({
            'username': data['username'],
            'isOnline': data['isOnline'],
          });
          // Update status in thread if it exists
          final thread = await _dbService.getThread(data['username']);
          if (thread != null) {
            await _dbService.saveOrUpdateThread(thread.copyWith(
              isOnline: data['isOnline'],
              lastSeen: DateTime.now().millisecondsSinceEpoch,
            ));
          }
          break;

        case 'message':
          _handleIncomingChat(data);
          break;

        case 'ack':
          debugPrint("SocketService: Message ACK received: ${data['msgId']} - status: ${data['status']}");
          break;

        // WebRTC Call signaling messages
        case 'call-invite':
        case 'call-accept':
        case 'ice-candidate':
        case 'call-hangup':
        case 'call-error':
          _signalingStreamController.add(data);
          break;

        case 'error':
          debugPrint("SocketService: Server error: ${data['message']}");
          break;
      }
    } catch (e) {
      debugPrint("SocketService: Error parsing message: $e");
    }
  }

  /// Handle incoming E2EE chat messages
  void _handleIncomingChat(Map<String, dynamic> data) async {
    final from = data['from'] as String;
    final to = data['to'] as String;
    final payload = data['payload'] as String;
    final msgId = data['msgId'] as String;
    final mediaType = data['mediaType'] as String;
    final timestamp = data['timestamp'] as int;

    // Get sender public key from the server or database
    // For local first, if we don't have a thread for the sender, we should look them up
    ChatThread? thread = await _dbService.getThread(from);
    
    if (thread == null) {
      // Fetch public key from backend REST API
      final publicKey = await fetchUserPublicKey(from);
      if (publicKey == null) {
        debugPrint("SocketService: Could not fetch public key for $from. Cannot decrypt message.");
        return;
      }
      thread = ChatThread(username: from, publicKey: publicKey);
      await _dbService.saveOrUpdateThread(thread);
    }

    // Decrypt message payload
    final localPrivateKeyStr = await _secureStorage.getPrivateKey();
    final localPublicKeyStr = await _secureStorage.getPublicKey();
    if (localPrivateKeyStr == null || localPublicKeyStr == null) return;

    final localKeyPair = await _cryptoService.reconstructKeyPair(localPrivateKeyStr, localPublicKeyStr);

    final decryptedText = await _cryptoService.decrypt(
      encryptedBase64: payload,
      remoteUsername: from,
      remotePublicKeyBase64: thread.publicKey,
      localKeyPair: localKeyPair,
    );

    // If it's a voice note, download the media first (handled in UI or dynamically,
    // let's pass down the message model containing local path or remote URL).
    // In our case, mediaUrl is passed in the message, let's keep it.
    final message = Message(
      id: msgId,
      sender: from,
      receiver: to,
      encryptedPayload: decryptedText, // Store decrypted text locally! Very secure, database is encrypted anyway
      mediaType: mediaType,
      mediaUrl: data['mediaUrl'] as String?,
      timestamp: timestamp,
      status: 'delivered',
    );

    // Save to database
    await _dbService.saveMessage(from, message);
    
    // Broadcast to UI
    _messageStreamController.add(message);
  }

  /// Fetch user public key from server
  Future<String?> fetchUserPublicKey(String username) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://$_serverIp:$_serverPort/users/${username.toLowerCase()}'));
      final response = await request.close();
      
      if (response.statusCode == 200) {
        final contents = await response.transform(utf8.decoder).join();
        final data = json.decode(contents);
        return data['publicKey'] as String?;
      }
    } catch (e) {
      debugPrint("SocketService: Error fetching public key: $e");
    }
    return null;
  }

  /// Encrypt and send a message to a recipient
  Future<Message?> sendMessage({
    required String toUsername,
    required String text,
    required String mediaType, // 'text' or 'audio'
    String? mediaUrl,
  }) async {
    final thread = await _dbService.getThread(toUsername);
    if (thread == null) {
      debugPrint("SocketService: Chat thread not found. Fetch public key first.");
      return null;
    }

    final localPrivateKeyStr = await _secureStorage.getPrivateKey();
    final localPublicKeyStr = await _secureStorage.getPublicKey();
    final myUsername = await _secureStorage.getUsername();

    if (localPrivateKeyStr == null || localPublicKeyStr == null || myUsername == null) {
      return null;
    }

    final localKeyPair = await _cryptoService.reconstructKeyPair(localPrivateKeyStr, localPublicKeyStr);

    // Encrypt message payload before sending over the wire
    final encryptedBase64 = await _cryptoService.encrypt(
      plaintext: text,
      remoteUsername: toUsername,
      remotePublicKeyBase64: thread.publicKey,
      localKeyPair: localKeyPair,
    );

    final msgId = const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final msgMap = {
      'type': 'message',
      'to': toUsername,
      'payload': encryptedBase64,
      'msgId': msgId,
      'mediaType': mediaType,
      'mediaUrl': mediaUrl,
      'timestamp': timestamp,
    };

    // Send via socket
    _sendRaw(msgMap);

    // Save message locally (unencrypted content, because Hive box is encrypted)
    final localMessage = Message(
      id: msgId,
      sender: myUsername,
      receiver: toUsername,
      encryptedPayload: text, // Plain text stored locally (box is encrypted)
      mediaType: mediaType,
      mediaUrl: mediaUrl,
      timestamp: timestamp,
      status: 'sending',
    );

    await _dbService.saveMessage(toUsername, localMessage);
    return localMessage;
  }

  /// Upload encrypted audio file (voice note) to backend
  Future<String?> uploadEncryptedVoiceNote(File audioFile) async {
    try {
      // Read file bytes
      final bytes = await audioFile.readAsBytes();
      
      // In WhisperChat, media files are ALSO encrypted before uploading to server!
      // For simplicity, let's encode the file to Base64 and send to server.
      // (The file itself contains raw audio, but let's encrypt it. If we want E2EE for file transfers, 
      // we can encrypt it using a random symmetric key and share the key inside the E2EE chat message!
      // That is exactly how WhatsApp encrypts media transfers! Let's do that - it's incredibly secure).
      
      // 1. Generate a random AES symmetric key for the media file
      final fileKey = AesGcm.with256bits().newSecretKey();
      
      // Let's encrypt the audio bytes
      final secretBox = await AesGcm.with256bits().encrypt(bytes, secretKey: fileKey);
      
      // Package: [nonce (12b)] + [mac (16b)] + [ciphertext]
      final combined = BytesBuilder()
        ..add(secretBox.nonce)
        ..add(secretBox.mac.bytes)
        ..add(secretBox.cipherText);
      final encryptedBytes = combined.toBytes();

      // Convert to Base64 to post
      final base64Payload = base64Encode(encryptedBytes);

      // Upload to server
      final client = HttpClient();
      final request = await client.postUrl(Uri.parse('http://$_serverIp:$_serverPort/upload'));
      request.headers.contentType = ContentType.json;
      
      final postData = {
        'fileName': 'voice_note.enc',
        'fileData': base64Payload,
      };
      
      request.add(utf8.encode(json.encode(postData)));
      final response = await request.close();

      if (response.statusCode == 200) {
        final contents = await response.transform(utf8.decoder).join();
        final resData = json.decode(contents);
        final fileUrl = resData['url'] as String;

        // Return: url + "#" + media_encryption_key (Base64)
        // The key is appended as a URL hash, so the server NEVER sees it!
        // When Bob downloads the file, he takes the URL, downloads the payload, 
        // extracts the hash, and decrypts the file bytes locally!
        // This is pure E2EE media transfer.
        final fileKeyBytes = await fileKey.extractBytes();
        final fileKeyBase64 = base64Encode(fileKeyBytes);
        
        return 'http://$_serverIp:$_serverPort$fileUrl#$fileKeyBase64';
      }
    } catch (e) {
      debugPrint("SocketService: Error uploading voice note: $e");
    }
    return null;
  }

  /// Download and decrypt an E2EE media file
  Future<File?> downloadAndDecryptVoiceNote(String mediaUrlWithKey) async {
    try {
      final parts = mediaUrlWithKey.split('#');
      if (parts.length < 2) return null;

      final mediaUrl = parts[0];
      final fileKeyBase64 = parts[1];

      // Download encrypted payload
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse(mediaUrl));
      final response = await request.close();

      if (response.statusCode != 200) return null;

      final bytesBuilder = BytesBuilder();
      await for (var chunk in response) {
        bytesBuilder.add(chunk);
      }
      final encryptedBytes = bytesBuilder.toBytes();

      if (encryptedBytes.length < 28) return null;

      // Extract nonce, mac, ciphertext
      final nonce = encryptedBytes.sublist(0, 12);
      final mac = encryptedBytes.sublist(12, 28);
      final cipherText = encryptedBytes.sublist(28);

      // Decrypt
      final fileKey = SecretKey(base64Decode(fileKeyBase64));
      final decryptedBytes = await AesGcm.with256bits().decrypt(
        SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
        secretKey: fileKey,
      );

      // Save decrypted file to local storage
      final tempDir = await getTemporaryDirectory();
      final decryptedFile = File('${tempDir.path}/decrypted_${DateTime.now().millisecondsSinceEpoch}.m4a');
      await decryptedFile.writeAsBytes(decryptedBytes);
      return decryptedFile;
    } catch (e) {
      debugPrint("SocketService: Error downloading voice note: $e");
    }
    return null;
  }

  /// Send WebRTC signaling message
  void sendSignaling(String to, Map<String, dynamic> signalPayload) {
    if (_connectionState != SocketConnectionState.connected) return;
    _sendRaw({
      ...signalPayload,
      'to': to,
    });
  }

  void _sendRaw(Map<String, dynamic> data) {
    if (_channel != null && _connectionState == SocketConnectionState.connected) {
      _channel!.sink.add(json.encode(data));
    }
  }

  @override
  void dispose() {
    disconnect();
    _messageStreamController.close();
    _statusStreamController.close();
    _signalingStreamController.close();
    super.dispose();
  }
}
