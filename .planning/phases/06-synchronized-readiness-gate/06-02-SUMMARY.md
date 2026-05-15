---
phase: 06-synchronized-readiness-gate
plan: 02
subsystem: presentation
tags: [flutter, receiver_screen, handshake, receiverReady, snackbar]

# Dependency graph
requires:
  - phase: 06-01
    provides: selectSenderHandshake() returns Future<String> doc ID; setReceiverReady(String docId) method on KeyRepository

provides:
  - _writeReceiverReady(String handshakeDocId) method in ReceiverScreen
  - _onSenderSelected updated to capture handshake doc ID and call _writeReceiverReady

affects:
  - 06-03 SenderScreen gate (receiverReady: true now written on sender selection, enabling sender stream gate to unlock)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Retryable SnackBar pattern: on failure surface SnackBarAction with recursive retry callback"
    - "Post-handshake readiness signal: capture doc ID from atomic batch, write readiness flag in separate step after session setup"

key-files:
  created: []
  modified:
    - lib/presentation/receiver/receiver_screen.dart

key-decisions:
  - "_writeReceiverReady placed after mounted setState block so session UI updates (handshakeDone=true) before the readiness write fires"
  - "Retry callback is recursive (_writeReceiverReady calls itself) — safe because each retry is a single Firestore update and SnackBar has 6s auto-dismiss (T-06-02-02 accepted)"
  - "Both tasks committed in single atomic commit — both modify only receiver_screen.dart and together deliver the complete plan objective"

requirements-completed: [SYNC-03]

# Metrics
duration: 5min
completed: 2026-05-15
---

# Phase 06 Plan 02: ReceiverScreen Readiness Trigger Summary

**_onSenderSelected updated to capture handshake doc ID from selectSenderHandshake() and call new _writeReceiverReady() helper which writes receiverReady: true with retryable SnackBar on failure**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-15T17:51:00Z
- **Completed:** 2026-05-15T17:56:00Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Updated `_onSenderSelected` try block: `selectSenderHandshake()` return value now captured as `handshakeDocId`; call to `_writeReceiverReady(handshakeDocId)` added after the `setState` block
- Added `_writeReceiverReady(String handshakeDocId)` private method immediately after `_showError()`: calls `_connService.setReceiverReady(handshakeDocId)`; on `FirebaseException` (or any error) shows floating SnackBar with text "Failed to signal readiness — tap to retry." and `SnackBarAction` label "Retry" with recursive retry callback
- `flutter analyze lib/presentation/receiver/receiver_screen.dart` passes with no issues

## Task Commits

Each task was committed atomically:

1. **Task 1 + Task 2 (combined): wire _writeReceiverReady into _onSenderSelected** - `ccf6123` (feat)

Both tasks committed together as a single atomic commit since they both modify only `receiver_screen.dart` and together constitute the plan's complete objective.

## Files Created/Modified

- `lib/presentation/receiver/receiver_screen.dart` — `_onSenderSelected` try block captures `handshakeDocId`; `_writeReceiverReady()` method added after `_showError()`

## Decisions Made

- Tasks 1 and 2 committed in a single atomic commit — both modify only `receiver_screen.dart` and together form the complete presentation-layer change
- `_writeReceiverReady` placed after the `mounted` setState block so the UI transitions to `handshakeDone=true` / `handshaking=false` before the readiness write fires; failure in the write does not roll back the UI state (by design — the handshake batch already succeeded)
- Retry callback is recursive: `onPressed: () => _writeReceiverReady(handshakeDocId)` — safe given 6s SnackBar duration and single-document Firestore update cost (T-06-02-02 accepted)

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

No new trust boundaries introduced beyond those documented in the plan's threat model.

| Flag | File | Description |
|------|------|-------------|
| threat_flag: write | lib/presentation/receiver/receiver_screen.dart | receiverReady: true write to handshakes doc after handshake batch — mitigated by Firestore rule (receiverId only) per T-06-02-01 |

---

## Self-Check: PASSED

- `lib/presentation/receiver/receiver_screen.dart` — FOUND (modified, 1047 lines)
- Commit `ccf6123` — FOUND in git log
- `grep handshakeDocId` — 5 occurrences (capture, pass, param, setReceiverReady arg, retry arg)
- `grep _writeReceiverReady` — 3 occurrences (definition, call in _onSenderSelected, retry onPressed)
- `flutter analyze` — No issues found

*Phase: 06-synchronized-readiness-gate*
*Completed: 2026-05-15*
