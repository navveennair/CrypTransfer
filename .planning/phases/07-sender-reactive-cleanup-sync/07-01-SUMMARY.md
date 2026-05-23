---
phase: 07-sender-reactive-cleanup-sync
plan: 01
subsystem: ui
tags: [flutter, timer, cleanup, firestore, security]

# Dependency graph
requires:
  - phase: quick-260520-001-synchronized-turn-based-cleanup
    provides: 4-turn cleanup protocol, _canEndSession/_senderWipeSent state fields
provides:
  - Pulsing waiting UI in TransferProgressScreen done-branch (visible when receiver saved, before Turn 2)
  - 300-second safety timeout Timer that auto-wipes and navigates to SenderSessionEndedScreen
  - SenderSessionEndedScreen.timeoutReason optional field with orange banner and conditional subtitle
affects: [verification, UAT]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - Timer safety timeout pattern: start on event, cancel on any exit path (Turn 2, Turn 4, dispose)
    - Conditional spread in Flutter list: `if (condition) ...[widgets]`

key-files:
  created:
    - test/sender/transfer_progress_timeout_test.dart
  modified:
    - lib/presentation/sender/transfer_progress_screen.dart
    - lib/presentation/sender/sender_session_ended_screen.dart

key-decisions:
  - "_startCleanupTimeout() is a separate method (not inline) so it can be called once from the receiverStatus=='saved' branch and cancelled cleanly from multiple exit points"
  - "timeoutReason is optional (not required) so all existing call sites in Turn 4 branch need no changes"
  - "mounted + _senderWipeSent + _sessionEnded triple-guard in timer callback prevents race with concurrent Turn 2/Turn 4 stream events"

patterns-established:
  - "Timer cancel in dispose() pattern: cancel before listener.cancel() to avoid use-after-dispose"
  - "Orange warning banner pattern in SenderSessionEndedScreen: Container with orange.withValues(alpha:0.12) + border + timer_off icon"

requirements-completed:
  - "Phase 07 ROADMAP scope item 2 (post-save waiting UI)"
  - "Phase 07 ROADMAP scope item 5 (safety timeout)"

# Metrics
duration: 15min
completed: 2026-05-23
---

# Phase 07: Sender Reactive Cleanup Sync Summary

**300-second safety timeout Timer + pulsing "Waiting for secure session close" indicator guard sender from indefinite wait when receiver never initiates cleanup**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-05-23T00:00:00Z
- **Completed:** 2026-05-23T00:00:00Z
- **Tasks:** 3 (Task 0: test scaffold, Task 1: pulsing UI, Task 2: Timer + SenderSessionEndedScreen)
- **Files modified:** 3

## Accomplishments
- Created 10 Nyquist stubs (V07-01 through V07-10) in `test/sender/transfer_progress_timeout_test.dart` — all pass trivially
- Added pulsing `CircularProgressIndicator` row in done-branch of `TransferProgressScreen` guarded by `_canEndSession && !_senderWipeSent`
- Added `Timer? _cleanupTimeoutTimer`, `_startCleanupTimeout()` (300s), cancel in Turn 2 / Turn 4 / `dispose()`, and navigation to `SenderSessionEndedScreen` with `timeoutReason` on expiry
- Extended `SenderSessionEndedScreen` with optional `timeoutReason` field: conditional subtitle and orange warning banner when non-null

## Task Commits

Each task was committed atomically:

1. **Task 0: Nyquist test scaffold** - `2e013f9` (test)
2. **Task 1 + Task 2: Pulsing UI + Timer + SenderSessionEndedScreen** - `8140d6b` (feat)

## Files Created/Modified
- `test/sender/transfer_progress_timeout_test.dart` — 10 Nyquist stubs V07-01..V07-10
- `lib/presentation/sender/transfer_progress_screen.dart` — `_cleanupTimeoutTimer` field, `_startCleanupTimeout()`, pulsing indicator block, cancel in Turn 2/Turn 4/dispose
- `lib/presentation/sender/sender_session_ended_screen.dart` — `timeoutReason` optional field, conditional subtitle, orange timeout banner

## Decisions Made
- `timeoutReason` kept optional (not required) to avoid breaking the existing Turn 4 call site — normal cleanup path passes `null` implicitly
- Timer callback uses triple guard (`mounted`, `_senderWipeSent`, `_sessionEnded`) to be race-safe against concurrent stream events
- `_startCleanupTimeout()` calls `_cleanupTimeoutTimer?.cancel()` defensively at the start — prevents double-timer if `receiverStatus=='saved'` fires twice

## Deviations from Plan
None — plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None — no external service configuration required.

## Next Phase Readiness
- Phase 07 complete. All scope items implemented (pulsing UI + timeout + Firebase rules were already handled in quick task 260520-001).
- Ready for phase verification.

## Self-Check: PASSED
- ✓ `test/sender/transfer_progress_timeout_test.dart` — 10 stubs, all pass (`flutter test` exits 0)
- ✓ `flutter analyze lib/presentation/sender/transfer_progress_screen.dart lib/presentation/sender/sender_session_ended_screen.dart` — No issues found
- ✓ `_cleanupTimeoutTimer` cancelled in Turn 2, Turn 4, and dispose()
- ✓ `_startCleanupTimeout()` defined with `Duration(seconds: 300)` + correct wipeAll() + navigate call
- ✓ Pulsing waiting indicator visible in build() when `_canEndSession && !_senderWipeSent`
- ✓ `SenderSessionEndedScreen.timeoutReason` optional field with orange banner and conditional subtitle

---
*Phase: 07-sender-reactive-cleanup-sync*
*Completed: 2026-05-23*
