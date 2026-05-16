---
phase: 06-synchronized-readiness-gate
reviewed: 2026-05-16T00:00:00Z
updated: 2026-05-16T00:10:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/data/repositories/key_repository.dart
  - lib/presentation/receiver/receiver_screen.dart
  - lib/presentation/sender/sender_screen.dart
findings:
  critical: 0
  warning: 1
  info: 1
  total: 2
status: issues_found
---

# Phase 6: Code Review Report

**Reviewed:** 2026-05-16
**Updated:** 2026-05-16 (plan 06-04 closed CR-01, WR-01, WR-03)
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found (1 warning, 1 info — 3 prior issues closed by plan 06-04)

## Summary

Phase 6 adds a synchronized readiness gate: the receiver signals `receiverReady: true`
on the handshake doc after completing `selectSenderHandshake`, and the sender's
Firestore stream reads that flag to unlock Steps 1–4. Three files were reviewed:
`key_repository.dart` (return-type change + `setReceiverReady`), `receiver_screen.dart`
(`_onSenderSelected` docId capture + `_writeReceiverReady`), and `sender_screen.dart`
(readiness timer, `_WaitingForReceiverWidget`, stream-driven gate).

**Plan 06-04 (commit bb37773) resolved three prior findings:** CR-01 (_streamSettled guard),
WR-01 ('receiverReady': false in keyPayload), and WR-03 (_revertToWaiting on revert).

One warning remains: use-after-dispose risk in the retry SnackBar closure (WR-02).
One info item covers the countdown display briefly reaching `00:00` before ejection (IN-01).

---

## ~~Critical Issues~~ — All Resolved

- ~~CR-01: Premature ejection on cold-start empty stream snapshot~~ — **Fixed in plan 06-04 (bb37773):** `_streamSettled` guard added
- ~~WR-01: Stale `receiverReady: true` bypasses gate for returning pairs~~ — **Fixed in plan 06-04 (bb37773):** `'receiverReady': false` added to `keyPayload`
- ~~WR-03: No recovery when `receiverReady` reverts to `false`~~ — **Fixed in plan 06-04 (bb37773):** `_revertToWaiting()` call + orange SnackBar

---

## Warnings

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
