import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // ─── Auth ────────────────────────────────────────────────────────────────

  Future<UserCredential> register({
    required String username,
    required String email,
    required String phone,
    required String password,
  }) async {
    // Check username uniqueness
    final existing = await _db
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      throw Exception('Username already taken. Please choose another.');
    }

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Store display name for easy access
    await credential.user!.updateDisplayName(username);


    await _db.collection('users').doc(credential.user!.uid).set({
      'username': username,
      'email': email,
      'phone': phone,
      'publicKey': null,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return credential;
  }

  /// Returns true if the username is already taken in Firestore.
  Future<bool> isUsernameTaken(String username) async {
    final result = await _db
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();
    return result.docs.isNotEmpty;
  }

  /// Logs in with username (looks up email in Firestore first).
  /// Throws [FirebaseAuthException] for auth errors (check .code).
  /// Throws [Exception] with a string code for lookup errors.
  Future<UserCredential> loginWithUsername({
    required String username,
    required String password,
  }) async {
    // Step 1 — Firestore lookup
    late QuerySnapshot<Map<String, dynamic>> query;
    try {
      query = await _db
          .collection('users')
          .where('username', isEqualTo: username)
          .limit(1)
          .get();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception('firestore-permission-denied');
      }
      throw Exception('firestore-error:${e.code}');
    }

    // Step 2 — Check document exists
    if (query.docs.isEmpty) {
      throw Exception('username-not-found');
    }

    // Step 3 — Extract email
    final data = query.docs.first.data();
    final email = (data['email'] as String?)?.trim() ?? '';
    if (email.isEmpty) {
      throw Exception('account-data-corrupted');
    }

    // Step 4 — Firebase Auth sign-in (let FirebaseAuthException propagate as-is)
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    // Step 5 — Success
    return credential;
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ─── RSA Key Management ───────────────────────────────────────────────────

  static const _privateKeyStorageKey = 'rsa_private_key';

  /// Generates a 2048-bit RSA key pair, stores the private key in secure
  /// storage and uploads the public key to Firestore.
  Future<void> generateAndStoreKeyPair() async {
    final pair = _generateRSAKeyPair();
    final pubKey = pair.publicKey as RSAPublicKey;
    final privKey = pair.privateKey as RSAPrivateKey;

    final encodedPublic = _encodePublicKey(pubKey);
    final encodedPrivate = _encodePrivateKey(privKey);

    // Private key stays on device only
    await _secureStorage.write(
      key: _privateKeyStorageKey,
      value: encodedPrivate,
    );

    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated.');

    await _db.collection('users').doc(uid).update({'publicKey': encodedPublic});
  }

  Future<bool> hasKeyPair() async {
    final stored = await _secureStorage.read(key: _privateKeyStorageKey);
    return stored != null;
  }

  Future<String?> getPublicKey() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    final doc = await _db.collection('users').doc(uid).get();
    return doc.data()?['publicKey'] as String?;
  }

  // ─── RSA helpers ─────────────────────────────────────────────────────────

  AsymmetricKeyPair<PublicKey, PrivateKey> _generateRSAKeyPair() {
    final secureRandom = FortunaRandom();
    final seedSource = Random.secure();
    secureRandom.seed(
      KeyParameter(
        Uint8List.fromList(
          List<int>.generate(32, (_) => seedSource.nextInt(256)),
        ),
      ),
    );

    final keyGen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.parse('65537'), 2048, 64),
          secureRandom,
        ),
      );

    return keyGen.generateKeyPair();
  }

  String _encodePublicKey(RSAPublicKey key) {
    return jsonEncode({
      'modulus': key.modulus!.toRadixString(16),
      'exponent': key.publicExponent!.toRadixString(16),
    });
  }

  String _encodePrivateKey(RSAPrivateKey key) {
    return jsonEncode({
      'modulus': key.modulus!.toRadixString(16),
      'privateExponent': key.privateExponent!.toRadixString(16),
      'p': key.p!.toRadixString(16),
      'q': key.q!.toRadixString(16),
    });
  }
}
