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
      mockAuth = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'user1'));
    });

    // HAND-01: sendProposal() creates neutral_handshakes doc with proposerId, partnerId, status=pending
    test('TC-HAND-01: sendProposal creates doc with proposerId/partnerId/status=pending', () async {
      fail('TC-HAND-01: not implemented yet');
    });

    // HAND-02: acceptProposal() WriteBatch updates status to connected
    test('TC-HAND-02: acceptProposal updates status to connected', () async {
      fail('TC-HAND-02: not implemented yet');
    });

    // HAND-03: rejectProposal() updates status to rejected
    test('TC-HAND-03: rejectProposal sets status to rejected', () async {
      fail('TC-HAND-03: not implemented yet');
    });

    // HAND-04: cancelProposal() deletes the doc
    test('TC-HAND-04: cancelProposal deletes the handshake doc', () async {
      fail('TC-HAND-04: not implemented yet');
    });

    // HAND-05: streamIncomingPending emits docs where partnerId==uid and status==pending
    test('TC-HAND-05: streamIncomingPending emits pending docs for partner', () async {
      fail('TC-HAND-05: not implemented yet');
    });
  });
}
