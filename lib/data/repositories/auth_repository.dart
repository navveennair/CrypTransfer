import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
    await credential.user!.updateDisplayName(username);

    await _db.collection(FirebaseConstants.users).doc(credential.user!.uid).set({
      'username': username,
      'email': email,
      'phone': phone,
      'publicKey': null,
      'createdAt': FieldValue.serverTimestamp(),
    });

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
      if (e.code == 'permission-denied') {
        throw AuthException('Database permission error. Check Firestore security rules.',
            code: 'firestore-permission-denied');
      }
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

    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> logout() => _auth.signOut();

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
}

