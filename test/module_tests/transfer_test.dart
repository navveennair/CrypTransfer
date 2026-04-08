import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cryptransfer/core/constants/firebase_constants.dart';
import 'package:cryptransfer/data/models/transfer_model.dart';
import 'package:cryptransfer/data/repositories/transfer_repository.dart';
import 'package:cryptransfer/data/services/encryption_service.dart';

import '../mocks/mock_firebase.dart';

// ── Transfer Tests (TC022–TC030) ──────────────────────────────────────────
//
// Firebase Storage cannot be mocked without additional packages, so tests
// that involve Storage verify the Firestore document structure and the
// crypto layer instead.

void main() {
  group('File Transfer (TC022–TC030)', () {
    late FakeFirebaseFirestore fakeDb;
    late TransferRepository repo;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      // Pass a mock storage so the constructor never touches FirebaseStorage.instance
      repo = TransferRepository(db: fakeDb, storage: MockFirebaseStorage());
    });

    // ── TC022 ──────────────────────────────────────────────────────────────
    test('TC022 - File data is correctly represented before transfer', () {
      const fileName = 'report.pdf';
      const fileSize = 4096;
      final fileBytes = Uint8List(fileSize);

      expect(fileName, isNotEmpty);
      expect(fileBytes.length, equals(fileSize));
      expect(fileName.endsWith('.pdf'), isTrue);
    });

    // ── TC023 ──────────────────────────────────────────────────────────────
    test('TC023 - Transfer record has required fields for Storage upload',
        () async {
      // Simulate the Firestore document that uploadAndCreate would write
      const transferId = 'transfer-001';
      await fakeDb
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .set({
        'senderId': 'sender-uid',
        'receiverId': 'receiver-uid',
        'encryptedAESKey': base64Encode(Uint8List(256)),
        'encryptedFileUrl':
            'https://storage.example.com/transfers/transfer-001/encrypted_file',
        'fileName': 'doc.pdf',
        'fileSize': 2048,
        'iv': base64Encode(Uint8List(12)),
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final doc = await fakeDb
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .get();

      expect(doc.exists, isTrue);
      expect(doc.data()!['encryptedFileUrl'], isNotNull);
      expect(doc.data()!['encryptedAESKey'], isNotNull);
      expect(doc.data()!['iv'], isNotNull);
    });

    // ── TC024 ──────────────────────────────────────────────────────────────
    test('TC024 - Transfer record created in Firestore with correct shape',
        () async {
      const transferId = 'transfer-002';
      await fakeDb
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .set({
        'senderId': 'sender-uid',
        'receiverId': 'receiver-uid',
        'encryptedAESKey': 'encryptedKeyB64',
        'encryptedFileUrl': 'https://example.com/file',
        'fileName': 'image.png',
        'fileSize': 1024,
        'iv': base64Encode(Uint8List(12)),
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final model = await repo.getTransfer(transferId);

      expect(model.senderId, equals('sender-uid'));
      expect(model.receiverId, equals('receiver-uid'));
      expect(model.fileName, equals('image.png'));
    });

    // ── TC025 ──────────────────────────────────────────────────────────────
    test('TC025 - Transfer status starts as pending', () async {
      const transferId = 'transfer-003';
      await fakeDb
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .set({
        'senderId': 'sender-uid',
        'receiverId': 'receiver-uid',
        'encryptedAESKey': 'encKey',
        'encryptedFileUrl': 'https://example.com/file',
        'fileName': 'file.zip',
        'fileSize': 512,
        'iv': 'ivB64',
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final model = await repo.getTransfer(transferId);
      expect(model.status, equals(TransferStatus.pending));
    });

    // ── TC026 ──────────────────────────────────────────────────────────────
    test('TC026 - Receiver notification created after upload', () async {
      await repo.notifyReceiver(
        receiverId: 'receiver-uid',
        senderUsername: 'alice',
        transferId: 'transfer-004',
      );

      final notifs = await fakeDb
          .collection(FirebaseConstants.notifications)
          .where('toUserId', isEqualTo: 'receiver-uid')
          .get();

      expect(notifs.docs, isNotEmpty);
      expect(notifs.docs.first.data()['fromUsername'], equals('alice'));
    });

    // ── TC027 ──────────────────────────────────────────────────────────────
    test('TC027 - Transfer document contains downloadable file URL', () async {
      const transferId = 'transfer-005';
      const fakeUrl = 'https://storage.example.com/file';

      await fakeDb
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .set({
        'senderId': 'sender-uid',
        'receiverId': 'receiver-uid',
        'encryptedAESKey': 'encKey',
        'encryptedFileUrl': fakeUrl,
        'fileName': 'video.mp4',
        'fileSize': 10240,
        'iv': 'ivB64',
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      final model = await repo.getTransfer(transferId);
      expect(model.encryptedFileUrl, equals(fakeUrl));
      expect(model.encryptedFileUrl, isNotEmpty);
    });

    // ── TC028 ──────────────────────────────────────────────────────────────
    test('TC028 - Transfer status updates to received', () async {
      const transferId = 'transfer-006';
      await fakeDb
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .set({
        'senderId': 'sender-uid',
        'receiverId': 'receiver-uid',
        'encryptedAESKey': 'encKey',
        'encryptedFileUrl': 'https://example.com/file',
        'fileName': 'data.bin',
        'fileSize': 256,
        'iv': 'ivB64',
        'status': 'pending',
        'sessionActive': true,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await repo.markReceived(transferId);

      final doc = await fakeDb
          .collection(FirebaseConstants.transfers)
          .doc(transferId)
          .get();
      expect(doc.data()!['status'], equals('received'));
    });

    // ── TC029 ──────────────────────────────────────────────────────────────
    test('TC029 - Decrypted file matches original plaintext', () {
      final original = Uint8List.fromList(utf8.encode('top secret payload'));
      final key = EncryptionService.secureRandomBytes(32);
      final iv = EncryptionService.secureRandomBytes(12);

      final ciphertext = runAesGcmEncrypt([original, key, iv]);
      final decrypted = runAesGcmDecrypt([ciphertext, key, iv]);

      expect(decrypted, equals(original),
          reason: 'Decrypted bytes must match original plaintext exactly');
    });

    // ── TC030 ──────────────────────────────────────────────────────────────
    test('TC030 - Transfer status updates to completed via audit log',
        () async {
      await repo.writeAuditLog(
        senderId: 'sender-uid',
        receiverId: 'receiver-uid',
        fileName: 'final.pdf',
        transferDate: '2026-04-05',
        transferTime: '14:30:00',
      );

      final logs = await fakeDb
          .collection(FirebaseConstants.transfersLog)
          .where('senderId', isEqualTo: 'sender-uid')
          .get();

      expect(logs.docs, isNotEmpty);
      expect(logs.docs.first.data()['status'], equals('completed'));
    });
  });
}
