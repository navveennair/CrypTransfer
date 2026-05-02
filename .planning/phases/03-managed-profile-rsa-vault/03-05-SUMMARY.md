---
phase: 03-managed-profile-rsa-vault
plan: "05"
subsystem: vault-ui
tags: [flutter, rsa-vault, firestore-rules, receiver-screen, sidebar-drawer, navigation]

dependency_graph:
  requires:
    - 03-04 (RsaKeyManagerScreen — biometric-gated vault UI, CrypButton Regenerate/Delete)
  provides:
    - Amber warning banner in ReceiverScreen Step 1 when no RSA keys present
    - Key Vault drawer entry in SidebarDrawer replacing old Generate RSA Keys dialog
    - Firestore security rules: rsa_key_manager (immutable) and profile (owner-writable) subcollection blocks
  affects:
    - verifier (Phase 03 fully wired; all entry points to vault complete)

tech_stack:
  added: []
  patterns:
    - Amber warning banner pattern: GestureDetector wrapping a styled Container navigates to vault screen with .then(_checkKeyStatus) refresh
    - Dead-code removal: inline key gen path (_generateKeys, _showProgressDialog) eliminated; vault is sole key lifecycle surface (D-07)
    - Firestore append-only audit block: update:false + action field enum validation (mirrors audit_logs pattern)

key_files:
  created: []
  modified:
    - lib/presentation/receiver/receiver_screen.dart — amber no-keys banner; Regenerate navigates to vault; removed _generateKeys/_showProgressDialog
    - lib/presentation/home/sidebar_drawer.dart — Key Vault ListTile; removed _KeyGenDialog/_KeyGenDialogState/_Status/_showKeyGenDialog
    - firestore.rules — rsa_key_manager (IMMUTABLE) and profile subcollection rules inside match /users/{userId}

key_decisions:
  - "Removed _generateKeys() and _showProgressDialog() — both methods became unreachable after _step1Content() was updated; analyzer flagged them; removed as dead code (D-07: vault is sole key lifecycle surface)"
  - "Kept AuthRepository import in sidebar_drawer.dart — still used by streamUserProfile() for admin check and logout()"
  - "rsa_key_manager and profile rules placed after audit_logs block and before friendships block inside match /users/{userId} — mirrors existing append-only audit_logs pattern exactly"

patterns_established:
  - "Vault navigation pattern: Navigator.push(RsaKeyManagerScreen).then((_) => _checkKeyStatus()) — used in both ReceiverScreen banner tap and Regenerate button"
  - "Drawer Key Vault pattern: Navigator.pop(context) then Navigator.push(RsaKeyManagerScreen) — closes drawer before pushing vault"

requirements_completed: [VAULT-04, VAULT-06, VAULT-07]

duration: 5min
completed: "2026-05-02"
---

# Phase 03 Plan 05: Entry Points Wiring & Firestore Rules Summary

**Amber no-keys warning banner in ReceiverScreen, Key Vault drawer entry replacing old inline dialog, and server-side immutability + ownership rules for rsa_key_manager and profile subcollections — Phase 03 fully wired.**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-05-02T18:09:27Z
- **Completed:** 2026-05-02T18:17:00Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- ReceiverScreen Step 1 now shows an amber `GestureDetector` banner "No RSA keys found — tap to generate" when no key pair present; tapping navigates to `RsaKeyManagerScreen` and refreshes key status on return via `.then(_checkKeyStatus())`
- ReceiverScreen Regenerate button in the _step1Done branch also navigates to `RsaKeyManagerScreen` (D-07: vault is sole key lifecycle surface; inline key gen fully eliminated)
- SidebarDrawer "Key Vault" ListTile replaces old "Generate RSA Keys" entry; old `_KeyGenDialog` class, `_KeyGenDialogState`, `_Status` enum, and `_showKeyGenDialog` method removed entirely
- `firestore.rules` gains `rsa_key_manager` block (IMMUTABLE via `update: false`, create validates `action` field) and `profile` block (owner read/create/update, admin delete) inside `match /users/{userId}`
- `flutter analyze --no-pub` exits 0; all 35 vault + security tests pass

## Task Commits

Each task was committed atomically:

1. **Task 1: Wire ReceiverScreen no-keys banner and SidebarDrawer Key Vault entry** - `2626b29` (feat)
2. **Task 2: Add rsa_key_manager and profile subcollection rules to firestore.rules** - `b669214` (feat)

**Plan metadata:** (docs commit — next)

## Files Created/Modified

- `lib/presentation/receiver/receiver_screen.dart` — amber warning banner in `_step1Content()` else branch; Regenerate navigates to vault; import `../vault/rsa_key_manager_screen.dart` added; `_generateKeys()` and `_showProgressDialog()` removed
- `lib/presentation/home/sidebar_drawer.dart` — "Key Vault" ListTile with `RsaKeyManagerScreen` navigation; `_KeyGenDialog`, `_KeyGenDialogState`, `_Status`, `_showKeyGenDialog` all removed; import `../vault/rsa_key_manager_screen.dart` added
- `firestore.rules` — two new match blocks inside `match /users/{userId}`: `rsa_key_manager` (append-only, immutable) and `profile` (owner-writable)

## Decisions Made

- Removed `_generateKeys()` method — after replacing both call sites in `_step1Content()` with direct navigation to `RsaKeyManagerScreen`, the method became unreachable. Analyzer flagged `unused_element`. Removed per D-07 (vault is sole key lifecycle surface). The old inline `generateAndStoreKeyPair()` path is no longer reachable from any ReceiverScreen UI element.
- Removed `_showProgressDialog()` method — this was a helper used only by `_generateKeys()`; removing the latter made the former an unused declaration as well. Removed for cleanliness.
- Kept `AuthRepository` import in `sidebar_drawer.dart` — still actively used at two call sites: `AuthRepository().streamUserProfile(user.uid)` (admin visibility check) and `AuthRepository().logout()` (logout handler).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed unused `_generateKeys()` method**
- **Found during:** Task 1 (`flutter analyze` after initial edit)
- **Issue:** After replacing both call sites (`_step1Content()` else branch + Regenerate button) with direct navigation, `_generateKeys()` had zero references. Analyzer warned `unused_element`.
- **Fix:** Removed the entire `_generateKeys()` method body (44 lines)
- **Files modified:** `lib/presentation/receiver/receiver_screen.dart`
- **Verification:** `flutter analyze --no-pub` → No issues
- **Committed in:** `2626b29`

**2. [Rule 1 - Bug] Removed unused `_showProgressDialog()` method**
- **Found during:** Task 1 (second `flutter analyze` pass after removing `_generateKeys`)
- **Issue:** `_showProgressDialog()` was used only inside `_generateKeys()`; removing the latter left the former unreachable. Analyzer warned `unused_element`.
- **Fix:** Removed the `_showProgressDialog()` method body (15 lines)
- **Files modified:** `lib/presentation/receiver/receiver_screen.dart`
- **Verification:** `flutter analyze --no-pub` → No issues
- **Committed in:** `2626b29`

---

**Total deviations:** 2 auto-fixed (both Rule 1 — unused dead code cascading from the intended call-site replacement)
**Impact on plan:** Both auto-fixes expected consequences of D-07 enforcement. No scope creep. Inline key gen path completely eliminated.

## Issues Encountered

None — both tasks executed cleanly. The cascade of unused declarations (`_generateKeys` → `_showProgressDialog`) was resolved in two quick analyzer passes before committing Task 1.

## Known Stubs

None — all navigation wiring is fully functional. `BiometricHelper.authenticate()` remains stubbed (pre-Viva — see CLAUDE.md Roadmap), but this is intentional and documented in prior plan summaries.

## Threat Flags

None — no new network endpoints or auth paths introduced. Navigation wiring is UI-only (Navigator.push). Firestore rules only restrict access; they add no new write surfaces beyond what AuthRepository already performs.

## Next Phase Readiness

- Phase 03 (Managed Profile & RSA Vault) is fully complete across all 5 plans
- All three vault entry points wired: ReceiverScreen banner (D-05), SidebarDrawer Key Vault (D-04), RsaKeyManagerScreen Regenerate/Delete (D-07)
- Firestore server-side immutability enforced for audit log (D-11, D-17)
- Profile subcollection rules in place (D-18)
- `flutter analyze` clean; 35 tests green; `03-VALIDATION.md` set to `nyquist_compliant: true`

## Self-Check: PASSED

Files exist:
- FOUND: lib/presentation/receiver/receiver_screen.dart
- FOUND: lib/presentation/home/sidebar_drawer.dart
- FOUND: firestore.rules

Commits exist:
- FOUND: 2626b29 (feat(03-05): wire ReceiverScreen no-keys banner and SidebarDrawer Key Vault entry)
- FOUND: b669214 (feat(03-05): add rsa_key_manager and profile subcollection rules to firestore.rules)

---
*Phase: 03-managed-profile-rsa-vault*
*Completed: 2026-05-02*
