import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:pointycastle/export.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../models/user_model.dart';
import '../services/encryption_service.dart';

// Top-level function required by compute() — must not be a closure or instance method.
AsymmetricKeyPair<PublicKey, PrivateKey> _generateKeyPairIsolate(dynamic _) =>
    EncryptionService.generateRsaKeyPairSync();

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final FlutterSecureStorage _secure;

  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FlutterSecureStorage? secure,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _secure = secure ?? const FlutterSecureStorage();

  // ─── Auth state ────────────────────────────────────────────────────────────

  User? get currentUser => _auth.currentUser;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Register ──────────────────────────────────────────────────────────────

  Future<UserCredential> register({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    final existing = await _db
        .collection(FirebaseConstants.users)
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      throw AuthException('Username already taken. Please choose another.');
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    // Wait for JWT so subsequent Firestore writes are authenticated.
    await credential.user!.getIdToken();
    await credential.user!.updateDisplayName(username);

    final uid = credential.user!.uid;
    final batch = _db.batch();
    batch.set(
      _db.collection(FirebaseConstants.users).doc(uid),
      {
        'username': username,
        'email': email,
        'phone': phone,
        'publicKey': null,
        'isAdmin': false,
        'isFirstTime': true,
        'createdAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      _db
          .collection(FirebaseConstants.users)
          .doc(uid)
          .collection(FirebaseConstants.profile)
          .doc('preferences'),
      {
        'biometricGateEnabled': false,
        'themeMode': 'dark',
        'keyVaultCreatedAt': null,
        'lastVaultAccessAt': null,
      },
    );
    await batch.commit();

    return credential;
  }

  // ─── Login ─────────────────────────────────────────────────────────────────

  Future<UserCredential> loginWithUsername({
    required String username,
    required String password,
  }) async {
    late QuerySnapshot<Map<String, dynamic>> query;
    try {
      query = await _db
          .collection(FirebaseConstants.users)
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
    } on FirebaseException catch (e) {
      throw NetworkException('Database error. Check your connection.',
          code: 'firestore-error:${e.code}');
    }

    if (query.docs.isEmpty) {
      throw AuthException('No account found with this username.',
          code: 'username-not-found');
    }

    final data = query.docs.first.data();
    final email = (data['email'] as String?)?.trim() ?? '';
    if (email.isEmpty) {
      throw AuthException('Account data is corrupted. Please re-register.',
          code: 'account-data-corrupted');
    }

    final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
    await cred.user?.getIdToken();
    return cred;
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn(
        serverClientId: FirebaseConstants.googleWebClientId,
      ).signIn();
      if (googleUser == null) throw AuthException('Google sign in cancelled.');

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user!;
      await user.getIdToken();

      // Check if user document exists, if not create one
      final userDoc = await _db.collection(FirebaseConstants.users).doc(user.uid).get();
      if (!userDoc.exists) {
        String username = user.email!.split('@')[0].replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '');

        bool taken = await isUsernameTaken(username);
        if (taken) {
          username = '${username}_${DateTime.now().millisecondsSinceEpoch % 1000}';
        }

        final gBatch = _db.batch();
        gBatch.set(
          _db.collection(FirebaseConstants.users).doc(user.uid),
          {
            'username': username,
            'email': user.email,
            'phone': user.phoneNumber ?? '',
            'publicKey': null,
            'isAdmin': false,
            'isFirstTime': true,
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
        gBatch.set(
          _db
              .collection(FirebaseConstants.users)
              .doc(user.uid)
              .collection(FirebaseConstants.profile)
              .doc('preferences'),
          {
            'biometricGateEnabled': false,
            'themeMode': 'dark',
            'keyVaultCreatedAt': null,
            'lastVaultAccessAt': null,
          },
        );
        await gBatch.commit();
        await user.updateDisplayName(username);
      }

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw AuthException(e.message ?? 'Google Sign-In failed', code: e.code);
    } catch (e) {
      throw NetworkException('Google Sign-In failed: $e');
    }
  }

  Future<void> logout() async {
    await GoogleSignIn().signOut();
    await _auth.signOut();
  }

  // ─── Username uniqueness ───────────────────────────────────────────────────

  Future<bool> isUsernameTaken(String username) async {
    final result = await _db
        .collection(FirebaseConstants.users)
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    return result.docs.isNotEmpty;
  }

  // ─── RSA key management ────────────────────────────────────────────────────

  Future<void> generateAndStoreKeyPair() async {
    final pair = await compute(_generateKeyPairIsolate, null);
    final pubKey = pair.publicKey as RSAPublicKey;
    final privKey = pair.privateKey as RSAPrivateKey;

    await _secure.write(
      key: FirebaseConstants.privateKeyStorageKey,
      value: EncryptionService.encodePrivateKey(privKey),
    );

    final uid = _auth.currentUser?.uid;
    if (uid == null) throw AuthException('Not authenticated.');

    await _db.collection(FirebaseConstants.users).doc(uid).update({
      'publicKey': EncryptionService.encodePublicKey(pubKey),
    });
  }

  Future<bool> hasKeyPair() async {
    final stored =
        await _secure.read(key: FirebaseConstants.privateKeyStorageKey);
    return stored != null;
  }

  Future<String?> getPublicKey() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db.collection(FirebaseConstants.users).doc(uid).get();
    return doc.data()?['publicKey'] as String?;
  }

  Future<String?> getPrivateKeyJson() async {
    return _secure.read(key: FirebaseConstants.privateKeyStorageKey);
  }

  // ─── User profile ──────────────────────────────────────────────────────────

  Future<UserModel?> getUserProfile(String uid) async {
    final doc = await _db.collection(FirebaseConstants.users).doc(uid).get();
    if (!doc.exists) return null;
    return UserModel.fromDoc(doc);
  }

  Stream<UserModel?> streamUserProfile(String uid) {
    return _db
        .collection(FirebaseConstants.users)
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromDoc(doc) : null);
  }
}

