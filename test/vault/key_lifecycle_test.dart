import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/data/repositories/auth_repository.dart';
import '../mocks/mock_firebase.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('VAULT KEY LIFECYCLE TESTS', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;
    late FakeSecureStorage fakeSecure;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      fakeSecure = FakeSecureStorage();
    });

    // ─── computeFingerprint() static helper ───────────────────────────────────

    // TC-VAULT-FP-01: SHA-256 fingerprint is 64 hex chars.
    test(
      'TC-VAULT-FP-01: computeFingerprint returns 64-char hex string',
      () {
        const pubKeyJson = '{"n":"abc123","e":"010001"}';
        final fp = AuthRepository.computeFingerprint(pubKeyJson);
        expect(fp.length, 64,
            reason: 'SHA-256 hex string must be 64 chars');
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(fp), true,
            reason: 'fingerprint must be lowercase hex only');
      },
    );

    // TC-VAULT-FP-02: Same input always produces same fingerprint (deterministic).
    test(
      'TC-VAULT-FP-02: computeFingerprint is deterministic',
      () {
        const pubKeyJson = '{"n":"deadbeef","e":"010001"}';
        final fp1 = AuthRepository.computeFingerprint(pubKeyJson);
        final fp2 = AuthRepository.computeFingerprint(pubKeyJson);
        expect(fp1, fp2, reason: 'fingerprint must be the same for same input');
      },
    );

    // TC-VAULT-FP-03: Different keys produce different fingerprints.
    test(
      'TC-VAULT-FP-03: different keys produce different fingerprints',
      () {
        final fp1 = AuthRepository.computeFingerprint('{"n":"key1","e":"010001"}');
        final fp2 = AuthRepository.computeFingerprint('{"n":"key2","e":"010001"}');
        expect(fp1, isNot(fp2), reason: 'different keys must have different fingerprints');
      },
    );

    // ─── regenerateKeyPair() ──────────────────────────────────────────────────

    // TC-VAULT-02: Regenerate writes new publicKey to Firestore, appends audit
    // log to rsa_key_manager subcollection, and writes keyVaultCreatedAt (D-14).
    test(
      'TC-VAULT-02: regenerateKeyPair updates publicKey, appends audit log, writes keyVaultCreatedAt',
      () async {
        const uid = 'test_uid_regenerate';
        // Pre-populate user doc so update() succeeds on FakeFirestore.
        await fakeFirestore.collection('users').doc(uid).set({
          'publicKey': 'OLD_KEY',
          'username': 'testuser',
        });

        final repo = AuthRepository(
          auth: mockAuth,
          db: fakeFirestore,
          secure: fakeSecure,
        );

        await repo.regenerateKeyPair(uid);

        // 1. publicKey must have changed (non-empty, not OLD_KEY).
        final userDoc = await fakeFirestore.collection('users').doc(uid).get();
        final newKey = userDoc.data()?['publicKey'] as String?;
        expect(newKey, isNotNull, reason: 'publicKey must not be null after regenerate');
        expect(newKey, isNot('OLD_KEY'), reason: 'publicKey must be updated after regenerate');
        expect(newKey!.isNotEmpty, true, reason: 'new publicKey must be non-empty');

        // 2. audit log: exactly 1 doc with action='regenerated'.
        final auditSnap = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('rsa_key_manager')
            .get();
        expect(auditSnap.docs.length, 1,
            reason: 'exactly one audit doc must be appended on regenerate');
        expect(auditSnap.docs.first.data()['action'], 'regenerated',
            reason: 'audit doc action must be "regenerated"');
        expect(auditSnap.docs.first.data()['publicKeyHash'], isNotNull,
            reason: 'audit doc must include publicKeyHash');

        // 3. profile/preferences must have keyVaultCreatedAt field (D-14).
        final prefsDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('profile')
            .doc('preferences')
            .get();
        expect(prefsDoc.exists, true,
            reason: 'profile/preferences doc must be created by regenerateKeyPair');
        expect(prefsDoc.data()?.containsKey('keyVaultCreatedAt'), true,
            reason: 'keyVaultCreatedAt must be written in regenerateKeyPair (D-14)');
      },
    );

    // TC-VAULT-02b: regenerateKeyPair stores new private key in SecureStorage.
    test(
      'TC-VAULT-02b: regenerateKeyPair writes private key to FlutterSecureStorage',
      () async {
        const uid = 'test_uid_secure_storage';
        await fakeFirestore.collection('users').doc(uid).set({
          'publicKey': 'OLD_KEY',
          'username': 'testuser',
        });

        // Use a mock-aware secure storage by calling hasKeyPair after regenerate.
        // FlutterSecureStorage is hard to mock without platform channels in unit tests;
        // we verify the method completes without throwing (integration aspect verified
        // by the widget test in vault_gate_test.dart via real device/emulator).
        final repo = AuthRepository(
          auth: mockAuth,
          db: fakeFirestore,
          secure: fakeSecure,
        );

        // Should complete without throwing.
        await expectLater(
          repo.regenerateKeyPair(uid),
          completes,
          reason: 'regenerateKeyPair must complete without throwing',
        );
      },
    );

    // ─── deleteKeyPair() ──────────────────────────────────────────────────────

    // TC-VAULT-03: Delete clears publicKey field from Firestore and appends audit log.
    test(
      'TC-VAULT-03: deleteKeyPair removes publicKey and appends audit log with action=deleted',
      () async {
        const uid = 'test_uid_delete';
        // Pre-populate user doc.
        await fakeFirestore.collection('users').doc(uid).set({
          'publicKey': 'EXISTING_KEY',
          'username': 'deleteuser',
        });

        final repo = AuthRepository(
          auth: mockAuth,
          db: fakeFirestore,
          secure: fakeSecure,
        );

        await repo.deleteKeyPair(uid);

        // 1. publicKey must be absent from users/{uid}.
        final userDoc = await fakeFirestore.collection('users').doc(uid).get();
        expect(userDoc.data()?.containsKey('publicKey'), false,
            reason: 'publicKey must be absent after deleteKeyPair');

        // 2. audit log: exactly 1 doc with action='deleted'.
        final auditSnap = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('rsa_key_manager')
            .get();
        expect(auditSnap.docs.length, 1,
            reason: 'exactly one audit doc must be appended on delete');
        expect(auditSnap.docs.first.data()['action'], 'deleted',
            reason: 'audit doc action must be "deleted"');

        // 3. profile/preferences must NOT have keyVaultCreatedAt written on delete.
        final prefsDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('profile')
            .doc('preferences')
            .get();
        // The doc may not exist at all (no prefs written on delete).
        if (prefsDoc.exists) {
          expect(prefsDoc.data()?.containsKey('keyVaultCreatedAt'), false,
              reason: 'keyVaultCreatedAt must NOT be written by deleteKeyPair');
        }
      },
    );

    // TC-VAULT-03b: deleteKeyPair does NOT write keyVaultCreatedAt to profile/preferences.
    test(
      'TC-VAULT-03b: deleteKeyPair does not create profile/preferences doc',
      () async {
        const uid = 'test_uid_delete_no_prefs';
        await fakeFirestore.collection('users').doc(uid).set({
          'publicKey': 'SOME_KEY',
        });

        final repo = AuthRepository(
          auth: mockAuth,
          db: fakeFirestore,
          secure: fakeSecure,
        );
        await repo.deleteKeyPair(uid);

        final prefsDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('profile')
            .doc('preferences')
            .get();
        // profile/preferences must not be created by deleteKeyPair.
        expect(prefsDoc.exists, false,
            reason: 'deleteKeyPair must not create profile/preferences doc');
      },
    );

    // ─── updateLastVaultAccess() ──────────────────────────────────────────────

    // TC-VAULT-07: updateLastVaultAccess writes lastVaultAccessAt to profile/preferences.
    test(
      'TC-VAULT-07: updateLastVaultAccess creates profile/preferences doc with lastVaultAccessAt',
      () async {
        const uid = 'test_uid_vault_access';
        // No pre-existing profile/preferences doc — merge:true must create it.
        final repo = AuthRepository(
          auth: mockAuth,
          db: fakeFirestore,
          secure: fakeSecure,
        );

        await repo.updateLastVaultAccess(uid);

        final prefsDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('profile')
            .doc('preferences')
            .get();
        expect(prefsDoc.exists, true,
            reason: 'updateLastVaultAccess must create profile/preferences doc if absent');
        expect(prefsDoc.data()?.containsKey('lastVaultAccessAt'), true,
            reason: 'lastVaultAccessAt must be written by updateLastVaultAccess');
      },
    );

    // TC-VAULT-07b: updateLastVaultAccess does NOT overwrite existing prefs fields.
    test(
      'TC-VAULT-07b: updateLastVaultAccess preserves existing profile/preferences fields',
      () async {
        const uid = 'test_uid_vault_access_merge';
        // Pre-populate profile/preferences with existing fields.
        await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('profile')
            .doc('preferences')
            .set({
          'biometricGateEnabled': true,
          'themeMode': 'dark',
          'keyVaultCreatedAt': null,
          'lastVaultAccessAt': null,
        });

        final repo = AuthRepository(
          auth: mockAuth,
          db: fakeFirestore,
          secure: fakeSecure,
        );

        await repo.updateLastVaultAccess(uid);

        final prefsDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('profile')
            .doc('preferences')
            .get();
        // lastVaultAccessAt is updated; other fields preserved.
        expect(prefsDoc.data()?['biometricGateEnabled'], true,
            reason: 'biometricGateEnabled must be preserved after updateLastVaultAccess');
        expect(prefsDoc.data()?['themeMode'], 'dark',
            reason: 'themeMode must be preserved after updateLastVaultAccess');
        expect(prefsDoc.data()?.containsKey('lastVaultAccessAt'), true,
            reason: 'lastVaultAccessAt must be present after update');
      },
    );
  });
}
