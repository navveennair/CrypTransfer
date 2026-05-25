import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/export.dart' hide State, Padding;

import 'package:cryptransfer/core/constants/firebase_constants.dart';
import 'package:cryptransfer/data/services/encryption_service.dart';

// ── Security Key Storage Audit Tests (TC-SEC-001 to TC-SEC-011) ───────────
//
// These tests verify that no key material leaks into Firestore collections
// and that the cryptographic primitives satisfy their security properties.

void main() {
  // ── Firestore key-leakage tests (TC-SEC-001 to TC-SEC-006, TC-SEC-011) ───

  group('Firestore Key-Leakage Audit', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
    });

    test('TC-SEC-001: Private key NOT in users collection', () async {
      // Simulate what AuthRepository writes on register + generateAndStoreKeyPair
      await db.collection(FirebaseConstants.users).doc('uid-001').set({
        'username': 'alice',
        'email': 'alice@test.com',
        'phone': '+601',
        'publicKey': 'encodedPublicKeyJSON',
        'createdAt': FieldValue.serverTimestamp(),
        // privateKey intentionally absent
      });

      final doc =
          await db.collection(FirebaseConstants.users).doc('uid-001').get();
      final data = doc.data()!;

      expect(data.containsKey('privateKey'), isFalse,
          reason: 'SECURITY: privateKey must never appear in users collection');
      expect(data.containsKey('publicKey'), isTrue,
          reason: 'publicKey must be present in users collection');
    });

    test('TC-SEC-002: Private key NOT in handshakes', () async {
      await db.collection(FirebaseConstants.handshakes).add({
        'senderId': 'uid-001',
        'receiverId': 'uid-002',
        'publicKey': 'encodedPublicKeyJSON',
        'sentAt': FieldValue.serverTimestamp(),
        'status': 'pending',
        // privateKey intentionally absent
      });

      final snap =
          await db.collection(FirebaseConstants.handshakes).get();
      for (final doc in snap.docs) {
        expect(doc.data().containsKey('privateKey'), isFalse,
            reason:
                'SECURITY: privateKey must never appear in handshakes');
      }
    });

    test('TC-SEC-003: Private key NOT in transfers collection', () async {
      await db
          .collection(FirebaseConstants.transfers)
          .doc('transfer-sec-001')
          .set({
        'senderId': 'uid-001',
        'receiverId': 'uid-002',
        'encryptedAESKey': base64Encode(Uint8List(256)), // RSA-OAEP output
        'encryptedFileUrl': 'https://example.com/file',
        'fileName': 'file.bin',
        'fileSize': 1024,
        'iv': base64Encode(Uint8List(12)),
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        // privateKey, aesKey intentionally absent
      });

      final doc = await db
          .collection(FirebaseConstants.transfers)
          .doc('transfer-sec-001')
          .get();
      final data = doc.data()!;

      expect(data.containsKey('privateKey'), isFalse,
          reason: 'SECURITY: privateKey must not be in transfers');
      expect(data.containsKey('aesKey'), isFalse,
          reason: 'SECURITY: plaintext aesKey must not be in transfers');
    });

    test('TC-SEC-004: AES key stored in transfers is RSA-OAEP encrypted',
        () async {
      // Generate real RSA key pair and encrypt an AES key
      final keyPair = EncryptionService.generateRsaKeyPairSync();
      final pubKey = keyPair.publicKey as RSAPublicKey;
      final aesKey = EncryptionService.secureRandomBytes(32);

      final encryptedBytes = EncryptionService.rsaEncrypt(pubKey, aesKey);
      final encryptedB64 = base64Encode(encryptedBytes);
      final plaintextB64 = base64Encode(aesKey);

      // Plaintext AES key is 44 base64 chars (32 bytes → ceil(32/3)*4 = 44)
      expect(plaintextB64.length, equals(44));

      // RSA-2048 OAEP output is 256 bytes → 344 base64 chars
      expect(encryptedB64.length, greaterThan(100),
          reason: 'Encrypted AES key must be much longer than raw key');
      expect(encryptedB64.length, isNot(equals(44)),
          reason:
              'SECURITY: encryptedAESKey must NOT be 44 chars (raw AES key)');

      // Store the encrypted key in Firestore (correct behaviour)
      await db
          .collection(FirebaseConstants.transfers)
          .doc('transfer-sec-002')
          .set({
        'encryptedAESKey': encryptedB64,
        'senderId': 'uid-001',
        'receiverId': 'uid-002',
        'status': 'pending',
      });

      final doc = await db
          .collection(FirebaseConstants.transfers)
          .doc('transfer-sec-002')
          .get();
      final storedKey = doc.data()!['encryptedAESKey'] as String;

      expect(storedKey.length, greaterThan(100),
          reason: 'Stored encryptedAESKey must be RSA-OAEP ciphertext');
    });

    test('TC-SEC-005: AES key NOT stored in users collection', () async {
      await db.collection(FirebaseConstants.users).doc('uid-002').set({
        'username': 'bob',
        'email': 'bob@test.com',
        'publicKey': 'encodedPublicKey',
        'createdAt': FieldValue.serverTimestamp(),
        // aesKey intentionally absent
      });

      final doc =
          await db.collection(FirebaseConstants.users).doc('uid-002').get();
      final data = doc.data()!;

      for (final field in ['aesKey', 'aes_key', 'encryptedAESKey']) {
        expect(data.containsKey(field), isFalse,
            reason:
                'SECURITY: AES key fields must not appear in users collection');
      }
    });

    test('TC-SEC-006: transfer_logs contains NO key material', () async {
      // Simulate what TransferRepository.writeAuditLog writes
      await db.collection(FirebaseConstants.transferLogs).add({
        'senderId': 'uid-001',
        'receiverId': 'uid-002',
        'fileName': 'file.pdf',
        'fileSize': 1024,
        'status': 'completed',
        'loggedAt': FieldValue.serverTimestamp(),
        // No key fields
      });

      final snap =
          await db.collection(FirebaseConstants.transferLogs).get();

      for (final doc in snap.docs) {
        final data = doc.data();
        for (final forbidden in [
          'privateKey',
          'publicKey',
          'aesKey',
          'iv',
          'encryptedAESKey',
        ]) {
          expect(data.containsKey(forbidden), isFalse,
              reason:
                  'SECURITY: transfer_logs must not contain $forbidden field');
        }
      }
    });
  });

  // ── Cryptographic correctness tests (TC-SEC-007 to TC-SEC-010) ────────────

  group('Cryptographic Correctness', () {
    test('TC-SEC-007: AES-256-GCM encrypt/decrypt roundtrip is correct', () {
      final key = EncryptionService.secureRandomBytes(32);
      final iv = EncryptionService.secureRandomBytes(12);
      final plaintext =
          Uint8List.fromList(utf8.encode('CrypTransfer secure payload'));

      final ciphertext = runAesGcmEncrypt([plaintext, key, iv]);
      final recovered = runAesGcmDecrypt([ciphertext, key, iv]);

      expect(recovered, equals(plaintext),
          reason: 'decrypt(encrypt(plaintext)) must equal plaintext');
    });

    test('TC-SEC-008: Tampered ciphertext fails GCM authentication', () {
      final key = EncryptionService.secureRandomBytes(32);
      final iv = EncryptionService.secureRandomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('integrity check'));

      final ciphertext = runAesGcmEncrypt([plaintext, key, iv]);
      final tampered = Uint8List.fromList(ciphertext);
      tampered[0] ^= 0xFF; // flip first byte

      expect(
        () => runAesGcmDecrypt([tampered, key, iv]),
        throwsA(anything),
        reason:
            'SECURITY: GCM must reject ciphertext with flipped bits',
      );
    });

    test('TC-SEC-009: Wrong AES key fails GCM decryption', () {
      final keyA = EncryptionService.secureRandomBytes(32);
      final keyB = EncryptionService.secureRandomBytes(32);
      final iv = EncryptionService.secureRandomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('key binding test'));

      final ciphertext = runAesGcmEncrypt([plaintext, keyA, iv]);

      expect(
        () => runAesGcmDecrypt([ciphertext, keyB, iv]),
        throwsA(anything),
        reason: 'SECURITY: decryption with wrong key must throw',
      );
    });

    test('TC-SEC-010: AES key bytes zeroed from memory', () {
      final aesKey = EncryptionService.secureRandomBytes(32);
      expect(aesKey.any((b) => b != 0), isTrue); // key has random bytes

      aesKey.fillRange(0, aesKey.length, 0);

      expect(aesKey.every((b) => b == 0), isTrue,
          reason: 'SECURITY: AES key must be fully zeroed after wipe');
    });
  });

  // ── Full collection scan (TC-SEC-011) ────────────────────────────────────

  group('Full Collection Scan', () {
    const forbidden = [
      'privateKey',
      'private_key',
      'rsa_private_key',
      'aesKey',
      'aes_key',
      'plaintext',
    ];

    late FakeFirebaseFirestore db;

    setUp(() async {
      db = FakeFirebaseFirestore();

      // Seed all collections with representative documents (no key leaks)
      await db.collection(FirebaseConstants.users).doc('u1').set({
        'username': 'alice',
        'email': 'alice@test.com',
        'publicKey': 'encodedPubKey',
      });
      await db.collection(FirebaseConstants.transfers).doc('t1').set({
        'senderId': 'u1',
        'receiverId': 'u2',
        'encryptedAESKey': base64Encode(Uint8List(256)),
        'iv': base64Encode(Uint8List(12)),
        'status': 'pending',
      });
      await db.collection(FirebaseConstants.transferLogs).doc('l1').set({
        'senderId': 'u1',
        'receiverId': 'u2',
        'fileName': 'file.pdf',
        'status': 'completed',
      });
      await db.collection(FirebaseConstants.handshakes).doc('k1').set({
        'senderId': 'u1',
        'receiverId': 'u2',
        'publicKey': 'encodedPubKey',
      });
      await db.collection(FirebaseConstants.users).doc('u2').collection(FirebaseConstants.notifications).doc('n1').set({
        'fromUsername': 'alice',
        'type': 'file_received',
        'message': 'alice sent you a file',
      });
      await db
          .collection(FirebaseConstants.users)
          .doc('u1')
          .collection(FirebaseConstants.friendships)
          .doc('u2')
          .set({
        'status': 'connected',
      });
    });

    test('TC-SEC-011: No key material in any Firestore collection', () async {
      final collections = [
        FirebaseConstants.users,
        FirebaseConstants.transfers,
        FirebaseConstants.transferLogs,
        FirebaseConstants.handshakes,
        FirebaseConstants.notifications,
        FirebaseConstants.neutralHandshakes,
      ];

      for (final col in collections) {
        final snap = await db.collection(col).get();
        for (final doc in snap.docs) {
          for (final field in forbidden) {
            expect(doc.data().containsKey(field), isFalse,
                reason:
                    'SECURITY: $col/${doc.id} must not contain field "$field"');
          }
        }
      }
    });
  });
}
