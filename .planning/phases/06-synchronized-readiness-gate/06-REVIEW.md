---
phase: 06-synchronized-readiness-gate
reviewed: 2026-05-16T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/data/repositories/key_repository.dart
  - lib/presentation/receiver/receiver_screen.dart
  - lib/presentation/sender/sender_screen.dart
findings:
  critical: 1
  warning: 3
  info: 1
  total: 5
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-05-16
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 6 adds a synchronized readiness gate: the receiver signals `receiverReady: true`
on the handshake doc after completing `selectSenderHandshake`, and the sender's
Firestore stream reads that flag to unlock Steps 1–4. Three files were reviewed:
`key_repository.dart` (return-type change + `setReceiverReady`), `receiver_screen.dart`
(`_onSenderSelected` docId capture + `_writeReceiverReady`), and `sender_screen.dart`
(readiness timer, `_WaitingForReceiverWidget`, stream-driven gate).

The return-type change on `selectSenderHandshake` is sound and both code paths
(`existing` vs. `newRef`) correctly populate `docId`. Timer teardown in `dispose`
and `_revertToWaiting` is complete. The animation widget lifecycle is correct.

One critical race condition exists in the pre-filled sender flow. Three warnings cover:
a stale `receiverReady` flag that can bypass the gate for returning pairs, a
use-after-dispose risk in the retry SnackBar closure, and an unhandled state when
`receiverReady` reverts to `false` after being `true`. One info item covers the
countdown display briefly reaching `00:00` before ejection.

---

## Critical Issues

### CR-01: Premature ejection on first empty stream event (pre-filled sender flow)

**File:** `lib/presentation/sender/sender_screen.dart:120-127`
**Issue:** `_startHandshakeListener()` is called in `initState` (line 87) before any
handshake doc exists in Firestore. When `preFilledPartnerUid` is set (Active Connection
role picker), the sender enters `SenderScreen` before the receiver has called
`selectSenderHandshake`. Firestore streams always emit an initial snapshot. If that
first snapshot is empty and `_receiverReady` is `false` (which it always is at this
point), `_ejectToHomeScreen()` fires immediately — sending the user back to
`HomeScreen` before the receiver has had any chance to open their mailbox.

The condition `if (!_receiverReady)` was intended to guard against a mid-session
disconnect, but it triggers identically on the cold-start empty snapshot.

```dart
// sender_screen.dart lines 120-127 (current — bug)
if (snap.docs.isEmpty) {
  if (!_receiverReady) {          // true on cold start → eject fires spuriously
    _readinessTimer?.cancel();
    _readinessTimer = null;
    _ejectToHomeScreen();
    return;
  }
  // ...
}
```

**Fix:** Introduce an initialization-settled flag that is set to `true` after the
first stream event (or after a short debounce). Only eject when already settled AND
not yet ready. Alternatively, only start the ejection logic after `_receiverSelected`
is confirmed AND the readiness timer has already started (meaning the stream fired
at least one non-empty snapshot previously).

```dart
// Add field:
bool _streamSettled = false;

// In _onHandshakeUpdate, at the top of the empty-docs branch:
if (snap.docs.isEmpty) {
  if (!_streamSettled) {
    _streamSettled = true; // first event was empty — receiver not connected yet; stay
    return;
  }
  if (!_receiverReady) {
    _readinessTimer?.cancel();
    _readinessTimer = null;
    _ejectToHomeScreen();
    return;
  }
  // ... existing revert logic
}

// In the non-empty branch, set settled after first good event:
_streamSettled = true;
```

---

## Warnings

### WR-01: Stale `receiverReady: true` bypasses readiness gate for returning pairs

**File:** `lib/data/repositories/key_repository.dart:490-492`
**Issue:** When an existing handshake doc is found, the batch `update` at line 492
does not reset `receiverReady` to `false`. A prior session that completed
successfully will have left `receiverReady: true` on the doc. On the next session,
the sender's `_onHandshakeUpdate` receives the initial Firestore snapshot with
`receiverReady: true` and immediately calls `_onReceiverBecameReady()` (line 165,
`sender_screen.dart`), unlocking Steps 1–4 before `setReceiverReady()` has been
called in the new session. The readiness gate is bypassed entirely for any
sender/receiver pair that has previously completed a transfer.

```dart
// key_repository.dart lines 490-492 (current — missing reset)
if (existing.docs.isNotEmpty) {
  docId = existing.docs.first.id;
  batch.update(existing.docs.first.reference, keyPayload);  // receiverReady not reset
}
```

**Fix:** Add `'receiverReady': false` to `keyPayload` so both code paths reset the flag:

```dart
final keyPayload = <String, dynamic>{
  'publicKey': publicKey,
  'sentAt': FieldValue.serverTimestamp(),
  'fromUsername': fromUsername,
  'receiverUsername': fromUsername,
  'status': 'handshake_complete',
  'receiverReady': false,   // reset on every new session
};
```

---

### WR-02: Use-after-dispose in `_writeReceiverReady` retry SnackBar closure

**File:** `lib/presentation/receiver/receiver_screen.dart:418-421`
**Issue:** The SnackBar action's `onPressed` closure captures `handshakeDocId` and
calls `_writeReceiverReady(handshakeDocId)` recursively. The outer call is guarded
by `if (!mounted) return` at line 410. However the retry closure runs after the
SnackBar is dismissed — which may be seconds later, after `ReceiverScreen` has been
disposed. At that point `_writeReceiverReady` is called on a dead state object.
Inside the recursive call, `Theme.of(context)` and
`ScaffoldMessenger.of(context).showSnackBar(...)` are executed without a `mounted`
check (the check at line 410 only guards the first invocation path at call time, not
the closure captured by `onPressed`).

```dart
// receiver_screen.dart lines 418-421 (current — no mounted guard in closure)
action: SnackBarAction(
  label: 'Retry',
  onPressed: () => _writeReceiverReady(handshakeDocId),
),
```

**Fix:** Wrap the closure body in a `mounted` guard:

```dart
action: SnackBarAction(
  label: 'Retry',
  onPressed: () {
    if (!mounted) return;
    _writeReceiverReady(handshakeDocId);
  },
),
```

---

### WR-03: No recovery path when `receiverReady` reverts to `false` after being `true`

**File:** `lib/presentation/sender/sender_screen.dart:166-169`
**Issue:** The `else if (_receiverReady != receiverReady)` branch at line 167 handles
the case where `_receiverReady` is `true` and the incoming `receiverReady` is `false`
(e.g. due to the stale-doc bug described in WR-01, or an unexpected Firestore write).
It sets `_receiverReady = false` via `setState`, which hides Steps 1–4 behind the
`AnimatedOpacity`/`IgnorePointer` gate. However it does not restart the readiness
timer or call `_ejectToHomeScreen`. The sender is left with Step 0 showing
`_WaitingForReceiverWidget` with the countdown at whatever `_secondsRemaining` was —
frozen, because `_readinessTimer` was cancelled in `_onReceiverBecameReady` and is
not restarted here. The UI is effectively stuck.

```dart
// sender_screen.dart lines 165-169 (current — no timer restart)
if (!_receiverReady && receiverReady) {
  _onReceiverBecameReady();
} else if (_receiverReady != receiverReady) {
  setState(() => _receiverReady = receiverReady);  // timer not restarted
}
```

**Fix:** When reverting to `false`, restart the timer so the ejection path eventually
fires, or call `_revertToWaiting()` which already handles the full state reset:

```dart
} else if (_receiverReady != receiverReady) {
  // receiverReady flipped back to false after being true — treat as session collapse
  _revertToWaiting();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Receiver readiness lost — session reset.'),
      backgroundColor: Colors.orange,
    ),
  );
}
```

---

## Info

### IN-01: Countdown display shows `00:00` for one frame before ejection

**File:** `lib/presentation/sender/sender_screen.dart:413-420`
**Issue:** `_secondsRemaining` is decremented before the `<= 0` check. At 60 ticks
(starting from 60, decrementing before check), the final value is 0, which triggers
ejection. Before ejection the parent calls `setState(() => _secondsRemaining--)`,
which rebuilds `_WaitingForReceiverWidget` showing `00:00` for one frame. This is
cosmetically minor but visible.

```dart
_readinessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
  if (!mounted) return;
  setState(() => _secondsRemaining--);  // decrements to 0 before check
  if (_secondsRemaining <= 0) {         // 00:00 already shown
    _readinessTimer?.cancel();
    _readinessTimer = null;
    _ejectToHomeScreen();
  }
});
```

**Fix:** Check before decrement, or start at 61 and display after decrement, or clamp
the display value to a minimum of 1 in `_WaitingForReceiverWidget.build`:

```dart
// In _WaitingForReceiverWidget.build:
final display = widget.secondsRemaining > 0
    ? '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}'
    : 'Ending…';
```

---

_Reviewed: 2026-05-16_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
