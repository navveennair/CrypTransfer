import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart' hide State, Padding;

import '../../core/errors/app_exceptions.dart';

// ─── Top-level isolate functions ──────────────────────────────────────────────
// These must be top-level (not instance methods) for Flutter's compute().

Uint8List runAesGcmEncrypt(List<Uint8List> args) {
  final plaintext = args[0];
  final key = args[1]; // 32 bytes
  final iv = args[2]; // 12 bytes
  final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
  final cipher = GCMBlockCipher(AESEngine())..init(true, params);
  return cipher.process(plaintext);
}

Uint8List runAesGcmDecrypt(List<Uint8List> args) {
  final ciphertext = args[0]; // ciphertext + 16-byte GCM tag
  final key = args[1]; // 32 bytes
  final iv = args[2]; // 12 bytes
  final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
  final cipher = GCMBlockCipher(AESEngine())..init(false, params);
  return cipher.process(ciphertext);
}

// ─── Result type for AES encryption ──────────────────────────────────────────

class AesEncryptResult {
  final Uint8List ciphertext;
  final Uint8List key;
  final Uint8List iv;

  const AesEncryptResult({
    required this.ciphertext,
    required this.key,
    required this.iv,
  });
}

// ─── EncryptionService ────────────────────────────────────────────────────────

class EncryptionService {
  const EncryptionService._();

  // ─── Secure random ──────────────────────────────────────────────────────

  static Uint8List secureRandomBytes(int length) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => rng.nextInt(256)));
  }

  // ─── AES-256-GCM ────────────────────────────────────────────────────────

  /// Generates a fresh 256-bit AES key + 96-bit IV, then encrypts [plaintext]
  /// via AES-256-GCM in a compute() isolate.
  static Future<AesEncryptResult> encryptAesGcm(Uint8List plaintext) async {
    try {
      final key = secureRandomBytes(32);
      final iv = secureRandomBytes(12);
      final ciphertext = await compute(runAesGcmEncrypt, [plaintext, key, iv]);
      return AesEncryptResult(ciphertext: ciphertext, key: key, iv: iv);
    } catch (e) {
      throw CryptoException('AES encryption failed: $e');
    }
  }

  /// Decrypts [ciphertext] (with GCM tag) using [key] and [iv] in a
  /// compute() isolate.
  static Future<Uint8List> decryptAesGcm(
    Uint8List ciphertext,
    Uint8List key,
    Uint8List iv,
  ) async {
    try {
      return await compute(runAesGcmDecrypt, [ciphertext, key, iv]);
    } catch (e) {
      throw CryptoException('AES decryption failed: $e');
    }
  }

  // ─── RSA key generation ──────────────────────────────────────────────────

  /// Generates a 2048-bit RSA key pair. Runs on the calling isolate
  /// (caller should wrap in compute() if called from UI).
  static AsymmetricKeyPair<PublicKey, PrivateKey> generateRsaKeyPairSync() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    secureRandom.seed(
      KeyParameter(
        Uint8List.fromList(
          List<int>.generate(32, (_) => seedSource.nextInt(256)),
        ),
      ),
    );

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          secureRandom,
        ),
      );
    return keyGen.generateKeyPair();
  }

  // ─── RSA key encode / decode ─────────────────────────────────────────────

  static String encodePublicKey(RSAPublicKey key) => jsonEncode({
        'modulus': key.modulus!.toRadixString(16),
        'exponent': key.publicExponent!.toRadixString(16),
      });

  static String encodePrivateKey(RSAPrivateKey key) => jsonEncode({
        'modulus': key.modulus!.toRadixString(16),
        'privateExponent': key.privateExponent!.toRadixString(16),
        'p': key.p!.toRadixString(16),
        'q': key.q!.toRadixString(16),
      });

  static RSAPublicKey decodePublicKey(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return RSAPublicKey(
        BigInt.parse(map['modulus'] as String, radix: 16),
        BigInt.parse(map['exponent'] as String, radix: 16),
      );
    } catch (e) {
      throw CryptoException('Failed to decode public key: $e');
    }
  }

  static RSAPrivateKey decodePrivateKey(String json) {
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      return RSAPrivateKey(
        BigInt.parse(map['modulus'] as String, radix: 16),
        BigInt.parse(map['privateExponent'] as String, radix: 16),
        BigInt.parse(map['p'] as String, radix: 16),
        BigInt.parse(map['q'] as String, radix: 16),
      );
    } catch (e) {
      throw CryptoException('Failed to decode private key: $e');
    }
  }

  // ─── RSA-OAEP encrypt / decrypt ──────────────────────────────────────────

  /// RSA-OAEP encrypts [data] with [publicKey]. Used by the sender to wrap
  /// the AES session key.
  static Uint8List rsaEncrypt(RSAPublicKey publicKey, Uint8List data) {
    try {
      final cipher = OAEPEncoding(RSAEngine())
        ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
      return cipher.process(data);
    } catch (e) {
      throw CryptoException('RSA encryption failed: $e');
    }
  }

  /// RSA-OAEP decrypts [ciphertext] with [privateKey]. Used by the receiver
  /// to recover the AES session key.
  static Uint8List rsaDecrypt(RSAPrivateKey privateKey, Uint8List ciphertext) {
    try {
      final cipher = OAEPEncoding(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
      return cipher.process(ciphertext);
    } catch (e) {
      throw CryptoException('RSA decryption failed: $e');
    }
  }

  // ─── Convenience: decrypt AES key from private key JSON string ───────────

  /// Decodes the private key JSON then RSA-OAEP decrypts [encryptedAesKey].
  /// Convenience wrapper used by DecryptScreen.
  static Uint8List decryptAesKeyWithPrivateKeyJson(
    String privateKeyJson,
    Uint8List encryptedAesKey,
  ) {
    final privateKey = decodePrivateKey(privateKeyJson);
    return rsaDecrypt(privateKey, encryptedAesKey);
  }
}
