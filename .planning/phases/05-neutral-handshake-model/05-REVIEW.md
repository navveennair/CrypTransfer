---
phase: 05-neutral-handshake-model
reviewed: 2026-05-15T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - lib/presentation/home/home_screen.dart
  - lib/presentation/receiver/receiver_screen.dart
findings:
  critical: 0
  warning: 2
  info: 1
  total: 3
status: issues_found
---

# Phase 05: Code Review Report (Gap Closure — home + receiver fix pass)

**Reviewed:** 2026-05-15
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Targeted review of the two files modified in the Phase 05 gap-closure fix pass:
`home_screen.dart` (four stated bug fixes) and `receiver_screen.dart` (deferred-prefill
pattern). Most stated fixes are correctly implemented:

- **Async Accept with `finally`**: `_PendingRequestRowState` wraps the `await widget.onAccept()`
  call in `try`/`finally`, correctly resetting `_accepting = false` whether the call
  succeeds or throws (lines 1246-1254). PASS.
- **`hasError` branch in nested `StreamBuilder`**: `_ActiveConnectionsSection` checks
  `proposerSnap.hasError || partnerSnap.hasError || pendingSnap.hasError` before the
  loading/data branches (lines 933-945). PASS.
- **Stream deduplication**: `_incomingPendingStream` and `_outgoingPendingStream` are
  `late final` fields initialised once in `initState` and passed to both the listener
  subscriptions and the `StreamBuilder` widgets. Each `.listen()` / `StreamBuilder`
  creates its own independent Firestore subscription from the same stream object, which
  is the correct pattern for Firestore streams. PASS.
- **`InkWell` removal from pending rows**: `_ActiveConnectionRow.build()` only wraps the
  row in `InkWell` when `isConnected == true`; pending rows (`isConnected == false`) are
  returned as plain `GlassContainer` (lines 1088-1098). PASS.
- **Deferred prefill in `receiver_screen.dart`**: `_pendingPrefilledSender` is populated
  after `_checkKeyStatus()` completes (lines 73-87) and consumed with an explicit
  `_pendingPrefilledSender = null` before calling `_onSenderSelected` inside
  `_onToggleReady(true)` (lines 219-223). The null-clear prevents re-firing on a second
  toggle-on. PASS.

Two issues were found that were not addressed by the stated fixes.

---

## Warnings

### WR-01: `_PendingRequestsSection` silently swallows stream errors — `onShowError` never called

**File:** `lib/presentation/home/home_screen.dart:1119`

**Issue:** The `StreamBuilder` in `_PendingRequestsSection` checks only
`ConnectionState.waiting` and then falls through to `snapshot.data?.docs ?? []`. When
the Firestore stream emits an error, `snapshot.hasError == true` and `snapshot.data` is
`null`, so `docs` becomes `[]` and the widget silently returns `SizedBox.shrink()`. The
`onShowError` callback is declared in the constructor (line 1107) and passed in from
`_HomeScreenState.build()` (lines 453-456), but is never invoked inside `build()`.
The user sees the Pending Requests section disappear without any feedback — identical to
the "no pending requests" state. This is inconsistent with `_ActiveConnectionsSection`,
which has an explicit `hasError` branch rendering an error message (line 933).

**Fix:** Add a `hasError` guard immediately after the `waiting` check:

```dart
// _PendingRequestsSection.build() — inside StreamBuilder builder:
if (snapshot.connectionState == ConnectionState.waiting) {
  return const SizedBox.shrink();
}
if (snapshot.hasError) {
  onShowError('Could not load pending requests. Check your connection.');
  return const SizedBox.shrink();
}
final docs = snapshot.data?.docs ?? [];
```

---

### WR-02: `_rejecting` flag never reset on Firestore failure — Decline button permanently stuck

**File:** `lib/presentation/home/home_screen.dart:1222`

**Issue:** In `_PendingRequestRowState.build()`, tapping "Decline Request" sets
`_rejecting = true` (line 1226) and calls `widget.onReject(docId: widget.docId)` (line
1227). The callback resolves to `_HomeScreenState._rejectProposal`, which is a void,
fire-and-forget method — it returns nothing, and the call site does not `await` it. There
is no `finally` block to reset `_rejecting = false`.

On **success**, the Firestore document is deleted, the stream emits a removal event, and
the `StreamBuilder` removes the row from the widget tree — the stuck state is never
observed. On **failure**, the snackbar fires correctly (via `.catchError`) but `_rejecting`
stays `true` permanently: the row remains visible, the Decline spinner keeps spinning,
`isLoading` remains `true`, and both "Decline" and "Accept" buttons are disabled. The
user cannot retry without navigating away and back.

The Accept path (lines 1244-1254) correctly uses `async`/`await` with `try`/`finally`.
The Decline path should follow the same pattern.

**Fix:** Change `onReject` to `Future<void> Function` through the chain so the row can
`await` the operation and reset `_rejecting` in a `finally` block:

```dart
// 1. _PendingRequestRow and _PendingRequestsSection — change the field type:
final Future<void> Function({required String docId}) onReject;

// 2. _HomeScreenState._rejectProposal — make async, use try/catch + rethrow:
Future<void> _rejectProposal({required String docId}) async {
  try {
    await _handshakeRepo.rejectProposal(docId);
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Couldn't decline request. Try again."),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
    rethrow; // let the row's finally reset the flag
  }
}

// 3. _PendingRequestRowState — await with try/finally:
onPressed: isLoading
    ? null
    : () async {
        setState(() => _rejecting = true);
        try {
          await widget.onReject(docId: widget.docId);
        } finally {
          if (mounted) setState(() => _rejecting = false);
        }
      },
```

---

## Info

### IN-01: `_acceptProposal` rethrows after displaying snackbar — unused in current callers

**File:** `lib/presentation/home/home_screen.dart:336`

**Issue:** `_HomeScreenState._acceptProposal` shows a snackbar in its `catch` block and
then calls `rethrow`. The only caller is `_PendingRequestRowState`, which wraps the call
in `try`/`finally` — the `finally` only resets `_accepting = false` and does not re-catch
the rethrown exception. Dart will swallow the unhandled `Future` error at the boundary
without crashing. The `rethrow` adds no observable benefit at the current call site: the
`finally` runs regardless, and the snackbar has already fired. If `_acceptProposal` is
ever called from a second site without a surrounding `catch`, the rethrow could produce
a silent unhandled-future error.

**Fix:** Remove the `rethrow` for consistency with `_rejectProposal` (once WR-02 is
fixed, both methods will use the same try/catch + rethrow pattern and the suggestion
becomes moot). If keeping the current Accept pattern, document the intent:

```dart
// Option A: remove rethrow (snackbar is sufficient, finally handles state):
Future<void> _acceptProposal(
    {required String docId, required String proposerId}) async {
  try {
    await _handshakeRepo.acceptProposal(docId, proposerId);
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text("Couldn't accept request. Try again."),
      backgroundColor: Theme.of(context).colorScheme.error,
    ));
    // No rethrow — caller's finally resets _accepting regardless.
  }
}
```

---

_Reviewed: 2026-05-15_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
