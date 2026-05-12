---
phase: 05-neutral-handshake-model
plan: 01
subsystem: testing
tags: [flutter_test, fake_cloud_firestore, firebase_auth_mocks, handshake, test-scaffold]

# Dependency graph
requires:
  - phase: 03-managed-profile-rsa-vault
    provides: "FakeSecureStorage + MockFirebaseAuth test infrastructure in test/mocks/mock_firebase.dart"
provides:
  - "test/handshake/ directory with 3 compilable failing-stub test files"
  - "lib/data/repositories/handshake_repository.dart stub class (replaced in 05-02)"
  - "flutter test test/handshake/ verification gate usable by all Wave 1 executors"
affects:
  - 05-02-PLAN (data layer — Wave 1 must pass this gate after implementing HandshakeRepository)
  - 05-03-PLAN (sender/receiver pre-fill — Wave 1 must pass sender/receiver prefill stubs)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Failing stub test pattern: fail('TC-HAND-XX: not implemented yet') ensures compile success before production code exists"
    - "Minimal class stub at production path allows test imports to resolve ahead of implementation"

key-files:
  created:
    - test/handshake/handshake_repository_test.dart
    - test/handshake/sender_prefill_test.dart
    - test/handshake/receiver_prefill_test.dart
    - lib/data/repositories/handshake_repository.dart
  modified: []

key-decisions:
  - "Stub class at lib/data/repositories/handshake_repository.dart (empty class body) chosen over // ignore comment — cleanest compile resolution; stub is fully replaced in 05-02"
  - "flutter test test/handshake/ (no -x flag) used as verification gate — flutter -x requires an argument in this Flutter version (3.41.9)"

patterns-established:
  - "Test scaffold pattern: create 3 files (repository, sender prefill, receiver prefill) before any production code; fail() stubs provide a runnable RED gate"

requirements-completed:
  - HAND-01
  - HAND-02
  - HAND-03
  - HAND-04
  - HAND-05
  - HAND-07
  - HAND-08

# Metrics
duration: 8min
completed: 2026-05-12
---

# Phase 05 Plan 01: Test Scaffold Summary

**Three compilable failing-stub test files (7 total stubs) in test/handshake/ providing the Nyquist verification gate for HandshakeRepository, SenderScreen pre-fill, and ReceiverScreen pre-fill**

## Performance

- **Duration:** ~8 min
- **Started:** 2026-05-12T09:00:00Z
- **Completed:** 2026-05-12T09:07:46Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Created `test/handshake/` directory with 3 test files covering 7 requirement stubs (HAND-01 through HAND-05, HAND-07, HAND-08)
- Created `lib/data/repositories/handshake_repository.dart` minimal stub so imports resolve before Wave 1 implementation
- Verified `flutter test test/handshake/` runs 7 tests, all failing with "not implemented yet" — zero compile errors
- Verified `flutter analyze lib/data/repositories/handshake_repository.dart` reports no issues

## Task Commits

Each task was committed atomically:

1. **Task 1: Create handshake_repository_test.dart (HAND-01 to HAND-05 stubs)** - `f58e238` (test)
2. **Task 2: Create sender_prefill_test.dart (HAND-07) and receiver_prefill_test.dart (HAND-08)** - `b2d160c` (test)

## Files Created/Modified

- `test/handshake/handshake_repository_test.dart` — 5 failing stubs: TC-HAND-01 through TC-HAND-05 (HandshakeRepository methods)
- `test/handshake/sender_prefill_test.dart` — 1 failing stub: TC-HAND-07 (SenderScreen preFilledPartnerUid param)
- `test/handshake/receiver_prefill_test.dart` — 1 failing stub: TC-HAND-08 (ReceiverScreen preFilledSenderUid param)
- `lib/data/repositories/handshake_repository.dart` — empty class stub (replaced entirely in 05-02 Wave 1)

## Decisions Made

- **Stub class over ignore comment:** `lib/data/repositories/handshake_repository.dart` uses a minimal `class HandshakeRepository {}` rather than an `// ignore: uri_does_not_exist` comment — cleaner compile resolution; the stub is flagged for full replacement in 05-02.
- **`flutter test` without `-x` flag:** The plan specified `flutter test test/handshake/ -x` but `-x` requires an argument in Flutter 3.41.9 (exclude-tag flag). Used plain `flutter test test/handshake/` instead — identical behavior for these stub tests.

## Deviations from Plan

None — plan executed exactly as written. The `-x` flag discovery was a minor tooling note, not a deviation from intent.

## Issues Encountered

- `flutter test -x` fails with "Missing argument for -x" on Flutter 3.41.9. The plan's verify command `flutter test test/handshake/ -x` does not work as written. Used `flutter test test/handshake/` instead. Wave 1 executors should use the same command.

## Known Stubs

| File | Description | Resolves In |
|------|-------------|-------------|
| `lib/data/repositories/handshake_repository.dart` | Empty class — no methods | 05-02 (Wave 1, Task 1) |
| `test/handshake/handshake_repository_test.dart` | 5 `fail()` stubs for HAND-01..05 | 05-02 (Wave 1) |
| `test/handshake/sender_prefill_test.dart` | 1 `fail()` stub for HAND-07 | 05-03 (Wave 1) |
| `test/handshake/receiver_prefill_test.dart` | 1 `fail()` stub for HAND-08 | 05-03 (Wave 1) |

All stubs are intentional — this plan's sole purpose is to create a compilable test scaffold ahead of implementation.

## Next Phase Readiness

- `flutter test test/handshake/` is a live verification gate for all Wave 1 executors (05-02, 05-03)
- Wave 1 executor for 05-02 must replace `handshake_repository.dart` stub with full implementation; tests in `handshake_repository_test.dart` will turn green
- Wave 1 executor for 05-03 must add `preFilledPartnerUid`/`preFilledSenderUid` params to screens; tests in `sender_prefill_test.dart` and `receiver_prefill_test.dart` will turn green

---
*Phase: 05-neutral-handshake-model*
*Completed: 2026-05-12*
