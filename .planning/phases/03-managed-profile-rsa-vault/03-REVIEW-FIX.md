---
phase: 03-managed-profile-rsa-vault
fixed_at: 2026-05-03T00:00:00Z
review_path: .planning/phases/03-managed-profile-rsa-vault/03-REVIEW.md
iteration: 1
findings_in_scope: 7
fixed: 6
skipped: 1
status: partial
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-05-03T00:00:00Z
**Source review:** `.planning/phases/03-managed-profile-rsa-vault/03-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7
- Fixed: 6
- Skipped: 1

## Fixed Issues

### CR-02: Firestore `allow list: if true` exposes user data to unauthenticated clients

**Files modified:** `firestore.rules`
**Commit:** 6ea1abf
**Applied fix:** Changed `allow list: if true` to `allow list: if isAuthenticated()` on the `/users/{userId}` match block, preventing unauthenticated enumeration of all user records.

---

### WR-01: Race condition in `generateAndStoreKeyPair` — private key written before uid check

**Files modified:** `lib/data/repositories/auth_repository.dart`
**Commit:** e0b1898
**Applied fix:** Moved the `_auth.currentUser?.uid` check and null guard to the very top of `generateAndStoreKeyPair()`, before `compute()` and before any `_secure.write` call. If uid is null the method now throws `AuthException('Not authenticated.')` immediately, preventing the private key from being written to device storage when no authenticated user is present.

---

### WR-02: `_onToggleReady` swallows `uid == null` silently

**Files modified:** `lib/presentation/receiver/receiver_screen.dart`
**Commit:** e5726e4
**Applied fix:** Replaced the silent `return` on uid null with an explicit `setState(() => _isTogglingReady = false)` plus `_showError('Not authenticated.')` before returning, so the loading spinner is cleared and the user sees an error message.

---

### WR-03: `_transferStatusWidget` calls `_handleIncomingTransfer` without deduplication guard

**Files modified:** `lib/presentation/receiver/receiver_screen.dart`
**Commit:** ced9db3
**Applied fix:** Added `bool _incomingHandled = false` field to `_ReceiverScreenState`. In `_transferStatusWidget`'s StreamBuilder builder, the condition now checks `!_incomingHandled` in addition to `!_sessionLocked`, and sets `_incomingHandled = true` synchronously before scheduling the post-frame callback. This prevents multiple rapid Firestore snapshots from registering multiple callbacks before the first one fires.

---

### WR-04: Firestore `friendships` rule has dead `allow create` clause

**Files modified:** `firestore.rules`
**Commit:** eddeb18
**Applied fix:** Removed the unreachable `allow create: if isAuthenticated() && request.resource.data.uid == request.auth.uid` clause. Consolidated `allow read` and `allow write` into a single `allow read, write: if request.auth.uid == userId` line and added an explanatory comment documenting why the dead clause was removed.

---

### WR-05: `RsaKeyManagerScreen._onRegenerate` dismisses progress dialog incorrectly

**Files modified:** `lib/presentation/vault/rsa_key_manager_screen.dart`
**Commit:** 592b34a
**Applied fix:** Added `Navigator.canPop(context)` guard before `Navigator.pop(context)` in the `catch` block of `_onRegenerate`. If `regenerateKeyPair` throws before the progress dialog's first frame is pushed, the guarded pop is skipped instead of dismissing the vault screen.

---

## Skipped Issues

### CR-01: `dart:io Platform` used unconditionally in `lib/data/repositories/auth_repository.dart`

**File:** `lib/data/repositories/auth_repository.dart:2,286,308`
**Reason:** skipped: code context differs from review — fix already present in source. The file has no `dart:io` import and both `regenerateKeyPair` (line 285) and `deleteKeyPair` (line 307) already use `defaultTargetPlatform.name` from `flutter/foundation.dart`. The reviewed code state referenced by the finding does not match the current file state; the fix was applied prior to this review iteration.
**Original issue:** `dart:io Platform` import used unconditionally, crashing on Web/macOS builds.

---

_Fixed: 2026-05-03T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
