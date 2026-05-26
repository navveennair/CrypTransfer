# CRITICAL CONFLICT AUDIT: Hook 1 vs Hook 2

## Executive Summary

**YES — CRITICAL ARCHITECTURAL CONFLICTS DETECTED**

Three separate issues have been identified that could cause state corruption, race conditions, and broken stream logic when Hook 1 (Add New Connection) intersects with Hook 2 (Send/Receive File).

---

## 1. DIRECTIONALITY MISMATCH

### Hook 1: Connection Directionality (neutral_handshakes)

**Document ID scheme:** `${proposerId}_${partnerId}` (UNSORTED, direction matters)

```dart
// handshake_repository.dart:54
final docRef = _db
    .collection(FirebaseConstants.neutralHandshakes)
    .doc('${_uid}_$partnerUid');  // ← currentUser is PROPOSER

// Fields written:
{
  'proposerId': currentUser,      // ← Initiator (who clicked Send)
  'partnerId': targetUser,        // ← Approver (who receives request)
  'status': 'pending' → 'connected'
}
```

**Example:** User A sends request to User B
- Document ID: `a_b`
- proposerId: a
- partnerId: b

---

### Hook 2: Transfer Directionality (handshakes)

**Document ID scheme:** `${sortedUid1}_${sortedUid2}` (SORTED, direction-neutral)

```dart
// key_repository.dart:668-669
final sortedUids = [currentUid, partnerUid]..sort();
final docId = '${sortedUids[0]}_${sortedUids[1]}';  // ← ALWAYS alphabetical

// Fields written:
{
  'senderId': senderUid,          // ← Whoever clicks "Send File"
  'receiverId': receiverUid,      // ← Whoever clicks "Receive File"
  'status': 'handshake_pending'
}
```

**Example 1:** User A clicks "Send File" to User B
- Document ID: `a_b` (a < b alphabetically)
- senderId: a
- receiverId: b

**Example 2:** User B clicks "Send File" to User A
- Document ID: `a_b` (same ID!)
- senderId: b
- receiverId: a (OVERWRITES previous!)

---

## 2. CRITICAL CONFLICT #1: Document ID Collision & Last-Writer-Wins

### The Problem

Both hooks can write to overlapping document IDs when roles reverse.

```
Scenario: User A proposes to User B, then roles flip

Timeline:
─────────────────────────────────────────────────────────

T1: User A sends connection request to B
    neutral_handshakes/a_b: {proposerId: a, partnerId: b, status: pending}

T2: User B accepts connection request
    neutral_handshakes/a_b: {proposerId: a, partnerId: b, status: connected}

T3: User A clicks "Send File" to B
    ├─ Calls: assignTransferRole(partnerUid: b, isSender: true)
    ├─ Sorted UIDs: [a, b].sort() = [a, b]
    └─ Writes to handshakes/a_b:
       {senderId: a, receiverId: b, rolesAssignedAt: T3, ...}
       
    SenderScreen initialized with:
    - handshakeDocId: a_b
    - Expected: senderId == a, receiverId == b

T4: User B clicks "Send File" to A (SIMULTANEOUS or RACE)
    ├─ Calls: assignTransferRole(partnerUid: a, isSender: true)
    ├─ Sorted UIDs: [b, a].sort() = [a, b]
    └─ Writes to handshakes/a_b:  ← SAME DOCUMENT!
       {senderId: b, receiverId: a, rolesAssignedAt: T4, ...}
       ↑ OVERWRITES User A's role assignment!

T5: User A's SenderScreen still references handshakeDocId=a_b
    ├─ But the document now has senderId: b (NOT a)
    ├─ User A is no longer the sender!
    └─ CONFLICT: SenderScreen expects to send, but doc says b is sender
```

---

## 3. CRITICAL CONFLICT #2: Stream Query Mismatch

### The Problem

SenderScreen listens to a stream that filters by `senderId == currentUser`. If the document gets overwritten by the partner, the query result changes mid-flow.

```dart
// sender_screen.dart: _startHandshakeListener()
Stream<QuerySnapshot<Map<String, dynamic>>> streamHandshakesForSender() {
  final senderId = _uid;
  return _db
      .collection(FirebaseConstants.handshakes)
      .where('senderId', isEqualTo: senderId)  // ← Filters by sender
      .snapshots();
}
```

**Scenario Breakdown:**

```
T1: User A navigates to SenderScreen with handshakeDocId=a_b
    ├─ SenderScreen initialized
    ├─ _startHandshakeListener() called
    └─ Listening to: handshakes WHERE senderId == a
       
       Current state in Firestore:
       handshakes/a_b: {senderId: a, receiverId: b, ...}
       
       Query result: ✅ Document appears (senderId == a)

T2: User B clicks "Send File" simultaneously
    └─ Overwrites: handshakes/a_b: {senderId: b, receiverId: a, ...}
    
       New state in Firestore:
       handshakes/a_b: {senderId: b, receiverId: a, ...}
       
       Query result: ❌ Document DISAPPEARS (senderId != a)

T3: User A's SenderScreen stream fires with EMPTY result
    ├─ The document User A thought was handshaking is gone from their view
    ├─ UI state becomes inconsistent
    └─ ERROR: Expected to see their own handshake doc, but can't
```

**Code Location:** `lib/presentation/sender/sender_screen.dart:95-96`

```dart
_startHandshakeListener();  // ← This stream expects the document to stay assigned to sender
```

---

## 4. CRITICAL CONFLICT #3: No Connection Validation

### The Problem

`assignTransferRole()` creates a handshake document WITHOUT validating that a `neutral_handshakes` connection exists.

```dart
// key_repository.dart:657-698
Future<String> assignTransferRole({
  required String partnerUid,
  required bool isSender,
}) async {
  try {
    final currentUid = _uid;
    
    // ⚠️ NO VALIDATION that currentUid and partnerUid are actually connected!
    
    final sortedUids = [currentUid, partnerUid]..sort();
    final docId = '${sortedUids[0]}_${sortedUids[1]}';
    
    // ⚠️ DIRECT WRITE to handshakes collection
    await _db.collection(FirebaseConstants.handshakes).doc(docId).set({
      'receiverId': receiverUid,
      'senderId': senderUid,
      'status': 'handshake_pending',
      // ...
    }, SetOptions(merge: true));  // ← merge: true allows overwriting
    
    return docId;
  }
}
```

**Missing Validation:**

```dart
// Should have:
final connectionStatus = await getConnectionStatus(partnerUid);
if (connectionStatus != 'accepted') {
  throw Exception('Connection not established yet');
}
```

**Consequence:** A user can call assignTransferRole with someone they have NO connection to in `neutral_handshakes`. The role assignment succeeds, but there's no bilateral connection established.

---

## 5. SetOptions(merge: true) Vulnerability

### The Problem

The `merge: true` option allows PARTIAL document overwrites. Each call to `assignTransferRole()` with the same UID pair will merge-update the senderId/receiverId fields.

```dart
SetOptions(merge: true)  // ← Dangerous with role fields

// T1: User A writes
await _db.collection('handshakes').doc('a_b').set({
  senderId: a,
  receiverId: b,
  status: 'handshake_pending',
  createdAt: T1,
}, SetOptions(merge: true));

// T2: User B writes (OVERWRITES role fields)
await _db.collection('handshakes').doc('a_b').set({
  senderId: b,
  receiverId: a,
  status: 'handshake_pending',
  createdAt: T1,  // Still T1 because of merge
}, SetOptions(merge: true));

// Result:
handshakes/a_b: {
  senderId: b,      // ← OVERWRITTEN
  receiverId: a,    // ← OVERWRITTEN
  status: 'handshake_pending',  // Last writer wins
  createdAt: T1     // Preserved from T1
}
```

---

## 6. Specific Code Locations of Conflicts

| Conflict | File | Line | Issue |
|----------|------|------|-------|
| No connection validation | key_repository.dart | 657-698 | assignTransferRole() doesn't check neutral_handshakes status |
| Document ID collision | key_repository.dart | 668-669 | Sorted UID scheme allows overwrites |
| Dangerous merge: true | key_repository.dart | 683 | SetOptions(merge: true) allows role field overwrite |
| Stream query mismatch | sender_screen.dart | 95-96 | streamHandshakesForSender() filters by senderId (vulnerable to overwrite) |
| No role conflict protection | receiver_screen.dart | 386-399 | Role validation runs AFTER navigation; too late to prevent conflict |

---

## 7. Stream Listener Implications

### Receiver Role Validation (Too Late)

**File:** `lib/presentation/receiver/receiver_screen.dart:386-399`

```dart
// This validation runs AFTER role picker navigation
if (docId.isNotEmpty && mounted) {
  try {
    final handshakeDoc = await FirebaseFirestore.instance
        .collection(FirebaseConstants.handshakes)
        .doc(docId)
        .get();
    final receiverUid = handshakeDoc.data()?['receiverUid'] as String?;
    
    if (receiverUid != null && receiverUid.isNotEmpty && receiverUid != currentUid) {
      _showError('Role conflict — partner chose a different role. Try again.');
      await _onToggleReady(false);
      return;  // ← Navigation already happened!
    }
```

**Problem:** This is a ONE-TIME check in `initState()`. If the partner overwrites the role AFTER ReceiverScreen is initialized, this validation never fires again.

---

## 8. Why This Breaks

### Race Condition Window

```
Scenario: User A (proposer) and User B (partner) are connected

A: Click "Send File" → assignTransferRole(isSender: true) → SenderScreen
                       (handshakes/a_b: senderId=a, receiverId=b)

B: Click "Send File" → assignTransferRole(isSender: true) → ReceiverScreen?
                       (handshakes/a_b: senderId=b, receiverId=a) OVERWRITES!

Result:
├─ A's SenderScreen has handshakeDocId=a_b but senderId!=a on that doc
├─ B is now the sender, but A is in SenderScreen (expects to send)
├─ A's stream listener (WHERE senderId=a) no longer sees the doc
└─ CONFLICT: A thinks they're the sender but the document says otherwise
```

---

## 9. How Roles SHOULD Work

**Hook 1 Roles (Connection Layer):** IMMUTABLE
```
neutral_handshakes/a_b: {proposerId: a, partnerId: b}
                        ↑ Established once, never changes
```

**Hook 2 Roles (Transfer Layer):** DYNAMIC per-session
```
handshakes/{docId}: {senderId: ?, receiverId: ?}
                    ↑ Determined when user clicks "Send" or "Receive"
```

**The Conflict:** Hook 2 uses a DETERMINISTIC doc ID that CAN COLLIDE with the connection initiator's assumptions.

---

## 10. Recommended Fixes

### Fix 1: Validate Connection Status in assignTransferRole()

```dart
Future<String> assignTransferRole({
  required String partnerUid,
  required bool isSender,
}) async {
  // NEW: Verify connection exists
  final status = await getConnectionStatus(partnerUid);
  if (status != 'accepted') {
    throw Exception('Connection with @$partnerUid not established yet');
  }
  
  // ... rest of code
}
```

### Fix 2: Use Non-Deterministic Doc ID for Role Assignment

Instead of sorted UID scheme, use a unique transfer-session ID:

```dart
// Generate unique session ID (not based on UID pair)
final transferSessionId = FirebaseFirestore.instance.collection('dummy').doc().id;

// Write to: handshakes/{uniqueSessionId}
// Pass sessionId to both SenderScreen and ReceiverScreen
```

### Fix 3: Add Atomic Role Lock

Use a Firestore transaction to ensure only ONE role assignment succeeds per pair:

```dart
await _db.runTransaction((tx) async {
  final docRef = _db.collection('handshakes').doc(docId);
  final snap = await tx.get(docRef);
  
  if (snap.exists && snap.data()?['rolesAssignedAt'] != null) {
    throw Exception('Roles already assigned for this session');
  }
  
  tx.set(docRef, {
    'senderId': senderUid,
    'receiverId': receiverUid,
    'rolesAssignedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));
});
```

### Fix 4: Remove merge: true for Role Fields

```dart
// Instead of merge: true (allows overwrites)
await _db.collection('handshakes').doc(docId).set({
  'senderId': senderUid,
  'receiverId': receiverUid,
  'status': 'handshake_pending',
}, SetOptions(merge: true));  // ← Only merge NON-ROLE fields

// Or use atomic set (no merge)
await _db.collection('handshakes').doc(docId).set({
  'senderId': senderUid,
  'receiverId': receiverUid,
  'status': 'handshake_pending',
});  // ← No merge = atomic
```

---

## 11. Severity Assessment

| Conflict | Severity | User Impact | Likelihood |
|----------|----------|-------------|-----------|
| Document ID collision | 🔴 CRITICAL | Transfer roles swap mid-flow; encryption keys sent to wrong party | HIGH (any simultaneous clicks) |
| Stream query mismatch | 🔴 CRITICAL | SenderScreen loses visibility of its own transfer doc | HIGH (same race condition) |
| No connection validation | 🟠 HIGH | Users can initiate transfers with non-connected peers | MEDIUM (edge case) |
| Last-writer-wins overwrite | 🔴 CRITICAL | Role fields corrupted; causality chain broken | HIGH (race condition) |

---

## PLAIN ANSWER

**YES — These two hooks CONTRADICT and BREAK each other's logic.**

The **connection layer** (Hook 1) establishes proposer → partner directionality in one collection, but the **transfer layer** (Hook 2) uses a direction-neutral sorted UID scheme that allows ROLE REVERSAL without atomic protection.

**When roles reverse (proposer becomes receiver or vice versa), the deterministic document ID causes the handshakes document to be OVERWRITTEN, breaking the stream listeners and creating a race condition where the last user to assign roles wins, corrupting the state for the first user.**

This is especially dangerous because:
1. No validation that a connection exists before role assignment
2. No atomic guarantee that only one role assignment succeeds
3. Stream listeners become stale if roles are overwritten
4. `merge: true` allows partial field overwrites instead of atomic assignment

---
