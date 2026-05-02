---
phase: 03-managed-profile-rsa-vault
plan: "02"
subsystem: auth-profile-init
tags: [firebase-constants, auth-repository, write-batch, profile-subcollection, atomic-write]
dependency_graph:
  requires:
    - 03-01 (analyzer clean, test/vault/ stubs)
  provides:
    - FirebaseConstants.rsaKeyManager constant
    - FirebaseConstants.profile constant
    - users/{uid}/profile/preferences doc created atomically on registration
    - WriteBatch pattern in register() and signInWithGoogle()
  affects:
    - lib/core/constants/firebase_constants.dart
    - lib/data/repositories/auth_repository.dart
tech_stack:
  added: []
  patterns:
    - WriteBatch atomic write pattern (user doc + profile/preferences in one commit)
    - FirebaseConstants as single source of truth for subcollection names
key_files:
  created: []
  modified:
    - lib/core/constants/firebase_constants.dart
    - lib/data/repositories/auth_repository.dart
decisions:
  - "WriteBatch used for both register() and signInWithGoogle() — prevents partial-write where user doc exists but profile/preferences is absent"
  - "gBatch variable name used in signInWithGoogle() to avoid shadowing the batch variable from a hypothetical outer scope — consistent with plan spec"
  - "profile/preferences initial values: biometricGateEnabled=false, themeMode='dark', keyVaultCreatedAt=null, lastVaultAccessAt=null"
metrics:
  duration_seconds: 211
  completed_date: "2026-05-02T13:29:43Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 2
---

# Phase 03 Plan 02: Profile Subcollection Init & FirebaseConstants Summary

**One-liner:** Added `rsaKeyManager`/`profile` constants to FirebaseConstants and migrated `register()` + `signInWithGoogle()` to WriteBatch so `users/{uid}/profile/preferences` is created atomically with the user document.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add rsaKeyManager and profile constants to FirebaseConstants | `f7dd165` | lib/core/constants/firebase_constants.dart |
| 2 | Migrate register() and signInWithGoogle() to WriteBatch with profile/preferences init | `7995612` | lib/data/repositories/auth_repository.dart |

## Verification Results

1. `flutter analyze --no-pub` → **No issues found!**
2. `grep "rsaKeyManager\|static const String profile" lib/core/constants/firebase_constants.dart` → 2 lines (lines 15–16)
3. `grep "batch\|gBatch" lib/data/repositories/auth_repository.dart` → 8 matches (2 batch declarations + 4 set() calls + 2 commit() calls)
4. `FirebaseConstants.profile` referenced at lines 78 and 171 in auth_repository.dart (one per method)
5. `flutter test test/vault/ --no-pub` → **All 5 stubs PASSED** (TC-VAULT-01/02/03/05/06-stub)

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

No new stubs introduced in this plan. The existing `TC-VAULT-05-stub` in `test/vault/profile_init_test.dart` tests the WriteBatch pattern against FakeFirebaseFirestore directly (not through AuthRepository). A full integration test against the real AuthRepository will be added in a later plan once dependency injection is in place (as noted in the plan's action section).

## Threat Flags

None — no new network endpoints or auth paths beyond what was planned. The WriteBatch write crosses the AuthRepository → Firestore boundary as intended (T-03-02-01 and T-03-02-02 mitigated).

## Self-Check: PASSED

Files exist:
- FOUND: lib/core/constants/firebase_constants.dart (modified — rsaKeyManager + profile at lines 15–16)
- FOUND: lib/data/repositories/auth_repository.dart (modified — WriteBatch in register() at line 61, WriteBatch in signInWithGoogle() at line 154)

Commits exist:
- FOUND: f7dd165 (feat — rsaKeyManager and profile constants)
- FOUND: 7995612 (feat — WriteBatch profile init)
