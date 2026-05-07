---
phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast
reviewed: 2026-05-08T00:00:00Z
depth: standard
files_reviewed: 5
files_reviewed_list:
  - test/security/session_termination_test.dart
  - lib/presentation/receiver/receiver_end_session_screen.dart
  - lib/presentation/sender/sender_session_ended_screen.dart
  - lib/presentation/sender/transfer_progress_screen.dart
  - lib/presentation/receiver/decrypt_screen.dart
findings:
  critical: 0
  warning: 4
  info: 3
  total: 7
status: issues_found
---

# Phase 04: Code Review Report

**Reviewed:** 2026-05-08
**Depth:** standard
**Files Reviewed:** 5
**Status:** issues_found

## Summary

Five files implementing Phase 04 (receiver-as-master session termination) were reviewed: three presentation screens, one decryption screen, and the security test suite. The overall architecture is sound — the D-03 cleanup ordering (audit → storage → batch-delete → RSA wipe) is correctly implemented and the TC-TERM-005/006 Pitfall-1/2 guards are correctly modelled in tests. No critical security vulnerabilities were found.

Four warnings were identified:

1. A narrow unchecked null dereference in `_startTransferListener` when `_statusMessage` is used in the receiver-status badge — if the stream emits `decrypted` or `saved` but the UI branch renders before `_statusMessage` is set, the force-unwrap `_statusMessage!` on line 409 crashes.
2. `ReceiverEndSessionScreen._endSession()` silently swallows *all* errors on retry rather than only transient ones, hiding a class of permanent failures.
3. `SenderSessionEndedScreen._checkAndMarkDone()` performs a direct Firestore delete without error handling; a network error causes the spinner to never complete (UI stuck in "Verifying cleanup…").
4. Tests TC-TERM-001 through TC-TERM-008 are stubs that never call the real production methods — they test in-lined reimplementations of the logic, not the actual service layer, so a regression in `endSessionCleanup()` or `closeReceiverSession()` would not be caught.

Three info items are also noted.

---

## Warnings

### WR-01: Null-unsafe force-unwrap of `_statusMessage` in receiver status badge

**File:** `lib/presentation/sender/transfer_progress_screen.dart:409`

**Issue:** The receiver-status badge block only renders when `_receiverDecrypted || _canEndSession` is true (line 374). Both those flags are set via `setState` in the Firestore listener callback (lines 129–141), and `_statusMessage` is assigned in the same `setState` calls. However, the condition on line 374 checks the bool flags and the `Text` on line 409 force-unwraps `_statusMessage!`. If a future refactor sets `_receiverDecrypted = true` without also setting `_statusMessage` (or if the stream fires a second time after a reconnect resets `_statusMessage` to null while the bool stays true), the app will throw a `Null check operator used on a null value` at runtime.

**Fix:**
```dart
// Replace line 409 with a null-safe fallback:
_statusMessage ?? '',
// Or guard the entire badge block on _statusMessage != null instead of the bool flags:
if (_statusMessage != null)
  AnimatedSwitcher(
    ...
    child: Container(
      key: ValueKey(_statusMessage),
      ...
      child: Text(_statusMessage!, ...),
    ),
  ),
```

---

### WR-02: Blanket error swallow in `_endSession()` reset path hides permanent failures

**File:** `lib/presentation/receiver/receiver_end_session_screen.dart:207-213`

**Issue:** The `catch (e)` block on lines 207–213 catches every exception — including permanent ones such as a Firestore permission-denied, a null handshakeId that caused `endSessionCleanup()` to throw, or a missing RSA key — and sets `_phase = _Phase.ready`, which re-enables the "Retry End Session" button. For non-transient errors the user will be stuck in a retry loop that can never succeed. The error text is also stripped of its `Exception: ` prefix but otherwise shown verbatim, which may expose internal Firebase error codes to the UI.

More critically, if step 2 (`endSessionCleanup`) partially fails between the `tick()` and `done()` calls, the `_steps` list retains `active=true` on that step but `_phase` reverts to `ready` — the UI would show a spinner alongside the "Retry End Session" button on the next render cycle.

**Fix:**
```dart
} catch (e) {
  // Reset the active-step state so the UI is consistent on retry.
  for (final s in _steps) {
    s.active = false;
  }
  if (mounted) {
    setState(() {
      _phase = _Phase.ready;
      _error = e.toString().replaceFirst('Exception: ', '');
    });
  }
}
```

Add `for (final s in _steps) { s.active = false; }` before the `setState` so re-entering `_buildReady` does not show a stale active step indicator.

---

### WR-03: Missing error handling in `_checkAndMarkDone()` leaves UI stuck

**File:** `lib/presentation/sender/sender_session_ended_screen.dart:58-72`

**Issue:** `_checkAndMarkDone()` performs a Firestore get and conditional delete with no try/catch. If either call throws (network timeout, permission-denied, etc.) the exception propagates unhandled from `initState` through `_checkAndMarkDone()`, the `Future` is fire-and-forgotten (no `await` in `initState` for the returned future — the exception is silently dropped), and `_aesCleanDone` is never set to `true`. The UI shows an indefinite "Verifying cleanup…" spinner with no way for the user to proceed.

**Fix:**
```dart
Future<void> _checkAndMarkDone() async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection(FirebaseConstants.transfers)
        .doc(widget.transferId)
        .get();
    if (doc.exists) {
      await FirebaseFirestore.instance
          .collection(FirebaseConstants.transfers)
          .doc(widget.transferId)
          .delete();
    }
  } catch (_) {
    // Non-critical safety net; receiver already performed cleanup.
    // Proceed to mark done regardless.
  }
  if (mounted) setState(() => _aesCleanDone = true);
}
```

---

### WR-04: Test stubs validate reimplemented logic, not the real service layer

**File:** `test/security/session_termination_test.dart:16-296`

**Issue:** All five tests (TC-TERM-001, TC-TERM-002, TC-TERM-003, TC-TERM-004, TC-TERM-008) are explicitly marked as stubs and exercise inline code that reimplements the same logic as `endSessionCleanup()`, `deleteStorageFile()`, and `closeReceiverSession()` rather than calling those methods. As a result:

- A regression introduced into `KeyRepository.endSessionCleanup()` (e.g. the `selectedSenderUid` batch.update being accidentally removed) would not be caught by TC-TERM-003.
- TC-TERM-004 verifies a Firestore update and a `FakeSecureStorage.delete()` call that are coded directly in the test, not delegated to `EncryptionService.closeReceiverSession()`.
- TC-TERM-002 tests the guard pattern with a locally thrown exception, not `TransferRepository.deleteStorageFile()`.

The stubs correctly document intent and are safe to ship as scaffolding for Wave 1, but the test suite will not catch production regressions until Wave 1 wires up real service calls.

**Fix:** When Wave 1 is implemented, replace each stub body with a call to the real production method through injected fakes:

```dart
// TC-TERM-003 example after Wave 1:
final keyRepo = KeyRepository(db: fakeFirestore);
await keyRepo.endSessionCleanup(
  transferId: transferId,
  handshakeId: handshakeId,
  receiverId: receiverId,
);
final transferAfter = await fakeFirestore.collection('transfers').doc(transferId).get();
expect(transferAfter.exists, false, reason: '...');
```

---

## Info

### IN-01: `_DoneStepRow` is duplicated verbatim in two files

**File:** `lib/presentation/sender/sender_session_ended_screen.dart:240-262`

**Issue:** Line 238 has a comment: `// Copied verbatim from end_session_screen.dart lines 679–703.` The `_DoneStepRow` widget is identical across both files. This is a maintenance risk — a visual change (e.g. icon size, padding) must be applied in both places.

**Fix:** Extract `_DoneStepRow` into `lib/presentation/widgets/shared_widgets.dart` (already the home of `CrypButton` and other shared components) and import it from both screens.

---

### IN-02: `transferredAt` passed as `DateTime.now()` instead of server timestamp

**File:** `lib/presentation/receiver/decrypt_screen.dart:226`

**Issue:** `ReceiverEndSessionScreen` receives `transferredAt` as a `DateTime` argument. The caller passes `DateTime.now()` (line 226 of `decrypt_screen.dart`) at navigation time, which is the time the Save button was tapped, not the canonical server-side transfer creation time. For audit display purposes this is acceptable (it is labelled "Transfer Summary"), but the value differs from the Firestore `createdAt` server timestamp that was recorded earlier in `_startUpload`. If the value is ever compared against the audit log's `timestamp` field, there will be a small discrepancy.

**Fix (optional):** Pass `_transfer.createdAt` from `TransferModel` if a precise creation time is available, or document the intentional choice of "time saved" as distinct from "time created."

---

### IN-03: `print()` calls in test file with `// ignore: avoid_print` annotations

**File:** `test/security/session_termination_test.dart:73, 116, 155, 204, 247, 294`

**Issue:** Six `print()` calls are used to surface pass messages. These are suppressed with `// ignore: avoid_print`. In a CI environment the output is typically captured; however, structured test output via `expect()` reason strings (already present) is sufficient, and the prints add noise.

**Fix:** Remove the `print()` calls and the corresponding `// ignore` annotations. The `reason:` strings on each `expect()` already provide the pass/fail context.

---

_Reviewed: 2026-05-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
