---
phase: 05-neutral-handshake-model
reviewed: 2026-05-12T00:00:00Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/data/repositories/handshake_repository.dart
  - lib/core/constants/firebase_constants.dart
  - firestore.rules
  - lib/presentation/sender/sender_screen.dart
  - lib/presentation/receiver/receiver_screen.dart
  - lib/presentation/home/home_screen.dart
  - test/handshake/handshake_repository_test.dart
  - test/handshake/sender_prefill_test.dart
  - test/handshake/receiver_prefill_test.dart
findings:
  critical: 1
  warning: 7
  info: 4
  total: 12
status: issues_found
---

# Phase 5: Code Review Report

**Reviewed:** 2026-05-12T00:00:00Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Phase 5 introduces the neutral handshake model cleanly: `HandshakeRepository` is
well-structured with dependency injection, the `FirebaseConstants` addition is
correct, and the pre-fill constructor parameters on `SenderScreen`/`ReceiverScreen`
are wired consistently. However, several correctness and security issues were found
across the repository, Firestore rules, HomeScreen stream lifecycle, and tests.

The most urgent finding is a Firestore rule gap: the `transfers` create rule still
gates on the legacy `connections` subcollection rather than `neutral_handshakes`.
Additionally, HomeScreen leaks a Firestore stream subscription (the outer
`streamOutgoingPending` listen is fire-and-forget), and the `sendProposal` merge
clobbers `createdAt` on every re-send.

---

## Critical Issues

### CR-01: Firestore `transfers` create rule does not recognise `neutral_handshakes` connections

**File:** `firestore.rules:139-160`
**Issue:** The `transfers` collection create rule uses a dual `exists()` check against the
legacy `users/{uid}/connections` subcollection as its connection-based fallback. The
Phase 5 `neutral_handshakes` collection is never consulted. Users who establish a
connection exclusively through `neutral_handshakes` (the new Phase 5 path) will be
blocked from creating a transfer document unless they also have mirror `connections`
docs, which the new flow does not create. The `selectedSenderUid` handshake path still
works, but any scenario where that field is absent or stale will silently deny the
transfer write.

**Fix:** Add a `neutral_handshakes` existence check as an additional OR branch in the
create rule:

```
allow create: if isAuthenticated() &&
                 request.resource.data.senderId == request.auth.uid &&
                 (
                   // Handshake-authorized: receiver explicitly selected this sender
                   get(/databases/$(database)/documents/users/$(request.resource.data.receiverId)).data['selectedSenderUid'] == request.auth.uid

                   // Legacy bilateral connections
                   || (exists(/databases/$(database)/documents/users/$(request.resource.data.senderId)/connections/$(request.resource.data.receiverId)) &&
                       exists(/databases/$(database)/documents/users/$(request.resource.data.receiverId)/connections/$(request.resource.data.senderId)))

                   // Phase 5 neutral handshake: either party may have proposed
                   || exists(/databases/$(database)/documents/neutral_handshakes/$(request.auth.uid + '_' + request.resource.data.receiverId))
                   || exists(/databases/$(database)/documents/neutral_handshakes/$(request.resource.data.receiverId + '_' + request.auth.uid))
                 );
```

---

## Warnings

### WR-01: `sendProposal` overwrites `createdAt` on every merge, defeating idempotency intent

**File:** `lib/data/repositories/handshake_repository.dart:46-57`
**Issue:** `SetOptions(merge: true)` is used with `createdAt: FieldValue.serverTimestamp()`
included in the document map. On a re-send to the same `proposerId_partnerId` doc,
`createdAt` is overwritten with the new server time. This corrupts the audit trail and
means the timestamp no longer reflects when the original proposal was made. The comment
says "re-sends are idempotent" but the timestamp is not stable.

**Fix:** Use `set` with `SetOptions(mergeFields: [...])` listing every field except
`createdAt`, or use a separate `update` path after checking existence:

```dart
await _db
    .collection(FirebaseConstants.neutralHandshakes)
    .doc(docId)
    .set({
  'proposerId': _uid,
  'proposerUsername': currentUsername,
  'partnerId': partnerUid,
  'partnerUsername': partnerUsername,
  'status': 'pending',
  'createdAt': FieldValue.serverTimestamp(),   // only set on new doc
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(mergeFields: [
  'proposerUsername',   // allow username refresh on re-send
  'partnerUsername',
  'status',
  'updatedAt',
  // 'createdAt' intentionally omitted — not merged
]));
// For brand-new docs, createdAt must be seeded separately:
// Use a transaction or check doc.exists before deciding.
```

Simplest safe approach: use a transaction — set `createdAt` only when `!docSnap.exists`.

---

### WR-02: `sendProposal` silently sends proposals with empty `proposerUsername`

**File:** `lib/data/repositories/handshake_repository.dart:43-44`
**Issue:** The `currentUsername` is fetched from the user's Firestore document. If
the `username` field is absent or the document does not exist yet, it falls back to
`''`. The proposal is then written with `proposerUsername: ''`. `_ProposalBanner` in
HomeScreen renders this as `"@ wants to connect"` with no name — confusing for the
recipient and not detectable at the call site.

**Fix:** Add a guard after the fetch:

```dart
final currentUsername = userDoc.data()?['username'] as String? ?? '';
if (currentUsername.isEmpty) {
  throw AuthException('User profile incomplete — username not set.');
}
```

---

### WR-03: HomeScreen `_startOutcomeListener` leaks its outer stream subscription

**File:** `lib/presentation/home/home_screen.dart:85-123`
**Issue:** The `streamOutgoingPending()` subscription in `_startOutcomeListener` is
created via `.listen(...)` but the returned `StreamSubscription` is never stored.
`dispose()` only cancels `_pendingProposalSub` and the per-doc `_outcomeSubs`. The
outer outgoing-pending subscription continues to deliver events after the widget is
disposed. The `if (!mounted) return;` guard prevents UI updates but cannot cancel
the subscription, so new per-doc subscriptions will not be started (no crash), but
the parent Firestore listener remains open indefinitely for the lifetime of the
isolate.

**Fix:** Store and cancel the subscription:

```dart
StreamSubscription<QuerySnapshot>? _outcomePendingSub;  // new field

void _startOutcomeListener() {
  _outcomePendingSub = _handshakeRepo.streamOutgoingPending().listen((snap) {
    // ... existing body
  });
}

@override
void dispose() {
  _notifSub?.cancel();
  _bannerEntry?.remove();
  _pendingProposalSub?.cancel();
  _outcomePendingSub?.cancel();    // add this
  for (final sub in _outcomeSubs.values) sub.cancel();
  _outcomeSubs.clear();
  super.dispose();
}
```

---

### WR-04: Null crash in `_showNotifBanner` when user is signed out during dismiss

**File:** `lib/presentation/home/home_screen.dart:140,147`
**Issue:** `FirebaseAuth.instance.currentUser!.uid` uses a bang operator in both the
`onDismiss` and `onTap` callbacks of `_NotifBanner`. If the user is signed out
between the time the banner is shown and the time they dismiss or tap it (e.g., token
expiry, concurrent sign-out on another device), `currentUser` is `null` and the app
crashes with a `Null check operator used on a null value` exception.

**Fix:** Use null-safe access and guard the call:

```dart
onDismiss: () {
  entry.remove();
  if (_bannerEntry == entry) _bannerEntry = null;
  if (type != 'outcome') {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) NotificationService.markRead(uid, docId);
  }
},
```

Apply the same pattern to the `onTap` callback.

---

### WR-05: `neutral_handshakes` update rule permits proposer to self-accept a proposal

**File:** `firestore.rules:202-208`
**Issue:** The update rule permits the proposer to set `status = 'connected'` on their
own doc (`resource.data.proposerId == request.auth.uid && request.resource.data.status == 'connected'`).
This branch is intended to support the mutual-accept WriteBatch (where a second doc
`B_A` is also marked connected when `A_B` is accepted). However, a proposer can also
call `.update({'status': 'connected'})` directly on the `A_B` doc they created,
self-accepting their own pending proposal without waiting for the partner. Additionally,
a user could send a proposal to themselves (`proposerId == partnerId == auth.uid`) and
immediately self-accept it.

**Fix:** Add a guard to restrict the proposer-connected branch to the mutual-accept
scenario (where the current user is the partner on the canonical doc, i.e., a different
doc exists where `auth.uid` is the partner accepting):

At minimum, disallow self-proposals at the create rule level:
```
allow create: if isAuthenticated() &&
                 request.resource.data.proposerId == request.auth.uid &&
                 request.resource.data.proposerId != request.resource.data.partnerId;
```

For the mutual-accept branch, consider restricting it so the proposer-connected update
only applies when the mutual doc (`partnerId_proposerId`) also exists in connected state,
verified via `get()`.

---

### WR-06: `neutral_handshakes` update rule does not restrict updatable fields

**File:** `firestore.rules:202-208`
**Issue:** The update condition only checks the incoming `status` value — it does not
restrict which other fields are being modified. A malicious partner could accept a
proposal while also writing arbitrary values to `proposerUsername`, `partnerUsername`,
`createdAt`, or any other field in the same update call. While no privilege escalation
is possible, it allows data tampering in proposals (e.g., spoofing the displayed
username in banners).

**Fix:** Restrict the update to only allow changes to `status` and `updatedAt`:

```
allow update: if isAuthenticated() && (
  (resource.data.partnerId == request.auth.uid &&
   request.resource.data.status in ['connected', 'rejected'] &&
   request.resource.data.diff(resource.data).affectedKeys()
     .hasOnly(['status', 'updatedAt']))
  ||
  (resource.data.proposerId == request.auth.uid &&
   request.resource.data.status == 'connected' &&
   request.resource.data.diff(resource.data).affectedKeys()
     .hasOnly(['status', 'updatedAt']))
);
```

---

### WR-07: Pre-fill in `SenderScreen` is lost permanently on `_revertToWaiting`

**File:** `lib/presentation/sender/sender_screen.dart:112-115,147-160`
**Issue:** When `snap.docs.isEmpty` (receiver closed their session), `_revertToWaiting()`
nulls `_receiverId` and `_receiverUsername`. If the screen was launched with
`preFilledPartnerUid`, those values are gone. The pre-fill is only applied once in
`initState` and there is no re-application logic. After the revert, the UI shows the
pulsing "Waiting for Secure Connection" widget with no indication that the partner UID
context is still relevant, and the user cannot recover without navigating back and
re-entering `SenderScreen`.

Additionally, `streamHandshakesForSender()` fetches all incoming handshakes — if
another receiver connects first, `snap.docs.first` at line 125 will use their doc
regardless of `preFilledPartnerUid`. The filter at line 136-137 only applies when
assigning the fields, not to `_revertToWaiting()`, so any empty snapshot (even from a
different user's disconnect) triggers the revert.

**Fix:** In `_revertToWaiting()`, preserve the pre-fill when reverting:

```dart
void _revertToWaiting() {
  _wipeSensitiveData();
  if (mounted) {
    setState(() {
      // Preserve pre-fill so the sender stays targeted at the intended partner
      _receiverId = widget.preFilledPartnerUid;
      _receiverUsername = widget.preFilledPartnerUsername ?? 'Partner';
      _selectedReceiverPublicKeyJson = null;
      _file = null;
      _encryptedAESKey = null;
      _encrypting = false;
      _encryptingKey = false;
    });
  }
}
```

For the multi-receiver race: also filter `_onHandshakeUpdate` to only call
`_revertToWaiting()` when the empty snapshot is relevant to the pre-filled partner
(i.e., do not revert if pre-fill is active and the emptied docs were from a different
sender).

---

## Info

### IN-01: TC-HAND-03 uses the wrong actor — proposer rejects instead of partner

**File:** `test/handshake/handshake_repository_test.dart:67-87`
**Issue:** `rejectProposal` is called using `mockAuth` (user1), who is the proposer.
By design and by the Firestore rules, only the partner may reject. The test passes
because `fake_cloud_firestore` does not enforce security rules, but the same call
would be denied on real Firestore. The test is validating the wrong authorization
path and gives false confidence.

**Fix:** Use `auth2` (user2, the partner) to call `rejectProposal`:

```dart
final auth2 = MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'user2'));
final repo = HandshakeRepository(db: fakeFirestore, auth: auth2);
await repo.rejectProposal('user1_user2');
```

---

### IN-02: Test coverage gap — streaming and outcome methods not tested

**File:** `test/handshake/handshake_repository_test.dart`
**Issue:** `streamActiveConnectionsAsProposer`, `streamActiveConnectionsAsPartner`,
`streamOutgoingPending`, and `streamProposalOutcome` have no test cases. Given that
these streams drive the HomeScreen Active Connections section and the outcome banner,
their absence means the main UI data paths are untested. TC-HAND-06 is referenced in
comments but not present.

**Fix:** Add tests for at minimum the two `streamActiveConnections*` methods and
`streamProposalOutcome`, verifying they emit the correct docs after an `acceptProposal`
call.

---

### IN-03: `sender_prefill_test.dart` TC-HAND-07 is a constructor smoke test, not a behavioral test

**File:** `test/handshake/sender_prefill_test.dart:12-31`
**Issue:** The test only verifies that the widget can be constructed and that the
constructor fields are accessible. It does not verify the D-13 behavior: that
`_receiverId` is set to `preFilledPartnerUid` during `initState`, skipping the
`_FindSenderSheet`. The actual pre-fill logic (lines 82-91 of `sender_screen.dart`)
is untested.

**Fix:** Use `testWidgets` with a mocked Firebase environment to pump `SenderScreen`
with pre-fill parameters and verify the `_ConnectedBadge` (not `_WaitingForConnectionWidget`)
is rendered for the pre-filled username.

---

### IN-04: HomeScreen Recent Transfers `StreamBuilder` creates a new stream on every rebuild

**File:** `lib/presentation/home/home_screen.dart:457-464`
**Issue:** The Firestore query for Recent Transfers is constructed inline inside
`build()`. Each call to `build()` produces a new `Stream` object with a different
object identity. `StreamBuilder` compares stream identity and re-subscribes when the
stream reference changes, opening a new Firestore listener on every `setState` call
in `_HomeScreenState`. Since `_HomeScreenState` receives updates from three active
stream subscriptions (`_notifSub`, `_pendingProposalSub`, `_outcomeSubs`), this can
open many redundant listeners.

**Fix:** Lift the stream into a field initialized in `initState`:

```dart
late final Stream<QuerySnapshot> _recentTransfersStream;

@override
void initState() {
  super.initState();
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  _recentTransfersStream = FirebaseFirestore.instance
      .collection(FirebaseConstants.users)
      .doc(uid)
      .collection(FirebaseConstants.auditLogs)
      .orderBy('loggedAt', descending: true)
      .limit(10)
      .snapshots();
  // ... rest of initState
}
```

Then reference `stream: _recentTransfersStream` in the `StreamBuilder`.

---

_Reviewed: 2026-05-12T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
