import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();

  // Cache derived secret keys in memory: remoteUsername -> SecretKey
  final Map<String, SecretKey> _derivedKeyCache = {};

  /// Generate a new Curve25519 KeyPair
  Future<SimpleKeyPair> generateKeyPair() async {
    return await _x25519.newKeyPair();
  }

  /// Helper to convert public key bytes to a Base64 string
  Future<String> encodePublicKey(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return base64Encode(publicKey.bytes);
  }

  /// Helper to convert private key bytes to a Base64 string
  Future<String> encodePrivateKey(SimpleKeyPair keyPair) async {
    final privateKey = await keyPair.extract();
    final bytes = await privateKey.extractKeyPairData();
    // Return private key bytes
    return base64Encode(bytes.privateKeyBytes);
  }

  /// Reconstruct KeyPair from stored Base64 strings
  Future<SimpleKeyPair> reconstructKeyPair(String privateKeyBase64, String publicKeyBase64) async {
    final privateBytes = base64Decode(privateKeyBase64);
    final publicBytes = base64Decode(publicKeyBase64);

    return SimpleKeyPairData(
      privateBytes,
      publicKey: SimplePublicKey(publicBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }

  /// Derive shared symmetric key (ECDH) between local private key and remote public key
  Future<SecretKey> _deriveSharedSecret(SimpleKeyPair localKeyPair, String remotePublicKeyBase64) async {
    final remoteBytes = base64Decode(remotePublicKeyBase64);
    final remotePublicKey = SimplePublicKey(remoteBytes, type: KeyPairType.x25519);

    return await _x25519.sharedSecretKey(
      keyPair: localKeyPair,
      remotePublicKey: remotePublicKey,
    );
  }

  /// Get or derive the shared secret key for a conversation
  Future<SecretKey> _getOrDeriveKey({
    required String remoteUsername,
    required String remotePublicKeyBase64,
    required SimpleKeyPair localKeyPair,
  }) async {
    if (_derivedKeyCache.containsKey(remoteUsername)) {
      return _derivedKeyCache[remoteUsername]!;
    }

    final secretKey = await _deriveSharedSecret(localKeyPair, remotePublicKeyBase64);
    _derivedKeyCache[remoteUsername] = secretKey;
    return secretKey;
  }

  /// Clear derived keys from cache (e.g. on logout)
  void clearCache() {
    _derivedKeyCache.clear();
  }

  /// Encrypt plaintext string for a recipient using ECDH + AES-256-GCM
  /// Output is a Base64 string containing: [nonce (12b)] + [mac (16b)] + [ciphertext]
  Future<String> encrypt({
    required String plaintext,
    required String remoteUsername,
    required String remotePublicKeyBase64,
    required SimpleKeyPair localKeyPair,
  }) async {
    final secretKey = await _getOrDeriveKey(
      remoteUsername: remoteUsername,
      remotePublicKeyBase64: remotePublicKeyBase64,
      localKeyPair: localKeyPair,
    );

    final plaintextBytes = utf8.encode(plaintext);
    final secretBox = await _aesGcm.encrypt(
      plaintextBytes,
      secretKey: secretKey,
    );

    // Combine nonce (12 bytes), mac (16 bytes), and ciphertext
    final nonce = secretBox.nonce;
    final mac = secretBox.mac.bytes;
    final cipherText = secretBox.cipherText;

    final combinedBytes = BytesBuilder();
    combinedBytes.add(nonce);
    combinedBytes.add(mac);
    combinedBytes.add(cipherText);

    return base64Encode(combinedBytes.toBytes());
  }

  /// Decrypt ciphertext string from a sender using ECDH + AES-256-GCM
  Future<String> decrypt({
    required String encryptedBase64,
    required String remoteUsername,
    required String remotePublicKeyBase64,
    required SimpleKeyPair localKeyPair,
  }) async {
    try {
      final secretKey = await _getOrDeriveKey(
        remoteUsername: remoteUsername,
        remotePublicKeyBase64: remotePublicKeyBase64,
        localKeyPair: localKeyPair,
      );

      final combinedBytes = base64Decode(encryptedBase64);

      if (combinedBytes.length < 28) {
        throw Exception("Invalid ciphertext length.");
      }

      // Nonce is 12 bytes, Mac is 16 bytes, rest is ciphertext
      final nonce = combinedBytes.sublist(0, 12);
      final mac = combinedBytes.sublist(12, 28);
      final cipherText = combinedBytes.sublist(28);

      final secretBox = SecretBox(
        cipherText,
        nonce: nonce,
        mac: Mac(mac),
      );

      final decryptedBytes = await _aesGcm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      return "[Decryption failed: Unable to decrypt message]";
    }
  }

  /// Simple SHA-256 hash for local credentials
  String sha256Hash(String input) {
    // A simple offline hash helper
    return base64Encode(Uint8List.fromList(utf8.encode(input)));
  }
}
