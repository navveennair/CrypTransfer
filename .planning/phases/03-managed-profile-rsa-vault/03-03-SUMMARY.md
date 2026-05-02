---
phase: 03-managed-profile-rsa-vault
plan: "03"
subsystem: auth-repository-key-lifecycle
tags: [auth-repository, rsa-key-management, write-batch, audit-log, sha256-fingerprint, tdd]
dependency_graph:
  requires:
    - 03-02 (FirebaseConstants rsaKeyManager/profile + WriteBatch profile init)
  provides:
    - AuthRepository.computeFingerprint() static method
    - AuthRepository.regenerateKeyPair(uid) — 3-doc WriteBatch (publicKey + audit + keyVaultCreatedAt)
    - AuthRepository.deleteKeyPair(uid) — 2-doc WriteBatch (publicKey delete + audit)
    - AuthRepository.updateLastVaultAccess(uid) — set(merge:true) on profile/preferences
  affects:
    - lib/data/repositories/auth_repository.dart
    - test/vault/key_lifecycle_test.dart
tech_stack:
  added: []
  patterns:
    - SHA256Digest (PointyCastle) for public key fingerprint
    - 3-doc WriteBatch: publicKey update + audit log + keyVaultCreatedAt (D-14)
    - 2-doc WriteBatch: publicKey FieldValue.delete() + audit log
    - set(merge:true) for upsert-safe profile/preferences write
    - compute() reuse of existing _generateKeyPairIsolate top-level function
    - TestWidgetsFlutterBinding.ensureInitialized() + FakeSecureStorage for unit tests
key_files:
  created: []
  modified:
    - lib/data/repositories/auth_repository.dart
    - test/vault/key_lifecycle_test.dart
decisions:
  - "dart:typed_data import removed — Uint8List already re-exported by flutter/foundation.dart (Rule 1 auto-fix)"
  - "Tests use FakeSecureStorage from test/mocks/mock_firebase.dart instead of const FlutterSecureStorage() — avoids platform channel binding requirement in unit tests"
  - "TestWidgetsFlutterBinding.ensureInitialized() added in setUpAll — required by compute() which internally uses ServicesBinding"
  - "MockFirebaseAuth added to all AuthRepository test instances — constructor calls FirebaseAuth.instance as default even when methods don't use auth"
  - "TC-VAULT-07 and TC-VAULT-07b added for updateLastVaultAccess — not in original plan test file, added as part of Task 2 TDD cycle"
metrics:
  duration_seconds: 406
  completed_date: "2026-05-02T17:59:40Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 0
  files_modified: 2
---

# Phase 03 Plan 03: AuthRepository Key Lifecycle Methods Summary

**One-liner:** Added four AuthRepository methods — `computeFingerprint()` (static SHA-256), `regenerateKeyPair()` (3-doc WriteBatch + compute RSA), `deleteKeyPair()` (2-doc WriteBatch), `updateLastVaultAccess()` (merge-safe upsert) — with full TDD coverage via 9 new tests.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add computeFingerprint, regenerateKeyPair, deleteKeyPair to AuthRepository | `d3a8b00` | lib/data/repositories/auth_repository.dart, test/vault/key_lifecycle_test.dart |
| 2 | Add updateLastVaultAccess() to AuthRepository | `ae76d65` | lib/data/repositories/auth_repository.dart, test/vault/key_lifecycle_test.dart |

## Verification Results

1. `flutter analyze --no-pub` → **No issues found!**
2. `grep -c "Future<void> regenerateKeyPair|Future<void> deleteKeyPair|Future<void> updateLastVaultAccess|static String computeFingerprint" lib/data/repositories/auth_repository.dart` → **4**
3. `grep "SHA256Digest|computeFingerprint" lib/data/repositories/auth_repository.dart` → **2 matches**
4. `grep "keyVaultCreatedAt" lib/data/repositories/auth_repository.dart` → **1 match in regenerateKeyPair WriteBatch** (plus comments/initial values in register/signInWithGoogle from Plan 02)
5. `grep -c "WriteBatch|batch.commit|gBatch.commit" lib/data/repositories/auth_repository.dart` → **6** (2 from Plan 02 + 2 new from regenerate/delete)
6. `flutter test test/vault/ --no-pub` → **12/12 PASSED** (3 FP + 4 regenerate/delete + 2 updateLastVaultAccess + 3 stubs)
7. `flutter test test/security/ --no-pub` → **23/23 PASSED** — no regressions

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Unnecessary dart:typed_data import**
- **Found during:** Task 1 flutter analyze
- **Issue:** `import 'dart:typed_data'` caused `unnecessary_import` warning — `Uint8List` already re-exported by `flutter/foundation.dart`
- **Fix:** Removed the import
- **Files modified:** lib/data/repositories/auth_repository.dart
- **Commit:** d3a8b00

**2. [Rule 1 - Bug] Test instances called FirebaseAuth.instance without initialization**
- **Found during:** Task 1 TDD GREEN phase
- **Issue:** `AuthRepository(db: fakeFirestore, secure: ...)` without passing `auth:` triggers `FirebaseAuth.instance` in the constructor, which requires `Firebase.initializeApp()` — fails in unit test environment
- **Fix:** Added `MockFirebaseAuth` from `firebase_auth_mocks` (already in pubspec) to all 4 test instances; added `import 'package:firebase_auth_mocks/firebase_auth_mocks.dart'`; removed unused `import 'package:cloud_firestore/cloud_firestore.dart'`
- **Files modified:** test/vault/key_lifecycle_test.dart
- **Commit:** d3a8b00

**3. [Rule 1 - Bug] FlutterSecureStorage platform channel calls without binding**
- **Found during:** Task 1 TDD GREEN phase (after Rule 1 fix #2)
- **Issue:** `const FlutterSecureStorage()` calls platform channel methods (`write`, `delete`) which require `ServicesBinding` to be initialized — fails with "Binding has not yet been initialized"; `compute()` also requires binding
- **Fix:** Added `TestWidgetsFlutterBinding.ensureInitialized()` in `setUpAll`; replaced all `const FlutterSecureStorage()` with `FakeSecureStorage` from `test/mocks/mock_firebase.dart` (in-memory Map-backed fake, already in codebase)
- **Files modified:** test/vault/key_lifecycle_test.dart
- **Commit:** d3a8b00

**4. [Rule 2 - Missing critical functionality] TC-VAULT-07/07b tests absent for updateLastVaultAccess**
- **Found during:** Task 2 TDD RED phase
- **Issue:** No failing test existed for `updateLastVaultAccess` — the plan required TDD but the original key_lifecycle_test.dart only covered fingerprint + regenerate + delete
- **Fix:** Added TC-VAULT-07 (creates doc when absent, writes lastVaultAccessAt) and TC-VAULT-07b (merge preserves existing biometricGateEnabled and themeMode fields) to key_lifecycle_test.dart before implementing the method
- **Files modified:** test/vault/key_lifecycle_test.dart
- **Commit:** ae76d65

## TDD Gate Compliance

Both tasks followed RED/GREEN cycle:

| Task | RED commit | GREEN commit |
|------|-----------|-------------|
| Task 1 | Tests existed pre-implementation, confirmed compile errors | d3a8b00 |
| Task 2 | TC-VAULT-07/07b added and confirmed failing before implementation | ae76d65 |

Note: Task 1 RED and GREEN are in the same commit (d3a8b00) because the pre-existing tests in key_lifecycle_test.dart were committed in Plan 01 — the RED state was the compilation failure shown in verification output before implementation.

## Known Stubs

None — all four methods are fully implemented with real logic. No hardcoded empty values or placeholder behaviour.

## Threat Flags

None — no new network endpoints beyond the planned AuthRepository → Firestore boundary. All three threat mitigations from the plan's STRIDE register are implemented:

- **T-03-03-01 (partial key rotation):** `regenerateKeyPair` writes new private key to SecureStorage FIRST, then commits Firestore batch — old key superseded before public key update
- **T-03-03-02 (audit log tampering):** Only `set()` with auto-generated doc IDs used on audit refs — no `update()` call anywhere on audit docs
- **T-03-03-05 (pre-Phase-03 users):** `updateLastVaultAccess` uses `SetOptions(merge: true)` creating doc if absent; `NetworkException` wraps `FirebaseException`

## Self-Check: PASSED

Files exist:
- FOUND: lib/data/repositories/auth_repository.dart (contains `computeFingerprint`, `regenerateKeyPair`, `deleteKeyPair`, `updateLastVaultAccess`)
- FOUND: test/vault/key_lifecycle_test.dart (contains TC-VAULT-FP-01/02/03, TC-VAULT-02/02b, TC-VAULT-03/03b, TC-VAULT-07/07b)

Commits exist:
- FOUND: d3a8b00 (feat — computeFingerprint, regenerateKeyPair, deleteKeyPair)
- FOUND: ae76d65 (feat — updateLastVaultAccess)
