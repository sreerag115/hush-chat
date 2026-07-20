import 'package:firebase_core/firebase_core.dart' show Firebase, FirebaseOptions;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'services/database_service.dart';
import 'services/firebase_service.dart';
import 'services/secure_storage_service.dart';
import 'services/webrtc_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/call_screen.dart';

/// Top-level background message handler for FCM.
/// This MUST be a top-level function (not a class method).
/// It runs in a separate isolate when the app is killed/background.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized in the background isolate
  await Firebase.initializeApp();
  debugPrint('🔔 Background FCM message received: ${message.messageId}');
  // The notification payload (title/body) from the Cloud Function
  // is automatically displayed by Android's system notification tray.
  // No additional code needed here — Android handles it natively.
}

// Call runApp() FIRST — no awaits before this.
// Everything initializes inside the widget tree using FutureBuilder.
void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Register the background message handler BEFORE runApp
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  final webrtcService = WebRtcService();
  final firebaseService = FirebaseService();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<FirebaseService>.value(value: firebaseService),
        ChangeNotifierProvider<WebRtcService>.value(value: webrtcService),
      ],
      child: HushApp(
        webrtcService: webrtcService,
        firebaseService: firebaseService,
      ),
    ),
  );
}

Future<String> _initializeApp() async {
  // Small delay to ensure platform channels are fully ready after runApp()
  await Future.delayed(const Duration(milliseconds: 300));

  String firebaseResult = 'not_tried';

  // Try without options first (native auto-init from google-services.json)
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
      firebaseResult = 'success_no_options';
    } else {
      firebaseResult = 'already_initialized';
    }
  } catch (e1) {
    firebaseResult = 'no_options_failed: $e1';
    // Fallback: try with explicit options
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        firebaseResult = 'success_with_options';
      }
    } catch (e2) {
      firebaseResult = 'both_failed: $e2';
    }
  }

  debugPrint('🔥 Firebase init result: $firebaseResult');

  // Local Hive DB
  try {
    await DatabaseService().init();
  } catch (e) {
    debugPrint('DB init: $e');
  }

  return firebaseResult;
}

class HushApp extends StatelessWidget {
  final WebRtcService webrtcService;
  final FirebaseService firebaseService;

  const HushApp({
    super.key,
    required this.webrtcService,
    required this.firebaseService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hush',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: FutureBuilder<String>(
        future: _initializeApp(),
        builder: (context, snapshot) {
          // Show splash while initializing
          if (!snapshot.hasData) {
            return const _SplashScreen();
          }
          final firebaseResult = snapshot.data ?? 'unknown';
          final firebaseOk = firebaseResult.startsWith('success') ||
              firebaseResult == 'already_initialized';
          // Initialization complete — show main app
          return _MainShell(
            webrtcService: webrtcService,
            firebaseService: firebaseService,
            firebaseInitResult: firebaseResult,
            firebaseReady: firebaseOk,
          );
        },
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      fontFamily: 'sans-serif',
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFD8B48C),
        secondary: Color(0xFF8FA1AE),
        surface: Color(0xFF171B30),
        background: Color(0xFF0E1120),
        error: Color(0xFFEF4444),
      ),
      scaffoldBackgroundColor: const Color(0xFF0E1120),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E1120),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: 'serif',
          fontWeight: FontWeight.bold,
          fontSize: 22,
          color: Colors.white,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: Color(0xFFD8B48C)),
      ),
      cardTheme: CardThemeData(
        color: const Color(0xFF171B30),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF171B30),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white10),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD8B48C), width: 1.5),
        ),
        labelStyle: const TextStyle(color: Color(0xFF8FA1AE)),
        hintStyle: const TextStyle(color: Colors.white30),
      ),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0E1120),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Image.asset(
                'assets/images/logo.png',
                width: 130,
                height: 130,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 28),
            const Text(
              'WhisperChat',
              style: TextStyle(
                fontFamily: 'serif',
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD8B48C),
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Chat Privately. Connect Securely.',
              style: TextStyle(
                color: Color(0xFF8FA1AE),
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 54),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFD8B48C),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainShell extends StatefulWidget {
  final WebRtcService webrtcService;
  final FirebaseService firebaseService;
  final String firebaseInitResult;
  final bool firebaseReady;

  const _MainShell({
    required this.webrtcService,
    required this.firebaseService,
    required this.firebaseInitResult,
    required this.firebaseReady,
  });

  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  bool _isLoggedIn = false;

  @override
  void initState() {
    super.initState();
    _checkLoginAndInit();
  }

  Future<void> _checkLoginAndInit() async {
    // Check login state
    final secureStorage = SecureStorageService();
    final uid = await secureStorage.getUid();
    final hasKeys = await secureStorage.getPrivateKey() != null;
    bool firebaseReady = false;
    try {
      firebaseReady = Firebase.apps.isNotEmpty;
    } catch (_) {}
    final loggedIn = firebaseReady &&
        widget.firebaseService.currentUser != null &&
        uid != null &&
        hasKeys;

    if (mounted) setState(() => _isLoggedIn = loggedIn);

    // Init WebRTC after UI is shown
    try {
      await widget.webrtcService.init();
    } catch (e) {
      debugPrint('WebRTC: $e');
    }

    // Sync if logged in
    if (loggedIn) {
      try {
        await widget.firebaseService.setPresence(true);
        await widget.firebaseService.syncContacts();
      } catch (e) {
        debugPrint('Sync: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: _isLoggedIn ? const HomeScreen() : const LoginScreen(),
          ),
          Positioned.fill(
            child: Consumer<WebRtcService>(
              builder: (context, webrtc, _) {
                if (webrtc.callState != CallState.idle) {
                  return const CallScreen();
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}