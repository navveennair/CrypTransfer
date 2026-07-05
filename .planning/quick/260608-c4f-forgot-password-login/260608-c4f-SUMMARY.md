---
status: complete
quick_id: 260608-c4f
slug: forgot-password-login
phase: quick
plan: 260608-c4f
subsystem: auth
tags: [auth, firebase, password-reset, ui, bottom-sheet]
dependency_graph:
  requires: []
  provides: [forgot-password-flow]
  affects: [lib/data/repositories/auth_repository.dart, lib/presentation/auth/login_screen.dart]
tech_stack:
  added: []
  patterns: [StatefulBuilder bottom sheet, AuthRepository Firestore username lookup]
key_files:
  created: []
  modified:
    - lib/data/repositories/auth_repository.dart
    - lib/presentation/auth/login_screen.dart
decisions:
  - Username-based lookup (not email) for password reset, consistent with loginWithUsername pattern
  - StatefulBuilder bottom sheet keeps reset flow self-contained without a new screen
  - Success state leaves sheet open with green confirmation (user sees result without sheet closing)
metrics:
  duration: ~10 minutes
  completed: 2026-06-08T02:14:33Z
  tasks_completed: 2
  files_modified: 2
---

# Quick Task 260608-c4f: Forgot Password Summary

## One-liner

Username-to-email Firestore lookup feeds `FirebaseAuth.sendPasswordResetEmail`, surfaced via a glassmorphic bottom sheet on the login screen.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 | Add `sendPasswordResetEmail` to AuthRepository | a86f0bf | lib/data/repositories/auth_repository.dart |
| 2 | Add "Forgot password?" button and bottom sheet to LoginScreen | 341454d | lib/presentation/auth/login_screen.dart |

## What Was Built

### Task 1 — AuthRepository.sendPasswordResetEmail

Added `Future<void> sendPasswordResetEmail(String username)` after `loginWithUsername`:

1. Queries `users` collection where `username == username`, limit 1
2. Throws `AuthException('No account found with this username.', code: 'username-not-found')` if no results
3. Extracts and trims `email` field; throws `AuthException('Account data is corrupted.', code: 'account-data-corrupted')` if empty
4. Calls `_auth.sendPasswordResetEmail(email: email)`

### Task 2 — LoginScreen forgot password UI

- Added `_forgotPasswordController = TextEditingController()`, disposed in `dispose()`
- Added `_showForgotPasswordSheet(BuildContext context)` using `showModalBottomSheet` with `StatefulBuilder` for local `_loading`/`_error`/`_sent` state
- Bottom sheet layout: `GlassContainer(padding: 24, borderRadius: 28)` wrapping title, subtitle, username `TextField` (matching login form decoration), `CrypButton("Send Reset Link")`, and `Padding(viewInsets.bottom)` for keyboard avoidance
- Success state: green `check_circle_rounded` icon + "Reset email sent! Check your inbox." text replaces the form
- Error state: inline `errorText` on the `TextField` (empty validation shows "Required", AuthException shows message, unknown shows generic message)
- "Forgot password?" `TextButton` inserted right-aligned after the password field with `cs.primary` color, font size 12
- `SizedBox(height: 28)` before error/login button shrunk to `SizedBox(height: 4)` since the TextButton already provides spacing

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None.

## Threat Flags

None — password reset uses Firebase's own token-based email flow; no new attack surface introduced.

## Self-Check: PASSED

- `lib/data/repositories/auth_repository.dart` contains `sendPasswordResetEmail` method
- `lib/presentation/auth/login_screen.dart` contains `_showForgotPasswordSheet` and `Forgot password?` TextButton
- Commits a86f0bf and 341454d both exist in git log
- `flutter analyze lib/data/repositories/auth_repository.dart lib/presentation/auth/login_screen.dart` → No issues found
