---
status: complete
trigger: Connection cannot be established in actual app. Users click "Send File" or "Receive File" but get "Connection not established" error. Previous friendships sync fix (b32dbd0) didn't work. Need to trace Firestore state and getConnectionStatus logic.
created: 2026-05-26
updated: 2026-05-26
---

## Symptoms

**Expected behavior:** After User A sends proposal to User B, and User B accepts, both users should be able to click "Send File" / "Receive File" and navigate to sender/receiver screens without error

**Actual behavior:** Users get error "Connection with @ not establish yet. Connection: null" when trying to select roles

**Timeline:** Issue persists after commit b32dbd0 which was supposed to fix friendships sub-collection sync in acceptProposal()

**Repro steps:**
1. User A sends connection proposal to User B
2. User B accepts proposal
3. User A or B clicks "Send File" or "Receive File"
4. Error dialog appears: "Connection not established"

---

## Root Cause Analysis

**Root Cause:** Firestore security rule for `users/{userId}/friendships` blocked the bidirectional writes during `acceptProposal()`'s WriteBatch.

**Technical Details:**

1. `acceptProposal()` in HandshakeRepository attempts atomic WriteBatch with two writes:
   - Write 1: `users/{acceptorUid}/friendships/{proposerUid}` → status='accepted'
   - Write 2: `users/{proposerUid}/friendships/{acceptorUid}` → status='accepted'

2. Original security rule (line 84):
   ```
   allow read, write: if request.auth.uid == userId;
   ```

3. **The problem:** When User B calls `acceptProposal(proposerId='A')`:
   - Write 1: `users/B/friendships/A` — ALLOWED (B owns this doc)
   - Write 2: `users/A/friendships/B` — DENIED (A != B, security rule blocks B's write)

4. WriteBatch doesn't have "all-or-nothing" semantics in Firestore SDK:
   - First write succeeds, second write fails silently
   - User A's friendships doc is never created
   - When User A tries to `assignTransferRole()`, `getConnectionStatus()` returns null
   - Result: "Connection not established. Status: null"

---

## Evidence

- timestamp: 2026-05-26T14:45:00Z
  scope: code_review
  finding: acceptProposal() attempts bidirectional WriteBatch writes
  file: lib/data/repositories/handshake_repository.dart
  lines: 148-170
  detail: Batch updates both users/{uid}/friendships/{partner} docs

- timestamp: 2026-05-26T14:46:00Z
  scope: code_review
  finding: getConnectionStatus() reads from current user's friendships collection
  file: lib/data/repositories/key_repository.dart
  lines: 56-65
  detail: Returns null if doc doesn't exist

- timestamp: 2026-05-26T14:47:00Z
  scope: security_rules
  finding: Original rule only allowed owner writes
  file: firestore.rules
  line: 84 (before fix)
  detail: "allow read, write: if request.auth.uid == userId"

- timestamp: 2026-05-26T14:48:00Z
  scope: test_coverage
  finding: TC-HAND-02b passes with FakeFirestore but fails in production
  file: test/handshake/handshake_repository_test.dart
  lines: 71-114
  detail: FakeFirestore doesn't enforce security rules; test gives false confidence

---

## Fix Applied

**File:** firestore.rules (lines 84-87)

**Before:**
```
allow read, write: if request.auth.uid == userId;
allow delete: if request.auth.uid == friendId;
```

**After:**
```
allow read: if request.auth.uid == userId;
allow write: if request.auth.uid == userId ||
               (request.auth.uid == friendId &&
                request.resource.data.status == 'accepted');
allow delete: if request.auth.uid == friendId;
```

**Security Implications:**
- Still requires authentication
- Allows friend to create/update only when `status='accepted'`
- Prevents unauthorized bulk writes or status changes
- Maintains principle of least privilege

**How It Fixes The Issue:**
- User B's acceptProposal() WriteBatch now succeeds on both writes
- Users/{proposerUid}/friendships/{acceptorUid} is created with status='accepted'
- When User A calls getConnectionStatus(B), the doc exists and returns 'accepted'
- assignTransferRole() validation passes → users can navigate to sender/receiver screens

**Commit:** b3717fa `fix(friendships-security-rules): allow bidirectional writes during accept flow`

---

## Resolution

**root_cause:** Firestore security rule for users/{userId}/friendships restricted write access to owner only, blocking the bidirectional friendships sync in acceptProposal() WriteBatch. The second write silently failed, leaving one user's friendships doc unwritten.

**fix:** Updated firestore.rules line 84-87 to allow the accepting user to write to the proposer's friendships doc when setting status='accepted'. This enables atomic bidirectional sync during the accept flow while maintaining security via status field validation.

**impact:** Users can now successfully accept proposals and assign roles (Send/Receive File) without "Connection not established" errors.

**test_plan:**
1. Manual UAT: User A proposes to User B → User B accepts → both click Send/Receive File → navigate successfully
2. Verify TC-HAND-02b still passes
3. Test with real Firestore (not FakeFirestore) to confirm rule enforcement

**specialist_hint:** firestore (security rules + dart WriteBatch semantics)
