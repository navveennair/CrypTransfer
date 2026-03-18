import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ConnectionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String get _uid => _auth.currentUser!.uid;

  // ─── User search ──────────────────────────────────────────────────────────

  /// Returns users whose username starts with [query] (case-sensitive prefix).
  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

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
  }

  // ─── Connection requests ──────────────────────────────────────────────────

  /// Returns the status of the connection with [otherUserId]:
  /// 'accepted', 'pending', or null if no connection exists.
  Future<String?> getConnectionStatus(String otherUserId) async {
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
  }

  /// Sends a connection request to [receiverId].
  /// Sets status to 'accepted' immediately (acceptance UI added in a later week).
  Future<void> sendConnectionRequest(String receiverId) async {
    final status = await getConnectionStatus(receiverId);
    if (status != null) return; // already connected or pending

    await _db.collection('friend_requests').add({
      'senderId': _uid,
      'receiverId': receiverId,
      'participants': [_uid, receiverId],
      'status': 'accepted',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Connected friends ────────────────────────────────────────────────────

  /// Returns all users connected to the current user (status == accepted).
  Future<List<Map<String, dynamic>>> getConnectedFriends() async {
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
  }

  // ─── RSA key transfer ─────────────────────────────────────────────────────

  /// Fetches the current user's public key from Firestore and writes it to
  /// [toUserId]'s rsa_key_transfers collection.
  Future<void> sendPublicKey(String toUserId) async {
    final userDoc = await _db.collection('users').doc(_uid).get();
    final publicKey = userDoc.data()?['publicKey'];
    if (publicKey == null) {
      throw Exception(
          'You have not generated an RSA key pair yet.\nGo to the sidebar → Generate RSA Keys first.');
    }

    // Overwrite any previous transfer to the same recipient (upsert)
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
  }

  /// Returns all RSA keys sent to the current user, enriched with sender username.
  Future<List<Map<String, dynamic>>> getReceivedKeys() async {
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

    // Sort newest first (sentAt may be null briefly after write)
    keys.sort((a, b) {
      final aTs = a['sentAt'] as Timestamp?;
      final bTs = b['sentAt'] as Timestamp?;
      if (aTs == null && bTs == null) return 0;
      if (aTs == null) return 1;
      if (bTs == null) return -1;
      return bTs.compareTo(aTs);
    });

    return keys;
  }

  /// Saves a friend's public key to secure local storage, keyed by their userId.
  Future<void> saveReceivedKey(String fromUserId, String publicKey) async {
    await _secure.write(
      key: 'rsa_public_key_$fromUserId',
      value: publicKey,
    );
  }

  /// Returns true if the friend's public key is already saved locally.
  Future<bool> isKeySaved(String fromUserId) async {
    final val = await _secure.read(key: 'rsa_public_key_$fromUserId');
    return val != null;
  }
}
