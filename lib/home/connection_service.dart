import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ConnectionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw Exception('Not authenticated.');
    return uid;
  }

  // ─── User search ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    try {
      final result = await _db
          .collection('users')
          .where('username', isGreaterThanOrEqualTo: q)
          .where('username', isLessThanOrEqualTo: '$q\uf8ff')
          .limit(10)
          .get();

      return result.docs
          .where((doc) => doc.id != _uid)
          .map((doc) => {'uid': doc.id, ...doc.data()})
          .toList();
    } on FirebaseException catch (e) {
      throw Exception('User search failed: ${e.message ?? e.code}');
    }
  }

  // ─── Connection requests ──────────────────────────────────────────────────

  Future<String?> getConnectionStatus(String otherUserId) async {
    try {
      final sent = await _db
          .collection('friend_requests')
          .where('senderId', isEqualTo: _uid)
          .where('receiverId', isEqualTo: otherUserId)
          .limit(1)
          .get();
      if (sent.docs.isNotEmpty) {
        return sent.docs.first.data()['status'] as String;
      }

      final received = await _db
          .collection('friend_requests')
          .where('senderId', isEqualTo: otherUserId)
          .where('receiverId', isEqualTo: _uid)
          .limit(1)
          .get();
      if (received.docs.isNotEmpty) {
        return received.docs.first.data()['status'] as String;
      }

      return null;
    } on FirebaseException catch (e) {
      throw Exception('Could not check connection status: ${e.message ?? e.code}');
    }
  }

  /// Called by the RECEIVER to connect with a SENDER.
  /// Auto-accepts, then immediately writes the receiver's public key to
  /// rsa_key_transfers so the sender can encrypt files for them.
  Future<void> sendConnectionRequest(String targetUserId) async {
    try {
      final status = await getConnectionStatus(targetUserId);
      if (status != null) return;

      await _db.collection('friend_requests').add({
        'senderId': _uid,
        'receiverId': targetUserId,
        'participants': [_uid, targetUserId],
        'status': 'accepted',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Auto-write own public key to rsa_key_transfers so the sender has it
      await _writePublicKeyTo(targetUserId);
    } on FirebaseException catch (e) {
      throw Exception('Connection request failed: ${e.message ?? e.code}');
    }
  }

  /// Writes current user's public key (from Firestore) to rsa_key_transfers.
  /// No-op if the key hasn't been generated yet.
  Future<void> _writePublicKeyTo(String toUserId) async {
    try {
      final userDoc = await _db.collection('users').doc(_uid).get();
      final publicKey = userDoc.data()?['publicKey'] as String?;
      if (publicKey == null || publicKey.isEmpty) return;

      final existing = await _db
          .collection('rsa_key_transfers')
          .where('fromUserId', isEqualTo: _uid)
          .where('toUserId', isEqualTo: toUserId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.update({
          'publicKey': publicKey,
          'sentAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('rsa_key_transfers').add({
          'fromUserId': _uid,
          'toUserId': toUserId,
          'publicKey': publicKey,
          'sentAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseException catch (e) {
      throw Exception('Failed to share public key: ${e.message ?? e.code}');
    }
  }

  /// Re-sends the current user's public key to all accepted connections.
  /// Used after key regeneration so existing senders get the updated key.
  Future<void> resyncPublicKeyToAllConnections() async {
    try {
      final friends = await getConnectedFriends();
      for (final f in friends) {
        await _writePublicKeyTo(f['uid'] as String);
      }
    } on FirebaseException catch (e) {
      throw Exception('Key resync failed: ${e.message ?? e.code}');
    }
  }

  /// Explicitly sends the current user's RSA public key to [toUserId].
  /// Upserts rsa_key_transfers and writes a Firestore notification.
  Future<void> sendPublicKey({
    required String toUserId,
    required String toUsername,
  }) async {
    try {
      final userDoc = await _db.collection('users').doc(_uid).get();
      final publicKey = userDoc.data()?['publicKey'] as String?;
      if (publicKey == null || publicKey.isEmpty) {
        throw Exception('Generate RSA keys first');
      }
      final fromUsername = userDoc.data()?['username'] as String? ??
          _auth.currentUser?.displayName ??
          'Unknown';

      final existing = await _db
          .collection('rsa_key_transfers')
          .where('fromUserId', isEqualTo: _uid)
          .where('toUserId', isEqualTo: toUserId)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        await existing.docs.first.reference.update({
          'publicKey': publicKey,
          'fromUsername': fromUsername,
          'status': 'pending',
          'sentAt': FieldValue.serverTimestamp(),
        });
      } else {
        await _db.collection('rsa_key_transfers').add({
          'fromUserId': _uid,
          'fromUsername': fromUsername,
          'toUserId': toUserId,
          'publicKey': publicKey,
          'status': 'pending',
          'sentAt': FieldValue.serverTimestamp(),
        });
      }

      await _db.collection('notifications').add({
        'toUserId': toUserId,
        'fromUsername': fromUsername,
        'type': 'rsa_key_received',
        'message': '🔑 $fromUsername sent you their RSA Public Key',
        'createdAt': FieldValue.serverTimestamp(),
        'read': false,
      });
    } on FirebaseException catch (e) {
      throw Exception('Failed to send key: ${e.message ?? e.code}');
    }
  }

  // ─── Connected friends ────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getConnectedFriends() async {
    try {
      final sent = await _db
          .collection('friend_requests')
          .where('senderId', isEqualTo: _uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final received = await _db
          .collection('friend_requests')
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

      final friends = <Map<String, dynamic>>[];
      for (final uid in otherUids) {
        final userDoc = await _db.collection('users').doc(uid).get();
        if (userDoc.exists) {
          friends.add({'uid': uid, ...userDoc.data()!});
        }
      }
      return friends;
    } on FirebaseException catch (e) {
      throw Exception('Could not load connections: ${e.message ?? e.code}');
    }
  }

  // ─── RSA key transfer ─────────────────────────────────────────────────────

  /// Returns true if [fromUserId] has sent their public key to the current user.
  Future<bool> hasReceivedKeyFrom(String fromUserId) async {
    try {
      final result = await _db
          .collection('rsa_key_transfers')
          .where('fromUserId', isEqualTo: fromUserId)
          .where('toUserId', isEqualTo: _uid)
          .limit(1)
          .get();
      return result.docs.isNotEmpty;
    } on FirebaseException catch (e) {
      throw Exception('Key lookup failed: ${e.message ?? e.code}');
    }
  }

  /// Returns all key transfers the current user has SENT (as a receiver
  /// sharing their public key with senders).
  Future<List<Map<String, dynamic>>> getSentKeyTransfers() async {
    try {
      final snapshot = await _db
          .collection('rsa_key_transfers')
          .where('fromUserId', isEqualTo: _uid)
          .get();

      final transfers = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final toUserId = data['toUserId'] as String;
        final userDoc = await _db.collection('users').doc(toUserId).get();
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
      throw Exception('Could not load sent keys: ${e.message ?? e.code}');
    }
  }

  /// Returns all keys received by the current user (from other users who
  /// shared their public key).
  Future<List<Map<String, dynamic>>> getReceivedKeys() async {
    try {
      final snapshot = await _db
          .collection('rsa_key_transfers')
          .where('toUserId', isEqualTo: _uid)
          .get();

      final keys = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final fromUserId = data['fromUserId'] as String;
        final userDoc = await _db.collection('users').doc(fromUserId).get();
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
      throw Exception('Could not load received keys: ${e.message ?? e.code}');
    }
  }

  /// Saves a friend's public key to secure local storage.
  Future<void> saveReceivedKey(String fromUserId, String publicKey) async {
    try {
      await _secure.write(
        key: 'rsa_public_key_$fromUserId',
        value: publicKey,
      );
    } catch (e) {
      throw Exception('Failed to save key locally: $e');
    }
  }

  /// Returns true if the friend's public key is already saved locally.
  Future<bool> isKeySaved(String fromUserId) async {
    try {
      final val = await _secure.read(key: 'rsa_public_key_$fromUserId');
      return val != null;
    } catch (_) {
      return false;
    }
  }

  /// Returns the RSA public key string for [fromUserId] from Firestore
  /// (the key they shared with the current user).
  Future<String?> getPublicKeyFor(String fromUserId) async {
    try {
      final result = await _db
          .collection('rsa_key_transfers')
          .where('fromUserId', isEqualTo: fromUserId)
          .where('toUserId', isEqualTo: _uid)
          .limit(1)
          .get();
      if (result.docs.isEmpty) return null;
      return result.docs.first.data()['publicKey'] as String?;
    } on FirebaseException catch (e) {
      throw Exception('Could not fetch public key: ${e.message ?? e.code}');
    }
  }
}
