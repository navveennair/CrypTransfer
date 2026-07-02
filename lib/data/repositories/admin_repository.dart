import 'dart:async';

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

  /// Returns a polled count of completed transfers across all users.
  ///
  /// Uses AggregateQuery `.count().get()` — O(1) read cost regardless of
  /// collection size. Polls every 30 seconds so the dashboard stays fresh
  /// without downloading any document bodies.
  ///
  /// Every transfer writes one immutable record to the sender's subcollection
  /// AND one to the receiver's subcollection in the same batch, so the raw
  /// aggregate count is always 2x the number of transfers. Halve it for a
  /// true transfer count.
  Stream<int> streamTotalTransfers() {
    late StreamController<int> ctrl;
    Timer? timer;
    Future<void> fetch() async {
      try {
        final agg = await _db
            .collectionGroup(FirebaseConstants.auditLogs)
            .count()
            .get();
        if (!ctrl.isClosed) ctrl.add((agg.count ?? 0) ~/ 2);
      } on FirebaseException catch (e) {
        // Surface permission/network errors to StreamBuilder so the UI can
        // show an error state rather than silently displaying stale zeros (WR-009 fix).
        if (!ctrl.isClosed) {
          ctrl.addError(e);
          timer?.cancel();
          ctrl.close();
        }
      } catch (e) {
        if (!ctrl.isClosed) ctrl.add(0); // non-Firebase errors: degrade gracefully
      }
    }
    ctrl = StreamController<int>(
      onListen: () {
        fetch();
        timer = Timer.periodic(const Duration(seconds: 30), (_) => fetch());
      },
      onCancel: () {
        timer?.cancel();
        if (!ctrl.isClosed) ctrl.close();
      },
    );
    return ctrl.stream;
  }

  /// Returns a polled count of user documents.
  ///
  /// Uses AggregateQuery `.count()` — O(1) read cost. Polls every 30 seconds.
  /// The stream is cancellable — unsubscribing stops the timer immediately.
  Stream<int> streamTotalUsers() {
    late StreamController<int> ctrl;
    Timer? timer;
    Future<void> fetch() async {
      try {
        final agg =
            await _db.collection(FirebaseConstants.users).count().get();
        if (!ctrl.isClosed) ctrl.add(agg.count ?? 0);
      } on FirebaseException catch (e) {
        // Surface permission/network errors to StreamBuilder so the UI can
        // show an error state rather than silently displaying stale zeros (WR-009 fix).
        if (!ctrl.isClosed) {
          ctrl.addError(e);
          timer?.cancel();
          ctrl.close();
        }
      } catch (e) {
        if (!ctrl.isClosed) ctrl.add(0); // non-Firebase errors: degrade gracefully
      }
    }
    ctrl = StreamController<int>(
      onListen: () {
        fetch();
        timer = Timer.periodic(const Duration(seconds: 30), (_) => fetch());
      },
      onCancel: () {
        timer?.cancel();
        if (!ctrl.isClosed) ctrl.close();
      },
    );
    return ctrl.stream;
  }

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

  /// Stream recent transfer activity for admin dashboard (full QuerySnapshot).
  ///
  /// Reads the `audit_logs` collection group — the same immutable per-user
  /// records HomeScreen uses for "Recent Transfers". Each transfer appears
  /// twice (once from the sender's subcollection, once from the receiver's)
  /// since both copies carry identical senderUsername/receiverUsername/
  /// fileName/status fields.
  ///
  /// Polls via one-time `.get()` every 30 seconds rather than `.snapshots()`.
  /// A real-time listener on this exact query (collection-group + orderBy,
  /// rule-gated by an isAdmin() cross-document get()) returns PERMISSION_DENIED
  /// in production even though the identical query succeeds as a one-time read
  /// or aggregate — confirmed via the live ruleset test and REST API reads
  /// during the 2026-07-02 debug session. Matches the polling pattern already
  /// used by streamTotalTransfers()/streamTotalUsers() above.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamTransferLogsDetail() {
    late StreamController<QuerySnapshot<Map<String, dynamic>>> ctrl;
    Timer? timer;
    Future<void> fetch() async {
      try {
        final snap = await _db
            .collectionGroup(FirebaseConstants.auditLogs)
            .orderBy('loggedAt', descending: true)
            .limit(100)
            .get();
        if (!ctrl.isClosed) ctrl.add(snap);
      } on FirebaseException catch (e) {
        if (!ctrl.isClosed) {
          ctrl.addError(e);
          timer?.cancel();
          ctrl.close();
        }
      }
    }

    // Must be broadcast: unlike streamTotalTransfers()/streamTotalUsers()
    // (called fresh inline on every _AnalyticsTab rebuild), this stream is
    // created once in AdminDashboard.initState() and reused across the
    // widget's lifetime — a single-subscription controller throws "Stream
    // has already been listened to" the moment StreamBuilder resubscribes
    // (e.g. after a tab-switch remount).
    ctrl = StreamController<QuerySnapshot<Map<String, dynamic>>>.broadcast(
      onListen: () {
        fetch();
        timer = Timer.periodic(const Duration(seconds: 30), (_) => fetch());
      },
      onCancel: () {
        timer?.cancel();
        if (!ctrl.isClosed) ctrl.close();
      },
    );
    return ctrl.stream;
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
      final countAgg = await _db
          .collection(FirebaseConstants.users)
          .doc(uid)
          .collection(FirebaseConstants.friendships)
          .where('status', isEqualTo: 'accepted')
          .count()
          .get();
      return {
        'uid': uid,
        'username': data['username'] as String? ?? '',
        'connectionCount': countAgg.count ?? 0,
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
