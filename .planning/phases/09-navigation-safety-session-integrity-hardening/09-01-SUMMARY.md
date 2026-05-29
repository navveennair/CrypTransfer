---
plan: 09-01
phase: 09-navigation-safety-session-integrity-hardening
status: complete
completed: "2026-05-29"
commit: e5f985e
---

# Plan 09-01: Nyquist Test Stubs — Navigation Guard & Stale Key

## What Was Built

Created two Nyquist-compliant test stub files for Phase 9's automated test targets:

- `test/security/navigation_guard_test.dart` — 3 tests (GAP1-01, GAP1-02, GAP1-03)
- `test/sender/stale_key_test.dart` — 3 tests (GAP2-01, GAP2-02, GAP3-02)

## Key Files

### Created
- `test/security/navigation_guard_test.dart` — ReceiverScreen canPop logic, session-locked SnackBar path, confirmed wipeSession transition
- `test/sender/stale_key_test.dart` — stale AES key wipe on key change, mid-flight guard, Change File confirm wipe state

## Verification

- `flutter test test/security/navigation_guard_test.dart test/sender/stale_key_test.dart --no-pub` → **6/6 passed**
- Full suite: **113 passing, 1 pre-existing failure (TC010)** — baseline preserved

## Self-Check: PASSED

All must_haves satisfied:
- ✓ navigation_guard_test.dart compiles and 3 tests pass (GAP1-01, GAP1-02, GAP1-03)
- ✓ stale_key_test.dart compiles and 3 tests pass (GAP2-01, GAP2-02, GAP3-02)
- ✓ Both files import correct packages without errors
- ✓ Full suite shows 113/114 (pre-existing TC010 failure unchanged)
- ✓ Wave 2 plans (09-02, 09-03) can now reference these test files
