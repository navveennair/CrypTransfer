---
phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast
plan: "03"
subsystem: ui
tags: [flutter, firestore, session-termination, zero-remanence, security, sender]

requires:
  - phase: 04-02
    provides: ReceiverEndSessionScreen which deletes the transfer doc (triggering the Firestore stream this plan reacts to)

provides:
  - SenderSessionEndedScreen — static read-only screen with two cleanup attribution sections and D-10 edge-case Firestore safety check
  - TransferProgressScreen reactive !snapshot.exists listener — wipes AES key and navigates to SenderSessionEndedScreen when transfer doc disappears
  - Removed manual End Session button from TransferProgressScreen (sender side fully reactive)

affects:
  - 04-04 (final wave — any remaining wiring or cleanup referencing TransferProgressScreen or the sender flow)

tech-stack:
  added: []
  patterns:
    - "Reactive Firestore deletion detection: _startTransferListener checks !snapshot.exists with _done + _sessionEnded double-fire guard before wipeAll() + pushReplacement"
    - "D-10 edge-case safety net: SenderSessionEndedScreen._checkAndMarkDone() deletes stale transfer doc in initState if receiver cleanup was interrupted"

key-files:
  created:
    - lib/presentation/sender/sender_session_ended_screen.dart
  modified:
    - lib/presentation/sender/transfer_progress_screen.dart

key-decisions:
  - "aesKey is NOT a constructor arg on SenderSessionEndedScreen — zeroed by wipeAll() in TransferProgressScreen before navigation (D-07)"
  - "_completedAt field removed from TransferProgressScreen — was only used by the removed End Session CrypButton; kept would cause unused_field analyzer warning"
  - "_sessionEnded guard prevents double-navigation on Firestore stream reconnect after pushReplacement fires"
  - "D-10 check runs in initState before screen is interactive — edge case where receiver cleanup interrupted before WriteBatch committed"

patterns-established:
  - "wipeAll() called BEFORE Navigator.pushReplacement to SenderSessionEndedScreen — T-04-03-01 mitigation"
  - "if (!_done || _sessionEnded) return — upload-complete guard before reacting to !snapshot.exists (Pitfall 1 from RESEARCH.md)"

requirements-completed: [TERM-05, TERM-08]

duration: 18min
completed: "2026-05-08"
---

# Phase 04 Plan 03: Sender Session End Screen + Reactive Listener Summary

**SenderSessionEndedScreen with D-10 Firestore safety check + TransferProgressScreen fully reactive to receiver-driven cleanup (End Session button removed)**

## Performance

- **Duration:** ~18 min
- **Started:** 2026-05-08T00:00:00Z
- **Completed:** 2026-05-08T00:18:00Z
- **Tasks:** 2
- **Files modified:** 2 (1 created, 1 modified)

## Accomplishments

- Created `SenderSessionEndedScreen` with two attribution sections ("Receiver cleaned up" + "Your device cleaned up"), D-10 edge-case Firestore check in `initState`, `SecurityLifecycleMixin` applied, `PopScope(canPop: false)`, and "Back to Home" stack-clearing navigation
- Extended `_startTransferListener` in `TransferProgressScreen` to detect `!snapshot.exists` and react with `wipeAll()` + `pushReplacement` to `SenderSessionEndedScreen` — sender side is now fully reactive, no manual user action required
- Removed the manual "End Session" `CrypButton` from `TransferProgressScreen` and replaced `end_session_screen.dart` import with `sender_session_ended_screen.dart`

## Task Commits

1. **Task 1: Create SenderSessionEndedScreen** - `a55821a` (feat)
2. **Task 2: Reactive listener + remove End Session button** - `a39eb7d` (feat)

## Files Created/Modified

- `lib/presentation/sender/sender_session_ended_screen.dart` — new static screen; D-10 `_checkAndMarkDone()` in `initState`; two green checklist sections; `SecurityLifecycleMixin`; no `aesKey` arg
- `lib/presentation/sender/transfer_progress_screen.dart` — import swapped; `_sessionEnded` guard added; `!snapshot.exists` handler with `wipeAll()` + navigation; End Session `CrypButton` removed; `_completedAt` field removed

## Decisions Made

- `aesKey` is NOT passed to `SenderSessionEndedScreen` — the key is zeroed by `wipeAll()` in `TransferProgressScreen` before navigation, satisfying T-04-03-05
- `_sessionEnded = true` set before `Navigator.pushReplacement` fires — any subsequent stream reconnect fires the guard and returns immediately (T-04-03-03)
- The `!_done` guard ensures the listener only reacts after upload completes — prevents spurious navigation if Firestore reports the doc absent before `_startUpload()` creates it (T-04-03-02, Pitfall 1)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused `_completedAt` field after End Session button removal**
- **Found during:** Task 2 (Modify TransferProgressScreen — reactive listener + remove End Session button)
- **Issue:** `_completedAt` was declared and assigned in `_startUpload()` but only consumed by the removed End Session `CrypButton`. With the button gone, the field became unused, triggering an `unused_field` analyzer warning that would fail the acceptance criteria (`flutter analyze` must report 0 issues).
- **Fix:** Removed the `DateTime? _completedAt` declaration and the `_completedAt = DateTime.now()` assignment from `setState()` in `_startUpload()`. Also updated the `aesKey` doc comment to reflect the new D-07 zeroing pattern instead of the old "passed through to EndSessionScreen" description.
- **Files modified:** `lib/presentation/sender/transfer_progress_screen.dart`
- **Verification:** `flutter analyze lib/presentation/sender/transfer_progress_screen.dart` → No issues found
- **Committed in:** `a39eb7d` (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — bug/unused field introduced by removing End Session button)
**Impact on plan:** Necessary for analyzer-clean acceptance criteria. No scope creep.

## Issues Encountered

None — both files compiled cleanly after the auto-fix.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `SenderSessionEndedScreen` is fully implemented and wired. `TransferProgressScreen` is reactive.
- Plan 04 (final wave) can proceed; it should verify the full end-to-end flow and address any remaining dead code (`EndSessionScreen`, `DownloadConfirmScreen`) per D-15/D-16.

---
*Phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast*
*Completed: 2026-05-08*
