---
phase: 07-sender-reactive-cleanup-sync
reviewed: 2026-05-23T17:13:56Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/presentation/sender/transfer_progress_screen.dart
  - lib/presentation/sender/sender_session_ended_screen.dart
  - test/sender/transfer_progress_timeout_test.dart
findings:
  critical: 0
  warning: 5
  info: 3
  total: 8
status: issues_found
---

# Phase 07: Code Review Report

**Reviewed:** 2026-05-23T17:13:56Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Phase 07 added a 300-second safety timeout (`_cleanupTimeoutTimer`) and a pulsing waiting indicator to `TransferProgressScreen`, plus an optional `timeoutReason` banner in `SenderSessionEndedScreen`. The core flow is structurally sound and the timer lifecycle (cancel on Turn 2, Turn 4, and `dispose()`) is correct. However, five issues require attention before shipping:

- The timer can be re-armed on repeated Firestore stream emissions (resets the 300s window each time).
- The AES key erasure on Firestore uses an empty string instead of `FieldValue.delete()`, leaving a residual field.
- A silent `catch (_) {}` around the Firestore key-erasure write means failures are invisible and unretriable — the key survives in Firestore if the write fails.
- `SenderSessionEndedScreen._checkAndMarkDone()` has no error handling, leaving the UI in a permanent "Verifying cleanup…" spinner on network failure.
- The receiver-cleanup checklist is unconditionally shown as fully complete on the timeout path, which is factually wrong.

All 10 tests in the test file are empty stubs that pass trivially and provide zero coverage.

---

## Warnings

### WR-01: Timer re-armed on every repeated `receiverStatus == 'saved'` snapshot

**File:** `lib/presentation/sender/transfer_progress_screen.dart:167-173`

**Issue:** `_startCleanupTimeout()` is called inside the stream listener whenever `receiverStatus == 'saved'`. Although `_startCleanupTimeout()` cancels any running timer before creating a new one (line 191), Firestore snapshot listeners can re-emit the same document state on reconnect, connection resume, or listener re-attach. Each re-emission with `receiverStatus == 'saved'` resets the 300-second clock to zero. A session that experiences repeated reconnections could have its timeout extended indefinitely — the "5-minute safety net" never fires.

**Fix:** Add a `_timeoutStarted` boolean guard so the timer is armed exactly once:

```dart
bool _timeoutStarted = false; // add to state fields

// inside the receiverStatus == 'saved' branch:
if (receiverStatus == 'saved' && mounted) {
  setState(() {
    _statusMessage = '✅ Receiver saved the file securely';
    _canEndSession = true;
  });
  if (!_timeoutStarted) {           // guard: arm once only
    _timeoutStarted = true;
    _startCleanupTimeout();
  }
}
```

---

### WR-02: AES key field set to `''` instead of `FieldValue.delete()` on Turn 2

**File:** `lib/presentation/sender/transfer_progress_screen.dart:142`

**Issue:** The Turn 2 Firestore update writes `'encryptedAESKey': ''`. Setting the field to an empty string leaves a residual Firestore field rather than removing it. Any downstream code that checks `data['encryptedAESKey'] != null` will see a non-null, non-absent field, which may be misinterpreted as a zero-length key rather than a deletion. Using `FieldValue.delete()` is the semantically correct operation and matches what `closeReceiverSession()` does for other key material.

**Fix:**
```dart
await FirebaseFirestore.instance
    .collection('transfers')
    .doc(widget.transferId)
    .update({
  'encryptedAESKey': FieldValue.delete(), // ← was: ''
  'senderCleanedUp': true,
  'senderCleanedUpAt': FieldValue.serverTimestamp(),
});
```

---

### WR-03: Silent `catch (_) {}` makes AES key erasure failure invisible and unretriable

**File:** `lib/presentation/sender/transfer_progress_screen.dart:134-155`

**Issue:** `_senderWipeSent` is set to `true` at line 136 before the `await` Firestore update. The `catch (_) {}` at line 146 silently swallows all Firestore errors. If the write fails (network error, Firestore rules, quota), `wipeAll()` still runs and zeroes local RAM — which is correct — but `_senderWipeSent` is already `true` so no retry is ever attempted. The AES key field (`encryptedAESKey`) survives in Firestore with its original ciphertext value, violating the Turn 2 zero-remanence contract. There is no user-visible indication that the remote erasure failed.

**Fix:** Log the error (without key material) or surface it. At minimum, do not swallow it silently when it has a security consequence:

```dart
try {
  await FirebaseFirestore.instance
      .collection('transfers')
      .doc(widget.transferId)
      .update({
    'encryptedAESKey': FieldValue.delete(),
    'senderCleanedUp': true,
    'senderCleanedUpAt': FieldValue.serverTimestamp(),
  });
} catch (e) {
  // Remote key erasure failed — local wipe still runs below.
  // Log to audit trail so the gap is visible in security review.
  debugPrint('[Security] Turn 2 Firestore key erasure failed: $e');
  // Consider writing a security event to transfers_log here.
}
```

---

### WR-04: `_checkAndMarkDone()` has no error handling — UI stuck in permanent spinner on network failure

**File:** `lib/presentation/sender/sender_session_ended_screen.dart:60-74`

**Issue:** `_checkAndMarkDone()` is called as a fire-and-forget future at line 57 (`_checkAndMarkDone()` — no `await`, no `.catchError`). If either the Firestore `get()` (line 64) or `delete()` (line 70) throws, the exception is unhandled and `_aesCleanDone` remains `false`. The "Your device cleaned up" section then shows "Verifying cleanup…" with a spinner indefinitely. The user sees a stuck UI with no explanation.

**Fix:** Wrap with try/catch and ensure `_aesCleanDone` is set to `true` regardless of success so the UI does not hang:

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
    // D-10 edge-case cleanup failed — doc may already be gone or
    // network is unavailable. AES key was already zeroed upstream.
  } finally {
    if (mounted) setState(() => _aesCleanDone = true);
  }
}
```

---

### WR-05: Receiver cleanup checklist shown as fully complete on the timeout path

**File:** `lib/presentation/sender/sender_session_ended_screen.dart:161-197`

**Issue:** When `timeoutReason != null`, the receiver did NOT complete cleanup — the safety timeout fired because `cleanup_initiated` never arrived (receiver crash, network failure, or app kill). Despite this, the screen unconditionally renders all four "Receiver cleaned up" checkmarks as done (audit log, file deleted, transfer record deleted, RSA key wiped). This misrepresents the security state. On the timeout path, the receiver may still hold plaintext in memory and the encrypted file may still be in Firebase Storage.

**Fix:** Conditionally replace the receiver-cleanup section on the timeout path with a warning card:

```dart
// ── Section 1: Receiver cleaned up ────────────────────────────
if (widget.timeoutReason != null) ...[
  Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.orange.shade300),
    ),
    child: const Text(
      'Receiver cleanup status is unknown — the session ended by timeout before cleanup completed.',
      style: TextStyle(fontSize: 13),
    ),
  ),
] else ...[
  // existing four _DoneStepRow widgets
],
```

---

## Info

### IN-01: `_DoneStepRow` is duplicated from `end_session_screen.dart`

**File:** `lib/presentation/sender/sender_session_ended_screen.dart:266`

**Issue:** The comment at line 266 explicitly acknowledges this: "Copied verbatim from end_session_screen.dart lines 679–703." This is intentional duplication. Consider extracting `_DoneStepRow` (or a public `DoneStepRow`) to `shared_widgets.dart` to eliminate drift if the style changes.

**Fix:** Move to `lib/presentation/widgets/shared_widgets.dart` as a non-private widget and import from both screens.

---

### IN-02: All 10 test stubs are empty — they pass trivially and provide zero coverage

**File:** `test/sender/transfer_progress_timeout_test.dart:9-57`

**Issue:** Every test body is a comment block with a `// TODO`. Empty test bodies contain no assertions, so `flutter test` reports 10 passes with no actual validation. This creates a false sense of coverage. The test file header labels them "Nyquist stubs" — they should either be implemented or marked `skip` with a reason so the test runner surfaces them clearly as pending rather than silently passing.

**Fix:** Mark stubs as skipped until implemented:

```dart
test('V07-01: CircularProgressIndicator visible when _canEndSession=true and _senderWipeSent=false', () {
  // TODO: implement
}, skip: 'V07 stub — not yet implemented');
```

---

### IN-03: `encryptedBytes` buffer registered but never unregistered after upload completes

**File:** `lib/presentation/sender/transfer_progress_screen.dart:74`

**Issue:** `widget.encryptedBytes` is registered via `registerBuffer()` at line 74 and is passed to `ref.putData()` at line 225. After the upload completes (line 237), the bytes are no longer needed but remain registered and in memory until `wipeAll()` is called (on Turn 2 or Turn 4). In a long-running wait between upload completion and receiver cleanup, these encrypted bytes occupy memory unnecessarily. This is not a correctness bug but an opportunity for early wipe.

**Fix:** After the upload task resolves successfully, explicitly wipe and unregister `encryptedBytes`:

```dart
final snapshot = await uploadTask;
// Eagerly wipe ciphertext — no longer needed after upload completes.
widget.encryptedBytes.fillRange(0, widget.encryptedBytes.length, 0);
unregisterBuffer(widget.encryptedBytes);

final downloadUrl = await snapshot.ref.getDownloadURL();
// ... rest of upload logic
```

---

_Reviewed: 2026-05-23T17:13:56Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
