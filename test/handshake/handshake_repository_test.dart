import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptransfer/data/repositories/handshake_repository.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  group('HANDSHAKE REPOSITORY TESTS', () {
    late FakeFirebaseFirestore fakeFirestore;
    late MockFirebaseAuth mockAuth;

    setUp(() {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(
          signedIn: true, mockUser: MockUser(uid: 'user1'));
    });

    // HAND-01: sendProposal() creates neutral_handshakes doc with proposerId, partnerId, status=pending
    test('TC-HAND-01: sendProposal creates doc with proposerId/partnerId/status=pending',
        () async {
      final repo =
          HandshakeRepository(db: fakeFirestore, auth: mockAuth);

      await repo.sendProposal(
          partnerUid: 'user2', partnerUsername: 'alice');

      final snap = await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .get();

      expect(snap.exists, isTrue);
      expect(snap.data()!['proposerId'], equals('user1'));
      expect(snap.data()!['partnerId'], equals('user2'));
      expect(snap.data()!['status'], equals('pending'));
    });

    // HAND-02: acceptProposal() WriteBatch updates status to connected
    test('TC-HAND-02: acceptProposal updates status to connected', () async {
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .set({
        'proposerId': 'user1',
        'partnerId': 'user2',
        'status': 'pending',
      });

      // Current user is user2 (the partner accepting the proposal)
      final auth2 = MockFirebaseAuth(
          signedIn: true, mockUser: MockUser(uid: 'user2'));
      final repo = HandshakeRepository(db: fakeFirestore, auth: auth2);

      await repo.acceptProposal('user1_user2', 'user1');

      final snap = await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .get();
      expect(snap.data()!['status'], equals('connected'));
    });

    // HAND-03: rejectProposal() updates status to rejected
    test('TC-HAND-03: rejectProposal sets status to rejected', () async {
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .set({
        'proposerId': 'user1',
        'partnerId': 'user2',
        'status': 'pending',
      });

      final repo =
          HandshakeRepository(db: fakeFirestore, auth: mockAuth);

      await repo.rejectProposal('user1_user2');

      final snap = await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .get();
      expect(snap.data()!['status'], equals('rejected'));
    });

    // HAND-04: cancelProposal() deletes the doc
    test('TC-HAND-04: cancelProposal deletes the handshake doc', () async {
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .set({
        'proposerId': 'user1',
        'partnerId': 'user2',
        'status': 'pending',
      });

      final repo =
          HandshakeRepository(db: fakeFirestore, auth: mockAuth);

      await repo.cancelProposal('user1_user2');

      final snap = await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .get();
      expect(snap.exists, isFalse);
    });

    // HAND-05: streamIncomingPending emits docs where partnerId==uid and status==pending
    test('TC-HAND-05: streamIncomingPending emits pending docs for partner',
        () async {
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user2_user1')
          .set({
        'proposerId': 'user2',
        'partnerId': 'user1',
        'status': 'pending',
      });

      // Current user is user1 (the partner)
      final repo =
          HandshakeRepository(db: fakeFirestore, auth: mockAuth);

      final snap = await repo.streamIncomingPending().first;
      expect(snap.docs.length, equals(1));
      expect(snap.docs.first.get('proposerId'), equals('user2'));
    });
  });
}
