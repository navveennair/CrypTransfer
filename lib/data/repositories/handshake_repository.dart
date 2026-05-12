import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/errors/app_exceptions.dart';

/// Manages neutral handshake proposals for the connection-layer.
///
/// Uses the `neutral_handshakes` Firestore collection with deterministic
/// doc IDs (`${proposerId}_${partnerId}`). Operations are symmetric —
/// proposer and partner have equal roles after acceptance.
class HandshakeRepository {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  HandshakeRepository({FirebaseFirestore? db, FirebaseAuth? auth})
      : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw AuthException('Not authenticated.');
    return uid;
  }

  // ─── Write operations ─────────────────────────────────────────────────────

  /// Creates a new connection proposal from the current user to [partnerUid].
  ///
  /// Uses a deterministic doc ID `${_uid}_${partnerUid}` so re-sends are
  /// idempotent (SetOptions.merge overwrites without creating duplicates).
  ///
  /// Throws [AuthException] if [partnerUid] is empty.
  /// Throws [NetworkException] on Firestore failure.
  Future<void> sendProposal({
    required String partnerUid,
    required String partnerUsername,
  }) async {
    if (partnerUid.isEmpty) throw AuthException('partnerUid required');
    try {
      final docId = '${_uid}_$partnerUid';
      final userDoc =
          await _db.collection(FirebaseConstants.users).doc(_uid).get();
      final currentUsername = userDoc.data()?['username'] as String? ?? '';

      await _db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc(docId)
          .set({
        'proposerId': _uid,
        'proposerUsername': currentUsername,
        'partnerId': partnerUid,
        'partnerUsername': partnerUsername,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException catch (e) {
      throw NetworkException('Failed to send proposal: ${e.message ?? e.code}');
    }
  }

  /// Accepts a pending proposal identified by [docId].
  ///
  /// Uses a WriteBatch to atomically update the primary doc (`A_B`) to
  /// `connected`. If a mutual doc (`B_A`) exists — from a simultaneous
  /// proposal by the same user — it is also updated to `connected` in the
  /// same batch (mutual-accept pattern, Pitfall 4).
  ///
  /// [proposerId] is required to derive the mutual doc ID.
  Future<void> acceptProposal(String docId, String proposerId) async {
    try {
      final mutualDocId = '${_uid}_$proposerId';
      final mutualRef = _db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc(mutualDocId);
      final mutualSnap = await mutualRef.get();

      final batch = _db.batch();
      batch.update(
        _db.collection(FirebaseConstants.neutralHandshakes).doc(docId),
        {'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()},
      );
      if (mutualSnap.exists) {
        batch.update(mutualRef,
            {'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()});
      }
      await batch.commit();
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Failed to accept proposal: ${e.message ?? e.code}');
    }
  }

  /// Rejects a pending proposal. Only the partner may call this.
  Future<void> rejectProposal(String docId) async {
    try {
      await _db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc(docId)
          .update({
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Failed to reject proposal: ${e.message ?? e.code}');
    }
  }

  /// Cancels (deletes) a proposal. Either party may call this.
  Future<void> cancelProposal(String docId) async {
    try {
      await _db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc(docId)
          .delete();
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Failed to cancel proposal: ${e.message ?? e.code}');
    }
  }

  // ─── Stream operations ────────────────────────────────────────────────────

  /// Stream of docs where the current user is the partner and status is pending.
  ///
  /// Used by the inbox / notification banner on HomeScreen.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamIncomingPending() =>
      _db
          .collection(FirebaseConstants.neutralHandshakes)
          .where('partnerId', isEqualTo: _uid)
          .where('status', isEqualTo: 'pending')
          .snapshots();

  /// Stream of docs where the current user is the proposer and status is pending.
  ///
  /// Used to show outgoing proposals still awaiting acceptance.
  Stream<QuerySnapshot<Map<String, dynamic>>> streamOutgoingPending() =>
      _db
          .collection(FirebaseConstants.neutralHandshakes)
          .where('proposerId', isEqualTo: _uid)
          .where('status', isEqualTo: 'pending')
          .snapshots();

  /// Stream of connected docs where the current user is the proposer.
  ///
  /// HomeScreen merges this with [streamActiveConnectionsAsPartner] to build
  /// the full connected-users list (Firestore does not support OR on different
  /// fields in a single query).
  Stream<QuerySnapshot<Map<String, dynamic>>>
      streamActiveConnectionsAsProposer() =>
          _db
              .collection(FirebaseConstants.neutralHandshakes)
              .where('proposerId', isEqualTo: _uid)
              .where('status', isEqualTo: 'connected')
              .snapshots();

  /// Stream of connected docs where the current user is the partner.
  ///
  /// HomeScreen merges this with [streamActiveConnectionsAsProposer].
  Stream<QuerySnapshot<Map<String, dynamic>>>
      streamActiveConnectionsAsPartner() =>
          _db
              .collection(FirebaseConstants.neutralHandshakes)
              .where('partnerId', isEqualTo: _uid)
              .where('status', isEqualTo: 'connected')
              .snapshots();

  /// Single-document stream for tracking outcome of a specific proposal.
  ///
  /// Used by the sender side to reactively detect acceptance or rejection
  /// without polling.
  Stream<DocumentSnapshot<Map<String, dynamic>>> streamProposalOutcome(
          String docId) =>
      _db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc(docId)
          .snapshots();
}
