import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cryptransfer/core/constants/firebase_constants.dart';
import 'package:cryptransfer/data/repositories/key_repository.dart';

import '../mocks/mock_firebase.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('KeyRepository.scanForStaleKeys', () {
    late FakeFirebaseFirestore db;
    late MockFirebaseAuth auth;
    late FakeSecureStorage secure;
    const uid = 'user1';

    setUp(() {
      db = FakeFirebaseFirestore();
      auth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid));
      secure = FakeSecureStorage();
    });

    KeyRepository repo() => KeyRepository(db: db, auth: auth, secure: secure);

    // ─── TC-CC-01 ──────────────────────────────────────────────────────────

    test('TC-CC-01: clean state returns isClean == true', () async {
      await db.collection(FirebaseConstants.users).doc(uid).set({
        'isReadyToReceive': false,
      });

      final scan = await repo().scanForStaleKeys();

      expect(scan.isClean, true,
          reason: 'no publicKey, no local key, no transfers → clean');
      expect(scan.hasStaleRsaSession, false);
      expect(scan.staleTransferIds, isEmpty);
    });

    // ─── TC-CC-02 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-02: stale RSA via Firestore publicKey (isReadyToReceive false)',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
          'publicKey': 'LEFTOVER_PUBLIC_KEY',
        });

        final scan = await repo().scanForStaleKeys();

        expect(scan.hasStaleRsaSession, true,
            reason: 'publicKey present + isReadyToReceive=false = stale');
        expect(scan.staleTransferIds, isEmpty);
      },
    );

    // ─── TC-CC-03 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-03: stale RSA via local secure-storage key only '
      '(no Firestore publicKey)',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
        });
        await secure.write(
          key: FirebaseConstants.privateKeyStorageKey,
          value: 'LEFTOVER_PRIVATE_KEY_PEM',
        );

        final scan = await repo().scanForStaleKeys();

        expect(scan.hasStaleRsaSession, true,
            reason: 'the OR branch — local private key alone must also '
                'count as stale, per the design doc\'s "either ... OR" rule');
      },
    );

    // ─── TC-CC-04 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-04: active session (isReadyToReceive true) is NOT flagged',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': true,
          'publicKey': 'ACTIVE_PUBLIC_KEY',
        });
        await secure.write(
          key: FirebaseConstants.privateKeyStorageKey,
          value: 'ACTIVE_PRIVATE_KEY_PEM',
        );

        final scan = await repo().scanForStaleKeys();

        expect(scan.hasStaleRsaSession, false,
            reason: 'isReadyToReceive=true means this is a live session, '
                'regardless of what key material exists');
      },
    );

    // ─── TC-CC-05 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-05: stale transfers — only terminal-status docs with a '
      'non-empty encryptedAESKey are returned',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
        });

        // Stale: terminal status, key present.
        final staleDoc = await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other1',
          'status': 'completed',
          'encryptedAESKey': 'LEFTOVER_AES_KEY',
        });
        // Not stale: terminal status, but key already wiped.
        await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other2',
          'status': 'completed',
          'encryptedAESKey': '',
        });
        // Not stale: not terminal.
        await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other3',
          'status': 'in-progress',
          'encryptedAESKey': 'IN_PROGRESS_KEY',
        });

        final scan = await repo().scanForStaleKeys();

        expect(scan.staleTransferIds, [staleDoc.id]);
      },
    );

    // ─── TC-CC-06 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-06: active transfer (status pending, key set) is NOT flagged, '
      'NOT a candidate for deletion',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
        });
        await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other1',
          'status': 'pending',
          'encryptedAESKey': 'ACTIVE_AES_KEY',
        });

        final scan = await repo().scanForStaleKeys();

        expect(scan.staleTransferIds, isEmpty);
      },
    );

    // ─── TC-CC-07 ──────────────────────────────────────────────────────────

    test(
      'TC-CC-07: both stale RSA and stale transfers detected in one scan',
      () async {
        await db.collection(FirebaseConstants.users).doc(uid).set({
          'isReadyToReceive': false,
          'publicKey': 'LEFTOVER_PUBLIC_KEY',
        });
        final staleDoc = await db.collection(FirebaseConstants.transfers).add({
          'senderId': uid,
          'receiverId': 'other1',
          'status': 'aborted',
          'encryptedAESKey': 'LEFTOVER_AES_KEY',
        });

        final scan = await repo().scanForStaleKeys();

        expect(scan.hasStaleRsaSession, true);
        expect(scan.staleTransferIds, [staleDoc.id]);
        expect(scan.isClean, false);
      },
    );
  });
}
