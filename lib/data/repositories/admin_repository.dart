import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/firebase_constants.dart';
import '../models/user_model.dart';

class AdminRepository {
  final FirebaseFirestore _db;

  AdminRepository({
    FirebaseFirestore? db,
  }) : _db = db ?? FirebaseFirestore.instance;

  // ─── Stats ───────────────────────────────────────────────────────────────

  Stream<int> streamTotalTransfers() =>
      _db.collection(FirebaseConstants.transferLogs).snapshots().map((s) => s.size);

  Stream<int> streamTotalUsers() =>
      _db.collection(FirebaseConstants.users).snapshots().map((s) => s.size);

  // ─── User Management ─────────────────────────────────────────────────────

  Stream<List<UserModel>> streamAllUsers() => _db
      .collection(FirebaseConstants.users)
      .limit(200)
      .snapshots()
      .map((s) => s.docs.map((d) => UserModel.fromDoc(d)).toList());

  Future<void> setUserActiveStatus(String uid, bool isActive) async {
    await _db.collection(FirebaseConstants.users).doc(uid).update({
      'isActive': isActive,
    });

    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    // Log the administrative action
    await _db.collection(FirebaseConstants.securityAuditLog).add({
      'event': isActive ? 'ADMIN_USER_RESTORE' : 'ADMIN_USER_REVOKE',
      'details': 'User $uid access status changed to $isActive',
      'adminUid': adminUid ?? 'unknown',
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ─── Additional admin dashboard streams ───────────────────────────────────

  /// Stream active handshakes for admin dashboard (full QuerySnapshot)
  Stream<QuerySnapshot<Map<String, dynamic>>> streamActiveHandshakesDetail() {
    return _db
        .collection(FirebaseConstants.handshakes)
        .where('status', isEqualTo: 'handshake_complete')
        .snapshots();
  }

  /// Stream user connections for connection node map
  Stream<QuerySnapshot<Map<String, dynamic>>> streamUserConnections() {
    return _db.collection(FirebaseConstants.users).snapshots();
  }

  /// Stream security audit log for security pulse feed
  Stream<QuerySnapshot<Map<String, dynamic>>> streamSecurityAuditLog() {
    return _db
        .collection(FirebaseConstants.securityAuditLog)
        .orderBy('timestamp', descending: true)
        .limit(100)
        .snapshots();
  }

  /// Stream transfer logs for admin dashboard (full QuerySnapshot)
  Stream<QuerySnapshot<Map<String, dynamic>>> streamTransferLogsDetail() {
    return _db
        .collection(FirebaseConstants.transferLogs)
        .orderBy('loggedAt', descending: true)
        .limit(100)
        .snapshots();
  }

  // ─── Connection Node Map ─────────────────────────────────────────────────

  /// Fetches users with their accepted friendship counts for the connection node map.
  /// Capped at 50 users (D-09). Runs once per tab open via FutureBuilder.
  Future<List<Map<String, dynamic>>> fetchUserConnections() async {
    final usersSnap = await _db
        .collection(FirebaseConstants.users)
        .limit(50)
        .get();

    final futures = usersSnap.docs.map((userDoc) async {
      final uid = userDoc.id;
      final data = userDoc.data();
      final friendships = await _db
          .collection(FirebaseConstants.users)
          .doc(uid)
          .collection(FirebaseConstants.friendships)
          .where('status', isEqualTo: 'accepted')
          .get();
      return {
        'uid': uid,
        'username': data['username'] as String? ?? '',
        'connectionCount': friendships.size,
      };
    }).toList();

    return Future.wait(futures);
  }
}
