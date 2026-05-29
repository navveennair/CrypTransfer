import 'dart:async';

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
  /// idempotent. A transaction protects `createdAt` — it is written only when
  /// the document does not yet exist, preserving the original proposal timestamp
  /// on subsequent re-sends (WR-01 fix).
  ///
  /// Throws [AuthException] if [partnerUid] is empty or the caller has no username.
  /// Throws [NetworkException] on Firestore failure.
  Future<void> sendProposal({
    required String partnerUid,
    required String partnerUsername,
  }) async {
    if (partnerUid.isEmpty) throw AuthException('partnerUid required');
    try {
      final userDoc =
          await _db.collection(FirebaseConstants.users).doc(_uid).get();
      final currentUsername = userDoc.data()?['username'] as String? ?? '';
      if (currentUsername.isEmpty) {
        throw AuthException('User profile incomplete — username not set.');
      }

      final docRef = _db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc('${_uid}_$partnerUid');

      await _db.runTransaction((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) {
          tx.set(docRef, {
            'proposerId': _uid,
            'proposerUsername': currentUsername,
            'partnerId': partnerUid,
            'partnerUsername': partnerUsername,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.update(docRef, {
            'proposerUsername': currentUsername,
            'partnerUsername': partnerUsername,
            'status': 'pending',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
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
  /// Also updates the bidirectional `users/{uid}/friendships/{partnerId}` and
  /// `users/{partnerId}/friendships/{uid}` sub-collection documents with
  /// `status: 'accepted'` to enable downstream role assignment checks.
  ///
  /// [proposerId] is required to derive the mutual doc ID.
  Future<void> acceptProposal(String docId, String proposerId) async {
    try {
      final primaryRef = _db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc(docId);

      // Fetch the primary doc to extract user data
      final primarySnap = await primaryRef.get();
      if (!primarySnap.exists) {
        throw NetworkException('Proposal not found: $docId');
      }

      final data = primarySnap.data()!;
      final proposerUsername = data['proposerUsername'] as String? ?? '';
      final partnerUsername = data['partnerUsername'] as String? ?? '';

      // The current user (_uid) is the partner accepting the proposal
      // The proposerId is the person who originally sent the proposal
      final otherUserUid = proposerId;

      // Build friendships sub-collection refs for both directions
      // myFriendshipRef is for the current user (_uid = partner accepting)
      final myFriendshipRef = _db
          .collection(FirebaseConstants.users)
          .doc(_uid)
          .collection(FirebaseConstants.friendships)
          .doc(otherUserUid);
      // partnerFriendshipRef is for the proposer
      final otherFriendshipRef = _db
          .collection(FirebaseConstants.users)
          .doc(otherUserUid)
          .collection(FirebaseConstants.friendships)
          .doc(_uid);

      final mutualRef = _db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc('${_uid}_$proposerId');

      final batch = _db.batch();

      // Update neutral_handshakes
      batch.update(primaryRef,
          {'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()});

      // Check and update mutual neutral_handshakes doc if it exists
      final mutualSnap = await mutualRef.get();
      if (mutualSnap.exists) {
        batch.update(mutualRef,
            {'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()});
      }

      // Update bidirectional friendships sub-collection documents
      // Current user's perspective (acceptor = partner)
      // They are adding the proposer to their friendships
      // Note: Documents don't exist yet, so use batch.set() without SetOptions(merge: true)
      batch.set(
        myFriendshipRef,
        {
          'uid': otherUserUid,
          'username': proposerUsername,
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      // Proposer's perspective
      // They are updating their existing request to accepted
      // Note: Documents don't exist yet, so use batch.set() without SetOptions(merge: true)
      batch.set(
        otherFriendshipRef,
        {
          'uid': _uid,
          'username': partnerUsername,
          'status': 'accepted',
          'updatedAt': FieldValue.serverTimestamp(),
        },
      );

      await batch.commit();
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Failed to accept proposal: ${e.message ?? e.code}');
    }
  }

  /// Atomically removes both directional docs for the pair, covering the
  /// mutual-accept case where two 'connected' docs coexist.
  Future<void> disconnectFromUser(String partnerUid) async {
    try {
      final batch = _db.batch();
      batch.delete(_db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc('${_uid}_$partnerUid'));
      batch.delete(_db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc('${partnerUid}_$_uid'));
      await batch.commit();
    } on FirebaseException catch (e) {
      throw NetworkException(
          'Failed to disconnect: ${e.message ?? e.code}');
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

  /// Streams the live handshake status between [_uid] and [partnerUid].
  ///
  /// Listens to both directions (`${_uid}_$partnerUid` and `${partnerUid}_$_uid`)
  /// because Firestore does not support OR queries on document IDs. Emits the
  /// resolved status + doc ID whenever either document changes. Returns null
  /// when no relationship exists.
  Stream<({String status, String docId})?> streamHandshakeWithUser(
      String partnerUid) {
    final myUid = _uid;
    final outRef = _db
        .collection(FirebaseConstants.neutralHandshakes)
        .doc('${myUid}_$partnerUid');
    final inRef = _db
        .collection(FirebaseConstants.neutralHandshakes)
        .doc('${partnerUid}_$myUid');

    DocumentSnapshot<Map<String, dynamic>>? outSnap;
    DocumentSnapshot<Map<String, dynamic>>? inSnap;
    final ctrl = StreamController<({String status, String docId})?>();

    // Single subscription — merge both document streams
    final outSub = outRef.snapshots().listen((snap) {
      outSnap = snap;
      _emitIfResolved(ctrl, outSnap, inSnap, myUid, partnerUid);
    });

    final inSub = inRef.snapshots().listen((snap) {
      inSnap = snap;
      _emitIfResolved(ctrl, outSnap, inSnap, myUid, partnerUid);
    });

    ctrl.onCancel = () {
      outSub.cancel();
      inSub.cancel();
      ctrl.close();
    };

    return ctrl.stream;
  }

  /// Helper: Resolve and emit the first non-null status from either doc direction.
  void _emitIfResolved(
    StreamController<({String status, String docId})?> ctrl,
    DocumentSnapshot<Map<String, dynamic>>? outSnap,
    DocumentSnapshot<Map<String, dynamic>>? inSnap,
    String myUid,
    String partnerUid,
  ) {
    if (outSnap != null && inSnap != null) {
      // Both snaps fetched — resolve
      if (outSnap.exists) {
        final status = outSnap.data()?['status'] as String? ?? 'unknown';
        ctrl.add((status: status, docId: outSnap.id));
      } else if (inSnap.exists) {
        final status = inSnap.data()?['status'] as String? ?? 'unknown';
        ctrl.add((status: status, docId: inSnap.id));
      } else {
        ctrl.add(null);
      }
    }
  }
}
