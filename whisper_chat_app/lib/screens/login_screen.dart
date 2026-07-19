import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/crypto_service.dart';
import '../services/firebase_service.dart';
import '../services/secure_storage_service.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController(text: '+91');
  final _otpCtrl = TextEditingController();

  String? _verificationId;
  bool _isLoading = false;
  String _loadingMsg = '';
  String _step = 'phone'; // 'phone' | 'otp' | 'keys'

  void _sendOtp() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.length < 8) {
      _showError('Please enter a valid phone number with country code (e.g. +91...)');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMsg = 'Sending verification code...';
    });

    try {
      final firebase = Provider.of<FirebaseService>(context, listen: false);
      await firebase.sendOtp(
        phone,
        onCodeSent: (verificationId) {
          setState(() {
            _verificationId = verificationId;
            _isLoading = false;
            _step = 'otp';
          });
        },
        onError: (e) {
          setState(() => _isLoading = false);
          _showError('Failed to send OTP: ${e.message}');
        },
      );
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error: $e');
    }
  }

  void _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      _showError('Enter the 6-digit code sent to you.');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMsg = 'Verifying code...';
    });

    try {
      final firebase = Provider.of<FirebaseService>(context, listen: false);
      await firebase.verifyOtp(_verificationId!, otp);

      setState(() => _loadingMsg = 'Generating secure E2EE keys...');

      // Generate Curve25519 keypair
      final crypto = CryptoService();
      final keyPair = await crypto.generateKeyPair();
      final privateKey = await crypto.encodePrivateKey(keyPair);
      final publicKey = await crypto.encodePublicKey(keyPair);

      // Save keys locally (device Keystore)
      final storage = SecureStorageService();
      await storage.savePrivateKey(privateKey);
      await storage.savePublicKey(publicKey);

      setState(() => _loadingMsg = 'Registering on Whisper Network...');

      // Register on Firestore
      final phone = _phoneCtrl.text.trim();
      await firebase.registerProfile(
        phoneNumber: phone,
        publicKeyBase64: publicKey,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      _showError('Invalid code: ${e.message}');
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Error: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1120),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(32),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 110,
                  height: 110,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'WhisperChat',
                style: TextStyle(
                  fontFamily: 'serif',
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFD8B48C),
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Chat Privately. Connect Securely.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8FA1AE),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 48),

              // Card
              Card(
                color: const Color(0xFF171B30),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: Colors.white.withOpacity(0.05)),
                ),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _isLoading
                      ? _buildLoading()
                      : _step == 'phone'
                          ? _buildPhoneStep(theme)
                          : _buildOtpStep(theme),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Column(
      children: [
        SizedBox(height: 8),
        CircularProgressIndicator(color: Color(0xFFD8B48C)),
        SizedBox(height: 24),
        Text('Loading...', style: TextStyle(color: Colors.white70, fontSize: 13)),
        SizedBox(height: 8),
      ],
    );
  }

  Widget _buildPhoneStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter Your Phone Number',
          style: TextStyle(fontFamily: 'serif', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          'We will send you a one-time verification code via SMS.',
          style: TextStyle(fontSize: 12, color: Color(0xFF8FA1AE)),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          style: const TextStyle(fontSize: 18, letterSpacing: 1, color: Colors.white),
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.phone, color: Color(0xFF8FA1AE)),
            labelText: 'Phone Number',
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _sendOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD8B48C),
            foregroundColor: const Color(0xFF0E1120),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: const Text(
            'Send Verification Code',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter Verification Code',
          style: TextStyle(fontFamily: 'serif', fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'A 6-digit code has been sent to ${_phoneCtrl.text.trim()}.',
          style: const TextStyle(fontSize: 12, color: Color(0xFF8FA1AE)),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, letterSpacing: 8, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
          decoration: const InputDecoration(
            counterText: '',
            hintText: '------',
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _verifyOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFD8B48C),
            foregroundColor: const Color(0xFF0E1120),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
          child: const Text(
            'Verify & Sign In',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _step = 'phone'),
          child: const Text('Change Number', style: TextStyle(color: Color(0xFF8FA1AE))),
        ),
      ],
    );
  }
}
