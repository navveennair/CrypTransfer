---
phase: 06-synchronized-readiness-gate
test: WR-03
status: diagnosed
---

# Root Cause: _revertToWaiting() resets countdown but never restarts the timer

`_revertToWaiting()` at `sender_screen.dart:194` cancels `_readinessTimer`, sets
`_readinessTimer = null`, and resets `_secondsRemaining = 60` via setState. But it
never calls `_startReadinessTimer()`. The widget rebuilds showing 01:00 frozen because
no `Timer.periodic` is running to decrement it.

The timer-start check at line 169 only fires inside `_onHandshakeUpdate`'s non-empty
branch, which requires a new Firestore event. When the receiver deletes the handshake
doc, the stream goes isEmpty — no new non-empty event arrives, so the timer never starts.

## Fix

Add `_startReadinessTimer()` after the setState block in `_revertToWaiting()`:

```dart
void _revertToWaiting() {
  _readinessTimer?.cancel();
  _readinessTimer = null;
  _wipeSensitiveData();
  if (mounted) {
    setState(() {
      ...
      _secondsRemaining = 60;
      _streamSettled = false;
    });
    _startReadinessTimer();  // ← add this
  }
}
```

## Files

- `lib/presentation/sender/sender_screen.dart:194-214` — _revertToWaiting body
- `lib/presentation/sender/sender_screen.dart:432` — _startReadinessTimer definition
