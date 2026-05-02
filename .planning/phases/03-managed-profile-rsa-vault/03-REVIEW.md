---
phase: 03-managed-profile-rsa-vault
reviewed: 2026-05-02T00:00:00Z
depth: standard
files_reviewed: 12
files_reviewed_list:
  - lib/app_theme.dart
  - lib/core/constants/firebase_constants.dart
  - lib/data/repositories/auth_repository.dart
  - lib/presentation/admin/admin_dashboard.dart
  - lib/presentation/home/sidebar_drawer.dart
  - lib/presentation/receiver/receiver_screen.dart
  - lib/presentation/vault/rsa_key_manager_screen.dart
  - firestore.rules
  - test/vault/vault_gate_test.dart
  - test/vault/key_lifecycle_test.dart
  - test/vault/profile_init_test.dart
  - test/vault/receiver_banner_test.dart
findings:
  critical: 2
  warning: 5
  info: 4
  total: 11
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-05-02T00:00:00Z
**Depth:** standard
**Files Reviewed:** 12
**Status:** issues_found

## Summary

Phase 03 adds the Managed Profile subcollection (`users/{uid}/profile`), RSA Key Vault screen with biometric gate, `regenerateKeyPair` / `deleteKeyPair` lifecycle in `AuthRepository`, and the `rsa_key_manager` audit subcollection. The Firestore rules were also extended to cover the new subcollections and the `handshakes` top-level collection.

Overall the architecture is sound and the security-critical paths (biometric gate, audit log immutability, secure-storage write ordering) are implemented correctly. Two critical issues were found — one a web/non-Android crash from an unconditional `dart:io Platform` import, and one a Firestore security rule that allows any unauthenticated actor to enumerate all user records. Five warnings cover races, missing guards, and a rule gap. Four informational items note dead code and test gaps.

---

## Critical Issues

### CR-01: `dart:io Platform` used unconditionally — crashes on Web/macOS builds

**File:** `lib/data/repositories/auth_repository.dart:2,286,308`

**Issue:** The file imports `dart:io show Platform` at line 2 and calls `Platform.operatingSystem` / `Platform.operatingSystemVersion` inside `regenerateKeyPair()` (line 286) and `deleteKeyPair()` (line 308) to record `deviceInfo` in the audit log. `dart:io` is not available on Flutter Web or certain CI runners. If the project ever runs on web or the CI runner is Linux-headless without the `dart:io` shim, both methods throw at runtime. The CLAUDE.md notes a planned Play Store release; web is not an explicit target, but the `transfer_service.dart` already uses a web/mobile branch (`resolve()`) — meaning web is partially supported.

**Fix:** Guard the platform read behind `kIsWeb` or replace with `defaultTargetPlatform`:
```dart
import 'package:flutter/foundation.dart'; // already transitively imported via compute

// inside regenerateKeyPair / deleteKeyPair:
final deviceInfo = kIsWeb
    ? 'web'
    : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
```
Or, to avoid the conditional entirely, use the already-imported `flutter/foundation.dart` only:
```dart
final deviceInfo = defaultTargetPlatform.name; // e.g. 'android', 'iOS'
```

---

### CR-02: Firestore rule `allow list: if true` exposes all user emails/phones to unauthenticated clients

**File:** `firestore.rules:24`

**Issue:** The `/users/{userId}` match block has `allow list: if true;`. A Firestore list/query against the `users` collection requires no authentication. Every user document contains `email`, `phone`, `username`, `isAdmin`, and `publicKey`. An unauthenticated attacker can enumerate all users including their email addresses and phone numbers by running `db.collection('users').get()` from any Firestore client. The comment says _"List is public so username lookup works before auth (login/register)"_ — but a list query is not required for username lookup; a targeted `where('username', isEqualTo, ...)` works under a narrower rule.

**Fix:** Restrict list to authenticated callers, or scope it further to queries that only expose the username field. The minimum-viable fix:
```
allow list: if isAuthenticated();
```
If unauthenticated username uniqueness checking (during registration) is genuinely needed, the preferred pattern is a Cloud Function that returns only a boolean — not a raw list of user documents. Alternatively, keep an unauthenticated-readable `usernames` collection that contains only `{username: uid}` mappings and remove the broad list permission from `users`.

---

## Warnings

### WR-01: Race condition in `generateAndStoreKeyPair` — private key written before `uid` is checked

**File:** `lib/data/repositories/auth_repository.dart:213-229`

**Issue:** `generateAndStoreKeyPair()` writes the private key to `FlutterSecureStorage` at line 218-221, then checks `_auth.currentUser?.uid` at line 223. If `currentUser` is null (e.g. concurrent sign-out between key generation and the uid check), the private key is written to device storage but the public key is never pushed to Firestore, leaving them permanently out of sync. The user now has a local private key that matches no known public key.

**Fix:** Check uid availability before any write:
```dart
Future<void> generateAndStoreKeyPair() async {
  final uid = _auth.currentUser?.uid;
  if (uid == null) throw AuthException('Not authenticated.');
  
  final pair = await compute(_generateKeyPairIsolate, null);
  // ... rest of writes
}
```
Note: `regenerateKeyPair(uid)` already receives `uid` as a parameter (correct pattern) — `generateAndStoreKeyPair` should follow the same convention.

---

### WR-02: `_onToggleReady` swallows `uid == null` silently

**File:** `lib/presentation/receiver/receiver_screen.dart:166-168`

**Issue:** When opening the mailbox (`value == true`), the method checks `uid == null` and returns early with `setState(() => _isTogglingReady = false)` absent (the finally block sets it to false only `if (mounted)`, which is fine), but more critically: if uid is null the loading spinner set at line 164 (`setState(() => _isTogglingReady = true)`) is never reset because the early return at line 167 exits before the `finally` clause. The user sees a permanently-spinning toggle switch with no error message.

**Fix:**
```dart
final uid = FirebaseAuth.instance.currentUser?.uid;
if (uid == null) {
  setState(() => _isTogglingReady = false);
  _showError('Not authenticated.');
  return;
}
```

---

### WR-03: `_transferStatusWidget` calls `_handleIncomingTransfer` from `addPostFrameCallback` without deduplication guard

**File:** `lib/presentation/receiver/receiver_screen.dart:531-535`

**Issue:** Every time the `StreamBuilder` rebuilds (which happens on each Firestore snapshot, including repeated snapshots of the same document), a new `addPostFrameCallback` is registered that calls `_handleIncomingTransfer`. The `_sessionLocked` guard inside `_handleIncomingTransfer` prevents multiple navigations once the first fires, but between the snapshot arriving and the next frame there is a window where `_sessionLocked` is still `false` and multiple callbacks could each read `_sessionLocked == false` before the first callback sets it to `true`. This is a benign race in practice (all callbacks run synchronously in the same frame), but if the stream emits two rapid snapshots for the same doc (e.g. pending → status update) the guard may not cover all cases.

**Fix:** Use a dedicated boolean flag that is set synchronously, before the post-frame callback fires, to prevent re-entry:
```dart
bool _incomingHandled = false; // class field

// inside StreamBuilder builder:
if (hasPending && !_sessionLocked && !_incomingHandled) {
  _incomingHandled = true; // set immediately, synchronously
  final doc = snap.data!.docs.first;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _handleIncomingTransfer(doc.id, doc.data());
  });
}
```

---

### WR-04: Firestore `friendships` rule has a `write` catch-all that overrides the narrower `create`

**File:** `firestore.rules:116-120`

**Issue:** The `friendships/{friendId}` match block contains both:
```
allow write: if request.auth.uid == userId;
allow create: if isAuthenticated() && request.resource.data.uid == request.auth.uid;
```
In Firestore security rules, `write` is a superset of `create`, `update`, and `delete`. The more specific `allow create` line is therefore dead code — the `allow write` already grants full write access to the owner. This means the intended constraint (`request.resource.data.uid == request.auth.uid`) on cross-user friendship creation is unenforced. Any authenticated user where `auth.uid == userId` can write any document, regardless of the `uid` field in the document.

More critically, the second `allow create` was presumably intended to allow _other_ users to add themselves to someone else's `friendships` subcollection. But the `allow write: if auth.uid == userId` already blocks that path for non-owners. The rule intent is ambiguous — clarify and remove the dead clause:
```
match /friendships/{friendId} {
  allow read, write: if request.auth.uid == userId;
  // Remove the dead 'allow create' — it is unreachable.
}
```
If cross-user create is genuinely needed, replace the `write` with explicit `read, update, delete` and keep only the narrowly scoped `create`.

---

### WR-05: `RsaKeyManagerScreen._onRegenerate` dismisses the progress dialog with `Navigator.pop` before confirming the pop targets the dialog

**File:** `lib/presentation/vault/rsa_key_manager_screen.dart:84-89`

**Issue:** `_showProgressDialog` calls `showDialog` without capturing the returned `Future`. On success, `Navigator.pop(context)` at line 85 is intended to close the progress dialog — but if `regenerateKeyPair` fails and throws before the dialog is shown (possible if `compute` throws immediately), the `Navigator.pop` in the `catch` block at line 92 pops the _underlying vault screen_ instead of the dialog, unexpectedly dismissing the screen.

Additionally, `_showProgressDialog` returns `void` (it fires `showDialog` but does not await it). There is no guarantee the dialog is even in the navigator stack by the time `Navigator.pop` is called in the catch branch (if `regenerateKeyPair` were to throw synchronously before the dialog's first frame).

**Fix:** Capture the dialog barrier and dismiss it by its route, or use a state variable:
```dart
setState(() => _regenerating = true);
try {
  _showProgressDialog('Generating RSA-2048 keypair…');
  await _authRepo.regenerateKeyPair(uid);
  if (mounted) {
    Navigator.pop(context); // dismiss dialog on success
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('RSA keys regenerated successfully.')),
    );
  }
} catch (e) {
  if (mounted) {
    // Only pop if dialog is open — check navigator can pop
    if (Navigator.canPop(context)) Navigator.pop(context);
    _showError(e.toString());
  }
}
```

---

## Info

### IN-01: `FirebaseConstants.auditLogs` constant is defined but not used in the reviewed files

**File:** `lib/core/constants/firebase_constants.dart:8`

**Issue:** `static const String auditLogs = 'audit_logs'` is defined, but the collection name used throughout the codebase is `transfer_logs` (via `transferLogs`). The `auditLogs` constant appears to be dead code left from an earlier naming iteration. It's separate from the per-user `users/{uid}/audit_logs` subcollection which uses Firestore path strings directly in `transfer_repository.dart`.

**Fix:** Verify whether `auditLogs` is referenced anywhere outside the reviewed files. If unused, remove the constant to avoid confusion between collection name variants.

---

### IN-02: `sidebar_drawer.dart` instantiates `AuthRepository()` on every build

**File:** `lib/presentation/home/sidebar_drawer.dart:107`

**Issue:** `AuthRepository().streamUserProfile(user.uid)` creates a new `AuthRepository` instance (and thus a new Firestore stream) every time `SidebarDrawer.build` is called. While the `StreamBuilder` handles the stream lifecycle, rebuilding the parent widget (e.g. theme change, MediaQuery change) will create a fresh stream, causing a brief flicker as `snapshot.data` resets to `null` before the new stream emits.

**Fix:** Either hoist `AuthRepository` to a higher-level provider, or — at minimum — cache the stream reference. Since `SidebarDrawer` is a `StatelessWidget`, the simplest fix without adding state is to use a `const` cached singleton or pass the stream in as a constructor parameter.

---

### IN-03: Test stub `TC-VAULT-01` uses `// ignore: avoid_print` with a `print` statement

**File:** `test/vault/vault_gate_test.dart:17`

**Issue:** The stub test uses `print('✅ TC-VAULT-01-stub PASSED: ...')` with a `// ignore: avoid_print` suppression. The same pattern appears in `profile_init_test.dart:47` and `receiver_banner_test.dart:40`. These print calls add noise to CI output and the suppression comments signal that the linter rule is being bypassed intentionally. Test assertions are self-documenting via `expect` — print statements are redundant.

**Fix:** Remove the `print` calls and the corresponding `// ignore` suppressions in all three stub test files.

---

### IN-04: `key_lifecycle_test.dart` TC-VAULT-02b does not actually verify SecureStorage write

**File:** `test/vault/key_lifecycle_test.dart:115-142`

**Issue:** TC-VAULT-02b is labeled "regenerateKeyPair writes private key to FlutterSecureStorage" but the test body only checks that the method completes without throwing. The `FakeSecureStorage` mock is fully instrumented (read/write/delete all work in-memory) so a real assertion is feasible:
```dart
await repo.regenerateKeyPair(uid);
final stored = await fakeSecure.read(key: FirebaseConstants.privateKeyStorageKey);
expect(stored, isNotNull, reason: 'private key must be stored in FlutterSecureStorage');
expect(stored!.isNotEmpty, isTrue);
```
The current test would pass even if the `_secure.write` line were deleted from `regenerateKeyPair`.

**Fix:** Add the explicit `fakeSecure.read` assertion shown above. The `FakeSecureStorage` instance is already available in scope.

---

_Reviewed: 2026-05-02T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
