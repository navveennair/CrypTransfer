---
phase: 05-neutral-handshake-model
reviewed: 2026-05-13T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - firestore.rules
  - lib/data/repositories/handshake_repository.dart
  - lib/presentation/home/home_screen.dart
  - lib/presentation/sender/sender_screen.dart
  - test/handshake/handshake_repository_test.dart
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 05: Code Review Report (Re-review — Gap Closure Pass)

**Reviewed:** 2026-05-13T00:00:00Z
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

This is the re-review of the five files modified to close the findings from the prior
pass (CR-01, WR-01 through WR-07, IN-01, IN-02, IN-04). The prior critical finding
(CR-01) and five of seven warnings are correctly resolved. Specifically:

- WR-01 (`createdAt` clobbered on re-send): fixed via `runTransaction` — the `createdAt`
  field is now only written when `!snap.exists`.
- WR-02 (empty proposerUsername): fixed — `AuthException` is now thrown if `currentUsername` is empty.
- WR-03 (`_outcomePendingSub` leaked): fixed — field stored and cancelled in `dispose()`.
- WR-04 (null bang crash on banner dismiss/tap): fixed — `currentUser?.uid` with null guard.
- WR-05 (self-proposal): fixed — `proposerId != partnerId` added to create rule.
- WR-06 (field restriction on update): fixed — `affectedKeys().hasOnly(['status', 'updatedAt'])` applied.
- WR-07 (`_revertToWaiting` drops pre-fill): fixed — `preFilledPartnerUid/Username` preserved.
- IN-01 (TC-HAND-03 used wrong actor): fixed — auth2 (partner) now used.
- IN-02 (streaming methods untested): fixed — TC-HAND-06a/06b/06c added.
- IN-04 (`_recentTransfersStream` in `build()`): fixed — stream lifted to `initState`.

Three new findings remain that were introduced or left unresolved in this pass.

---

## Warnings

### WR-01: Firestore `neutral_handshakes` exists check in `transfers` create rule does not verify `status == 'connected'`

**File:** `firestore.rules:153-154`

**Issue:** The two Phase 5 OR branches added to the `transfers` create rule use `exists()`
to check for a `neutral_handshakes` document, but do not verify that its `status` is
`'connected'`. A `pending` or `rejected` handshake document also satisfies the rule.
This allows a sender to create a transfer document before the receiver has accepted the
connection request — bypassing the handshake acceptance gating entirely.

```javascript
// Current — any status (pending, rejected, connected) satisfies the rule:
|| exists(/databases/$(database)/documents/neutral_handshakes/$(request.auth.uid + '_' + request.resource.data.receiverId))
|| exists(/databases/$(database)/documents/neutral_handshakes/$(request.resource.data.receiverId + '_' + request.auth.uid))
```

**Fix:** Switch from `exists()` to `get()` with a status field check. Use `.get('status', '')`
to safely handle missing fields (returns `''` when the document doesn't exist, avoiding
a Firestore rules null-access error):

```javascript
// Fixed — only a connected handshake authorises a transfer:
|| get(/databases/$(database)/documents/neutral_handshakes/$(request.auth.uid + '_' + request.resource.data.receiverId)).data.get('status', '') == 'connected'
|| get(/databases/$(database)/documents/neutral_handshakes/$(request.resource.data.receiverId + '_' + request.auth.uid)).data.get('status', '') == 'connected'
```

Note: `get()` returns `__null__` (not an error) if the document does not exist, and
chaining `.data.get('status', '')` safely returns `''` in that case. This pattern is
consistent with the `selectedSenderUid` check already used on line 148.

---

### WR-02: `sendProposal` re-send on a `connected` doc resets it to `pending`

**File:** `lib/data/repositories/handshake_repository.dart:66-72`

**Issue:** The `runTransaction` `else` branch (triggered when the doc already exists)
unconditionally writes `'status': 'pending'` on line 70. If the existing document has
`status == 'connected'` — meaning the receiver already accepted the proposal — calling
`sendProposal` again silently tears down the established connection by resetting it to
`pending`. This can be triggered if the user navigates to `FindFriendsScreen` and taps
"Send" on a contact they are already connected to.

```dart
} else {
  tx.update(docRef, {
    'proposerUsername': currentUsername,
    'partnerUsername': partnerUsername,
    'status': 'pending',      // BUG: overwrites 'connected'
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
```

**Fix:** Read the current `status` inside the transaction and only set it to `'pending'`
when the document is not already connected:

```dart
} else {
  final currentStatus = snap.data()?['status'] as String? ?? '';
  final updates = <String, dynamic>{
    'proposerUsername': currentUsername,
    'partnerUsername': partnerUsername,
    'updatedAt': FieldValue.serverTimestamp(),
  };
  // Only reset to pending if not already connected — do not break
  // an established connection on a redundant send.
  if (currentStatus != 'connected') {
    updates['status'] = 'pending';
  }
  tx.update(docRef, updates);
}
```

---

### WR-03: `acceptProposal` mutual-doc read is outside the batch — TOCTOU gap

**File:** `lib/data/repositories/handshake_repository.dart:91-105`

**Issue:** `mutualRef.get()` on line 94 is called before the `WriteBatch` is created.
If the partner's mutual proposal document (`B_A`) is created by another client in the
narrow window between the `get()` and `batch.commit()`, the batch will not include it
(`mutualSnap.exists` is stale), leaving an asymmetric state: the primary doc is
`'connected'` but the simultaneously-created mutual doc remains `'pending'`.

```dart
final mutualSnap = await mutualRef.get();   // snapshot taken here

final batch = _db.batch();
batch.update(primaryRef, {'status': 'connected', ...});
if (mutualSnap.exists) {                    // stale read; race window here
  batch.update(mutualRef, {'status': 'connected', ...});
}
await batch.commit();
```

**Fix:** Move both reads and writes into a `runTransaction` so they are atomic:

```dart
Future<void> acceptProposal(String docId, String proposerId) async {
  try {
    final primaryRef = _db
        .collection(FirebaseConstants.neutralHandshakes)
        .doc(docId);
    final mutualRef = _db
        .collection(FirebaseConstants.neutralHandshakes)
        .doc('${_uid}_$proposerId');

    await _db.runTransaction((tx) async {
      final mutualSnap = await tx.get(mutualRef);
      tx.update(primaryRef,
          {'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()});
      if (mutualSnap.exists) {
        tx.update(mutualRef,
            {'status': 'connected', 'updatedAt': FieldValue.serverTimestamp()});
      }
    });
  } on FirebaseException catch (e) {
    throw NetworkException(
        'Failed to accept proposal: ${e.message ?? e.code}');
  }
}
```

---

## Info

### IN-01: No client-side self-proposal guard in `sendProposal`

**File:** `lib/data/repositories/handshake_repository.dart:41`

**Issue:** `sendProposal` validates that `partnerUid` is non-empty but does not check
whether `partnerUid == _uid`. If the caller passes their own UID, the call is blocked
server-side by the Firestore rule (`proposerId != partnerId`), but the caller receives
a generic `NetworkException` (permission-denied wrapped) rather than a meaningful error
message. The `FindFriendsScreen` UI likely prevents this from happening normally, but
the repository layer should be defensive.

**Fix:** Add a self-proposal guard alongside the empty check:

```dart
if (partnerUid.isEmpty) throw AuthException('partnerUid required');
if (partnerUid == _uid) throw AuthException('Cannot send a connection request to yourself.');
```

---

### IN-02: No test for `sendProposal` called on an already-`connected` doc

**File:** `test/handshake/handshake_repository_test.dart`

**Issue:** The WR-02 bug above (re-proposal resets a `connected` doc to `pending`) is not
covered by any test. If WR-02 is fixed, a regression test should lock the behaviour to
prevent future regressions.

**Fix:** Add a test case after fixing WR-02:

```dart
test('TC-HAND-07: sendProposal on connected doc preserves connected status',
    () async {
  await fakeFirestore.collection('neutral_handshakes').doc('user1_user2').set({
    'proposerId': 'user1',
    'partnerId': 'user2',
    'status': 'connected',
    'proposerUsername': 'testuser1',
    'partnerUsername': 'alice',
  });

  final repo = HandshakeRepository(db: fakeFirestore, auth: mockAuth);
  await repo.sendProposal(partnerUid: 'user2', partnerUsername: 'alice');

  final snap = await fakeFirestore
      .collection('neutral_handshakes').doc('user1_user2').get();
  expect(snap.data()!['status'], equals('connected'));
});
```

---

### IN-03: Hard cast `notif['docId'] as String` is fragile against stream contract changes

**File:** `lib/presentation/home/home_screen.dart:139`

**Issue:** `_showNotifBanner` performs `final docId = notif['docId'] as String;` as a
hard cast. The cast is currently safe because `NotificationService.latestUnreadStream`
always populates `'docId'` (line 49 of `notification_service.dart`). However, `_showNotifBanner`
is also called from `_startOutcomeListener` (line 118) with an inline map that always
includes `'docId'`. The danger is that if `latestUnreadStream` contract ever changes
(e.g., the `docId` key is renamed or omitted in a refactor), this becomes a `TypeError`
crash at runtime rather than a graceful fallback.

**Fix:** Use a null-safe cast and add a guard:

```dart
final docId = notif['docId'] as String?;
if (docId == null) return; // defensive guard — skip if contract violated
final message = notif['message'] as String? ?? 'New notification';
```

---

_Reviewed: 2026-05-13T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
