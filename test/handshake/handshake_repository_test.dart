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

    setUp(() async {
      fakeFirestore = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth(
          signedIn: true, mockUser: MockUser(uid: 'user1'));
      // Seed user profile so sendProposal's username fetch succeeds
      await fakeFirestore.collection('users').doc('user1').set({'username': 'testuser1'});
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
        'proposerUsername': 'testuser1',
        'partnerId': 'user2',
        'partnerUsername': 'alice',
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

    // HAND-02b: acceptProposal() also updates bidirectional friendships sub-collection
    test('TC-HAND-02b: acceptProposal updates friendships sub-collection with status=accepted',
        () async {
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .set({
        'proposerId': 'user1',
        'proposerUsername': 'testuser1',
        'partnerId': 'user2',
        'partnerUsername': 'alice',
        'status': 'pending',
      });

      // Current user is user2 (the partner accepting the proposal)
      final auth2 = MockFirebaseAuth(
          signedIn: true, mockUser: MockUser(uid: 'user2'));
      final repo = HandshakeRepository(db: fakeFirestore, auth: auth2);

      await repo.acceptProposal('user1_user2', 'user1');

      // Check user2's friendship doc for user1
      final user2FriendshipSnap = await fakeFirestore
          .collection('users')
          .doc('user2')
          .collection('friendships')
          .doc('user1')
          .get();
      expect(user2FriendshipSnap.exists, isTrue);
      expect(user2FriendshipSnap.data()?['status'], equals('accepted'));
      expect(user2FriendshipSnap.data()?['uid'], equals('user1'));
      expect(user2FriendshipSnap.data()?['username'], equals('testuser1'));

      // Check user1's friendship doc for user2
      final user1FriendshipSnap = await fakeFirestore
          .collection('users')
          .doc('user1')
          .collection('friendships')
          .doc('user2')
          .get();
      expect(user1FriendshipSnap.exists, isTrue);
      expect(user1FriendshipSnap.data()?['status'], equals('accepted'));
      expect(user1FriendshipSnap.data()?['uid'], equals('user2'));
      expect(user1FriendshipSnap.data()?['username'], equals('alice'));
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

      // Only the partner (user2) may reject — using auth2 matches the Firestore rule
      final auth2 = MockFirebaseAuth(
          signedIn: true, mockUser: MockUser(uid: 'user2'));
      final repo = HandshakeRepository(db: fakeFirestore, auth: auth2);

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

    // IN-02: streamActiveConnectionsAsProposer emits connected docs where proposerId==uid
    test('TC-HAND-06a: streamActiveConnectionsAsProposer emits connected docs for proposer',
        () async {
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .set({
        'proposerId': 'user1',
        'partnerId': 'user2',
        'status': 'connected',
      });
      // Doc where user1 is partner — should NOT appear in this stream
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user2_user1')
          .set({
        'proposerId': 'user2',
        'partnerId': 'user1',
        'status': 'connected',
      });

      final repo = HandshakeRepository(db: fakeFirestore, auth: mockAuth);
      final snap = await repo.streamActiveConnectionsAsProposer().first;
      expect(snap.docs.length, equals(1));
      expect(snap.docs.first.get('proposerId'), equals('user1'));
    });

    // IN-02: streamActiveConnectionsAsPartner emits connected docs where partnerId==uid
    test('TC-HAND-06b: streamActiveConnectionsAsPartner emits connected docs for partner',
        () async {
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user2_user1')
          .set({
        'proposerId': 'user2',
        'partnerId': 'user1',
        'status': 'connected',
      });
      // Doc where user1 is proposer — should NOT appear in this stream
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user3')
          .set({
        'proposerId': 'user1',
        'partnerId': 'user3',
        'status': 'connected',
      });

      final repo = HandshakeRepository(db: fakeFirestore, auth: mockAuth);
      final snap = await repo.streamActiveConnectionsAsPartner().first;
      expect(snap.docs.length, equals(1));
      expect(snap.docs.first.get('partnerId'), equals('user1'));
    });

    // IN-02: streamProposalOutcome emits the doc status after acceptProposal
    test('TC-HAND-06c: streamProposalOutcome emits connected status after accept',
        () async {
      await fakeFirestore
          .collection('neutral_handshakes')
          .doc('user1_user2')
          .set({
        'proposerId': 'user1',
        'proposerUsername': 'testuser1',
        'partnerId': 'user2',
        'partnerUsername': 'alice',
        'status': 'pending',
      });

      final auth2 = MockFirebaseAuth(
          signedIn: true, mockUser: MockUser(uid: 'user2'));
      final partnerRepo = HandshakeRepository(db: fakeFirestore, auth: auth2);
      await partnerRepo.acceptProposal('user1_user2', 'user1');

      final repo = HandshakeRepository(db: fakeFirestore, auth: mockAuth);
      final docSnap = await repo.streamProposalOutcome('user1_user2').first;
      expect(docSnap.data()?['status'], equals('connected'));
    });
  });
}
