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

  /// Returns a real-time count of transfer log documents.
  ///
  /// KNOWN LIMITATION (WR-02): This downloads every document in the
  /// `transfer_logs` collection on each emission, which is an unbounded read
  /// cost as the collection grows. The preferred fix is to use Firestore
  /// AggregateQuery (`collection.count().get()`) which runs server-side and
  /// transfers only the count — available in `cloud_firestore ^4.x`.
  ///
  /// TODO: Replace with AggregateQuery once the project upgrades to
  /// cloud_firestore >=4.0.0 and the Firebase project enables the
  /// AggregateQuery API. Until then, the collection is expected to stay small
  /// enough that read cost is acceptable.
  Stream<int> streamTotalTransfers() =>
      _db.collection(FirebaseConstants.transferLogs).snapshots().map((s) => s.size);

  /// Returns a real-time count of user documents.
  ///
  /// KNOWN LIMITATION (WR-02): Same unbounded read cost as [streamTotalTransfers].
  /// TODO: Replace with AggregateQuery when available (see above).
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

    // Batch sub-collection reads in groups of 10 to avoid hitting Firestore
    // concurrent-read quota limits (WR-01). Up to 50 users are fetched above.
    Future<Map<String, dynamic>> fetchOne(QueryDocumentSnapshot<Map<String, dynamic>> userDoc) async {
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
    }

    const batchSize = 10;
    final results = <Map<String, dynamic>>[];
    for (int i = 0; i < usersSnap.docs.length; i += batchSize) {
      final batch = usersSnap.docs.skip(i).take(batchSize);
      results.addAll(await Future.wait(batch.map(fetchOne)));
    }
    return results;
  }
}
