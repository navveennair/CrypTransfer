---
phase: 06-synchronized-readiness-gate
plan: 01
subsystem: database
tags: [flutter, firestore, key_repository, handshake, receiverReady]

# Dependency graph
requires:
  - phase: 05-neutral-handshake-model
    provides: selectSenderHandshake() WriteBatch, streamHandshakesForSender() stream, handshakes collection

provides:
  - selectSenderHandshake() returns Future<String> doc ID for caller to persist
  - setReceiverReady(String handshakeDocId) writes receiverReady: true to handshakes doc
  - receiverReady: false initialized in new-doc batch.set() payload

affects:
  - 06-02 ReceiverScreen trigger (calls selectSenderHandshake, captures docId, calls setReceiverReady)
  - 06-03 SenderScreen gate (stream on handshakes doc reads receiverReady field)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Firestore atomic batch returns doc ID to caller for downstream writes"
    - "receiverReady field initialized false on doc creation, set true by explicit caller action"

key-files:
  created: []
  modified:
    - lib/data/repositories/key_repository.dart

key-decisions:
  - "selectSenderHandshake returns the Firestore doc ID (either existing or newly created) so ReceiverScreen can pass it to setReceiverReady without a second query"
  - "receiverReady: false initialized in new-doc branch of batch.set() so the field always exists on the doc from creation (D-02 requirement)"
  - "setReceiverReady is a standalone method (not folded into selectSenderHandshake) so the receiver screen can call it after its own session setup completes"

patterns-established:
  - "Batch-return-ID pattern: when a WriteBatch creates or updates a doc, capture and return the doc ID so callers avoid re-querying"

requirements-completed: [SYNC-01, SYNC-02]

# Metrics
duration: 12min
completed: 2026-05-15
---

# Phase 06 Plan 01: KeyRepository Data Layer for Synchronized Readiness Gate Summary

**selectSenderHandshake() upgraded to Future<String> returning handshake doc ID; new setReceiverReady() method writes receiverReady: true to that doc via targeted Firestore update**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-05-15T17:39:00Z
- **Completed:** 2026-05-15T17:51:12Z
- **Tasks:** 2
- **Files modified:** 1

## Accomplishments

- Changed `selectSenderHandshake()` return type from `Future<void>` to `Future<String>`, capturing the handshake doc ID from whichever batch branch executes (existing doc reuse or new doc creation)
- Added `receiverReady: false` initialization in the new-doc `batch.set()` payload so the field is always present from doc creation
- Added `setReceiverReady(String handshakeDocId)` method that writes `receiverReady: true` to the handshakes doc identified by the caller-supplied ID, with `NetworkException` wrapping on `FirebaseException`

## Task Commits

Each task was committed atomically:

1. **Task 1: Change selectSenderHandshake return type to Future<String> and capture doc ID** - `3f8fe89` (feat)
2. **Task 2: Add setReceiverReady() method to KeyRepository** - `3f8fe89` (feat)

Both tasks committed together as a single atomic commit since they both modify only `key_repository.dart` and constitute the plan's complete objective.

**Plan metadata:** (docs commit follows)

## Files Created/Modified

- `lib/data/repositories/key_repository.dart` - Updated `selectSenderHandshake()` return type + doc ID capture + `receiverReady: false` init; added `setReceiverReady()` method

## Decisions Made

- Tasks 1 and 2 committed together in a single atomic commit — both modify only `key_repository.dart` and together form the complete data-layer change
- `receiverReady: false` added to new-doc `batch.set()` payload as a correctness requirement (D-02): field must exist from creation so sender's stream query can filter on it without missing-field ambiguity
- `setReceiverReady` placed between `setReadyToReceive` and `wipeAllSessionKeys` to group all readiness-state methods together

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

The READ-BEFORE-EDIT hook triggered on consecutive edits to the same file within the session. The first edit (Task 1) succeeded. The second edit (Task 2) also succeeded but the hook warning caused a second attempt that doubled the `setReceiverReady` block — the duplicate was removed before the final commit. The committed file is correct.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- `selectSenderHandshake()` now returns `Future<String>` — 06-02 ReceiverScreen can capture the doc ID and pass it to `setReceiverReady()`
- `setReceiverReady()` is ready for 06-02 wiring in `_onSenderSelected()`
- `receiverReady` field will be present on all new handshake docs — 06-03 SenderScreen stream gate can reliably filter on `receiverReady == true`
- No blockers

---
*Phase: 06-synchronized-readiness-gate*
*Completed: 2026-05-15*
