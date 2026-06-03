import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:cryptransfer/data/repositories/auth_repository.dart';
import 'package:cryptransfer/core/errors/app_exceptions.dart';

import '../mocks/mock_firebase.dart';

// ── Auth helpers for error-case tests ──────────────────────────────────────

/// Throws email-already-in-use on every createUser call.
class _EmailInUseAuth extends MockFirebaseAuth {
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    throw FirebaseAuthException(
      code: 'email-already-in-use',
      message: 'The email address is already in use.',
    );
  }
}

/// Throws wrong-password on every signIn call.
class _WrongPasswordAuth extends MockFirebaseAuth {
  _WrongPasswordAuth({required MockUser mockUser})
      : super(signedIn: false, mockUser: mockUser);

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    throw FirebaseAuthException(
      code: 'wrong-password',
      message: 'The password is invalid.',
    );
  }
}

// ── Tests ───────────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Stub GoogleSignIn MethodChannel so logout() doesn't hit native platform.
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/google_sign_in'),
      (_) async => null,
    );
  });

  // ── Registration tests (TC001–TC003) ──────────────────────────────────────
  group('Registration (TC001–TC003)', () {
    late FakeFirebaseFirestore fakeDb;
    late MockFirebaseAuth mockAuth;
    late FakeSecureStorage fakeStorage;
    late AuthRepository repo;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      mockAuth = MockFirebaseAuth();
      fakeStorage = FakeSecureStorage();
      repo = AuthRepository(auth: mockAuth, db: fakeDb, secure: fakeStorage);
    });

    test('TC001 - Register valid user creates Firestore document', () async {
      final cred = await repo.register(
        username: 'alice',
        email: 'alice@test.com',
        phone: '+601234567',
        password: 'password123',
      );

      expect(cred.user, isNotNull);

      final doc =
          await fakeDb.collection('users').doc(cred.user!.uid).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['username'], equals('alice'));
      expect(doc.data()!['email'], equals('alice@test.com'));
    });

    test('TC002 - Duplicate username rejected with AuthException', () async {
      await repo.register(
        username: 'bob',
        email: 'bob@test.com',
        phone: '+60111',
        password: 'pass123',
      );

      await expectLater(
        repo.register(
          username: 'bob',
          email: 'bob2@test.com',
          phone: '+60222',
          password: 'pass456',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('TC003 - Duplicate email propagates FirebaseAuthException', () async {
      final throwingRepo = AuthRepository(
        auth: _EmailInUseAuth(),
        db: fakeDb,
        secure: fakeStorage,
      );

      await expectLater(
        throwingRepo.register(
          username: 'charlie',
          email: 'existing@test.com',
          phone: '+60333',
          password: 'pass789',
        ),
        throwsA(isA<FirebaseAuthException>()),
      );
    });
  });

  // ── Login tests (TC004–TC006) ─────────────────────────────────────────────
  group('Login (TC004–TC006)', () {
    late FakeFirebaseFirestore fakeDb;
    late FakeSecureStorage fakeStorage;

    setUp(() {
      fakeDb = FakeFirebaseFirestore();
      fakeStorage = FakeSecureStorage();
    });

    test('TC004 - Login with valid credentials succeeds', () async {
      await fakeDb.collection('users').doc('uid-dave').set({
        'username': 'dave',
        'email': 'dave@test.com',
        'phone': '+60444',
        'publicKey': null,
      });

      final authWithUser = MockFirebaseAuth(
        signedIn: false,
        mockUser: MockUser(uid: 'uid-dave', email: 'dave@test.com'),
      );
      final repo = AuthRepository(
        auth: authWithUser,
        db: fakeDb,
        secure: fakeStorage,
      );

      final cred = await repo.loginWithUsername(
        username: 'dave',
        password: 'pass123',
      );

      expect(cred.user, isNotNull);
      expect(cred.user!.email, equals('dave@test.com'));
    });

    test('TC005 - Login with wrong password throws FirebaseAuthException',
        () async {
      final mockUser = MockUser(uid: 'uid-eve', email: 'eve@test.com');
      await fakeDb.collection('users').doc('uid-eve').set({
        'username': 'eve',
        'email': 'eve@test.com',
        'phone': '+60555',
      });

      final repo = AuthRepository(
        auth: _WrongPasswordAuth(mockUser: mockUser),
        db: fakeDb,
        secure: fakeStorage,
      );

      await expectLater(
        repo.loginWithUsername(username: 'eve', password: 'wrongpass'),
        throwsA(isA<FirebaseAuthException>()),
      );
    });

    test('TC006 - Login with non-existent username throws AuthException',
        () async {
      final repo = AuthRepository(
        auth: MockFirebaseAuth(),
        db: fakeDb,
        secure: fakeStorage,
      );

      await expectLater(
        repo.loginWithUsername(username: 'ghostuser', password: 'anypass'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.code,
            'code',
            'username-not-found',
          ),
        ),
      );
    });
  });

  // ── RSA key management (TC007–TC009) ──────────────────────────────────────
  // These generate a 2048-bit RSA key pair — allow extra time.
  group('RSA Key Management (TC007–TC009)', () {
    late FakeFirebaseFirestore fakeDb;
    late FakeSecureStorage fakeStorage;
    late AuthRepository repo;
    late String userId;

    setUpAll(() async {
      fakeDb = FakeFirebaseFirestore();
      fakeStorage = FakeSecureStorage();
      final auth = MockFirebaseAuth();
      repo = AuthRepository(auth: auth, db: fakeDb, secure: fakeStorage);

      final cred = await repo.register(
        username: 'keyuser',
        email: 'keyuser@test.com',
        phone: '+60999',
        password: 'pass123',
      );
      userId = cred.user!.uid;

      // Generate RSA key pair (~2–5 s)
      await repo.generateAndStoreKeyPair();
    });

    test('TC007 - RSA keypair generated on register', () async {
      final hasKey = await repo.hasKeyPair();
      expect(hasKey, isTrue,
          reason: 'hasKeyPair() must be true after generateAndStoreKeyPair()');
    });

    test('TC008 - Private key stored in secure storage NOT in Firestore',
        () async {
      final stored =
          await fakeStorage.read(key: 'rsa_private_key');
      expect(stored, isNotNull,
          reason: 'Private key must be written to secure storage');

      final doc = await fakeDb.collection('users').doc(userId).get();
      expect(doc.data()!.containsKey('privateKey'), isFalse,
          reason: 'privateKey field must NOT appear in Firestore users doc');
    });

    test('TC009 - Public key saved to Firestore', () async {
      final doc = await fakeDb.collection('users').doc(userId).get();
      final publicKey = doc.data()!['publicKey'] as String?;

      expect(publicKey, isNotNull, reason: 'publicKey must be in Firestore');
      expect(publicKey, isNotEmpty, reason: 'publicKey must not be empty');
    });
  });

  // ── Logout (TC010) ────────────────────────────────────────────────────────
  group('Logout (TC010)', () {
    test('TC010 - Logout clears current user', () async {
      final fakeDb = FakeFirebaseFirestore();
      final fakeStorage = FakeSecureStorage();

      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'uid-ivy', email: 'ivy@test.com'),
      );
      final repo =
          AuthRepository(auth: auth, db: fakeDb, secure: fakeStorage);

      expect(repo.currentUser, isNotNull,
          reason: 'Should be signed in before logout');

      await repo.logout();

      expect(repo.currentUser, isNull,
          reason: 'currentUser must be null after logout');
    });
  });
}
