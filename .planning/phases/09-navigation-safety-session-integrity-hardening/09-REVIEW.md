---
phase: 09-navigation-safety-session-integrity-hardening
reviewed: 2026-05-29T00:00:00Z
depth: standard
files_reviewed: 4
files_reviewed_list:
  - lib/presentation/receiver/receiver_screen.dart
  - lib/presentation/sender/sender_screen.dart
  - test/security/navigation_guard_test.dart
  - test/sender/stale_key_test.dart
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 9: Code Review Report

**Reviewed:** 2026-05-29
**Depth:** standard
**Files Reviewed:** 4
**Status:** issues_found

## Summary

Phase 9 implements navigation safety (PopScope guards on ReceiverScreen) and session integrity hardening (stale-key invalidation on SenderScreen). The architecture is sound and the primary security invariants are correctly implemented. No critical issues were found. Four warnings are raised — one involves a real data-loss window (wipeSession fires but the `navigator.pop()` that follows it uses a stale context captured before the async gap), one is a logic gap in the mid-flight guard, and two are edge-case correctness bugs. Three info items cover test coverage gaps and a UX inconsistency.

---

## Warnings

### WR-01: `navigator.pop()` executes after `wipeSession` — context captured before async gap but pop can still fail silently if widget is gone

**File:** `lib/presentation/receiver/receiver_screen.dart:657-661`

**Issue:**
```dart
final navigator = Navigator.of(context);  // captured before gap ✓
_showCloseSessionDialog().then((confirmed) {
  if (confirmed && mounted) {
    _sessionManager.wipeSession(onBuffersWipe: wipeAll);
    navigator.pop();   // ← pop AFTER wipeSession
  }
});
```
`wipeSession` transitions `SessionState.terminated`, which fires `stateStream`, which triggers `EncryptionService.closeReceiverSession` reactively. That async chain starts running immediately after `_set(terminated)`. By the time `navigator.pop()` is called synchronously after `wipeSession`, the widget tree is still intact, so the pop succeeds. However, `mounted` is checked once at the start of the `.then` callback but `wipeSession` itself may cause a downstream rebuild that disposes the state before `navigator.pop()` runs. In practice, with the captured `navigator` reference, the pop will still work on the `NavigatorState` object, but `wipeSession` and `navigator.pop()` are executed in the opposite order from the expected sequence: the session is terminated before the route is removed, leaving a brief window where `ReceiverScreen` is still on the stack but in `SessionState.terminated`. If the user triggers the back gesture again during this window (unlikely but possible), `_onSessionStateChanged` fires `setState` on a widget that is being popped.

**Fix:** Reverse the order — pop the route first, then wipe:
```dart
_showCloseSessionDialog().then((confirmed) {
  if (confirmed && mounted) {
    navigator.pop();  // remove route first
    _sessionManager.wipeSession(onBuffersWipe: wipeAll);  // then terminate
  }
});
```
This matches the `didPop == true` branch in `SenderScreen.onPopInvokedWithResult` (line 658) which calls `_wipeSensitiveData()` only after the pop has already happened.

---

### WR-02: `canPop` allows a free back-navigation when `_handshakeDocId` is non-null but `_isReadyToReceive` is false — roles are cleared in a fire-and-forget call

**File:** `lib/presentation/receiver/receiver_screen.dart:645, 667-669`

**Issue:**
```dart
canPop: _isReadyToReceive ? false : (_handshakeDocId == null),
```
When `_isReadyToReceive == false` and `_handshakeDocId != null`, `canPop` evaluates to `false`, which correctly routes through `onPopInvokedWithResult`. But when `_isReadyToReceive == false` and `_handshakeDocId == null` (the common initial state before any session), `canPop == true`, so `didPop == true` and the `else` branch at line 666 never runs (the guard `if (_handshakeDocId != null)` is always false).

The real issue is the `didPop == true` path at line 666:
```dart
} else {
  if (_handshakeDocId != null) {
    _connService.clearTransferRoles(handshakeDocId: _handshakeDocId!);
  }
}
```
`clearTransferRoles` is called fire-and-forget (a `Future<void>` is discarded with no `await`, no error handler). If Firestore is offline or the call throws, roles are never cleared and the peer is permanently stuck at the role-picker. The bug is not new to Phase 9, but the new PopScope handling makes it the only code path responsible for cleanup on a clean close.

**Fix:** Wrap the fire-and-forget call in an error-tolerant pattern:
```dart
} else {
  if (_handshakeDocId != null) {
    _connService
        .clearTransferRoles(handshakeDocId: _handshakeDocId!)
        .catchError((_) {}); // best-effort; peer will time out if offline
  }
}
```

---

### WR-03: Mid-flight guard in `_onHandshakeUpdate` is placed AFTER `setState` — stale-key wipe still fires on first stream event during encryption

**File:** `lib/presentation/sender/sender_screen.dart:207-229`

**Issue:**
```dart
// D-05: capture old key BEFORE setState
final previousPublicKey = _selectedReceiverPublicKeyJson;
setState(() {
  _receiverId = receiverId;
  _receiverUsername = receiverUsername;
  _selectedReceiverPublicKeyJson = publicKey;  // state updated
});
_streamSettled = true;
_checkTofuStatus(receiverId, publicKey);

// D-06: mid-flight guard — skip stale check if encryption is in flight
if (_encrypting || _encryptingKey) return;  // ← guard is here, AFTER setState

// D-05: stale AES key invalidation
if (previousPublicKey != null &&
    publicKey != previousPublicKey &&
    _encryptedAESKey != null) {
  _wipeSensitiveData();  // ← correctly skipped by mid-flight guard
  ...
}
```
The mid-flight guard correctly prevents `_wipeSensitiveData()` from running. However, `_checkTofuStatus` is also called before the guard. `_checkTofuStatus` is async and will call `_showKeyChangedDialog` if the key changed, which calls `_revertToWaiting()`. If `_encrypting == true` when the key changes, the mid-flight guard skips the stale-key block, but `_showKeyChangedDialog` can still fire (via `_checkTofuStatus`), which calls `_revertToWaiting()` and wipes the in-progress encryption. The guard comment says it protects stale-key invalidation, but `_checkTofuStatus` is not covered by it.

**Fix:** Move `_checkTofuStatus` to after the mid-flight guard, or skip it when in-flight:
```dart
if (_encrypting || _encryptingKey) return;  // guard moved up

_checkTofuStatus(receiverId, publicKey);

if (previousPublicKey != null && ...) {
  _wipeSensitiveData();
  ...
}
```
Alternatively, add a flight check inside `_checkTofuStatus` itself before showing the dialog.

---

### WR-04: `_revertToWaiting` calls `_startReadinessTimer()` unconditionally — can start a new timer immediately after the receiver disconnects even when no receiver is selected

**File:** `lib/presentation/sender/sender_screen.dart:277`

**Issue:**
```dart
void _revertToWaiting() {
  _readinessTimer?.cancel();
  _readinessTimer = null;
  _wipeSensitiveData();
  if (mounted) {
    setState(() {
      _receiverId = widget.preFilledPartnerUid;
      ...
      _receiverReady = false;
      ...
    });
    _startReadinessTimer();  // ← always starts timer
  }
}
```
`_startReadinessTimer` is called unconditionally. When `widget.preFilledPartnerUid == null` (no pre-filled partner, user arrived without a target), `_receiverId` is set to `null` inside `setState` but `_startReadinessTimer` still starts the 60-second countdown. At the end of the countdown, `_ejectToHomeScreen` fires even though the sender was never in a session with a specific receiver — the screen had simply not been given a partner yet. This is a logic error: a sender who is idle (no receiver selected, no handshake ever established) should not be ejected.

**Fix:** Gate the timer restart on whether a receiver was actually selected:
```dart
if (widget.preFilledPartnerUid != null) {
  _startReadinessTimer();
}
```

---

## Info

### IN-01: `GAP1-02` test does not actually exercise any real code path — the test is a no-op

**File:** `test/security/navigation_guard_test.dart:39-64`

**Issue:**
```dart
test('GAP1-02: Session-locked state prevents pop with SnackBar, no wipeSession', () {
  final manager = SessionManager();
  expect(manager.state, SessionState.open, ...);
  bool wipeCallbackFired = false;
  // "Simulate the _sessionLocked=true path"
  expect(manager.state, isNot(SessionState.terminated), ...);
  expect(wipeCallbackFired, false, ...);
  manager.dispose();
});
```
The test creates a fresh `SessionManager`, immediately asserts it is `open` (trivially true), and then asserts `wipeCallbackFired == false` (also trivially true because `wipeCallbackFired` is never set to `true` in the test body). The test passes because it makes no actual call that could fail. It does not simulate the widget code path it is supposed to guard (the `_sessionLocked == true` branch in `onPopInvokedWithResult`). This gives false confidence that GAP1-02 is covered.

**Fix:** At minimum, add a note that this test requires a widget test to properly verify. For a unit test, invoke `wipeSession` conditionally on the session-locked flag and verify it is not called:
```dart
bool sessionLocked = true;
bool wipeCallbackFired = false;

// Simulate: locked branch does NOT call wipeSession
if (!sessionLocked) {
  manager.wipeSession(onBuffersWipe: () => wipeCallbackFired = true);
}

expect(wipeCallbackFired, false, ...);
```

---

### IN-02: `GAP2-01` and `GAP3-02` tests use plain `Object?` for `encryptedAESKey` — the type does not exercise actual `Uint8List` zero-fill

**File:** `test/sender/stale_key_test.dart:20, 97`

**Issue:**
```dart
Object? encryptedAESKey = Uint8List(32); // non-null → encrypted
```
`encryptedAESKey` is typed as `Object?` rather than `Uint8List?`, which matches the production `_encryptedAESKey` field's type. While this does not break the test logic (null-check still works), the tests cannot exercise the fill-zero behavior of `_wipeSensitiveData()` because `Object?` does not expose `fillRange`. The test comment says "After wipe: encryptedAESKey must be null" but never zeroes the bytes — only nulls the pointer. A reader following the test as a specification of `_wipeSensitiveData` would not know that bytes must be zeroed before nulling.

**Fix:** Use `Uint8List?` to match the production type and demonstrate zero-fill:
```dart
Uint8List? encryptedAESKey = Uint8List(32);
// ...
if (shouldWipe) {
  encryptedAESKey?.fillRange(0, encryptedAESKey.length, 0);
  encryptedAESKey = null;
}
```

---

### IN-03: Settings button in ReceiverScreen AppBar is silently disabled when mailbox is open — no tooltip or visual cue for the user

**File:** `lib/presentation/receiver/receiver_screen.dart:678-680`

**Issue:**
```dart
IconButton(
  icon: const Icon(Icons.settings_suggest_rounded),
  onPressed: _isReadyToReceive ? null : _openKeyManager,
),
```
Passing `onPressed: null` to `IconButton` disables it with a grey tint in Material 3, but there is no `tooltip` explaining why it is disabled. A user who tries to tap the settings icon while the mailbox is open receives no feedback. The disable logic is correct for security (preventing key regeneration mid-session), but the UX gap may confuse users.

**Fix:** Add a tooltip that explains the disabled state:
```dart
Tooltip(
  message: _isReadyToReceive
      ? 'Close mailbox before managing keys'
      : 'RSA Key Manager',
  child: IconButton(
    icon: const Icon(Icons.settings_suggest_rounded),
    onPressed: _isReadyToReceive ? null : _openKeyManager,
  ),
),
```

---

_Reviewed: 2026-05-29_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
