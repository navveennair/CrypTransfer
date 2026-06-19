import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/core/constants/firebase_constants.dart';
import 'package:cryptransfer/core/errors/app_exceptions.dart';
import 'package:cryptransfer/data/repositories/key_repository.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('SELECT SENDER HANDSHAKE — Role Conflict Guard', () {
    late FakeFirebaseFirestore fakeFirestore;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
    });

    // TC-SSH-01: happy path — no conflict, both writes commit.
    test(
        'TC-SSH-01: writes selectedSenderUid + handshake doc when no conflict exists',
        () async {
      final auth =
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'receiver1'));
      await fakeFirestore.collection('users').doc('receiver1').set({
        'username': 'receiverOne',
        'publicKey': 'PUBKEY123',
      });
      await fakeFirestore
          .collection('users')
          .doc('sender1')
          .set({'username': 'senderOne'});

      final repo = KeyRepository(db: fakeFirestore, auth: auth);

      final docId = await repo.selectSenderHandshake(
        senderUid: 'sender1',
        senderUsername: 'senderOne',
      );

      expect(docId, isNotEmpty);

      final myDoc =
          await fakeFirestore.collection('users').doc('receiver1').get();
      expect(myDoc.data()!['selectedSenderUid'], equals('sender1'));

      final handshake =
          await fakeFirestore.collection(FirebaseConstants.handshakes).doc(docId).get();
      expect(handshake.data()!['receiverId'], equals('receiver1'));
      expect(handshake.data()!['senderId'], equals('sender1'));
      expect(handshake.data()!['status'], equals('handshake_complete'));
    });

    // TC-SSH-02: both-receiver conflict — partner already picked me as their sender.
    test(
        'TC-SSH-02: throws RoleConflictException when partner already selected me as their sender',
        () async {
      final auth =
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'userA'));
      await fakeFirestore.collection('users').doc('userA').set({
        'username': 'userA',
        'publicKey': 'PUBKEY_A',
      });
      // userB has already chosen userA as THEIR sender — both now want to be receiver.
      await fakeFirestore.collection('users').doc('userB').set({
        'username': 'userB',
        'selectedSenderUid': 'userA',
      });

      final repo = KeyRepository(db: fakeFirestore, auth: auth);

      await expectLater(
        repo.selectSenderHandshake(senderUid: 'userB', senderUsername: 'userB'),
        throwsA(isA<RoleConflictException>()),
      );
    });

    // TC-SSH-03: the guard fires for every caller of selectSenderHandshake — not just
    // the home-screen role-picker path — and the transaction leaves no partial write
    // behind when it aborts. This is the scenario the auto-reconnect-to-last-sender
    // path (ReceiverScreen._onToggleReady) and the incoming-handshake auto-detect
    // listener both hit without ever calling assignTransferRole() first.
    test(
        'TC-SSH-03: conflict guard commits no partial write when reached without assignTransferRole',
        () async {
      final auth =
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'userC'));
      await fakeFirestore.collection('users').doc('userC').set({
        'username': 'userC',
        'publicKey': 'PUBKEY_C',
      });
      await fakeFirestore.collection('users').doc('userD').set({
        'username': 'userD',
        'selectedSenderUid': 'userC',
      });

      final repo = KeyRepository(db: fakeFirestore, auth: auth);

      await expectLater(
        repo.selectSenderHandshake(senderUid: 'userD', senderUsername: 'userD'),
        throwsA(isA<RoleConflictException>()),
      );

      final myDoc = await fakeFirestore.collection('users').doc('userC').get();
      expect(myDoc.data()!.containsKey('selectedSenderUid'), isFalse);

      final handshakes = await fakeFirestore.collection(FirebaseConstants.handshakes).get();
      expect(handshakes.docs, isEmpty);
    });

    // TC-SSH-04: existing behavior preserved — missing public key still rejected.
    test('TC-SSH-04: throws KeyNotFoundException when receiver has no public key',
        () async {
      final auth =
          MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'userE'));
      await fakeFirestore
          .collection('users')
          .doc('userE')
          .set({'username': 'userE'});
      await fakeFirestore
          .collection('users')
          .doc('userF')
          .set({'username': 'userF'});

      final repo = KeyRepository(db: fakeFirestore, auth: auth);

      await expectLater(
        repo.selectSenderHandshake(senderUid: 'userF', senderUsername: 'userF'),
        throwsA(isA<KeyNotFoundException>()),
      );
    });
  });
}
