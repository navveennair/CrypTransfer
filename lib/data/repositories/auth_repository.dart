import 'dart:async';
import 'dart:convert';

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

  Completer<void>? _anonAuthCompleter;

  AuthRepository({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    FlutterSecureStorage? secure,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _secure = secure ?? const FlutterSecureStorage();

  // ─── Auth state ────────────────────────────────────────────────────────────

  User? get currentUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;
  String? get currentDisplayName => _auth.currentUser?.displayName;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── Register ──────────────────────────────────────────────────────────────

  Future<UserCredential> register({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    await _ensureAuthenticated();
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
    await _ensureAuthenticated();
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

  Future<void> sendPasswordResetEmail(String username) async {
    await _ensureAuthenticated();
    final query = await _db
        .collection(FirebaseConstants.users)
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    if (query.docs.isEmpty) {
      throw AuthException('No account found with this username.',
          code: 'username-not-found');
    }
    final email = (query.docs.first.data()['email'] as String?)?.trim() ?? '';
    if (email.isEmpty) {
      throw AuthException('Account data is corrupted.',
          code: 'account-data-corrupted');
    }
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
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

  // ─── Anonymous auth pre-flight ─────────────────────────────────────────────
  // Callers that need to query Firestore before the user is signed in (username
  // availability check, login username→email lookup, password reset) call this
  // first.  If there is already a real or anonymous session it is a no-op.
  // The anonymous session is silently superseded when the user later signs in
  // with email/password or Google.
  Future<void> _ensureAuthenticated() async {
    if (_auth.currentUser != null) return;
    if (_anonAuthCompleter != null) {
      await _anonAuthCompleter!.future;
      return;
    }
    final completer = Completer<void>();
    _anonAuthCompleter = completer;
    try {
      await _auth.signInAnonymously();
      completer.complete();
    } on FirebaseAuthException catch (e) {
      completer.completeError(e);
      throw NetworkException('Could not establish connection: ${e.message ?? e.code}');
    } finally {
      _anonAuthCompleter = null;
    }
  }

  // ─── Username uniqueness ───────────────────────────────────────────────────

  Future<bool> isUsernameTaken(String username) async {
    await _ensureAuthenticated();
    final result = await _db
        .collection(FirebaseConstants.users)
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    return result.docs.isNotEmpty;
  }

  // ─── RSA key management ────────────────────────────────────────────────────

  Future<void> generateAndStoreKeyPair() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw AuthException('Not authenticated.');

    final pair = await compute(_generateKeyPairIsolate, null);
    final pubKey = pair.publicKey as RSAPublicKey;
    final privKey = pair.privateKey as RSAPrivateKey;

    await _secure.write(
      key: FirebaseConstants.privateKeyStorageKey,
      value: EncryptionService.encodePrivateKey(privKey),
    );

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

  // Computes SHA-256 of the UTF-8 bytes of the JSON-encoded public key.
  // Returns full 64-char hex string. Display: fingerprint.substring(0, 16).toUpperCase()
  // STATIC: vault screen calls AuthRepository.computeFingerprint() without needing an instance.
  static String computeFingerprint(String publicKeyJson) {
    final bytes = Uint8List.fromList(utf8.encode(publicKeyJson));
    final digest = SHA256Digest();
    final hash = digest.process(bytes);
    return hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Regenerates the RSA-2048 keypair.
  /// Writes new private key to FlutterSecureStorage, updates publicKey in Firestore,
  /// and appends an immutable audit document to rsa_key_manager subcollection.
  /// Uses a 3-doc WriteBatch: publicKey update + audit log + keyVaultCreatedAt (D-14).
  Future<void> regenerateKeyPair(String uid) async {
    final pair = await compute(_generateKeyPairIsolate, null);
    final pubKey = pair.publicKey as RSAPublicKey;
    final privKey = pair.privateKey as RSAPrivateKey;

    final pubKeyJson = EncryptionService.encodePublicKey(pubKey);
    final privKeyJson = EncryptionService.encodePrivateKey(privKey);
    final fingerprint = computeFingerprint(pubKeyJson);

    // Write new private key first — old key is superseded immediately.
    await _secure.write(
      key: FirebaseConstants.privateKeyStorageKey,
      value: privKeyJson,
    );

    final userRef = _db.collection(FirebaseConstants.users).doc(uid);
    final auditRef = userRef.collection(FirebaseConstants.rsaKeyManager).doc();
    final prefsRef = userRef.collection(FirebaseConstants.profile).doc('preferences');
    final batch = _db.batch();
    batch.update(userRef, {'publicKey': pubKeyJson});
    batch.set(auditRef, {
      'action': 'regenerated',
      'timestamp': FieldValue.serverTimestamp(),
      'publicKeyHash': fingerprint,
      'deviceInfo': defaultTargetPlatform.name,
    });
    batch.set(prefsRef, {'keyVaultCreatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true)); // D-14: stamp regeneration time; merge preserves other prefs
    await batch.commit();
  }

  /// Deletes the RSA keypair.
  /// Removes private key from FlutterSecureStorage, clears publicKey in Firestore,
  /// and appends an immutable audit document to rsa_key_manager subcollection.
  /// Uses a 2-doc WriteBatch: publicKey delete + audit log (no keyVaultCreatedAt on delete).
  Future<void> deleteKeyPair(String uid) async {
    final userRef = _db.collection(FirebaseConstants.users).doc(uid);
    final auditRef = userRef.collection(FirebaseConstants.rsaKeyManager).doc();
    final batch = _db.batch();
    batch.update(userRef, {'publicKey': FieldValue.delete()});
    batch.set(auditRef, {
      'action': 'deleted',
      'timestamp': FieldValue.serverTimestamp(),
      'publicKeyHash': null, // no key to hash after deletion
      'deviceInfo': defaultTargetPlatform.name,
    });
    await batch.commit();
    // Secure-storage wipe only after Firestore commit succeeds.
    // If batch.commit() throws, the private key is NOT wiped — Firestore and
    // secure storage remain consistent (both still hold key material).
    await _secure.delete(key: FirebaseConstants.privateKeyStorageKey);
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

  /// Fetch the isReadyToReceive status for the user.
  Future<bool> getIsReadyToReceive(String uid) async {
    try {
      final doc = await _db.collection(FirebaseConstants.users).doc(uid).get();
      return doc.data()?['isReadyToReceive'] as bool? ?? false;
    } on FirebaseException {
      return false;
    }
  }

  /// Updates the lastVaultAccessAt timestamp in users/{uid}/profile/preferences.
  /// Uses set(merge: true) so it creates the doc if missing (safe for users
  /// who registered before Phase 03 and lack the profile/preferences document).
  Future<void> updateLastVaultAccess(String uid) async {
    try {
      await _db
          .collection(FirebaseConstants.users)
          .doc(uid)
          .collection(FirebaseConstants.profile)
          .doc('preferences')
          .set(
            {'lastVaultAccessAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true),
          );
    } on FirebaseException catch (e) {
      throw NetworkException(
        'Failed to update vault access time.',
        code: 'firestore-error:${e.code}',
      );
    }
  }
}

