import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/firebase_constants.dart';

/// Read-only helper for the per-user notifications sub-collection.
class NotificationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> _notifs(String uid) =>
      _db.collection(FirebaseConstants.users).doc(uid).collection(FirebaseConstants.notifications);

  // ─── Streams ──────────────────────────────────────────────────────────────

  /// Count of unread notifications for [uid].
  static Stream<int> unreadCountStream(String uid) => _notifs(uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((s) => s.size);

  /// Unread notifications for [uid], newest first. Read notifications are
  /// excluded — marking a notification read removes it from this stream.
  static Stream<List<Map<String, dynamic>>> allStream(String uid) =>
      _notifs(uid).where('read', isEqualTo: false).snapshots().map((s) {
        final list =
            s.docs.map((d) => {'docId': d.id, ...d.data()}).toList();
        list.sort((a, b) {
          final aTs = a['createdAt'] as Timestamp?;
          final bTs = b['createdAt'] as Timestamp?;
          if (aTs == null && bTs == null) return 0;
          if (aTs == null) return 1;
          if (bTs == null) return -1;
          return bTs.compareTo(aTs);
        });
        return list;
      });

  /// Latest single unread notification for [uid] (for banner display).
  static Stream<Map<String, dynamic>?> latestUnreadStream(String uid) =>
      _notifs(uid).where('read', isEqualTo: false).snapshots().map((s) {
        if (s.docs.isEmpty) return null;
        final sorted = s.docs.toList()
          ..sort((a, b) {
            final aTs = a.data()['createdAt'] as Timestamp?;
            final bTs = b.data()['createdAt'] as Timestamp?;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });
        return {'docId': sorted.first.id, ...sorted.first.data()};
      });

  // ─── Mutations ────────────────────────────────────────────────────────────

  /// Mark a single notification as read.
  static Future<void> markRead(String uid, String docId) async {
    try {
      await _notifs(uid).doc(docId).update({'read': true});
    } catch (_) {}
  }

  /// Mark all unread notifications for [uid] as read.
  static Future<void> markAllRead(String uid) async {
    try {
      final snap = await _notifs(uid).where('read', isEqualTo: false).get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {}
  }
}
