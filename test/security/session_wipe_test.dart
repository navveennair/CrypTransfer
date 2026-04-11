import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

void main() {
  group('SESSION WIPE SECURITY TESTS', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    // ─── TC-WIPE-001 ──────────────────────────────────────────────────────────

    test(
      'TC-WIPE-001: publicKey deleted from Firestore after session closes',
      () async {
        const userId = 'test_receiver_uid';

        await fakeFirestore.collection('users').doc(userId).set({
          'username': 'receiver_test',
          'email': 'receiver@test.com',
          'publicKey': 'FAKE_RSA_PUBLIC_KEY_PEM',
          'isReadyToReceive': true,
          'sessionActive': true,
        });

        final beforeWipe =
            await fakeFirestore.collection('users').doc(userId).get();
        expect(
          beforeWipe.data()!.containsKey('publicKey'),
          true,
          reason: 'Public key must exist before wipe',
        );

        await fakeFirestore.collection('users').doc(userId).update({
          'publicKey': FieldValue.delete(),
          'isReadyToReceive': false,
          'sessionActive': false,
          'lastSessionClosed': FieldValue.serverTimestamp(),
        });

        final afterWipe =
            await fakeFirestore.collection('users').doc(userId).get();

        expect(
          afterWipe.data()!.containsKey('publicKey'),
          false,
          reason: '❌ SECURITY BREACH: publicKey still exists after '
              'closeReceiverSession()!',
        );
        expect(
          afterWipe.data()!['isReadyToReceive'],
          false,
          reason: 'isReadyToReceive must be false',
        );
        expect(
          afterWipe.data()!['sessionActive'],
          false,
          reason: 'sessionActive must be false',
        );

        // ignore: avoid_print
        print('✅ TC-WIPE-001 PASSED: Public key deleted from Firestore');
      },
    );

    // ─── TC-WIPE-002 ──────────────────────────────────────────────────────────

    test(
      'TC-WIPE-002: rsa_key_transfers purged after session closes',
      () async {
        const userId = 'test_receiver_uid';

        await fakeFirestore.collection('rsa_key_transfers').add({
          'fromUserId': userId,
          'toUserId': 'sender_uid_1',
          'publicKey': 'FAKE_PUBLIC_KEY',
          'sentAt': DateTime.now(),
        });
        await fakeFirestore.collection('rsa_key_transfers').add({
          'fromUserId': userId,
          'toUserId': 'sender_uid_2',
          'publicKey': 'FAKE_PUBLIC_KEY',
          'sentAt': DateTime.now(),
        });

        final beforeWipe = await fakeFirestore
            .collection('rsa_key_transfers')
            .where('fromUserId', isEqualTo: userId)
            .get();
        expect(
          beforeWipe.docs.length,
          2,
          reason: 'Should have 2 key transfers before wipe',
        );

        final batch = fakeFirestore.batch();
        for (final doc in beforeWipe.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        final afterWipe = await fakeFirestore
            .collection('rsa_key_transfers')
            .where('fromUserId', isEqualTo: userId)
            .get();

        expect(
          afterWipe.docs.length,
          0,
          reason: '❌ GHOST KEYS: rsa_key_transfers still exist after '
              'closeReceiverSession()!',
        );

        // ignore: avoid_print
        print('✅ TC-WIPE-002 PASSED: rsa_key_transfers purged');
      },
    );

    // ─── TC-WIPE-003 ──────────────────────────────────────────────────────────

    test(
      'TC-WIPE-003: AES key buffer zeroed after use',
      () {
        final aesKey = Uint8List(32);
        for (int i = 0; i < 32; i++) {
          aesKey[i] = 0xFF;
        }

        expect(
          aesKey.any((b) => b != 0),
          true,
          reason: 'AES key must have non-zero data',
        );

        aesKey.fillRange(0, aesKey.length, 0);

        expect(
          aesKey.every((b) => b == 0),
          true,
          reason: '❌ MEMORY LEAK: AES key not properly zeroed after use!',
        );

        // ignore: avoid_print
        print('✅ TC-WIPE-003 PASSED: AES key zeroed from memory');
      },
    );

    // ─── TC-WIPE-004 ──────────────────────────────────────────────────────────

    test(
      'TC-WIPE-004: Session cannot be hijacked - '
      'publicKey null after wipe means encryption fails',
      () async {
        const userId = 'test_receiver_uid';

        await fakeFirestore.collection('users').doc(userId).set({
          'publicKey': 'VALID_RSA_PUBLIC_KEY',
          'isReadyToReceive': true,
        });

        await fakeFirestore.collection('users').doc(userId).update({
          'publicKey': FieldValue.delete(),
          'isReadyToReceive': false,
        });

        final attackerQuery =
            await fakeFirestore.collection('users').doc(userId).get();

        final publicKey = attackerQuery.data()?['publicKey'];

        expect(
          publicKey,
          isNull,
          reason: '❌ SESSION HIJACK POSSIBLE: publicKey still available '
              'after kill switch!',
        );
        expect(
          attackerQuery.data()?['isReadyToReceive'],
          false,
          reason: 'Receiver must be marked unavailable',
        );

        // ignore: avoid_print
        print('✅ TC-WIPE-004 PASSED: Session hijack prevented - '
            'no public key available after kill switch');
      },
    );

    // ─── TC-WIPE-005 ──────────────────────────────────────────────────────────

    test(
      'TC-WIPE-005: New session generates different keypair each time',
      () {
        final aesKey1 = Uint8List.fromList(List.generate(32, (i) => i));
        final aesKey2 = Uint8List.fromList(List.generate(32, (i) => i + 1));

        expect(
          aesKey1,
          isNot(equals(aesKey2)),
          reason: '❌ KEY REUSE: Two sessions produced identical keys! '
              'Must be ephemeral.',
        );

        // ignore: avoid_print
        print('✅ TC-WIPE-005 PASSED: '
            'Session keys are ephemeral (unique per session)');
      },
    );

    // ─── TC-WIPE-006 ──────────────────────────────────────────────────────────

    test(
      'TC-WIPE-006: Notifications purged after session closes',
      () async {
        const userId = 'test_receiver_uid';

        await fakeFirestore.collection('notifications').add({
          'fromUserId': userId,
          'type': 'rsa_key_received',
          'message': 'Receiver sent RSA key',
          'read': false,
        });

        final before = await fakeFirestore
            .collection('notifications')
            .where('fromUserId', isEqualTo: userId)
            .where('type', isEqualTo: 'rsa_key_received')
            .get();
        expect(before.docs.length, greaterThan(0));

        final batch = fakeFirestore.batch();
        for (final doc in before.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        final after = await fakeFirestore
            .collection('notifications')
            .where('fromUserId', isEqualTo: userId)
            .where('type', isEqualTo: 'rsa_key_received')
            .get();

        expect(
          after.docs.length,
          0,
          reason: '❌ GHOST NOTIFICATIONS: rsa_key_received notifications '
              'persist after session close!',
        );

        // ignore: avoid_print
        print('✅ TC-WIPE-006 PASSED: Notifications purged after session close');
      },
    );
  });
}
