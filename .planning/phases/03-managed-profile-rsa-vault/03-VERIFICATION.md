---
phase: 03-managed-profile-rsa-vault
verified: 2026-05-03T00:00:00Z
status: gaps_found
score: 18/19 must-haves verified
overrides_applied: 0
gaps:
  - truth: "When publicKey is present: View section shows algorithm (RSA-2048), fingerprint (first 16 hex chars uppercase), and lastVaultAccessAt from profile/preferences"
    status: partial
    reason: "RsaKeyManagerScreen shows Algorithm and Fingerprint rows correctly but does NOT display lastVaultAccessAt. The streamUserProfile() method only streams users/{uid} — it does not read the profile/preferences subcollection. UserModel has no lastVaultAccessAt field. The timestamp is written to Firestore by updateLastVaultAccess() but never surfaced in the vault UI."
    artifacts:
      - path: "lib/presentation/vault/rsa_key_manager_screen.dart"
        issue: "No _KeyInfoRow for lastVaultAccessAt; _buildVaultBody() renders Algorithm and Fingerprint only"
      - path: "lib/data/models/user_model.dart"
        issue: "UserModel lacks a lastVaultAccessAt field; streamUserProfile() cannot carry this value without schema change or a separate subcollection stream"
    missing:
      - "Add a Stream<Map<String,dynamic>?> for users/{uid}/profile/preferences to RsaKeyManagerScreen (or extend UserModel)"
      - "Render lastVaultAccessAt as a _KeyInfoRow in _buildVaultBody() when key is present (display formatted DateTime or 'Never')"
---

# Phase 03: Managed Profile & RSA Vault — Verification Report

**Phase Goal:** Implement a biometric-gated RSA Key Manager (Vault) as a zero-remanence proof-check, initialize a `profile` subcollection on user creation, and harden Firestore security rules for the new `rsa_key_manager` subcollection.
**Verified:** 2026-05-03T00:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `flutter analyze --no-pub` exits 0 with no issues | VERIFIED | Analyzer output: "No issues found!" — confirmed by running `flutter analyze --no-pub` |
| 2 | `test/vault/` directory exists with four test files | VERIFIED | 4 files: vault_gate_test.dart, key_lifecycle_test.dart, profile_init_test.dart, receiver_banner_test.dart — all present |
| 3 | `FirebaseConstants.rsaKeyManager` and `FirebaseConstants.profile` constants exist | VERIFIED | Lines 15–16 of `firebase_constants.dart`: `static const String rsaKeyManager = 'rsa_key_manager'` and `static const String profile = 'profile'` |
| 4 | `AppTheme.textMain` and `AppTheme.textSecondary` static const aliases exist | VERIFIED | Lines 20–21 of `app_theme.dart`: `static const Color textMain = darkTextMain` and `static const Color textSecondary = darkTextSecondary` |
| 5 | `register()` uses `WriteBatch` to atomically write `users/{uid}` + `users/{uid}/profile/preferences` | VERIFIED | `auth_repository.dart` lines 64–90: `final batch = _db.batch()` writes both docs; `await batch.commit()` is atomic |
| 6 | `signInWithGoogle()` uses `WriteBatch` for same atomic write on new users | VERIFIED | `auth_repository.dart` lines 157–183: `final gBatch = _db.batch()` writes user doc + profile/preferences; `await gBatch.commit()` |
| 7 | `profile/preferences` initial values correct (biometricGateEnabled=false, themeMode='dark', nulls) | VERIFIED | Both `register()` and `signInWithGoogle()` batch.set the preferences doc with these exact four fields |
| 8 | `AuthRepository.computeFingerprint()` is a static method returning 64-char hex SHA-256 | VERIFIED | `auth_repository.dart` lines 251–256: `static String computeFingerprint(String publicKeyJson)` using `SHA256Digest`; tested by TC-VAULT-FP-01/02/03 |
| 9 | `regenerateKeyPair(uid)` exists with 3-doc WriteBatch (publicKey + audit + keyVaultCreatedAt) | VERIFIED | `auth_repository.dart` lines 262–291: 3-doc batch with `batch.update(userRef, {'publicKey': pubKeyJson})`, `batch.set(auditRef, ...)`, `batch.set(prefsRef, {keyVaultCreatedAt: ...}, SetOptions(merge: true))` |
| 10 | `deleteKeyPair(uid)` exists with 2-doc WriteBatch (publicKey delete + audit) | VERIFIED | `auth_repository.dart` lines 297–311: 2-doc batch; no keyVaultCreatedAt written on delete |
| 11 | `updateLastVaultAccess(uid)` uses `set(merge:true)` safe for pre-Phase-03 users | VERIFIED | `auth_repository.dart` lines 332–348: `SetOptions(merge: true)` with error handling; tested by TC-VAULT-07/07b |
| 12 | `RsaKeyManagerScreen` opens and immediately fires `BiometricHelper.authenticate()` via `addPostFrameCallback` | VERIFIED | `rsa_key_manager_screen.dart` lines 27–41: `WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate())` in `initState` |
| 13 | On gate failure `Navigator.pop(context)` is called; on pass `updateLastVaultAccess()` is called | VERIFIED | `_authenticate()` at lines 32–41: `if (!ok) { Navigator.pop(context); return; }` then `_updateLastVaultAccess()` |
| 14 | `RsaKeyManagerScreen` uses `SecurityLifecycleMixin` | VERIFIED | Class declaration: `class _RsaKeyManagerScreenState extends State<RsaKeyManagerScreen> with SecurityLifecycleMixin<RsaKeyManagerScreen>` |
| 15 | `CrypButton` used for Regenerate and Delete vault actions | VERIFIED | Lines 325 and 337 of `rsa_key_manager_screen.dart`: two `CrypButton` usages (Generate/Regenerate + Delete) |
| 16 | Fingerprint delegates to `AuthRepository.computeFingerprint()` with no duplicated SHA-256 in UI layer | VERIFIED | `_fingerprint()` at lines 55–58 delegates to `AuthRepository.computeFingerprint(publicKeyJson)` |
| 17 | View section shows Algorithm (RSA-2048) and fingerprint; **does NOT show lastVaultAccessAt** | PARTIAL | `_buildVaultBody()` renders `_KeyInfoRow(label: 'Algorithm', value: 'RSA-2048')` and `_KeyInfoRow(label: 'Fingerprint', ...)` only — `lastVaultAccessAt` is absent. Plan 03-04 must_have requires it. |
| 18 | ReceiverScreen Step 1 shows amber warning banner "No RSA keys found — tap to generate" with vault navigation | VERIFIED | `receiver_screen.dart` lines 414–428: amber `Container` + `GestureDetector` with `RsaKeyManagerScreen` push and `.then((_) => _checkKeyStatus())` |
| 19 | SidebarDrawer "Key Vault" entry; old `_KeyGenDialog`/`_Status`/`_showKeyGenDialog` removed | VERIFIED | `sidebar_drawer.dart` line 94: `title: const Text('Key Vault')` navigates to `RsaKeyManagerScreen`; grep for old class/enum/method returns 0 matches |
| 20 | `firestore.rules` has `rsa_key_manager` block with `update: if false` (IMMUTABLE) and action validation | VERIFIED | `firestore.rules` lines 91–100: `match /rsa_key_manager/{logId}` with `allow update: if false` and `action in ['generated', 'regenerated', 'deleted']` |
| 21 | `firestore.rules` has `profile` block with owner create/update and admin delete | VERIFIED | `firestore.rules` lines 102–109: `match /profile/{prefId}` with `allow create: if isOwner(userId)` and `allow update: if isOwner(userId) || isAdmin()` |

**Score:** 18/19 truths verified (1 partial/failed — lastVaultAccessAt display)

---

### Deferred Items

None identified.

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/app_theme.dart` | `textMain` and `textSecondary` static const aliases | VERIFIED | Lines 20–21 present |
| `test/vault/vault_gate_test.dart` | VAULT-01 biometric gate test stub | VERIFIED | TC-VAULT-01-stub passes |
| `test/vault/key_lifecycle_test.dart` | VAULT-02/03 key lifecycle tests | VERIFIED | Full tests (not stubs): TC-VAULT-FP-01/02/03, TC-VAULT-02/02b, TC-VAULT-03/03b, TC-VAULT-07/07b all pass |
| `test/vault/profile_init_test.dart` | VAULT-05 profile subcollection test stub | VERIFIED | TC-VAULT-05-stub passes |
| `test/vault/receiver_banner_test.dart` | VAULT-06 receiver banner visibility test | VERIFIED | TC-VAULT-06-stub passes |
| `lib/core/constants/firebase_constants.dart` | `rsaKeyManager` and `profile` string constants | VERIFIED | Lines 15–16 present |
| `lib/data/repositories/auth_repository.dart` | `register()` and `signInWithGoogle()` with WriteBatch; `computeFingerprint()`, `regenerateKeyPair()`, `deleteKeyPair()`, `updateLastVaultAccess()` | VERIFIED | All 4 lifecycle methods + 2 WriteBatch registrations confirmed |
| `lib/presentation/vault/rsa_key_manager_screen.dart` | Biometric-gated RSA Key Vault screen with CrypButton actions | PARTIAL | Screen exists with gate, StreamBuilder, fingerprint, CrypButtons — missing `lastVaultAccessAt` display |
| `lib/presentation/receiver/receiver_screen.dart` | Amber no-keys banner in Step 1 | VERIFIED | Banner present at line 422 |
| `lib/presentation/home/sidebar_drawer.dart` | Key Vault drawer entry; old dialog classes removed | VERIFIED | Key Vault ListTile present; no legacy code found |
| `firestore.rules` | `rsa_key_manager` and `profile` subcollection rules inside `match /users/{userId}` | VERIFIED | Both blocks present with correct permissions |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `lib/app_theme.dart` | `receiver_screen.dart` (and others) | `AppTheme.textMain` reference resolved | WIRED | `static const Color textMain = darkTextMain` resolves the 17 analyzer errors |
| `lib/presentation/admin/admin_dashboard.dart` | `lib/app_theme.dart` | `import '../../app_theme.dart'` added | WIRED | Import present in admin_dashboard.dart |
| `auth_repository.dart register()` | `Firestore users/{uid}/profile/preferences` | `WriteBatch.set()` with `FirebaseConstants.profile` | WIRED | Confirmed at lines 77–89 |
| `auth_repository.dart signInWithGoogle()` | `Firestore users/{uid}/profile/preferences` | `WriteBatch.set()` with `FirebaseConstants.profile` | WIRED | Confirmed at lines 170–183 |
| `auth_repository.dart regenerateKeyPair()` | `Firestore users/{uid}/rsa_key_manager` | `WriteBatch.set()` with `FirebaseConstants.rsaKeyManager` | WIRED | `auditRef = userRef.collection(FirebaseConstants.rsaKeyManager).doc()` at line 278 |
| `auth_repository.dart regenerateKeyPair()` | `Firestore users/{uid}/profile/preferences` | `WriteBatch.set({keyVaultCreatedAt: ...}, merge: true)` | WIRED | `prefsRef` batch.set at lines 288–289 |
| `auth_repository.dart deleteKeyPair()` | `FlutterSecureStorage` | `_secure.delete(key: FirebaseConstants.privateKeyStorageKey)` | WIRED | Line 298 |
| `RsaKeyManagerScreen.initState` | `BiometricHelper.authenticate()` | `addPostFrameCallback → _authenticate()` | WIRED | Lines 27–41 |
| `RsaKeyManagerScreen._authenticate()` | `AuthRepository.updateLastVaultAccess()` | Called after gate passes | WIRED | Line 40 |
| `RsaKeyManagerScreen body` | `AuthRepository.streamUserProfile(uid)` | `StreamBuilder<UserModel?>` | WIRED | Lines 251–262 |
| `RsaKeyManagerScreen._onRegenerate()` | `AuthRepository.regenerateKeyPair(uid)` | Biometric gate + confirmation dialog + repository call | WIRED | Line 83 |
| `RsaKeyManagerScreen._onDelete()` | `AuthRepository.deleteKeyPair(uid)` | Biometric gate + confirmation dialog + repository call | WIRED | Line 121 |
| `RsaKeyManagerScreen._fingerprint()` | `AuthRepository.computeFingerprint()` | Static method call — no SHA-256 in presentation layer | WIRED | Line 56 |
| `ReceiverScreen._step1Content() banner tap` | `RsaKeyManagerScreen` | `Navigator.push + .then(_checkKeyStatus)` | WIRED | Lines 392–415 (both banner tap and Regenerate button) |
| `SidebarDrawer Key Vault ListTile` | `RsaKeyManagerScreen` | `Navigator.pop(context)` then `Navigator.push(RsaKeyManagerScreen)` | WIRED | Lines 94–103 |
| `firestore.rules rsa_key_manager block` | `AuthRepository.regenerateKeyPair() Firestore write` | `action in ['generated', 'regenerated', 'deleted']` create rule | WIRED | Lines 91–100 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `rsa_key_manager_screen.dart` | `user` (UserModel?) | `_authRepo.streamUserProfile(uid)` → Firestore `users/{uid}` | Yes — real Firestore snapshot stream | FLOWING |
| `rsa_key_manager_screen.dart` | `hasKey` | derived from `user?.publicKey != null` | Yes — reactive to Firestore writes | FLOWING |
| `rsa_key_manager_screen.dart` | `lastVaultAccessAt` | NOT FETCHED — no subcollection stream for `profile/preferences` | No — not fetched at all | DISCONNECTED |

---

### Behavioral Spot-Checks

| Behavior | Check | Result | Status |
|----------|-------|--------|--------|
| `flutter analyze --no-pub` exits 0 | Ran directly | "No issues found!" | PASS |
| All vault tests pass | `flutter test test/vault/ --no-pub` | 12/12 passed (TC-VAULT-01-stub, FP-01/02/03, 02/02b, 03/03b, 05-stub, 06-stub, 07/07b) | PASS |
| Security regression tests pass | `flutter test test/security/ --no-pub` | 23/23 passed | PASS |
| `AppTheme.textMain` alias exists | grep `lib/app_theme.dart` | `static const Color textMain = darkTextMain` at line 20 | PASS |
| `rsaKeyManager` constant exists | grep `firebase_constants.dart` | `static const String rsaKeyManager = 'rsa_key_manager'` at line 15 | PASS |
| `WriteBatch` in `register()` and `signInWithGoogle()` | grep `auth_repository.dart` | 4 matches: `batch`, `gBatch`, `batch.commit()`, `gBatch.commit()` | PASS |
| `computeFingerprint` is static | grep `auth_repository.dart` | `static String computeFingerprint(String publicKeyJson)` at line 251 | PASS |
| `rsa_key_manager` Firestore rule with `update: if false` | grep `firestore.rules` | line 98: `allow update: if false;       // IMMUTABLE` | PASS |
| Old sidebar dialog code removed | grep `sidebar_drawer.dart` | 0 matches for `_KeyGenDialog`, `_showKeyGenDialog`, `enum _Status` | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| VAULT-01 | 03-01, 03-04 | Biometric gate on vault screen | SATISFIED | `BiometricHelper.authenticate()` via `addPostFrameCallback` in `RsaKeyManagerScreen.initState()` |
| VAULT-02 | 03-01, 03-03, 03-04 | Key regeneration with audit log | SATISFIED | `regenerateKeyPair()` with 3-doc WriteBatch; CrypButton Regenerate in vault screen |
| VAULT-03 | 03-01, 03-03, 03-04 | Key deletion with audit log | SATISFIED | `deleteKeyPair()` with 2-doc WriteBatch; CrypButton Delete in vault screen |
| VAULT-04 | 03-05 | Primary vault entry point | SATISFIED | `SidebarDrawer` "Key Vault" ListTile navigates to `RsaKeyManagerScreen` |
| VAULT-05 | 03-01, 03-02 | Profile subcollection init on registration | SATISFIED | `register()` and `signInWithGoogle()` use WriteBatch with `profile/preferences` |
| VAULT-06 | 03-01, 03-05 | Receiver banner when no RSA keys | SATISFIED | Amber banner in `ReceiverScreen._step1Content()` else branch |
| VAULT-07 | 03-02, 03-03, 03-04, 03-05 | Firestore security rules for new subcollections | SATISFIED | `rsa_key_manager` (immutable, action-validated) and `profile` (owner-writable) rules in `firestore.rules` |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `lib/presentation/vault/rsa_key_manager_screen.dart` | 251–263 | `StreamBuilder` only streams `users/{uid}` — `profile/preferences` subcollection data (`lastVaultAccessAt`) is never fetched | Warning | `lastVaultAccessAt` display requirement from Plan 03-04 not met; vault displays only Algorithm + Fingerprint |

---

### Human Verification Required

#### 1. Biometric Gate Pop on Failure

**Test:** On a device/emulator with biometric auth configured (or BiometricHelper returning false), navigate to `RsaKeyManagerScreen`. The screen should immediately show a spinner then pop back.
**Expected:** Screen appears briefly, biometric prompt fires, on cancel/failure the screen closes and user returns to the originating screen.
**Why human:** `BiometricHelper.authenticate()` is currently stubbed to always return `true` (pre-Viva bypass per CLAUDE.md). The gate wiring is correct in code (`addPostFrameCallback` + `Navigator.pop(context)` on failure) but cannot be triggered by a test without a real/mock biometric service.

#### 2. Vault Key Regeneration End-to-End

**Test:** On a device/emulator authenticated to Firestore, open the vault screen, tap "Generate Keys" (or "Regenerate Keys"). Confirm the regeneration dialog. Observe that the vault shows the new fingerprint.
**Expected:** RSA-2048 pair generated, private key in SecureStorage, public key updated in Firestore `users/{uid}`, `rsa_key_manager` audit doc appended, vault screen reflects new fingerprint within 1–2 seconds via the StreamBuilder.
**Why human:** RSA key generation runs in a `compute()` isolate. The full round-trip (generate + batch commit + stream update → fingerprint refresh) requires live Firestore and SecureStorage, which are not exercisable in unit tests.

#### 3. Firestore Rules Enforcement

**Test:** Using Firebase Emulator or a test project, attempt to UPDATE an existing `rsa_key_manager` document as the owner. Attempt to CREATE a `rsa_key_manager` document with `action: 'invalid_action'`.
**Expected:** Both operations are rejected by Firestore rules (`update: if false` and action field validation).
**Why human:** Firestore rules can only be tested against the emulator or live Firebase — not verifiable through static code analysis.

---

### Gaps Summary

One gap blocks full verification of the phase's vault UI must-have:

**Gap 1: `lastVaultAccessAt` not displayed in RsaKeyManagerScreen**

Plan 03-04 explicitly requires: "When publicKey is present: View section shows algorithm (RSA-2048), fingerprint (first 16 hex chars uppercase), and **lastVaultAccessAt from profile/preferences**."

The vault screen (`rsa_key_manager_screen.dart`) renders Algorithm and Fingerprint correctly but never fetches or displays `lastVaultAccessAt`. Two structural blockers:

1. `streamUserProfile()` streams only `users/{uid}` — it does not read the `profile` subcollection. `lastVaultAccessAt` lives in `users/{uid}/profile/preferences`, which is a separate Firestore document.
2. `UserModel` has no `lastVaultAccessAt` field — even if the stream were extended, the model cannot carry this value.

**Root cause:** The screen would need either (a) a second `StreamBuilder` on `FirebaseFirestore.instance.collection('users').doc(uid).collection('profile').doc('preferences').snapshots()`, or (b) an extension of `UserModel` + `streamUserProfile()` to merge subcollection data.

This is a display-only gap and does not affect the core security functionality (biometric gate, key lifecycle, Firestore audit log). The timestamp IS written correctly by `updateLastVaultAccess()` and `regenerateKeyPair()` — it just is not surfaced in the UI.

All other 18 must-haves from Plans 03-01 through 03-05 are VERIFIED against the actual codebase.

---

_Verified: 2026-05-03T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
