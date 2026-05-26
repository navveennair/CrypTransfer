---
status: fixed
trigger: User cannot click "Send File" or "Receive File" buttons — buttons show visual feedback (ripple) but no navigation occurs. Error message shows "Connection with @ not establish yet. Connection: null"
created: 2026-05-26
updated: 2026-05-26
---

## Symptoms

**Expected behavior:** Tap "Send File" or "Receive File" → navigate to sender/receiver screen

**Actual behavior:** Button shows ripple/visual feedback but no navigation; error message displays "Connection with @ not establish yet. Connection: null"

**Error messages:** "Connection with @ not establish yet. Connection: null"

**Timeline:** Broken after changes to handshake → transfer model

**Reproducibility:** 100% reproducible every time

**Android logs:** OnBackInvokedCallback warning, EGL emulation stats (timing: avg=154.45ms, max=3989.28ms)

---

## Root Cause

**Category:** Data model sync failure between `neutral_handshakes` and `friendships` sub-collection

**Location:** `lib/data/repositories/handshake_repository.dart` method `acceptProposal()`

**Root Cause:** When a proposal was accepted, the `acceptProposal()` method updated the `neutral_handshakes` collection to `status: 'connected'` but failed to update the bidirectional `users/{uid}/friendships/{otherUid}` sub-collection documents. Downstream, `KeyRepository.assignTransferRole()` checks the friendships sub-collection for connection status, which was never populated, causing a null return and the error "Connection with @ not establish yet. Connection: null".

**Impact:** Users cannot navigate to sender/receiver screens after accepting a connection proposal — buttons show ripple feedback but no action taken.

---

## Fix Applied

**File modified:** `lib/data/repositories/handshake_repository.dart`

**Method:** `acceptProposal(String docId, String proposerId)`

**Changes:**
1. Fetch the primary `neutral_handshakes` doc to extract proposer/partner usernames (proposerUsername, partnerUsername)
2. Build bidirectional friendships sub-collection refs:
   - `users/{_uid}/friendships/{proposerId}` (acceptor's perspective — they are adding the proposer)
   - `users/{proposerId}/friendships/{_uid}` (proposer's perspective — they are updating their request to accepted)
3. Batch-update friendships docs with:
   - `status: 'accepted'`
   - `uid`: the other user's ID
   - `username`: the other user's username (proposerUsername for acceptor, partnerUsername for proposer)
   - `updatedAt: FieldValue.serverTimestamp()`
4. Use `SetOptions(merge: true)` to preserve any other fields in the friendship doc
5. Commit all updates (neutral_handshakes + friendships) in a single atomic WriteBatch

**Result:** When users accept a proposal:
- Both parties' `friendships` sub-collection documents are created/updated with `status: 'accepted'`
- Downstream call to `KeyRepository.getConnectionStatus(partnerUid)` finds the connection and returns `'accepted'`
- `KeyRepository.assignTransferRole()` passes the connection check and allows navigation
- User can tap "Send File" or "Receive File" and navigate to sender/receiver screen

---

## Testing

**Tests added:** `TC-HAND-02b` — new comprehensive test verifying bidirectional friendships sync

```dart
test('TC-HAND-02b: acceptProposal updates friendships sub-collection with status=accepted', () async {
  // Setup: create neutral_handshakes doc with usernames
  // Call: acceptProposal as user2 (the acceptor)
  // Verify: both friendship docs exist with status=accepted and correct usernames
});
```

**Test results:**
- All handshake tests: 11/11 PASSING ✓
- Handshake prefill tests: 2/2 PASSING ✓
- Total: 13/13 PASSING ✓

**Verification:**
- `flutter analyze` on modified file: No issues found ✓
- `flutter test test/handshake/` — All tests passing ✓

---

## Files Modified

1. `lib/data/repositories/handshake_repository.dart` — Updated acceptProposal() to sync friendships
2. `test/handshake/handshake_repository_test.dart` — Added TC-HAND-02b test case

---

## Resolution Summary

**Root Cause:** Two-collection data model mismatch — proposal acceptance updated `neutral_handshakes` but not `friendships` sub-collection

**Fix Type:** Atomically update both collections in `acceptProposal()` using WriteBatch

**Impact:**
- Unblocks "Send File" / "Receive File" navigation after connection acceptance
- Users can now proceed from HomeScreen → SenderScreen or ReceiverScreen
- Maintains data consistency across both collection layers

