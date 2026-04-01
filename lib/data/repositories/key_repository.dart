import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../models/user_model.dart';

/// Manages RSA key transfers and user connections.
/// Extracted from the former ConnectionService.
class KeyRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FlutterSecureStorage _secure;

  KeyRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    FlutterSecureStorage? secure,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _secure = secure ?? const FlutterSecureStorage();

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw AuthException('Not authenticated.');
    return uid;
  }

  // ─── User search ──────────────────────────────────────────────────────────

  Future<List<UserModel>> searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];
    try {
      final result = await _db
          .collection(FirebaseConstants.users)
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThanOrEqualTo: '$q\uf8ff')
          .limit(10)
          .get();
      return result.docs
          .where((doc) => doc.id != _uid)
          .map((doc) => UserModel.fromDoc(doc))
          .toList();
    } on FirebaseException catch (e) {
      throw NetworkException('User search failed: ${e.message ?? e.code}');
    }
  }

  // ─── Connections ──────────────────────────────────────────────────────────

  Future<String?> getConnectionStatus(String otherUserId) async {
    try {
      for (final field in ['senderId', 'receiverId']) {
        final other = field == 'senderId' ? 'receiverId' : 'senderId';
        final snap = await _db
            .collection(FirebaseConstants.friendRequests)
            .where(field, isEqualTo: _uid)
            .where(other, isEqualTo: otherUserId)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          return snap.docs.first.data()['status'] as String?;
        }
      }
      return null;
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Could not check connection status: ${e.message ?? e.code}');
    }
  }

  Future<void> sendConnectionRequest(String targetUserId) async {
    try {
      final status = await getConnectionStatus(targetUserId);
      if (status != null) return;
      await _db.collection(FirebaseConstants.friendRequests).add({
        'senderId': _uid,
        'receiverId': targetUserId,
        'participants': [_uid, targetUserId],
        'status': 'accepted',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _writePublicKeyTo(targetUserId);
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Connection request failed: ${e.message ?? e.code}');
    }
  }

  Future<List<UserModel>> getConnectedFriends() async {
    try {
      final sent = await _db
          .collection(FirebaseConstants.friendRequests)
          .where('senderId', isEqualTo: _uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      final received = await _db
          .collection(FirebaseConstants.friendRequests)
          .where('receiverId', isEqualTo: _uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final otherUids = <String>{};
      for (final doc in sent.docs) {
        otherUids.add(doc.data()['receiverId'] as String);
      }
      for (final doc in received.docs) {
        otherUids.add(doc.data()['senderId'] as String);
      }

      final friends = <UserModel>[];
      for (final uid in otherUids) {
        final doc = await _db.collection(FirebaseConstants.users).doc(uid).get();
        if (doc.exists) friends.add(UserModel.fromDoc(doc));
      }
      return friends;
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Could not load connections: ${e.message ?? e.code}');
    }
  }

  Future<void> resyncPublicKeyToAllConnections() async {
    try {
      final friends = await getConnectedFriends();
      for (final f in friends) {
        await _writePublicKeyTo(f.uid);
      }
    } on FirebaseException catch (e) {
      throw NetworkException('Key resync failed: ${e.message ?? e.code}');
    }
  }

  // ─── RSA public key sharing ───────────────────────────────────────────────

  Future<void> sendPublicKey({
    required String toUserId,
    required String toUsername,
  }) async {
    try {
      final userDoc =
          await _db.collection(FirebaseConstants.users).doc(_uid).get();
      final publicKey = userDoc.data()?['publicKey'] as String?;
      if (publicKey == null || publicKey.isEmpty) {
        throw KeyNotFoundException('Generate RSA keys first');
      }
      final fromUsername = userDoc.data()?['username'] as String? ??
          _auth.currentUser?.displayName ??
          'Unknown';

      await _upsertKeyTransfer(
        toUserId: toUserId,
        publicKey: publicKey,
        fromUsername: fromUsername,
        includeStatus: true,
      );

      await _db.collection(FirebaseConstants.notifications).add({
        'toUserId': toUserId,
        'fromUsername': fromUsername,
        'type': 'rsa_key_received',
        'message': '🔑 $fromUsername sent you their RSA Public Key',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } on KeyNotFoundException {
      rethrow;
    } on FirebaseException catch (e) {
      throw NetworkException('Failed to send key: ${e.message ?? e.code}');
    }
  }

  Future<String?> getPublicKeyFor(String fromUserId) async {
    try {
      final result = await _db
          .collection(FirebaseConstants.rsaKeyTransfers)
          .where('fromUserId', isEqualTo: fromUserId)
          .where('toUserId', isEqualTo: _uid)
          .limit(1)
          .get();
      if (result.docs.isEmpty) return null;
      return result.docs.first.data()['publicKey'] as String?;
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Could not fetch public key: ${e.message ?? e.code}');
    }
  }

  Future<List<Map<String, dynamic>>> getSentKeyTransfers() async {
    try {
      final snapshot = await _db
          .collection(FirebaseConstants.rsaKeyTransfers)
          .where('fromUserId', isEqualTo: _uid)
          .get();

      final transfers = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final toUserId = data['toUserId'] as String;
        final userDoc =
            await _db.collection(FirebaseConstants.users).doc(toUserId).get();
        transfers.add({
          'docId': doc.id,
          ...data,
          'toUsername': userDoc.data()?['username'] ?? 'Unknown',
        });
      }
      transfers.sort((a, b) {
        final aTs = a['sentAt'] as Timestamp?;
        final bTs = b['sentAt'] as Timestamp?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });
      return transfers;
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Could not load sent keys: ${e.message ?? e.code}');
    }
  }

  Future<List<Map<String, dynamic>>> getReceivedKeys() async {
    try {
      final snapshot = await _db
          .collection(FirebaseConstants.rsaKeyTransfers)
          .where('toUserId', isEqualTo: _uid)
          .get();

      final keys = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final fromUserId = data['fromUserId'] as String;
        final userDoc = await _db
            .collection(FirebaseConstants.users)
            .doc(fromUserId)
            .get();
        keys.add({
          'docId': doc.id,
          ...data,
          'fromUsername': userDoc.data()?['username'] ?? 'Unknown',
        });
      }
      keys.sort((a, b) {
        final aTs = a['sentAt'] as Timestamp?;
        final bTs = b['sentAt'] as Timestamp?;
        if (aTs == null && bTs == null) return 0;
        if (aTs == null) return 1;
        if (bTs == null) return -1;
        return bTs.compareTo(aTs);
      });
      return keys;
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Could not load received keys: ${e.message ?? e.code}');
    }
  }

  // ─── Local key storage ────────────────────────────────────────────────────

  Future<void> saveReceivedKey(String fromUserId, String publicKey) async {
    try {
      await _secure.write(
        key: '${FirebaseConstants.publicKeyStoragePrefix}$fromUserId',
        value: publicKey,
      );
    } catch (e) {
      throw NetworkException('Failed to save key locally: $e');
    }
  }

  Future<bool> isKeySaved(String fromUserId) async {
    try {
      final val = await _secure.read(
          key: '${FirebaseConstants.publicKeyStoragePrefix}$fromUserId');
      return val != null;
    } catch (_) {
      return false;
    }
  }

  Future<bool> hasReceivedKeyFrom(String fromUserId) async {
    try {
      final result = await _db
          .collection(FirebaseConstants.rsaKeyTransfers)
          .where('fromUserId', isEqualTo: fromUserId)
          .where('toUserId', isEqualTo: _uid)
          .limit(1)
          .get();
      return result.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      throw NetworkException('Key lookup failed: ${e.message ?? e.code}');
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  Future<void> _writePublicKeyTo(String toUserId) async {
    final userDoc = await _db.collection(FirebaseConstants.users).doc(_uid).get();
    final publicKey = userDoc.data()?['publicKey'] as String?;
    if (publicKey == null || publicKey.isEmpty) return;
    await _upsertKeyTransfer(toUserId: toUserId, publicKey: publicKey);
  }

  Future<void> _upsertKeyTransfer({
    required String toUserId,
    required String publicKey,
    String? fromUsername,
    bool includeStatus = false,
  }) async {
    final existing = await _db
        .collection(FirebaseConstants.rsaKeyTransfers)
        .where('fromUserId', isEqualTo: _uid)
        .where('toUserId', isEqualTo: toUserId)
        .limit(1)
        .get();

    final update = <String, dynamic>{
      'publicKey': publicKey,
      'sentAt': FieldValue.serverTimestamp(),
      if (fromUsername != null) 'fromUsername': fromUsername,
      if (includeStatus) 'status': 'pending',
    };

    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update(update);
    } else {
      await _db.collection(FirebaseConstants.rsaKeyTransfers).add({
        'fromUserId': _uid,
        'toUserId': toUserId,
        ...update,
      });
    }
  }
}
