---
phase: 05-neutral-handshake-model
plan: 06
subsystem: ui
tags: [flutter, firestore, streams, home-screen, handshake]

# Dependency graph
requires:
  - phase: 05-neutral-handshake-model
    provides: HandshakeRepository, neutral handshake streams, pending/active connection UI
provides:
  - Fixed _accepting spinner — resets on error via async/await + finally block
  - hasError branch in _ActiveConnectionsSection StreamBuilder — surfaces stream errors to user
  - Deduplicated Firestore streams — listeners reuse initState fields
  - Pending row InkWell removed — cancel icon is sole tap target, confirmation sheet reachable
affects: [05-neutral-handshake-model, home-screen-uat]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Async onPressed with finally block for resetting loading state on both success and error"
    - "hasError check before connectionState check in nested StreamBuilder innermost builder"
    - "Stream field typed as Stream<QuerySnapshot<Map<String,dynamic>>> for compile-time type safety"

key-files:
  created: []
  modified:
    - lib/presentation/home/home_screen.dart

key-decisions:
  - "rethrow in _acceptProposal propagates error to the row's finally block so _accepting resets even on failure"
  - "Stream fields typed explicitly as Stream<QuerySnapshot<Map<String,dynamic>>> — fixes pre-existing DocumentSnapshot<Object?> type error exposed by stream deduplication"
  - "Pending row else branch returns row directly (no InkWell) — the cancel IconButton is the only interaction surface for pending rows, making the confirmation sheet reliably reachable"

patterns-established:
  - "Async loading button pattern: setState(loading=true) → try { await action } finally { if (mounted) setState(loading=false) }"
  - "StreamBuilder error guard: check hasError before connectionState in nested builders"

requirements-completed: [D-03, D-07, D-08, D-09, D-10]

# Metrics
duration: 5min
completed: 2026-05-15
---

# Phase 05 Plan 06: Home Screen Bug Fixes Summary

**Four home_screen.dart defects fixed: Accept spinner reset via async/await+finally, Firestore error surfacing via hasError branch, stream deduplication using initState fields, and pending-row InkWell removed to unblock cancel confirmation sheet**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-15T11:11:40Z
- **Completed:** 2026-05-15T11:16:17Z
- **Tasks:** 3
- **Files modified:** 1

## Accomplishments

- Accept button in Pending Requests row now resets to default state after a network error (async/await + finally block)
- Active Connections section shows "Could not load connections. Check your connection." when Firestore streams error, instead of silent empty state
- `_startHandshakeListener` and `_startOutcomeListener` reuse the stable `_incomingPendingStream` / `_outgoingPendingStream` fields from initState — no duplicate subscriptions
- Tapping a pending outgoing row now reaches the cancel confirmation sheet; the InkWell SnackBar wrapper that swallowed the tap is removed

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix Bug A — _accepting spinner never resets on error** - `2f6d615` (fix)
2. **Task 2: Fix Bug B — add hasError branch to _ActiveConnectionsSection StreamBuilder** - `ea669de` (fix)
3. **Task 3: Fix Bug C and Gap 3 — deduplicate streams and remove InkWell from pending rows** - `be19ac1` (fix)

**Plan metadata:** `(see final commit below)` (docs: complete plan)

## Files Created/Modified

- `lib/presentation/home/home_screen.dart` — Four bug fixes: async Accept button, hasError error branch, stream deduplication, InkWell removal from pending rows

## Decisions Made

- `rethrow` in `_acceptProposal` propagates the error out to the caller's `finally` block. Without rethrow, the error is swallowed and `_accepting` stays `true` permanently.
- Stream fields explicitly typed as `Stream<QuerySnapshot<Map<String, dynamic>>>` rather than raw `Stream<QuerySnapshot>` — this was required to fix a pre-existing `DocumentSnapshot<Object?>` type error in `_startHandshakeListener` that only became visible as an analyzer error after the deduplication change surfaced it.
- Pending row `else` branch returns `row` directly with no `InkWell` wrapper. The `IconButton` for cancel has its own tap handler, so a containing `InkWell` with a competing `onTap` was absorbing taps intended for the icon on some devices.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pre-existing DocumentSnapshot type error in _startHandshakeListener**
- **Found during:** Task 3 (stream deduplication)
- **Issue:** Stream fields were typed `Stream<QuerySnapshot>` (i.e. `Stream<QuerySnapshot<Object?>>`). After deduplication, `_startHandshakeListener` passed `change.doc` (type `DocumentSnapshot<Object?>`) to `_showProposalBanner` which expects `DocumentSnapshot<Map<String, dynamic>>` — analyzer error: `argument_type_not_assignable`
- **Fix:** Typed all five stream fields as `Stream<QuerySnapshot<Map<String, dynamic>>>` to propagate the correct generic throughout
- **Files modified:** `lib/presentation/home/home_screen.dart`
- **Verification:** `dart analyze lib/presentation/home/home_screen.dart` — No issues found
- **Committed in:** `be19ac1` (Task 3 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 — Bug)
**Impact on plan:** Pre-existing latent type error that was exposed by the stream deduplication. Fix is purely mechanical (explicit generic typing) and required for correct compilation. No scope creep.

## Issues Encountered

None beyond the auto-fixed type error above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- All four UAT-blocking bugs in home_screen.dart are resolved
- Accept spinner correctly resets on both success and error
- Firestore stream errors are visible to the user
- Cancel confirmation sheet is reachable for any pending row tap
- Ready for UAT re-run (tests 5 and 8 that were previously failing)

---
*Phase: 05-neutral-handshake-model*
*Completed: 2026-05-15*
