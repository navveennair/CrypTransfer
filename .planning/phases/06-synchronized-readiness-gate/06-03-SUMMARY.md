---
phase: 06-synchronized-readiness-gate
plan: 03
subsystem: sender-ui
tags: [flutter, sender_screen, readiness-gate, timer, animated-opacity, ignore-pointer]

# Dependency graph
requires:
  - phase: 06-synchronized-readiness-gate
    plan: 01
    provides: receiverReady field initialized false on handshake doc creation; setReceiverReady() writes true
  - phase: 06-synchronized-readiness-gate
    plan: 02
    provides: ReceiverScreen calls setReceiverReady() after session setup; receiverReady: true written to Firestore

provides:
  - SenderScreen blocks file selection/encryption/sending until receiverReady==true from Firestore
  - 60-second countdown widget shown while waiting; ejects to HomeScreen on timeout or doc deletion
  - Green SnackBar confirmation when receiverReady flips true

affects:
  - lib/presentation/sender/sender_screen.dart

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Outer AnimatedOpacity+IgnorePointer gate: wraps a group of steps so they fade and become non-interactive as a unit"
    - "Three-state child switch: null-connection / waiting-for-readiness / ready distinguishes three display states in one conditional expression"
    - "Timer.periodic countdown: 60-second safety timer ejects sender to HomeScreen; cancelled when receiver becomes ready"

key-files:
  created: []
  modified:
    - lib/presentation/sender/sender_screen.dart

key-decisions:
  - "Single atomic commit for both tasks — both tasks modify only sender_screen.dart and together form the complete gate implementation"
  - "Outer AnimatedOpacity wraps all four steps as a unit so they fade in simultaneously when receiverReady becomes true, rather than each step fading independently"
  - "IgnorePointer placed inside AnimatedOpacity (not outside) so the fade animation completes before interaction is enabled — avoids tap-through during animation"
  - "ejectToHomeScreen() guard: isEmpty branch ejects only when !_receiverReady; if _receiverReady==true the existing wasConnected/SnackBar flow still runs (correct for deliberate disconnect after session is established)"

# Metrics
duration: 6min
completed: 2026-05-15
---

# Phase 06 Plan 03: SenderScreen Readiness Gate Summary

**Sender-side receiverReady gate: pulsing hourglass countdown widget + AnimatedOpacity/IgnorePointer Steps 1-4 wrapper + _ejectToHomeScreen safety timer eliminates race condition where sender acts before receiver's RSA key is published**

## Performance

- **Duration:** ~6 min
- **Started:** 2026-05-15T17:55:21Z
- **Completed:** 2026-05-15T18:01:38Z
- **Tasks:** 2 (committed as 1 atomic commit)
- **Files modified:** 1

## Accomplishments

- Added `_receiverReady`, `_readinessTimer`, `_secondsRemaining` state fields to `_SenderScreenState`
- Added `_readinessTimer?.cancel()` in `dispose()` to prevent timer callbacks after widget destruction
- Added eject guard in `_onHandshakeUpdate` isEmpty branch: when `!_receiverReady` and the handshake doc disappears, calls `_ejectToHomeScreen()` and returns early (skips the `_revertToWaiting` path which is only reachable when the session was already fully established)
- Added `doc['receiverReady']` parsing in the else branch of `_onHandshakeUpdate`: starts the 60-second timer on first connection, calls `_onReceiverBecameReady()` when the field flips true
- Added `_receiverReady = false` and `_secondsRemaining = 60` resets inside `_revertToWaiting()` setState block; added timer cancellation before `_wipeSensitiveData()`
- Added `_startReadinessTimer()`: creates `Timer.periodic(1s)` decrementing `_secondsRemaining`; fires `_ejectToHomeScreen()` at zero
- Added `_onReceiverBecameReady()`: cancels timer, sets `_receiverReady = true`, shows green floating SnackBar "Secure channel established. Receiver is ready."
- Added `_ejectToHomeScreen()`: calls `_wipeSensitiveData()`, shows error floating SnackBar "Session Terminated — receiver closed the session.", navigates via `Navigator.pushAndRemoveUntil` to `HomeScreen()`
- Updated Step 0 `done:` from `_receiverSelected` to `_receiverSelected && _receiverReady` — step indicator stays blue (incomplete) until both conditions are true
- Updated Step 0 `child:` to three-state switch: no receiver → `_WaitingForConnectionWidget`; receiver selected but not ready → `_WaitingForReceiverWidget(secondsRemaining: _secondsRemaining)`; receiver ready → `_ConnectedBadge(username: ...)`
- Wrapped Steps 1-4 in outer `AnimatedOpacity(opacity: _receiverReady ? 1.0 : 0.0)` + `IgnorePointer(ignoring: !_receiverReady)` — all four steps fade out and become non-interactive as a unit until receiver is ready
- Added `_WaitingForReceiverWidget` stateful class: `SingleTickerProviderStateMixin` + `ScaleTransition` + `FadeTransition` pulsing hourglass icon; `GlassContainer` countdown display formatted as MM:SS

## Task Commits

Both tasks committed together as a single atomic commit (both modify only `sender_screen.dart` and constitute the complete plan objective):

1. **Tasks 1+2: Complete receiver readiness gate implementation** - `70011af` (feat)

## Files Created/Modified

- `lib/presentation/sender/sender_screen.dart` — Added readiness gate state, timer methods, UI widget, Steps 1-4 outer wrapper; updated Step 0 done/child; added HomeScreen import

## Decisions Made

- Tasks 1 and 2 committed together in a single atomic commit — they both modify only `sender_screen.dart` and together form the complete readiness gate
- Outer `AnimatedOpacity` + `IgnorePointer` chosen over per-step gating to fade all steps as a unit (better UX: they all appear together when the receiver is ready rather than cascading)
- `IgnorePointer` nested inside `AnimatedOpacity` (not wrapping it) so the widget tree is stable during the fade animation
- eject guard in isEmpty branch uses early `return` so the existing `wasConnected`/SnackBar flow is preserved for the deliberate-disconnect case (when receiver closes session after transfer is already established, `_receiverReady` would be true and eject is skipped)

## Deviations from Plan

### Execution Environment Issue

**[Rule 3 - Blocking] Accidental commit to main branch during Task 1**
- **Found during:** Task 1 commit
- **Issue:** The initial `cd /c/Users/navve/projects/cryptransfer && git add ... && git commit` command routed to the main repo checkout rather than the worktree. Task 1 changes were committed as `cd7fbac` on `main` instead of the worktree branch.
- **Fix:** Copied the fully-edited `sender_screen.dart` (with all Task 1+2 changes applied via Edit tool to the correct absolute path) to the worktree directory, then staged and committed from the worktree CWD. All changes are correctly captured in worktree commit `70011af`. The `cd7fbac` commit on `main` is a duplicate that the orchestrator should clean up on merge.
- **Files modified:** `lib/presentation/sender/sender_screen.dart`
- **Commit:** `70011af` (worktree branch)

## Known Stubs

None — all features are fully wired. `_receiverReady` is driven by live Firestore stream data from the handshake doc; `_secondsRemaining` is driven by the live timer.

## Self-Check: PASSED

- FOUND: `lib/presentation/sender/sender_screen.dart` (1116 lines with all changes)
- FOUND: `.planning/phases/06-synchronized-readiness-gate/06-03-SUMMARY.md`
- FOUND: commit `70011af` on worktree branch `worktree-agent-a928d5b3aa14f6489`
