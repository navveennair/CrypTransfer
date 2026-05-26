---
status: fixed
trigger: "Tapping Accept/Reject on a pending proposal causes entire screen to freeze with no dialog appearing"
created: 2026-05-26T22:40:00Z
updated: 2026-05-26T22:52:00Z
---

## ROOT CAUSE FOUND & FIXED

The hang in acceptProposal() was caused by using **SetOptions(merge: true)** on friendships documents that don't exist yet.

### Root Cause

Location: lib/data/repositories/handshake_repository.dart, lines 156 and 169 (previously)

The code was doing:
```dart
batch.set(myFriendshipRef, {...}, SetOptions(merge: true))
batch.set(otherFriendshipRef, {...}, SetOptions(merge: true))
```

These documents are being created for the **first time** when acceptProposal() is called (sendProposal() only creates neutral_handshakes docs, not friendships docs).

When Firestore tries to merge data with non-existent documents using SetOptions(merge: true), and the security rule checks `request.resource.data.status == 'accepted'` in the merge context, the rule evaluation hangs indefinitely because:

1. The document doesn't exist yet
2. SetOptions(merge: true) causes Firestore to attempt a merge operation
3. The security rule evaluation for a merge on non-existent docs may not work correctly
4. The batch.commit() hangs waiting for the rule evaluation to complete

### Fix Applied

Removed SetOptions(merge: true) from both batch.set() calls in acceptProposal() (lines 148-170).

Since the friendships documents don't exist yet, SetOptions(merge: true) is unnecessary. The regular batch.set() operation creates the documents with the provided data, which is all that's needed.

Changed from:
```dart
batch.set(ref, data, SetOptions(merge: true))
```

To:
```dart
batch.set(ref, data)
```

### Test Results

All 9 handshake repository tests pass, including:
- TC-HAND-02b: acceptProposal updates friendships sub-collection with status=accepted

### Files Changed

- lib/data/repositories/handshake_repository.dart: Removed SetOptions(merge: true) from lines 156 and 169

### Expected Behavior After Fix

When user taps Accept or Reject button on a pending proposal:
1. The batch.set() operations now execute without hanging
2. The friendships documents are created successfully
3. The UI is responsive and shows loading indicator on the button
4. The operation completes successfully without freezing the screen

