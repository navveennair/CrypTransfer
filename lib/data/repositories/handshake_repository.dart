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
  /// idempotent. A plain get() + WriteBatch approach is used (not runTransaction)
  /// to avoid the Firestore Mobile SDK transaction retry loop that can hang
  /// indefinitely when the receiver simultaneously accepts the proposal (WR-01 fix
  /// preserved: createdAt is only written when the document does not yet exist).
  ///
  /// TWO records with clearly separated roles (R1 design):
  ///   1. The `neutral_handshakes` doc is the SOURCE OF TRUTH for the request's
  ///      lifecycle (pending → connected/rejected). It drives the FindFriends
  ///      "Incoming Requests" action surface (Accept/Decline) via
  ///      [streamIncomingPending]. There is NO live `_ProposalBanner` overlay.
  ///   2. A `connection_request` doc in the partner's `notifications` inbox is a
  ///      read-only AWARENESS ping so the bell badge + NotificationsScreen tell
  ///      the user "someone wants to connect". The user marks it read, returns
  ///      Home, taps "+ View" and acts in FindFriends. Written only for NEW
  ///      proposals (not re-sends) to avoid duplicate inbox entries.
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

      // Read the doc outside the batch — same pattern as acceptProposal() to
      // avoid the transaction retry loop that causes indefinite hangs when the
      // receiver simultaneously accepts the proposal (concurrent write contention).
      final snap = await docRef.get();
      final isNew = !snap.exists;

      final batch = _db.batch();
      if (!snap.exists) {
        // New proposal — write full document including createdAt (WR-01: idempotent).
        batch.set(docRef, {
          'proposerId': _uid,
          'proposerUsername': currentUsername,
          'partnerId': partnerUid,
          'partnerUsername': partnerUsername,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Re-send — refresh usernames and reset status; preserve original createdAt.
        batch.update(docRef, {
          'proposerUsername': currentUsername,
          'partnerUsername': partnerUsername,
          'status': 'pending',
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();

      // Awareness ping → partner's bell badge + NotificationsScreen (record #2,
      // see method doc). Read-only heads-up; the user clears it by marking read.
      // Best-effort: a failure here does not roll back the proposal. New
      // proposals only — re-sends must not stack duplicate inbox entries.
      if (isNew) {
        try {
          await _db
              .collection(FirebaseConstants.users)
              .doc(partnerUid)
              .collection(FirebaseConstants.notifications)
              .add({
            'toUserId': partnerUid,
            'type': 'connection_request',
            'message': '@$currentUsername wants to connect',
            'fromUid': _uid,
            'fromUsername': currentUsername,
            'read': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          // best-effort — non-critical: the request still exists in neutral_handshakes
          // and is actionable from the FindFriends "Incoming Requests" list.
        }
      }
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

  /// Atomically removes both directional neutral_handshake docs for the pair
  /// and clears any stale role-assignment fields from the calling user's own
  /// Firestore document.
  ///
  /// Only the calling user's own doc is updated — Firestore security rules
  /// (allow update: if isOwner(userId) || isAdmin()) prevent writing to another
  /// user's document. The partner's stale [pendingSenderFor] / [selectedSenderUid]
  /// fields are inert once the connection no longer exists and will be cleared
  /// by the partner's own [KeyRepository.clearTransferRoles] call on their next
  /// sender/receiver screen exit.
  ///
  /// The neutral_handshakes deletes cover both directions (`selfUid_partnerUid`
  /// and `partnerUid_selfUid`). If only one direction exists the other delete is
  /// a safe no-op because the security rule guards `resource == null`.
  Future<void> disconnectFromUser(String partnerUid) async {
    final selfUid = _uid; // capture before any await
    try {
      final batch = _db.batch();

      // Remove both directional neutral_handshake docs.
      batch.delete(_db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc('${selfUid}_$partnerUid'));
      batch.delete(_db
          .collection(FirebaseConstants.neutralHandshakes)
          .doc('${partnerUid}_$selfUid'));

      // Clear stale role fields from the calling user's own document only.
      // Writing to users/{partnerUid} would violate isOwner(partnerUid).
      // FieldValue.delete() on a non-existent field is a safe no-op.
      batch.update(
        _db.collection(FirebaseConstants.users).doc(selfUid),
        {
          FirebaseConstants.pendingSenderFor: FieldValue.delete(),
          'selectedSenderUid': FieldValue.delete(),
        },
      );

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

  /// Marks all `connection_request` notifications from [fromUid] in the
  /// current user's inbox as read. Called after accept/decline so the bell
  /// badge clears without requiring the user to manually open the inbox.
  /// Best-effort — failure is swallowed so it never blocks the caller.
  Future<void> clearConnectionRequestNotif(String fromUid) async {
    try {
      final snap = await _db
          .collection(FirebaseConstants.users)
          .doc(_uid)
          .collection(FirebaseConstants.notifications)
          .where('type', isEqualTo: 'connection_request')
          .where('fromUid', isEqualTo: fromUid)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.update(doc.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {
      // best-effort — non-critical
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
    final selfUid = _uid;
    final outRef = _db
        .collection(FirebaseConstants.neutralHandshakes)
        .doc('${selfUid}_$partnerUid');
    final inRef = _db
        .collection(FirebaseConstants.neutralHandshakes)
        .doc('${partnerUid}_$selfUid');

    DocumentSnapshot<Map<String, dynamic>>? outSnap;
    DocumentSnapshot<Map<String, dynamic>>? inSnap;
    final ctrl = StreamController<({String status, String docId})?>();

    // Single subscription — merge both document streams
    final outSub = outRef.snapshots().listen((snap) {
      outSnap = snap;
      _emitIfResolved(ctrl, outSnap, inSnap, selfUid, partnerUid);
    });

    final inSub = inRef.snapshots().listen((snap) {
      inSnap = snap;
      _emitIfResolved(ctrl, outSnap, inSnap, selfUid, partnerUid);
    });

    ctrl.onCancel = () {
      outSub.cancel();
      inSub.cancel();
      ctrl.close();
    };

    return ctrl.stream;
  }

  /// Helper: Resolve and emit a direction-aware status from either doc direction.
  ///
  /// outSnap = doc I created (${selfUid}_${partnerUid}) → I am the proposer.
  /// inSnap  = doc they created (${partnerUid}_${selfUid}) → they are the proposer.
  ///
  /// Emitted statuses:
  ///   'pending'   (outSnap) → 'pending_sent'
  ///   'pending'   (inSnap)  → 'pending_received'
  ///   'connected' (either)  → 'accepted'
  void _emitIfResolved(
    StreamController<({String status, String docId})?> ctrl,
    DocumentSnapshot<Map<String, dynamic>>? outSnap,
    DocumentSnapshot<Map<String, dynamic>>? inSnap,
    String selfUid,
    String partnerUid,
  ) {
    if (outSnap == null || inSnap == null) return;

    String mapStatus(String raw, bool isSent) {
      if (raw == 'connected') return 'accepted';
      if (raw == 'pending') return isSent ? 'pending_sent' : 'pending_received';
      return raw;
    }

    if (outSnap.exists) {
      final raw = outSnap.data()?['status'] as String? ?? 'unknown';
      ctrl.add((status: mapStatus(raw, true), docId: outSnap.id));
    } else if (inSnap.exists) {
      final raw = inSnap.data()?['status'] as String? ?? 'unknown';
      ctrl.add((status: mapStatus(raw, false), docId: inSnap.id));
    } else {
      ctrl.add(null);
    }
  }
}
