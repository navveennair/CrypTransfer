---
phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast
plan: "01"
subsystem: testing
tags: [flutter-test, fake-cloud-firestore, flutter-secure-storage, session-termination, security]

requires: []
provides:
  - "Wave 0 test scaffold: 6 TC-TERM stubs covering TERM-01..05, TERM-08"
  - "Nyquist contract for all Phase 04 implementation waves"
affects:
  - 04-02
  - 04-03
  - 04-04

tech-stack:
  added: []
  patterns:
    - "FakeFirebaseFirestore + FakeSecureStorage pattern from test/mocks/mock_firebase.dart"
    - "Stub tests with inline simulation logic — no real services, compile-and-pass from day 0"

key-files:
  created:
    - test/security/session_termination_test.dart
  modified: []

key-decisions:
  - "rethrow in TC-TERM-002 restructured from bare try/else into on FirebaseException catch block — bare rethrow outside catch clause is a Dart compile error"
  - "dart:typed_data import removed — not used in this test file (unlike session_wipe_test.dart which uses Uint8List)"
  - "Stub tests contain inline simulation logic rather than real service calls — keeps Wave 0 runnable before any implementation ships"

patterns-established:
  - "TC-TERM stub pattern: inline simulation of the target code path + assertions, with STUB comment linking to the wave/plan that will replace it with real calls"

requirements-completed:
  - TERM-01
  - TERM-02
  - TERM-03
  - TERM-04
  - TERM-05
  - TERM-08

duration: 3min
completed: "2026-05-07"
---

# Phase 04 Plan 01: Wave 0 Session Termination Test Scaffold Summary

**6 TC-TERM stubs (TERM-01..05, TERM-08) using FakeFirebaseFirestore + FakeSecureStorage — all pass from day 0 with inline simulation logic before any implementation ships**

## Performance

- **Duration:** 3 min
- **Started:** 2026-05-07T16:35:32Z
- **Completed:** 2026-05-07T16:38:31Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Created `test/security/session_termination_test.dart` with 6 stub tests covering all Wave 0 Nyquist contract IDs
- All 6 TC-TERM stubs pass with `flutter test test/security/session_termination_test.dart` (exit 0)
- Full security test suite (29 tests) passes — no regressions in existing TC-WIPE tests
- `flutter analyze` reports no issues on the new file

## Task Commits

1. **Task 1: Create session termination test scaffold with 6 stubs** - `67c1ab7` (test)

**Plan metadata:** _(docs commit follows)_

## Files Created/Modified

- `test/security/session_termination_test.dart` — 6 stub tests: TC-TERM-001 (audit log ordering), TC-TERM-002 (object-not-found tolerance), TC-TERM-003 (WriteBatch atomicity), TC-TERM-004 (publicKey + private key deletion), TC-TERM-005 (!snapshot.exists guard), TC-TERM-008 (D-10 edge case)

## Decisions Made

- `rethrow` in TC-TERM-002 restructured — bare `rethrow` outside a `catch` clause is a Dart compile error; restructured to `throw FirebaseException(...)` inside `try` + `on FirebaseException catch (e)` with conditional rethrow, accurately mirroring the production guard pattern
- `dart:typed_data` import removed — the plan template copied the import from `session_wipe_test.dart` (which uses `Uint8List`), but this test file does not; lint flagged `unused_import` → removed

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed `rethrow` outside catch clause in TC-TERM-002**
- **Found during:** Task 1 (test scaffold creation)
- **Issue:** Plan template contained `rethrow` inside a `try` block's `else` branch — invalid Dart; `rethrow` is only legal inside a `catch` clause. `flutter test` exited 1 with compile error.
- **Fix:** Restructured TC-TERM-002 to use `throw FirebaseException(...)` + `on FirebaseException catch (e) { if (e.code != 'object-not-found') { cleanupAborted = true; rethrow; } }` — accurately models the production guard pattern from `EndSessionScreen`.
- **Files modified:** `test/security/session_termination_test.dart`
- **Verification:** `flutter test test/security/session_termination_test.dart` exits 0, all 6 pass.
- **Committed in:** `67c1ab7` (task commit)

**2. [Rule 1 - Bug] Removed unused `dart:typed_data` import**
- **Found during:** Task 1 (post-test `flutter analyze`)
- **Issue:** Plan template included `import 'dart:typed_data';` (copied from sibling test file), but this file does not use `Uint8List`. Analyzer reported `unused_import` warning, violating the "flutter analyze reports no issues" success criterion.
- **Fix:** Removed the unused import.
- **Files modified:** `test/security/session_termination_test.dart`
- **Verification:** `flutter analyze test/security/session_termination_test.dart` — No issues found.
- **Committed in:** `67c1ab7` (task commit, fixed before final commit)

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs — compile error + lint warning in plan template)
**Impact on plan:** Both fixes were correctness requirements. The test file behavior and stub coverage are identical to the plan spec — only the rethrow syntax and unused import were corrected.

## Issues Encountered

None beyond the two auto-fixed deviations above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Wave 0 test scaffold is complete. Plans 02–04 (Waves 1–2) can now land implementation and upgrade these stubs to real assertions.
- TC-TERM-001..005 stubs reference specific plan/wave milestones in their comments for continuity.
- TC-TERM-008 references `SenderSessionEndedScreen._checkAndMarkDone()` (Wave 2, Plan 03).

## Self-Check: PASSED

| Item | Status |
|------|--------|
| `test/security/session_termination_test.dart` | FOUND |
| `04-01-SUMMARY.md` | FOUND |
| Commit `67c1ab7` | FOUND |

---
*Phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast*
*Completed: 2026-05-07*
