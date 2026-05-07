---
phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast
plan: "02"
subsystem: ui
tags: [flutter, firestore, firebase-storage, flutter-secure-storage, security, session-termination]

# Dependency graph
requires:
  - phase: 04-01
    provides: session_termination_test.dart with TC-TERM-001 through TC-TERM-008 stubs
  - phase: 03-managed-profile-rsa-vault
    provides: KeyRepository.endSessionCleanup(), getActiveHandshakeDocId(), EncryptionService.closeReceiverSession()
provides:
  - ReceiverEndSessionScreen: D-03 4-step cleanup UI (audit log → storage delete → WriteBatch → RSA wipe)
  - Security-enforced cleanup ordering: auditBatch before any deletion, endSessionCleanup before closeReceiverSession
affects:
  - 04-03 (DecryptScreen navigation change to ReceiverEndSessionScreen)
  - 04-04 (SenderSessionEndedScreen creation + TransferProgressScreen reactive listener)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - D-03 cleanup sequence: audit log first, storage, WriteBatch atomic delete, RSA wipe last
    - SecurityLifecycleMixin applied without buffer registration (plaintext wiped upstream)
    - PopScope(canPop: _phase == _Phase.ready) back-nav guard during cleanup + done phases
    - FirebaseAuth.instance.currentUser?.displayName for receiver username (Pitfall 3 fix)

key-files:
  created:
    - lib/presentation/receiver/receiver_end_session_screen.dart
  modified: []

key-decisions:
  - "4 steps for ReceiverEndSessionScreen (not 6 like EndSessionScreen) — D-03 sequence: audit log, storage delete, WriteBatch cleanup, RSA wipe"
  - "endSessionCleanup() called at step 2 BEFORE closeReceiverSession() at step 3 — prevents null handshakeId (RESEARCH.md Pitfall 2)"
  - "Removed dart:typed_data import — no aesKey in receiver version, import was unused"
  - "Receiver username read from FirebaseAuth.instance.currentUser?.displayName at cleanup time — consistent with EndSessionScreen pattern"

patterns-established:
  - "ReceiverEndSessionScreen is a structural copy of EndSessionScreen with updated step list and _endSession() body"
  - "_SummaryRow, _CleanStepTile, _DoneStepRow copied verbatim from EndSessionScreen (private widget reuse pattern)"

requirements-completed: [TERM-01, TERM-02, TERM-03, TERM-04]

# Metrics
duration: 2min
completed: 2026-05-07
---

# Phase 04 Plan 02: ReceiverEndSessionScreen Summary

**ReceiverEndSessionScreen with D-03 security-enforced 4-step cleanup: audit log first, then storage delete, atomic WriteBatch (transfer + handshake), and closeReceiverSession last**

## Performance

- **Duration:** 2 min
- **Started:** 2026-05-07T16:40:38Z
- **Completed:** 2026-05-07T16:43:28Z
- **Tasks:** 1
- **Files created:** 1

## Accomplishments

- `ReceiverEndSessionScreen` created with the exact D-03 security-critical step order: audit log committed before any deletion, `endSessionCleanup()` runs before `closeReceiverSession()` to avoid null handshakeId (Pitfall 2)
- `SecurityLifecycleMixin<ReceiverEndSessionScreen>` applied per D-14; no buffers registered (plaintext already wiped upstream in `DecryptScreen._saveAndWipe()`)
- `PopScope(canPop: _phase == _Phase.ready)` blocks back-navigation during `cleaning` and `done` phases, preventing duplicate audit log entries
- Private widgets `_SummaryRow`, `_CleanStepTile`, `_DoneStepRow` copied verbatim from `EndSessionScreen`; no behavioral differences
- Session summary card shows receiver row using `FirebaseAuth.instance.currentUser?.displayName` (Pitfall 3 fix — receiver username not passed from `DecryptScreen`)
- `flutter analyze`: 0 issues; all 6 TC-TERM tests pass (TC-TERM-001 through TC-TERM-005, TC-TERM-008)

## Task Commits

1. **Task 1: Create ReceiverEndSessionScreen** - `d5a2e94` (feat)

## Files Created/Modified

- `lib/presentation/receiver/receiver_end_session_screen.dart` — ReceiverEndSessionScreen with D-03 4-step cleanup sequence; inherits EndSessionScreen pattern with receiver-specific step order and RSA wipe as final step

## Decisions Made

- 4 steps chosen over EndSessionScreen's 6 steps — D-03 explicitly defines 4 logical phases for receiver cleanup; D-13's reference to "6 steps" in RESEARCH.md was reconciled as referring to the `_CleanStepTile` pattern, not the count
- `dart:typed_data` import removed — present in EndSessionScreen for `Uint8List aesKey`, not needed in receiver version (no AES key parameter)
- Receiver username sourced from `FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown'` at cleanup time, consistent with `EndSessionScreen` pattern

## Deviations from Plan

**1. [Rule 1 - Bug] Removed unused `dart:typed_data` import**
- **Found during:** Task 1 — flutter analyze
- **Issue:** Plan's import list included `dart:typed_data` (copied from EndSessionScreen template). ReceiverEndSessionScreen has no `aesKey: Uint8List?` parameter, so the import is unused.
- **Fix:** Removed `import 'dart:typed_data';` from the file.
- **Files modified:** `lib/presentation/receiver/receiver_end_session_screen.dart`
- **Verification:** `flutter analyze` reports 0 issues after removal
- **Committed in:** `d5a2e94` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (Rule 1 - unused import from template copy)
**Impact on plan:** Minimal — template import not needed in receiver variant. No scope creep.

## Issues Encountered

None — plan executed cleanly. All referenced methods (`endSessionCleanup`, `getActiveHandshakeDocId`, `deleteStorageFile`, `closeReceiverSession`) verified against source before implementation.

## Known Stubs

None — the screen is fully implemented. No hardcoded values or placeholder text flow to the UI.

## Threat Flags

No new trust boundaries introduced beyond those documented in the plan's threat model. All new Firestore writes/deletes use the existing `users`, `audit_logs`, `transfers`, `handshakes` collections — no new collection paths or auth surfaces.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- `ReceiverEndSessionScreen` is ready to receive navigation from `DecryptScreen._saveAndWipe()` (Plan 04-03 task)
- Constructor signature confirmed: `{transferId, fileName, fileSize, senderUsername, senderId, receiverId, transferredAt}` — all available at `DecryptScreen._saveAndWipe()` call site per RESEARCH.md

---
*Phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast*
*Completed: 2026-05-07*

## Self-Check: PASSED

- FOUND: `lib/presentation/receiver/receiver_end_session_screen.dart`
- FOUND: commit `d5a2e94`
- class ReceiverEndSessionScreen: present (1 occurrence)
- SecurityLifecycleMixin: present (1 occurrence)
- closeReceiverSession: present (step 3 — after endSessionCleanup)
- endSessionCleanup: present (step 2 — before closeReceiverSession)
- auditBatch.commit: present (step 0 — before deleteStorageFile)
- deleteStorageFile: present (step 1)
- canPop: _phase == _Phase.ready: present
- aesKey in constructor: absent (only appears in comment, not as constructor param)
- flutter analyze: 0 issues
- flutter test session_termination_test.dart: 6/6 passed
