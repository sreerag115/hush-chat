import 'dart:developer';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    // 1. Request Permission
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    log('User notification permission status: ${settings.authorizationStatus}');

    // 2. Initialize Flutter Local Notifications for Foreground Notification Display
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        log('Local notification tapped: ${response.payload}');
      },
    );

    // Create Notification Channel for Android 8.0+
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'whisper_msg_channel', // id
      'Whisper Messages', // name
      description: 'Notifications for new E2EE messages on WhisperChat.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(channel);
    }

    // 3. Listen for foreground notifications
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      log('Foreground notification received: ${message.messageId}');
      _showLocalNotification(message);
    });

    // 4. Save/Sync FCM Token
    await syncFcmToken();

    _initialized = true;
  }

  Future<void> syncFcmToken() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final token = await _fcm.getToken();
      if (token != null) {
        log('My FCM Token: $token');
        await FirebaseFirestore.instance.collection('users').doc(uid).update({
          'fcmToken': token,
        });
      }
    } catch (e) {
      log('Error syncing FCM token: $e');
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final android = message.notification?.android;

    if (notification != null) {
      await _localNotifications.show(
        id: notification.hashCode,
        title: notification.title,
        body: notification.body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'whisper_msg_channel',
            'Whisper Messages',
            channelDescription: 'Notifications for new E2EE messages on WhisperChat.',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
        ),
        payload: message.data.toString(),
      );
    }
  }

  /// Show a manual local notification (used when E2EE messages are fetched via Firestore)
  Future<void> showManualNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    await _localNotifications.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'whisper_msg_channel',
          'Whisper Messages',
          channelDescription: 'Notifications for new E2EE messages on WhisperChat.',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }
}
