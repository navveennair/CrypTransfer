import 'package:cloud_firestore/cloud_firestore.dart';

/// Read-only helper for the [notifications] Firestore collection.
/// Notification documents are written by [ConnectionService] and
/// [TransferProgressScreen] directly to Firestore.
class NotificationService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Streams ──────────────────────────────────────────────────────────────

  /// Count of unread notifications for [uid].
  static Stream<int> unreadCountStream(String uid) => _db
      .collection('notifications')
      .where('toUserId', isEqualTo: uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((s) => s.size);

  /// All notifications for [uid], newest first (client-side sort).
  static Stream<List<Map<String, dynamic>>> allStream(String uid) => _db
      .collection('notifications')
      .where('toUserId', isEqualTo: uid)
      .snapshots()
      .map((s) {
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
  static Stream<Map<String, dynamic>?> latestUnreadStream(String uid) => _db
      .collection('notifications')
      .where('toUserId', isEqualTo: uid)
      .where('read', isEqualTo: false)
      .snapshots()
      .map((s) {
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
  static Future<void> markRead(String docId) async {
    try {
      await _db.collection('notifications').doc(docId).update({'read': true});
    } catch (_) {}
  }

  /// Mark all unread notifications for [uid] as read.
  static Future<void> markAllRead(String uid) async {
    try {
      final snap = await _db
          .collection('notifications')
          .where('toUserId', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .get();
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {}
  }
}
