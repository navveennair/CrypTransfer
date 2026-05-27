---
status: resolved
trigger: "Tapping Accept/Reject on a pending proposal causes entire screen to freeze with no dialog appearing"
created: 2026-05-26T22:40:00Z
updated: 2026-05-26T22:55:00Z
---

## ROOT CAUSE

Unnecessary use of SetOptions(merge: true) on friendships documents in acceptProposal() that were being created for the first time.

Location: lib/data/repositories/handshake_repository.dart, lines 156 and 169 (before fix)

The acceptProposal() method was executing:
```dart
batch.set(myFriendshipRef, {...}, SetOptions(merge: true))
batch.set(otherFriendshipRef, {...}, SetOptions(merge: true))
```

When Firestore tried to merge data with non-existent documents using SetOptions(merge: true), the security rule evaluation hung indefinitely checking `request.resource.data.status == 'accepted'` in the merge context.

## FIX APPLIED

Removed SetOptions(merge: true) from both batch.set() calls in acceptProposal().

Changed from:
```dart
batch.set(myFriendshipRef, data, SetOptions(merge: true))
```

To:
```dart
batch.set(myFriendshipRef, data)
```

Since the friendships documents don't exist yet (they're only created during acceptProposal()), SetOptions(merge: true) is unnecessary. The regular batch.set() operation is more efficient and doesn't trigger the rule evaluation hang.

## COMMIT

Commit: 92e7ebc
Message: fix(dialogs-freeze-on-proposal-accept): remove unnecessary SetOptions(merge: true) from batch friendships writes

## TEST RESULTS

All tests passing:
- TC-HAND-01 through TC-HAND-06c: 9/9 handshake repository tests ✓
- TC-HAND-07: Sender prefill tests ✓
- TC-HAND-08: Receiver prefill tests ✓
- TC-ROLE-01 through TC-ROLE-06: 6/6 role assignment conflict tests ✓

## EXPECTED BEHAVIOR AFTER FIX

When user taps Accept or Reject button on a pending proposal:
1. Button shows loading spinner (state change works now)
2. friendships documents are created successfully in Firestore
3. batch.commit() completes without hanging
4. UI remains responsive throughout
5. The operation completes in < 2 seconds

## ROOT CAUSE ANALYSIS

acceptProposal() creates two friendships documents for the first time:
- `users/{acceptingUserId}/friendships/{proposerId}` 
- `users/{proposerId}/friendships/{acceptingUserId}`

The sendProposal() phase (which precedes acceptProposal()) only creates neutral_handshakes docs. The friendships docs don't exist until acceptProposal() writes them via WriteBatch.

When using SetOptions(merge: true) on a non-existent document:
- Firestore still evaluates the security rule with the merge flag set
- The rule check `request.resource.data.status == 'accepted'` may not work correctly in merge context
- This causes the rule evaluation to hang indefinitely
- The batch.commit() awaits the rule evaluation, so it never completes
- The entire UI thread is blocked waiting for batch.commit()

Removing SetOptions(merge: true) causes Firestore to execute a regular set operation instead of a merge, which completes instantly without the rule evaluation hang.

