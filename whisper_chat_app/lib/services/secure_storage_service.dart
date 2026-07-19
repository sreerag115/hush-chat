import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

class SecureStorageService {
  static final SecureStorageService _instance = SecureStorageService._internal();
  factory SecureStorageService() => _instance;
  SecureStorageService._internal();

  final _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Keys
  static const String _keyPhoneNumber   = 'phone_number';
  static const String _keyUid           = 'firebase_uid';
  static const String _keyPrivateKey    = 'private_key';
  static const String _keyPublicKey     = 'public_key';
  static const String _keyHiveKey       = 'hive_encryption_key';
  static const String _keyDisplayName   = 'display_name';

  // Display Name
  Future<void> saveDisplayName(String name) async =>
      _secureStorage.write(key: _keyDisplayName, value: name);
  Future<String?> getDisplayName() async =>
      _secureStorage.read(key: _keyDisplayName);

  // Phone Number (e.g. "+919876543210")
  Future<void> savePhoneNumber(String phone) async =>
      _secureStorage.write(key: _keyPhoneNumber, value: phone);
  Future<String?> getPhoneNumber() async =>
      _secureStorage.read(key: _keyPhoneNumber);

  // Firebase UID
  Future<void> saveUid(String uid) async =>
      _secureStorage.write(key: _keyUid, value: uid);
  Future<String?> getUid() async =>
      _secureStorage.read(key: _keyUid);

  // E2EE Private Key (Curve25519, stays only on device)
  Future<void> savePrivateKey(String key) async =>
      _secureStorage.write(key: _keyPrivateKey, value: key);
  Future<String?> getPrivateKey() async =>
      _secureStorage.read(key: _keyPrivateKey);

  // E2EE Public Key (uploaded to Firestore so friends can encrypt messages to us)
  Future<void> savePublicKey(String key) async =>
      _secureStorage.write(key: _keyPublicKey, value: key);
  Future<String?> getPublicKey() async =>
      _secureStorage.read(key: _keyPublicKey);

  // Hive AES-256 encryption key for local database
  Future<List<int>> getOrCreateHiveEncryptionKey() async {
    final stored = await _secureStorage.read(key: _keyHiveKey);
    if (stored != null) return base64Decode(stored);
    final key = Hive.generateSecureKey();
    await _secureStorage.write(key: _keyHiveKey, value: base64Encode(key));
    return key;
  }

  Future<void> clearAll() async {
    await _secureStorage.delete(key: _keyPhoneNumber);
    await _secureStorage.delete(key: _keyUid);
    await _secureStorage.delete(key: _keyPrivateKey);
    await _secureStorage.delete(key: _keyPublicKey);
    await _secureStorage.delete(key: _keyDisplayName);
    // NOTE: We intentionally keep the Hive key so local data remains accessible
    // even after changing accounts (can clear separately if desired).
  }
}
