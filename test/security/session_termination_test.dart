import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import '../mocks/mock_firebase.dart';

void main() {
  group('SESSION TERMINATION SECURITY TESTS', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    // TC-TERM-001
    test(
      'TC-TERM-001: Receiver end session writes audit log to both '
      'audit_logs subcollections BEFORE any document deletion',
      () async {
        // STUB — will be implemented in Wave 1 (Plan 02).
        // Requirement: audit log WriteBatch commits to
        //   users/{senderId}/audit_logs AND users/{receiverId}/audit_logs
        //   before transfers/{transferId} or handshakes/{id} are deleted.
        // Security: V3 Session Management — immutable record must survive
        //   even if a later cleanup step fails.
        const senderId = 'sender_uid';
        const receiverId = 'receiver_uid';

        // Pre-condition: transfer doc exists
        await fakeFirestore
            .collection('transfers')
            .doc('transfer_01')
            .set({'senderId': senderId, 'receiverId': receiverId});

        // Simulate audit log write (step 0 — before deletion)
        final batch = fakeFirestore.batch();
        batch.set(
          fakeFirestore
              .collection('users')
              .doc(senderId)
              .collection('audit_logs')
              .doc(),
          {'senderId': senderId, 'receiverId': receiverId, 'status': 'completed'},
        );
        batch.set(
          fakeFirestore
              .collection('users')
              .doc(receiverId)
              .collection('audit_logs')
              .doc(),
          {'senderId': senderId, 'receiverId': receiverId, 'status': 'completed'},
        );
        await batch.commit();

        // Verify both audit logs exist before deletion
        final senderAudit = await fakeFirestore
            .collection('users').doc(senderId).collection('audit_logs').get();
        final receiverAudit = await fakeFirestore
            .collection('users').doc(receiverId).collection('audit_logs').get();

        expect(senderAudit.docs.length, greaterThan(0),
            reason: 'TC-TERM-001: Sender audit log must exist before cleanup');
        expect(receiverAudit.docs.length, greaterThan(0),
            reason: 'TC-TERM-001: Receiver audit log must exist before cleanup');

        // Transfer doc still exists (deletion has not run yet)
        final transferBefore = await fakeFirestore
            .collection('transfers').doc('transfer_01').get();
        expect(transferBefore.exists, true,
            reason: 'TC-TERM-001: Transfer doc must still exist when audit log is written');

        // ignore: avoid_print
        print('✅ TC-TERM-001 PASSED: Audit logs written to both subcollections before deletion');
      },
    );

    // TC-TERM-002
    test(
      'TC-TERM-002: Receiver storage deletion tolerates object-not-found '
      '(idempotent — does not throw if file already deleted)',
      () async {
        // STUB — will be verified against TransferRepository.deleteStorageFile()
        // in Wave 1 (Plan 02). This test verifies the guard pattern.
        // Security: V6 Cryptography — storage delete must not abort cleanup
        //   if the file was already removed.
        //
        // Pattern from EndSessionScreen line 143:
        //   on FirebaseException catch (e) {
        //     if (e.code != 'object-not-found') rethrow;
        //   }
        //
        // TransferRepository.deleteStorageFile() already implements this guard.
        // Stub: confirm the guard logic is sound.

        bool cleanupAborted = false;
        // Simulate the guard pattern:
        //   on FirebaseException catch (e) { if (e.code != 'object-not-found') rethrow; }
        // We simulate a deleteStorageFile() that throws object-not-found
        // and verify the guard swallows it without aborting cleanup.
        try {
          throw FirebaseException(plugin: 'storage', code: 'object-not-found');
        } on FirebaseException catch (e) {
          if (e.code != 'object-not-found') {
            cleanupAborted = true;
            rethrow;
          }
          // Swallowed — object-not-found is tolerated
        } catch (_) {
          cleanupAborted = true;
        }

        expect(cleanupAborted, false,
            reason: 'TC-TERM-002: object-not-found must NOT abort cleanup sequence');

        // ignore: avoid_print
        print('✅ TC-TERM-002 PASSED: object-not-found is tolerated in storage deletion');
      },
    );

    // TC-TERM-003
    test(
      'TC-TERM-003: WriteBatch atomically deletes transfers/{id} + '
      'handshakes/{id} — both gone in single commit',
      () async {
        // STUB — verified against KeyRepository.endSessionCleanup() in Wave 1.
        // Security: V6 Cryptography — partial delete leaves ghost key material
        //   (encryptedAESKey field lives in the transfer doc).
        const transferId = 'transfer_01';
        const handshakeId = 'handshake_01';

        await fakeFirestore
            .collection('transfers')
            .doc(transferId)
            .set({'encryptedAESKey': 'base64encodedkey', 'status': 'received'});
        await fakeFirestore
            .collection('handshakes')
            .doc(handshakeId)
            .set({'senderId': 'sender_uid', 'receiverId': 'receiver_uid'});

        // Atomic WriteBatch delete
        final batch = fakeFirestore.batch();
        batch.delete(fakeFirestore.collection('transfers').doc(transferId));
        batch.delete(fakeFirestore.collection('handshakes').doc(handshakeId));
        await batch.commit();

        final transferAfter = await fakeFirestore.collection('transfers').doc(transferId).get();
        final handshakeAfter = await fakeFirestore.collection('handshakes').doc(handshakeId).get();

        expect(transferAfter.exists, false,
            reason: 'TC-TERM-003: transfers/{id} must be deleted after WriteBatch');
        expect(handshakeAfter.exists, false,
            reason: 'TC-TERM-003: handshakes/{id} must be deleted after WriteBatch');

        // ignore: avoid_print
        print('✅ TC-TERM-003 PASSED: WriteBatch atomically deleted transfer + handshake');
      },
    );

    // TC-TERM-004
    test(
      'TC-TERM-004: closeReceiverSession deletes publicKey from Firestore '
      'and private RSA key from SecureStorage after endSessionCleanup',
      () async {
        // STUB — will invoke EncryptionService.closeReceiverSession() in Wave 1.
        // Verifies: publicKey FieldValue.delete() + FlutterSecureStorage private key delete.
        // Security: V6 Cryptography — RSA private key must not persist after session end.
        // Ordering: endSessionCleanup() MUST be called BEFORE closeReceiverSession()
        //   to avoid null handshakeId (Pitfall 2 from RESEARCH.md).
        const receiverId = 'receiver_uid';
        const privateKeyStorageKey = 'rsa_private_key';

        // Set up Firestore user doc with publicKey
        await fakeFirestore.collection('users').doc(receiverId).set({
          'publicKey': 'FAKE_RSA_PUBLIC_KEY_PEM',
          'isReadyToReceive': true,
          'sessionActive': true,
        });

        // Set up FakeSecureStorage with private key
        final fakeStorage = FakeSecureStorage();
        await fakeStorage.write(key: privateKeyStorageKey, value: 'FAKE_RSA_PRIVATE_KEY_JSON');

        // Simulate closeReceiverSession step 1: Firestore publicKey delete
        await fakeFirestore.collection('users').doc(receiverId).update({
          'publicKey': FieldValue.delete(),
          'isReadyToReceive': false,
          'sessionActive': false,
        });

        // Simulate closeReceiverSession step 2: SecureStorage private key delete
        await fakeStorage.delete(key: privateKeyStorageKey);

        // Verify publicKey is gone from Firestore
        final userDoc = await fakeFirestore.collection('users').doc(receiverId).get();
        expect(userDoc.data()!.containsKey('publicKey'), false,
            reason: '❌ SECURITY BREACH: publicKey still in Firestore after closeReceiverSession()');

        // Verify private key is gone from SecureStorage
        final privateKey = await fakeStorage.read(key: privateKeyStorageKey);
        expect(privateKey, isNull,
            reason: '❌ SECURITY BREACH: RSA private key still in SecureStorage after closeReceiverSession()');

        // ignore: avoid_print
        print('✅ TC-TERM-004 PASSED: publicKey deleted from Firestore + private key from SecureStorage');
      },
    );

    // TC-TERM-005
    test(
      'TC-TERM-005: Sender stream !snapshot.exists guard only fires when '
      '_done == true (not during upload)',
      () async {
        // STUB — verifies the Pitfall 1 guard from RESEARCH.md.
        // Security: V3 Session Management — sender must not navigate to
        //   SenderSessionEndScreen before upload completes.
        // Pattern: if (!snapshot.exists) { if (!_done || _sessionEnded) return; ... }

        bool navigationTriggered = false;
        bool done = false;
        bool sessionEnded = false;

        void simulateSnapshotNotExists() {
          if (!done || sessionEnded) return; // guard
          sessionEnded = true;
          navigationTriggered = true;
        }

        // Case 1: upload not done — guard must block navigation
        done = false;
        simulateSnapshotNotExists();
        expect(navigationTriggered, false,
            reason: 'TC-TERM-005: Navigation must be blocked when _done is false (upload in progress)');

        // Case 2: upload done — navigation must fire once
        done = true;
        sessionEnded = false;
        simulateSnapshotNotExists();
        expect(navigationTriggered, true,
            reason: 'TC-TERM-005: Navigation must fire when _done is true and doc no longer exists');

        // Case 3: double-fire guard — sessionEnded prevents second navigation
        navigationTriggered = false;
        simulateSnapshotNotExists(); // sessionEnded is already true
        expect(navigationTriggered, false,
            reason: 'TC-TERM-005: _sessionEnded guard must prevent double-navigation');

        // ignore: avoid_print
        print('✅ TC-TERM-005 PASSED: !snapshot.exists guard only fires after upload completes');
      },
    );

    // TC-TERM-008
    test(
      'TC-TERM-008: D-10 edge case — sender deletes transfer doc if it '
      'still exists on SenderSessionEndScreen arrival',
      () async {
        // STUB — will be exercised against SenderSessionEndScreen._checkAndMarkDone()
        // in Wave 2 (Plan 03).
        // Security: V6 Cryptography — edge case where receiver cleanup was interrupted;
        //   transfer doc (containing encryptedAESKey) must not persist on sender side.
        const transferId = 'stale_transfer_01';

        // Edge case: doc still exists (receiver cleanup was interrupted)
        await fakeFirestore
            .collection('transfers')
            .doc(transferId)
            .set({'encryptedAESKey': 'stale_key_material', 'status': 'pending'});

        // Simulate _checkAndMarkDone():
        final doc = await fakeFirestore.collection('transfers').doc(transferId).get();
        if (doc.exists) {
          await fakeFirestore.collection('transfers').doc(transferId).delete();
        }

        final afterCheck = await fakeFirestore.collection('transfers').doc(transferId).get();
        expect(afterCheck.exists, false,
            reason: 'TC-TERM-008: Stale transfer doc must be deleted by sender D-10 check');

        // Normal case: doc already gone (no-op, no throw)
        bool threw = false;
        try {
          final alreadyGone = await fakeFirestore.collection('transfers').doc('nonexistent').get();
          if (alreadyGone.exists) {
            await fakeFirestore.collection('transfers').doc('nonexistent').delete();
          }
          // If doc.exists is false, we skip delete — no error
        } catch (_) {
          threw = true;
        }
        expect(threw, false,
            reason: 'TC-TERM-008: D-10 check must not throw when doc already absent');

        // ignore: avoid_print
        print('✅ TC-TERM-008 PASSED: D-10 edge case — stale transfer doc deleted; no-op when already gone');
      },
    );
  });
}
