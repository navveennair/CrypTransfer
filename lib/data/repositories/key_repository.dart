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

  CollectionReference<Map<String, dynamic>> _friendshipsOf(String userId) =>
      _db.collection(FirebaseConstants.users).doc(userId).collection(FirebaseConstants.friendships);

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
      final doc = await _friendshipsOf(_uid).doc(otherUserId).get();
      if (!doc.exists) return null;
      return doc.data()?['status'] as String?;
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Could not check connection status: ${e.message ?? e.code}');
    }
  }

  Future<void> sendConnectionRequest(String targetUserId) async {
    try {
      final status = await getConnectionStatus(targetUserId);
      if (status != null) return;

      final results = await Future.wait([
        _db.collection(FirebaseConstants.users).doc(_uid).get(),
        _db.collection(FirebaseConstants.users).doc(targetUserId).get(),
      ]);
      final myData = results[0].data() ?? {};
      final targetData = results[1].data() ?? {};

      final myUsername = myData['username'] as String? ?? 'Unknown';
      final myEmail = myData['email'] as String? ?? '';
      final targetUsername = targetData['username'] as String? ?? 'Unknown';
      final targetEmail = targetData['email'] as String? ?? '';

      final batch = _db.batch();

      batch.set(_friendshipsOf(_uid).doc(targetUserId), {
        'uid': targetUserId,
        'username': targetUsername,
        'email': targetEmail,
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(_friendshipsOf(targetUserId).doc(_uid), {
        'uid': _uid,
        'username': myUsername,
        'email': myEmail,
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      await _db
          .collection(FirebaseConstants.users)
          .doc(targetUserId)
          .collection(FirebaseConstants.notifications)
          .add({
        'toUserId': targetUserId,
        'fromUsername': myUsername,
        'type': 'friend_request',
        'message': '👋 $myUsername wants to connect with you.',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Connection request failed: ${e.message ?? e.code}');
    }
  }

  Future<List<Map<String, dynamic>>> getPendingRequests() async => [];

  Future<void> acceptConnectionRequest(String docId, String senderId) async {}

  Future<List<UserModel>> getConnectedFriends() async {
    try {
      final snap = await _friendshipsOf(_uid)
          .where('status', isEqualTo: 'accepted')
          .get();
      return snap.docs
          .map((doc) => UserModel.fromMap(doc.id, doc.data()))
          .toList();
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

  Future<void> disconnectFriend(String friendId) async {
    try {
      final batch = _db.batch();
      batch.delete(_friendshipsOf(_uid).doc(friendId));
      batch.delete(_friendshipsOf(friendId).doc(_uid));
      await batch.commit();
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Failed to disconnect: ${e.message ?? e.code}');
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
        senderId: toUserId,
        publicKey: publicKey,
        fromUsername: fromUsername,
        status: isHandshake ? 'handshake_complete' : 'pending',
      );

      await _db
          .collection(FirebaseConstants.users)
          .doc(toUserId)
          .collection(FirebaseConstants.notifications)
          .add({
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

  Future<String?> getPublicKeyFor(String senderId) async {
    try {
      final result = await _db
          .collection(FirebaseConstants.handshakes)
          .where('senderId', isEqualTo: senderId)
          .where('receiverId', isEqualTo: _uid)
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
          .collection(FirebaseConstants.handshakes)
          .where('receiverId', isEqualTo: _uid)
          .get();

      final transfers = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final senderId = data['senderId'] as String;
        final userDoc =
            await _db.collection(FirebaseConstants.users).doc(senderId).get();
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
          .collection(FirebaseConstants.handshakes)
          .where('senderId', isEqualTo: _uid)
          .get();

      final keys = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final receiverId = data['receiverId'] as String;
        final userDoc = await _db
            .collection(FirebaseConstants.users)
            .doc(receiverId)
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
          .collection(FirebaseConstants.handshakes)
          .where('senderId', isEqualTo: fromUserId)
          .where('receiverId', isEqualTo: _uid)
          .limit(1)
          .get();
      return result.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      throw NetworkException('Key lookup failed: ${e.message ?? e.code}');
    }
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  Future<void> _writePublicKeyTo(String senderId) async {
    final userDoc = await _db.collection(FirebaseConstants.users).doc(_uid).get();
    final publicKey = userDoc.data()?['publicKey'] as String?;
    if (publicKey == null || publicKey.isEmpty) return;
    await _upsertKeyTransfer(senderId: senderId, publicKey: publicKey, status: 'pending');
  }

  Future<void> _upsertKeyTransfer({
    required String senderId,
    required String publicKey,
    String? fromUsername,
    String status = 'pending',
  }) async {
    final existing = await _db
        .collection(FirebaseConstants.handshakes)
        .where('receiverId', isEqualTo: _uid)
        .where('senderId', isEqualTo: senderId)
        .limit(1)
        .get();

    final update = <String, dynamic>{
      'publicKey': publicKey,
      'sentAt': FieldValue.serverTimestamp(),
      'fromUsername': fromUsername,
      'status': status,
    };

    if (existing.docs.isNotEmpty) {
      await existing.docs.first.reference.update(update);
    } else {
      await _db.collection(FirebaseConstants.handshakes).add({
        'receiverId': _uid,
        'senderId': senderId,
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
          .collection(FirebaseConstants.handshakes)
          .where('senderId', isEqualTo: _uid)
          .get();

      final receivers = <UserModel>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final receiverId = data['receiverId'] as String;
        final publicKey = data['publicKey'] as String?;
        if (publicKey == null || publicKey.isEmpty) continue;
        final userDoc = await _db
            .collection(FirebaseConstants.users)
            .doc(receiverId)
            .get();
        if (!userDoc.exists) continue;
        final userData = userDoc.data()!;
        receivers.add(UserModel(
          uid: receiverId,
          username: userData['username'] as String? ?? 'Unknown',
          email: userData['email'] as String? ?? '',
          phone: userData['phone'] as String? ?? '',
          publicKey: publicKey,
          isAdmin: userData['isAdmin'] as bool? ?? false,
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
  /// 2. `handshakes` — upserts the receiver's RSA public key addressed
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
          .collection(FirebaseConstants.handshakes)
          .where('receiverId', isEqualTo: _uid)
          .where('senderId', isEqualTo: senderUid)
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
        // 'receiverUsername' is the canonical field read by SenderScreen.
        // 'fromUsername' is kept for backward compatibility.
        'receiverUsername': fromUsername,
        'status': 'handshake_complete',
      };
      if (existing.docs.isNotEmpty) {
        batch.update(existing.docs.first.reference, keyPayload);
      } else {
        final newRef = _db.collection(FirebaseConstants.handshakes).doc();
        batch.set(newRef, {
          'receiverId': _uid,
          'senderId': senderUid,
          ...keyPayload,
        });
      }

      await batch.commit();

      // Notification — best-effort, not part of the atomic batch.
      await _db
          .collection(FirebaseConstants.users)
          .doc(senderUid)
          .collection(FirebaseConstants.notifications)
          .add({
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

  /// Returns the Firestore document ID of the active handshake between
  /// [senderUid] and [receiverUid], or null if none exists.
  ///
  /// Used by [EndSessionScreen] for targeted deletion (avoids a second
  /// query by storing the ID ahead of time).
  Future<String?> getActiveHandshakeDocId({
    required String senderUid,
    required String receiverUid,
  }) async {
    try {
      final snap = await _db
          .collection(FirebaseConstants.handshakes)
          .where('senderId', isEqualTo: senderUid)
          .where('receiverId', isEqualTo: receiverUid)
          .limit(1)
          .get();
      return snap.docs.isEmpty ? null : snap.docs.first.id;
    } on FirebaseException {
      return null;
    }
  }

  /// Publishes the current user's RSA public key to [targetUserId] using a
  /// deterministic document ID (`${_uid}_${targetUserId}`), signalling the
  /// sender that a secure channel is ready.
  ///
  /// Unlike [selectSenderHandshake], this does not lock the session to a
  /// single sender — it only makes the public key available so the sender can
  /// begin encrypting before the receiver formally selects them.
  ///
  /// The sender's [streamHandshakesForSender] stream picks up the write and
  /// transitions them out of the "Waiting for Connection" state.
  ///
  /// Throws [KeyNotFoundException] if the receiver has not yet generated keys.
  Future<void> publishRSAPublicKey(String targetUserId) async {
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

      // Deterministic doc ID ensures idempotent re-sends without duplicates.
      final docId = '${_uid}_$targetUserId';
      await _db.collection(FirebaseConstants.handshakes).doc(docId).set({
        'receiverId': _uid,
        'senderId': targetUserId,
        'publicKey': publicKey,
        'receiverUsername': fromUsername,
        'fromUsername': fromUsername,
        'status': 'handshake_complete',
        'sentAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on KeyNotFoundException {
      rethrow;
    } on FirebaseException catch (e) {
      throw NetworkException('Failed to publish key: ${e.message ?? e.code}');
    }
  }

  /// Real-time stream of [handshakes] docs where the current user is
  /// the intended recipient and the status is `handshake_complete`.
  ///
  /// Used by [SenderScreen] to detect when a receiver has explicitly chosen
  /// this sender and published their RSA public key.  The stream fires once
  /// immediately with current state and again on every change — when the doc
  /// disappears (receiver wipes session / kill switch fires) the sender
  /// reverts to the waiting buffer.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamHandshakesForSender() =>
      _db
          .collection(FirebaseConstants.handshakes)
          .where('senderId', isEqualTo: _uid)
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
  /// - All handshakes documents where receiverId or senderId == uid
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

    // Wipe handshakes initiated by uid (as receiver)
    final sent = await _db
        .collection(FirebaseConstants.handshakes)
        .where('receiverId', isEqualTo: uid)
        .get();
    for (final doc in sent.docs) {
      await doc.reference.delete();
    }

    // Wipe handshakes received by uid (as sender)
    final received = await _db
        .collection(FirebaseConstants.handshakes)
        .where('senderId', isEqualTo: uid)
        .get();
    for (final doc in received.docs) {
      await doc.reference.delete();
    }

    // Wipe rsa_key_received notifications from this user's inbox
    final notifs = await _db
        .collection(FirebaseConstants.users)
        .doc(uid)
        .collection(FirebaseConstants.notifications)
        .where('type', isEqualTo: 'rsa_key_received')
        .get();
    for (final doc in notifs.docs) {
      await doc.reference.delete();
    }
  }

  /// Atomically purges session data from Firestore.
  /// Triggered by the 'End Session' button on the [EndSessionScreen].
  ///
  /// Verifies that [transferId] and [handshakeId] are not null before adding
  /// them to the [WriteBatch] to avoid runtime errors.
  Future<void> endSessionCleanup({
    String? transferId,
    String? handshakeId,
    required String receiverId,
  }) async {
    if (receiverId.isEmpty) {
      throw NetworkException('Cannot cleanup: receiverId is missing.');
    }
    final batch = _db.batch();

    if (transferId != null && transferId.isNotEmpty) {
      batch.delete(_db.collection(FirebaseConstants.transfers).doc(transferId));
    }

    if (handshakeId != null && handshakeId.isNotEmpty) {
      batch.delete(_db.collection(FirebaseConstants.handshakes).doc(handshakeId));
    }

    // Always clear the receiver authorization field as part of the cleanup.
    batch.update(
      _db.collection(FirebaseConstants.users).doc(receiverId),
      {'selectedSenderUid': FieldValue.delete()},
    );

    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      throw NetworkException('Cleanup failed: ${e.message ?? e.code}');
    }
  }
}
