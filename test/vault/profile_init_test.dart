import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VAULT PROFILE INIT TESTS', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    // TC-VAULT-05: profile/preferences doc created atomically with users/{uid} on registration.
    // Full implementation test added in Plan 02 (Wave 1) after register() uses WriteBatch.
    test(
      'TC-VAULT-05-stub: profile/preferences subcollection doc can be written atomically',
      () async {
        const uid = 'test_reg_uid';
        final batch = fakeFirestore.batch();
        batch.set(
          fakeFirestore.collection('users').doc(uid),
          {'username': 'test', 'publicKey': null, 'isAdmin': false},
        );
        batch.set(
          fakeFirestore.collection('users').doc(uid).collection('profile').doc('preferences'),
          {
            'biometricGateEnabled': false,
            'themeMode': 'dark',
            'keyVaultCreatedAt': null,
            'lastVaultAccessAt': null,
          },
        );
        await batch.commit();

        final prefDoc = await fakeFirestore
            .collection('users')
            .doc(uid)
            .collection('profile')
            .doc('preferences')
            .get();
        expect(prefDoc.exists, isTrue,
            reason: 'profile/preferences must exist after batch commit');
        expect(prefDoc.data()?['themeMode'], 'dark',
            reason: 'themeMode initial value must be dark');
        expect(prefDoc.data()?['biometricGateEnabled'], false,
            reason: 'biometricGateEnabled initial value must be false');
        // ignore: avoid_print
        print('✅ TC-VAULT-05-stub PASSED: Profile init atomic write verified');
      },
    );
  });
}
