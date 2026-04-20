---
phase: 02-receivertransferscreen-hardening-memory-safety
reviewed: 2026-04-20T12:00:00Z
depth: standard
files_reviewed: 6
files_reviewed_list:
  - lib/presentation/receiver/receiver_transfer_screen.dart
  - lib/presentation/receiver/receiver_screen.dart
  - lib/presentation/sender/sender_screen.dart
  - lib/core/utils/session_manager.dart
  - lib/core/utils/security_lifecycle_mixin.dart
  - lib/data/services/transfer_service.dart
findings:
  critical: 0
  warning: 1
  info: 3
  total: 4
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-04-20T12:00:00Z
**Depth:** standard
**Files Reviewed:** 6
**Status:** issues_found

## Summary

This review covers the post-fix state of the Phase 02 hardening work. All three previously identified critical/warning issues have been resolved:

- **CR-01 resolved:** `ReceiverTransferScreen` now receives `SessionManager` as a constructor arg, applies `SecurityLifecycleMixin`, and listens on `stateNotifier` to pop immediately when `SessionState.terminated` fires, showing a SnackBar before `popUntil`.
- **CR-02 resolved:** `FilePicker.pickFiles` now uses `withData: kIsWeb`, and `_pickFile` includes a null-path guard for cloud-URI picks on Android.
- **WR-01 resolved:** The `isFlagSecureActive()` check is now performed before any sensitive buffer allocation in `_encryptFile`.

One new warning and three info items were identified in the hardened codebase. None block security correctness — the kill-switch chain is intact, buffer registry is operative, and the null-path guard is properly placed.

---

## Warnings

### WR-01: `_wipeSensitiveData()` Does Not Null Out `_encryptedAESKey` — `_readyToSend` Returns True After Wipe

**File:** `lib/presentation/sender/sender_screen.dart:310-318`
**Issue:** `_wipeSensitiveData()` manually zeroes and nulls `_aesKey`, `_iv`, and `_encryptedBytes`, then calls `wipeAll()`. The `wipeAll()` call correctly zeroes the `_encryptedAESKey` buffer via the registry (registered at line 233), but the field `_encryptedAESKey` is never set to `null` inside `_wipeSensitiveData()`. After the method returns, `_readyToSend` (`_encryptedAESKey != null`) still evaluates to `true` because the field holds a reference to the now-zeroed buffer. In `_send()`, `_wipeSensitiveData()` is called before `Navigator.push`, so the screen is pushed away before a rebuild can show the stale "Send" button — but if `_wipeSensitiveData()` is called via other paths (e.g., direct `_revertToWaiting` skips and the receiver disconnects while `_readyToSend` is true), there is a one-frame window where the button appears enabled after the key material is gone. `_revertToWaiting` does null it in its own `setState`, but the inconsistency between `_wipeSensitiveData` and the three other fields it nulls out is a latent correctness hazard.

**Fix:**
```dart
void _wipeSensitiveData() {
  _aesKey?.fillRange(0, _aesKey!.length, 0);
  _iv?.fillRange(0, _iv!.length, 0);
  _encryptedBytes?.fillRange(0, _encryptedBytes!.length, 0);
  _aesKey = null;
  _iv = null;
  _encryptedBytes = null;
  // wipeAll() zeroes _encryptedAESKey via registry, but null the field too
  // so _readyToSend returns false immediately without waiting for a rebuild.
  _encryptedAESKey = null;
  wipeAll();
}
```

---

## Info

### IN-01: `lock()` + `setDecrypting()` in `_handleIncomingTransfer` — `lock()` Is a No-Op

**File:** `lib/presentation/receiver/receiver_screen.dart:382-383`
**Issue:** `_sessionManager.lock()` transitions `SessionState` to `locked`, then `_sessionManager.setDecrypting()` immediately transitions it to `decrypting`. The `locked` state fires the `stateNotifier` listener and emits on `stateStream` — both of which trigger `_onSessionStateChanged`. `_onSessionStateChanged` checks for `decrypting` (not `locked`), so the first transition is visually consumed by a `setState({})` rebuild showing amber/lock CrypButton state for one frame before the second transition fires. The `lock()` call was meaningful when there was a user-facing dwell in the `locked` state; now that navigation is automatic, `lock()` is vestigial and could be removed to avoid a redundant listener notification.

**Fix:**
```dart
// lib/presentation/receiver/receiver_screen.dart
// Remove the lock() call — setDecrypting() is sufficient for automatic navigation.
if (mounted) {
  setState(() {
    _incomingTransferId = transferId;
    _incomingFileName = fileName;
    _sessionLocked = true;
  });
  // _sessionManager.lock(); // <-- remove; state goes open → decrypting directly
  _sessionManager.setDecrypting();
}
```

---

### IN-02: `PopScope.onPopInvokedWithResult` in `ReceiverTransferScreen` Calls `wipeAll()` Redundantly

**File:** `lib/presentation/receiver/receiver_transfer_screen.dart:181-183`
**Issue:** The callback at line 182 calls `wipeAll()` explicitly when the route is popped. `dispose()` — which is always called when a route is removed from the stack — calls `super.dispose()` at line 99, which invokes `SecurityLifecycleMixin.dispose()` → `wipeAll()`. Since `wipeAll()` clears `_radioactiveBuffers` on the first call, the second call is a harmless no-op (as documented). This screen stores no `Uint8List` buffers, so neither call zeroes anything meaningful. The comment "SecurityLifecycleMixin already applied (CR-01)" is correct but the explicit `wipeAll()` in the callback is noise.

**Fix:** No immediate action required — `wipeAll()` is idempotent and the redundancy is harmless. If buffers are ever registered on this screen in future, the early call in `onPopInvokedWithResult` would be useful. Leave as-is or remove as desired.

---

### IN-03: `_encryptFile` Catch Block Does Not Eagerly Zero Partially-Allocated Buffers

**File:** `lib/presentation/sender/sender_screen.dart:199-203`
**Issue:** If `TransferService.resolve()` or `compute()` throws, `key` and `iv` (registered at lines 175-176) and possibly `plaintext` (registered at line 182) remain in the `_radioactiveBuffers` registry without being zeroed until `wipeAll()` is called on the next deliberate wipe or `dispose()`. The registry is the intended safety net here and it will zero them eventually. However, on an exception the buffers live in memory longer than necessary. The pattern on the happy path is to zero `plaintext` eagerly after `compute()` — the same eagerness could be applied in the error path.

**Fix:**
```dart
} catch (e) {
  // Eagerly zero any partially-allocated buffers rather than waiting for
  // the registry to clean them on dispose.
  wipeAll();
  if (mounted) {
    setState(() => _encrypting = false);
    _showError('Encryption failed: $e');
  }
}
```
Note: `wipeAll()` also clears `_aesKey`, `_iv`, and `_encryptedBytes` from the registry if they were registered. `_file` is not a `Uint8List` so it is unaffected.

---

_Reviewed: 2026-04-20T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
