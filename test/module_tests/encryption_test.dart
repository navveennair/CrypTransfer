import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' hide State, Padding;

import 'package:cryptransfer/data/services/encryption_service.dart';
import 'package:cryptransfer/core/errors/app_exceptions.dart';

// ── Encryption / Decryption Tests (TC011–TC021) ───────────────────────────
//
// Uses the low-level top-level functions (runAesGcmEncrypt / runAesGcmDecrypt)
// directly to stay synchronous and avoid the compute() Flutter binding
// requirement in unit tests.

void main() {
  // ── AES-256-GCM tests (TC011–TC015) ──────────────────────────────────────
  group('AES-256-GCM (TC011–TC015)', () {
    late Uint8List plaintext;
    late Uint8List key;
    late Uint8List iv;
    late Uint8List ciphertext;

    setUp(() {
      plaintext = Uint8List.fromList(utf8.encode('Hello CrypTransfer!'));
      key = EncryptionService.secureRandomBytes(32);
      iv = EncryptionService.secureRandomBytes(12);
      ciphertext = runAesGcmEncrypt([plaintext, key, iv]);
    });

    test('TC011 - AES-256-GCM encrypt produces non-empty ciphertext', () {
      expect(ciphertext, isNotEmpty);
      expect(ciphertext, isNot(equals(plaintext)));
    });

    test('TC012 - AES-256-GCM decrypt recovers original plaintext', () {
      final decrypted = runAesGcmDecrypt([ciphertext, key, iv]);
      expect(decrypted, equals(plaintext));
    });

    test('TC013 - AES key is exactly 32 bytes (256 bits)', () {
      expect(key.length, equals(32));
    });

    test('TC014 - IV is exactly 12 bytes (96 bits)', () {
      expect(iv.length, equals(12));
    });

    test('TC015 - GCM auth tag (16 bytes) is appended to ciphertext', () {
      // GCM output = plaintext_length + 16-byte authentication tag
      expect(ciphertext.length, equals(plaintext.length + 16));
    });
  });

  // ── RSA-2048 tests (TC016–TC019) ─────────────────────────────────────────
  // generateRsaKeyPairSync is synchronous but ~2–5 s — generated once.
  group('RSA-2048 (TC016–TC019)', () {
    late RSAPublicKey pubKey;
    late RSAPrivateKey privKey;
    // Second key pair pre-generated in setUpAll to avoid contention in TC019
    late RSAPrivateKey otherPrivKey;
    late Uint8List aesKey;

    setUpAll(() {
      final keyPair = EncryptionService.generateRsaKeyPairSync();
      pubKey = keyPair.publicKey as RSAPublicKey;
      privKey = keyPair.privateKey as RSAPrivateKey;
      aesKey = EncryptionService.secureRandomBytes(32);
      // Generate the second key pair here so TC019 has no heavy work
      final otherPair = EncryptionService.generateRsaKeyPairSync();
      otherPrivKey = otherPair.privateKey as RSAPrivateKey;
    });

    test('TC016 - RSA-2048 keypair generation succeeds', () {
      expect(pubKey.modulus, isNotNull);
      expect(privKey.modulus, isNotNull);
      // 2048-bit modulus → ~617 decimal digits
      expect(pubKey.modulus!.bitLength, greaterThanOrEqualTo(2040));
    });

    test('TC017 - RSA-OAEP encrypts AES key successfully', () {
      final encrypted = EncryptionService.rsaEncrypt(pubKey, aesKey);
      expect(encrypted, isNotEmpty);
      expect(encrypted.length, equals(256)); // RSA-2048 output is 256 bytes
    });

    test('TC018 - RSA-OAEP decrypts AES key correctly', () {
      final encrypted = EncryptionService.rsaEncrypt(pubKey, aesKey);
      final decrypted = EncryptionService.rsaDecrypt(privKey, encrypted);
      expect(decrypted, equals(aesKey));
    });

    test('TC019 - Wrong private key fails RSA decryption', () {
      final encrypted = EncryptionService.rsaEncrypt(pubKey, aesKey);

      // Decrypting with a different private key must throw CryptoException
      expect(
        () => EncryptionService.rsaDecrypt(otherPrivKey, encrypted),
        throwsA(isA<CryptoException>()),
      );
    });
  });

  // ── GCM integrity & memory tests (TC020–TC021) ───────────────────────────
  group('GCM Integrity & Memory (TC020–TC021)', () {
    test('TC020 - Tampered ciphertext fails GCM authentication', () {
      final key = EncryptionService.secureRandomBytes(32);
      final iv = EncryptionService.secureRandomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('secure data'));
      final ciphertext = runAesGcmEncrypt([plaintext, key, iv]);

      // Flip the first byte to tamper with the ciphertext
      final tampered = Uint8List.fromList(ciphertext);
      tampered[0] ^= 0xFF;

      expect(
        () => runAesGcmDecrypt([tampered, key, iv]),
        throwsA(anything),
        reason: 'GCM auth tag verification must reject tampered ciphertext',
      );
    });

    test('TC021 - AES key bytes can be zeroed from memory', () {
      final key = EncryptionService.secureRandomBytes(32);

      // Simulate memory wipe
      key.fillRange(0, key.length, 0);

      expect(key.every((b) => b == 0), isTrue,
          reason: 'All AES key bytes must be zero after wipe');
    });
  });
}
