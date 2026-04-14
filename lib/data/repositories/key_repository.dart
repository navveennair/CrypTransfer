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

  /// Sends the current user's RSA public key to [toUserId].
  ///
  /// When [isHandshake] is true (receiver has explicitly selected this sender),
  /// the key-transfer document is stamped with `status: 'handshake_complete'`
  /// instead of the default `'pending'`, signalling to the sender that the
  /// receiver is ready and the session is isolated to this pair.
  Future<void> sendPublicKey({
    required String toUserId,
    required String toUsername,
    bool isHandshake = false,
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
        status: isHandshake ? 'handshake_complete' : 'pending',
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
    await _upsertKeyTransfer(toUserId: toUserId, publicKey: publicKey, status: 'pending');
  }

  Future<void> _upsertKeyTransfer({
    required String toUserId,
    required String publicKey,
    String? fromUsername,
    String status = 'pending',
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
      'fromUsername': ?fromUsername,
      'status': status,
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

  // ─── Session key management ───────────────────────────────────────────────

  /// Returns all users who have sent their RSA public key to the current user.
  /// The [publicKey] on each [UserModel] comes from the key transfer document.
  Future<List<UserModel>> getAvailableReceivers() async {
    try {
      final snapshot = await _db
          .collection(FirebaseConstants.rsaKeyTransfers)
          .where('toUserId', isEqualTo: _uid)
          .get();

      final receivers = <UserModel>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final fromUserId = data['fromUserId'] as String;
        final publicKey = data['publicKey'] as String?;
        if (publicKey == null || publicKey.isEmpty) continue;
        final userDoc = await _db
            .collection(FirebaseConstants.users)
            .doc(fromUserId)
            .get();
        if (!userDoc.exists) continue;
        final userData = userDoc.data()!;
        receivers.add(UserModel(
          uid: fromUserId,
          username: userData['username'] as String? ?? 'Unknown',
          email: userData['email'] as String? ?? '',
          phone: userData['phone'] as String? ?? '',
          publicKey: publicKey,
        ));
      }
      return receivers;
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Could not load available receivers: ${e.message ?? e.code}');
    }
  }

  // ─── Receiver-Authorized Handshake ───────────────────────────────────────

  /// Atomically marks [senderUid] as the session-authorized sender.
  ///
  /// A single [WriteBatch] commits two writes together:
  ///
  /// 1. `users/{receiverUid}.selectedSenderUid = senderUid` — persists the
  ///    authorization so the sender side can verify it came from this receiver.
  ///
  /// 2. `rsa_key_transfers` — upserts the receiver's RSA public key addressed
  ///    to [senderUid] with `status: 'handshake_complete'`, signalling the
  ///    sender's Firestore stream that the secure channel is open.
  ///
  /// A notification is sent afterward (best-effort, outside the batch).
  /// Throws [KeyNotFoundException] if the receiver has no public key yet.
  Future<void> selectSenderHandshake({
    required String senderUid,
    required String senderUsername,
  }) async {
    try {
      // Read receiver's current public key and display name.
      final userDoc =
          await _db.collection(FirebaseConstants.users).doc(_uid).get();
      final publicKey = userDoc.data()?['publicKey'] as String?;
      if (publicKey == null || publicKey.isEmpty) {
        throw KeyNotFoundException('Generate RSA keys first');
      }
      final fromUsername = userDoc.data()?['username'] as String? ??
          _auth.currentUser?.displayName ??
          'Unknown';

      // Find existing key-transfer doc to reuse its reference in the batch.
      final existing = await _db
          .collection(FirebaseConstants.rsaKeyTransfers)
          .where('fromUserId', isEqualTo: _uid)
          .where('toUserId', isEqualTo: senderUid)
          .limit(1)
          .get();

      final batch = _db.batch();

      // Write 1 — mark selected sender on the receiver's user document.
      batch.set(
        _db.collection(FirebaseConstants.users).doc(_uid),
        {'selectedSenderUid': senderUid},
        SetOptions(merge: true),
      );

      // Write 2 — publish receiver's public key to the sender with
      // handshake_complete status so the sender's stream fires immediately.
      final keyPayload = <String, dynamic>{
        'publicKey': publicKey,
        'sentAt': FieldValue.serverTimestamp(),
        'fromUsername': fromUsername,
        'status': 'handshake_complete',
      };
      if (existing.docs.isNotEmpty) {
        batch.update(existing.docs.first.reference, keyPayload);
      } else {
        final newRef = _db.collection(FirebaseConstants.rsaKeyTransfers).doc();
        batch.set(newRef, {
          'fromUserId': _uid,
          'toUserId': senderUid,
          ...keyPayload,
        });
      }

      await batch.commit();

      // Notification — best-effort, not part of the atomic batch.
      await _db.collection(FirebaseConstants.notifications).add({
        'toUserId': senderUid,
        'fromUsername': fromUsername,
        'type': 'rsa_key_received',
        'message': '🔑 $fromUsername sent you their RSA Public Key',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } on KeyNotFoundException {
      rethrow;
    } on FirebaseException catch (e) {
      throw NetworkException('Handshake failed: ${e.message ?? e.code}');
    }
  }

  /// Real-time stream of [rsa_key_transfers] docs where the current user is
  /// the intended recipient and the status is `handshake_complete`.
  ///
  /// Used by [SenderScreen] to detect when a receiver has explicitly chosen
  /// this sender and published their RSA public key.  The stream fires once
  /// immediately with current state and again on every change — when the doc
  /// disappears (receiver wipes session / kill switch fires) the sender
  /// reverts to the waiting buffer.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamHandshakesForSender() =>
      _db
          .collection(FirebaseConstants.rsaKeyTransfers)
          .where('toUserId', isEqualTo: _uid)
          .where('status', isEqualTo: 'handshake_complete')
          .snapshots();

  /// Updates the current user's readiness-to-receive status in Firestore.
  Future<void> setReadyToReceive(bool ready) async {
    try {
      await _db.collection(FirebaseConstants.users).doc(_uid).update({
        'isReadyToReceive': ready,
        if (ready) 'readySince': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Could not update ready status: ${e.message ?? e.code}');
    }
  }

  /// Wipes all RSA session data for [uid] on app startup:
  /// - Secure storage entries with rsa_private_key_* / rsa_public_key_* prefixes
  /// - All rsa_key_transfers documents where fromUserId or toUserId == uid
  /// - All rsa_key_received notifications for uid
  Future<void> wipeAllSessionKeys(String uid) async {
    // Wipe secure storage
    final all = await _secure.readAll();
    for (final key in all.keys) {
      if (key.startsWith('rsa_private_key_') ||
          key.startsWith('rsa_public_key_')) {
        await _secure.delete(key: key);
      }
    }

    // Wipe rsa_key_transfers sent by uid
    final sent = await _db
        .collection(FirebaseConstants.rsaKeyTransfers)
        .where('fromUserId', isEqualTo: uid)
        .get();
    for (final doc in sent.docs) {
      await doc.reference.delete();
    }

    // Wipe rsa_key_transfers received by uid
    final received = await _db
        .collection(FirebaseConstants.rsaKeyTransfers)
        .where('toUserId', isEqualTo: uid)
        .get();
    for (final doc in received.docs) {
      await doc.reference.delete();
    }

    // Wipe rsa_key_received notifications
    final notifs = await _db
        .collection(FirebaseConstants.notifications)
        .where('toUserId', isEqualTo: uid)
        .where('type', isEqualTo: 'rsa_key_received')
        .get();
    for (final doc in notifs.docs) {
      await doc.reference.delete();
    }
  }
}
