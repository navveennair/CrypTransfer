---
phase: 06-synchronized-readiness-gate
plan: 04
subsystem: sender-ui
tags: [flutter, sender_screen, key_repository, readiness-gate, stream-settled, gap-closure]

# Dependency graph
requires:
  - phase: 06-synchronized-readiness-gate
    plan: 03
    provides: _onHandshakeUpdate with isEmpty eject path and receiverReady parsing
  - phase: 06-synchronized-readiness-gate
    plan: 01
    provides: selectSenderHandshake keyPayload and batch.update/batch.set branching

provides:
  - _streamSettled guard absorbs Firestore cold-start empty snapshot (CR-01 closed)
  - keyPayload includes 'receiverReady': false so both batch.update and batch.set paths reset the gate on every new session (WR-01 closed)
  - WR-03 frozen-revert branch replaced with _revertToWaiting() call + orange SnackBar (WR-03 closed)

affects:
  - lib/presentation/sender/sender_screen.dart
  - lib/data/repositories/key_repository.dart

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "_streamSettled guard: bool field that absorbs the Firestore stream's synchronous cold-start empty snapshot so the eject path only fires after at least one non-empty doc has been seen"
    - "keyPayload reset pattern: include 'receiverReady': false in the shared payload map so both update and set paths reset the field atomically"

key-files:
  created: []
  modified:
    - lib/presentation/sender/sender_screen.dart
    - lib/data/repositories/key_repository.dart

key-decisions:
  - "_streamSettled = true set in BOTH branches: isEmpty guard (marks settled after first empty) and non-empty else branch (marks settled after real doc). Either path settles the stream."
  - "_streamSettled = false in _revertToWaiting() so reconnections after a receiver disconnect go through the full settle cycle again (prevents stale true blocking next cold-start guard)"
  - "WR-03 fix uses _revertToWaiting() rather than bare setState to restart the 60s timer and re-activate the eject path — bare setState would freeze the countdown at its last value"
  - "batch.set new-doc branch keeps its existing 'receiverReady': false override — now redundant but retained for intent clarity"

requirements-completed: [SYNC-05, SYNC-06]

# Metrics
duration: 8min
completed: 2026-05-16
---

# Phase 06 Plan 04: Gap Closure Summary

**_streamSettled guard (CR-01) + keyPayload reset (WR-01) + _revertToWaiting on false-revert (WR-03) make the synchronized readiness gate reliable across all entry paths and sessions**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-16T00:00:00Z
- **Completed:** 2026-05-16T00:08:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `bool _streamSettled = false` field to `_SenderScreenState` (CR-01 guard)
- Inserted `if (!_streamSettled) { _streamSettled = true; return; }` at top of isEmpty branch — first empty Firestore snapshot is silently absorbed without triggering `_ejectToHomeScreen()`
- Set `_streamSettled = true` after `setState` in the non-empty else branch — marks the stream as settled once a real doc is seen
- Reset `_streamSettled = false` inside `_revertToWaiting()` setState block — allows reconnections after receiver disconnect to re-run the settle cycle
- Replaced `else if (_receiverReady != receiverReady) { setState(() => _receiverReady = receiverReady); }` with `_revertToWaiting()` call + orange SnackBar (WR-03 fix) — revert now restarts the 60s countdown and re-activates the eject path
- Added `'receiverReady': false` to `keyPayload` in `selectSenderHandshake()` — ensures both `batch.update` (existing doc) and `batch.set` (new doc) paths reset the field on every new session (WR-01 fix)

## Task Commits

1. **Task 1: Add _streamSettled guard (CR-01) and fix frozen-revert branch (WR-03) in SenderScreen** + **Task 2: Add 'receiverReady': false to keyPayload (WR-01)** - `bb37773` (fix)

## Files Created/Modified

- `lib/presentation/sender/sender_screen.dart` — _streamSettled field, isEmpty guard, non-empty settler, _revertToWaiting reset, WR-03 else-if replacement
- `lib/data/repositories/key_repository.dart` — 'receiverReady': false added to keyPayload

## Decisions Made

- Both tasks committed in a single atomic commit — both files together constitute the complete gap-closure unit; splitting would leave CR-01/WR-03 fixed but WR-01 open (or vice versa)
- `_streamSettled = true` in isEmpty guard as well as non-empty branch — ensures the guard never fires twice even if Firestore emits two empty snapshots before the real doc arrives

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None.

## Next Phase Readiness

- All three gap-closure defects closed; phase 06 is ready for re-verification
- Human smoke tests (CR-01 cold-start, WR-01 returning-pair bypass) can now be run per VERIFICATION.md

## Self-Check: PASSED

- FOUND: `lib/presentation/sender/sender_screen.dart` — `_streamSettled` appears 5 times (field, isEmpty guard entry, isEmpty guard setter, non-empty setter, _revertToWaiting reset)
- FOUND: `lib/data/repositories/key_repository.dart` — `'receiverReady': false` appears 2 times (keyPayload + batch.set branch)
- FOUND: commit `bb37773` on main
- VERIFIED: `flutter analyze` — No issues found

---
*Phase: 06-synchronized-readiness-gate*
*Completed: 2026-05-16*
