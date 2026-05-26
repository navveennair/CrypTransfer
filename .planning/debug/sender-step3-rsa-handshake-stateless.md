---
status: fixed
trigger: "Sender Step 3 'Encrypt Key for @' button is stateless when receiver completes all steps. RSA Key Handshake should trigger immediately but doesn't."
created: 2026-05-26T13:35:00Z
updated: 2026-05-27T13:45:00Z
fix_commit: 4d91de6
symptoms:
  expected: "RSA Key Handshake should be triggered immediately when receiver completes all steps"
  actual: "'Encrypt Key for @' button exists but is stateless (not responding/not functional)"
  reproducible: "Yes, consistently"
  questions:
    - "What allows Stepper 3 in Sender to function?"
    - "What database operation should invoke 'Encrypt Key for @'?"
    - "Why isn't receiver completing steps triggering the RSA Key Handshake?"
---

# Debug Session: Sender Step 3 RSA Handshake Flow

## Root Cause Found: State Transition Logic Bug

### Summary

The "Encrypt Key for @" button on SenderScreen Step 3 is rendered but blocked from interaction by `IgnorePointer(ignoring: !_receiverReady)`. The state variable `_receiverReady` is never transitioned from `false` → `true` because the condition that triggers the transition is never satisfied.

### The Button Blocking Chain

```
UI Rendering
├── Steps 1-4 wrapped in IgnorePointer(ignoring: !_receiverReady)
├── When _receiverReady == false: pointer events blocked
└── Button visually appears but tap events don't reach handler
```

File: `lib/presentation/sender/sender_screen.dart`
- Lines 770-775: Gated wrapper around Steps 1-4
- Line 244-245: Transition condition

### Root Cause: Missing Condition in State Transition

**The problem:** The condition on line 244 has a logic flaw when the receiver's mailbox is already open:

```dart
if (!_receiverReady && receiverReady) {
  _onReceiverBecameReady();
}
```

**Scenario: Receiver opens mailbox BEFORE selecting sender**
1. Receiver opens mailbox (calls `setReadyToReceive(true)`)
2. Receiver selects sender
3. `selectSenderHandshake()` reads `isReadyToReceive = true` from Firestore (line 461 in key_repository.dart)
4. **Creates handshake doc with `receiverReady: true` from the start** (line 486)
5. Sender's stream fires with this doc
6. Sender processes: `!_receiverReady` (true, since `_receiverReady = false`) && `receiverReady` (true)
7. **Condition SHOULD fire** → `_onReceiverBecameReady()` should be called

**What's actually happening:**
The condition IS logically correct, BUT the real issue is that this transition detection assumes the Firestore doc state changes from `false` → `true`. However, there are TWO writes:

1. **First write** (atomic batch in `selectSenderHandshake`, line 489-499):
   ```dart
   'receiverReady': isReadyToReceive,  // This is TRUE if mailbox already open
   ```

2. **Second write** (separate call in receiver_screen.dart, line 393-400):
   ```dart
   await _connService.setReceiverReady(docId);  // Updates to TRUE
   ```

When receiver's mailbox is already open:
- First write creates doc with `receiverReady: true`
- Sender stream fires immediately with `receiverReady: true`
- Sender's condition evaluates: `!false && true = true` ✓
- Should call `_onReceiverBecameReady()` and set `_receiverReady = true`
- Steps 1-4 become visible and interactive

### Why the Button Still Doesn't Work: The Real Issue

**The condition CAN fire, but `_onReceiverBecameReady()` may not be called because:**

Looking at the condition check flow (lines 238-256):

```dart
final receiverReady = doc['receiverReady'] as bool? ?? false;  // Line 238

if (_receiverSelected && !_receiverReady && _readinessTimer == null) {
  _startReadinessTimer();  // Line 240-242: Start 60-second timer
}

if (!_receiverReady && receiverReady) {
  _onReceiverBecameReady();  // Line 244-245: THIS SHOULD FIRE
} else if (_receiverReady != receiverReady) {
  _revertToWaiting();  // Line 246-256: Alternative path
}
```

**Key insight:** The first condition (line 240) starts a timer when:
- `_receiverSelected` (yes, receiver selected sender)
- `!_receiverReady` (yes, not ready yet)
- `_readinessTimer == null` (yes, no timer yet)

This timer runs a 60-second countdown. If `receiverReady` arrives BEFORE 60 seconds, the condition at line 244 should fire.

### The Actual Root Cause: Race Condition in `_onSenderSelected()`

Looking at `receiver_screen.dart` lines 356-414, the receiver flow is:

1. `_onSenderSelected()` is called
2. Calls `selectSenderHandshake()` (async, atomic batch write)
3. **Then immediately** calls `setReceiverReady(docId)` (async, separate write)

Both are async/await, so:
```dart
final docId = await _connService.selectSenderHandshake(...);  // Write 1 complete
// ... role validation ...
await _connService.setReceiverReady(docId);  // Write 2 happens AFTER Write 1
```

**The sender's listener sees:**
1. First snapshot: handshake doc with `receiverReady: isReadyToReceive` (either true or false depending on mailbox state)
2. Second snapshot: **If the second write happens**, the doc is updated to `receiverReady: true`

**But the transition condition `!_receiverReady && receiverReady` only fires if:**
- `_receiverReady` is currently false
- AND `receiverReady` is currently true
- This is a **one-time transition check**

If the first snapshot already has `receiverReady: true`, the condition fires ✓
If the first snapshot has `receiverReady: false`, the timer starts, and then the second snapshot (with `true`) should fire the condition ✓

### Why It's Actually Broken: The Missing Idempotency

**The real bug:** The second `setReceiverReady()` call (line 393-400 in receiver_screen.dart) is **redundant and creates a timing issue**.

When receiver's mailbox is already open:
- `selectSenderHandshake()` writes `receiverReady: true`
- `setReceiverReady()` updates it to `true` again (redundant)
- Sender sees two identical snapshots
- On the **second** snapshot, `_receiverReady` is already `true` (set by first snapshot)
- Condition `if (!true && true)` = `if (false && true)` = **FALSE** ❌
- `_onReceiverBecameReady()` never called a second time

**If receiver's mailbox is NOT open when selecting sender:**
- `selectSenderHandshake()` writes `receiverReady: false`
- Timer starts
- `setReceiverReady()` updates to `true`
- Sender sees transition from `false` → `true`
- Condition fires ✓

## Fix Strategy

### Option A: Remove Redundant `setReceiverReady()` Call (Recommended)

**Why:** Simplify the flow and eliminate the race condition.

**Changes:**
1. In `key_repository.dart`, line 486, change:
   ```dart
   'receiverReady': isReadyToReceive,
   ```
   to:
   ```dart
   'receiverReady': true,  // Receiver completing all steps = ready to receive
   ```

2. In `receiver_screen.dart`, lines 392-400, remove the `setReceiverReady()` call (it becomes redundant)

**Result:** Handshake doc is created with `receiverReady: true` from the start when receiver completes all steps, ensuring sender's transition condition fires exactly once.

### Option B: Handle Idempotent Updates (Fallback)

**Why:** If you want to keep the two-phase write pattern.

**Changes:**
1. In sender_screen.dart, line 244, replace:
   ```dart
   if (!_receiverReady && receiverReady) {
     _onReceiverBecameReady();
   }
   ```
   with:
   ```dart
   if (!_receiverReady && receiverReady) {
     _onReceiverBecameReady();
   } else if (!_receiverReady && receiverReady) {
     // Already ready — update state even if transition already happened
     _onReceiverBecameReady();
   }
   ```
   
   Actually, simpler fix:
   ```dart
   if (receiverReady && !_receiverReady) {
     _onReceiverBecameReady();
   }
   ```
   (Same logic, clearer intent: "if receiver is ready and we haven't marked ourselves as knowing that yet")

## Recommended Implementation

**File: `lib/data/repositories/key_repository.dart`**

Change line 486 from:
```dart
'receiverReady': isReadyToReceive,
```

To:
```dart
'receiverReady': true,  // Receiver has completed all steps; handshake signals readiness immediately
```

Then remove the redundant `setReceiverReady(docId)` call from `receiver_screen.dart` lines 392-400.

This ensures:
1. Handshake doc is created with the correct `receiverReady: true` state
2. Sender's stream fires once with the correct state
3. Condition `!_receiverReady && receiverReady` evaluates to TRUE
4. `_onReceiverBecameReady()` is called
5. `_receiverReady` is set to true via setState
6. Steps 1-4 become visible and interactive
7. Button responds to taps

