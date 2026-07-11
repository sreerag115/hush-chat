import 'package:firebase_core/firebase_core.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize local encrypted database
  await DatabaseService().init();

  // Initialize WebRTC renderers
  final webrtcService = WebRtcService();
  await webrtcService.init();

  // Check if user is already logged in (Firebase + local keys)
  final secureStorage = SecureStorageService();
  final uid = await secureStorage.getUid();
  final hasKeys = await secureStorage.getPrivateKey() != null;

  // If logged in via Firebase AND has local E2EE keys, go home
  final firebase = FirebaseService();
  final isFullyLoggedIn = firebase.currentUser != null && uid != null && hasKeys;

  if (isFullyLoggedIn) {
    await firebase.setPresence(true);
    await firebase.syncContacts();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<FirebaseService>.value(value: firebase),
        ChangeNotifierProvider<WebRtcService>.value(value: webrtcService),
      ],
      child: WhisperApp(isLoggedIn: isFullyLoggedIn),
    ),
  );
}

class WhisperApp extends StatelessWidget {
  final bool isLoggedIn;
  const WhisperApp({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WhisperChat',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: Scaffold(
        body: Stack(
          children: [
            isLoggedIn ? const HomeScreen() : const LoginScreen(),
            // Global call overlay — appears over any screen when a call is ringing or active
            Consumer<WebRtcService>(
              builder: (context, webrtc, _) {
                if (webrtc.callState != CallState.idle) {
                  return const CallScreen();
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6366F1),     // Indigo 500
        secondary: Color(0xFF14B8A6),   // Teal 500
        surface: Color(0xFF0F172A),     // Slate 900
        background: Color(0xFF020617), // Slate 950
        error: Color(0xFFEF4444),
      ),
      scaffoldBackgroundColor: const Color(0xFF020617),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F172A),
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 20,
          color: Colors.white,
        ),
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 4,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E293B),
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
          borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
        ),
      ),
    );
  }
}
