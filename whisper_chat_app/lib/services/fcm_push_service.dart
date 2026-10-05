import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';

/// Sends FCM push notifications directly from the sender's device.
/// Uses a Firebase service account to authenticate with the FCM v1 API.
/// This allows notifications to arrive even when the receiver's app is
/// completely killed / cleared from recents — no Cloud Functions needed.
class FcmPushService {
  static final FcmPushService _instance = FcmPushService._internal();
  factory FcmPushService() => _instance;
  FcmPushService._internal();

  ServiceAccountCredentials? _credentials;
  AutoRefreshingAuthClient? _authClient;
  String? _projectId;

  /// Load the service account credentials from the bundled asset
  Future<void> _ensureInitialized() async {
    if (_credentials != null && _authClient != null) return;

    try {
      final jsonStr = await rootBundle.loadString('assets/service-account.json');
      final jsonMap = json.decode(jsonStr) as Map<String, dynamic>;

      _projectId = jsonMap['project_id'] as String?;
      _credentials = ServiceAccountCredentials.fromJson(jsonMap);

      _authClient = await clientViaServiceAccount(
        _credentials!,
        ['https://www.googleapis.com/auth/firebase.messaging'],
      );

      debugPrint('✅ FCM Push Service initialized (project: $_projectId)');
    } catch (e) {
      debugPrint('⚠️ FCM Push Service init failed: $e');
      debugPrint('   Place your service-account.json in assets/ folder');
    }
  }

  /// Send a high-priority FCM push notification to a specific user.
  /// Looks up the receiver's FCM token from Firestore and sends the push.
  Future<void> sendPushNotification({
    required String receiverUid,
    required String senderPhone,
    required String mediaType,
  }) async {
    try {
      await _ensureInitialized();
      if (_authClient == null || _projectId == null) {
        debugPrint('⚠️ FCM Push: Not initialized, skipping push');
        return;
      }

      // Look up receiver's FCM token from Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(receiverUid)
          .get();

      if (!userDoc.exists) {
        debugPrint('⚠️ FCM Push: User $receiverUid not found');
        return;
      }

      final fcmToken = userDoc.data()?['fcmToken'] as String?;
      if (fcmToken == null || fcmToken.isEmpty) {
        debugPrint('⚠️ FCM Push: No FCM token for $receiverUid');
        return;
      }

      // Build notification body
      final notificationBody = mediaType == 'audio'
          ? '🎤 Voice Note'
          : 'New encrypted message';

      // Call FCM v1 API
      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send',
      );

      final payload = json.encode({
        'message': {
          'token': fcmToken,
          'notification': {
            'title': senderPhone,
            'body': notificationBody,
          },
          'android': {
            'priority': 'high',
            'notification': {
              'channel_id': 'whisper_msg_channel',
              'priority': 'MAX',
              'default_sound': true,
              'default_vibrate_timings': true,
            },
          },
          'data': {
            'type': 'new_message',
            'senderPhone': senderPhone,
          },
        },
      });

      final response = await _authClient!.post(url,
        headers: {'Content-Type': 'application/json'},
        body: payload,
      );

      if (response.statusCode == 200) {
        debugPrint('✅ FCM push sent to $receiverUid');
      } else {
        debugPrint('❌ FCM push failed (${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      debugPrint('❌ FCM push error: $e');
    }
  }
}
