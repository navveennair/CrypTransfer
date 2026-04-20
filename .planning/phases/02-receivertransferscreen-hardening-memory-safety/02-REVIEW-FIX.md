---
phase: 02-receivertransferscreen-hardening-memory-safety
fixed_at: 2026-04-20T02:37:39Z
review_path: .planning/phases/02-receivertransferscreen-hardening-memory-safety/02-REVIEW.md
iteration: 1
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-04-20T02:37:39Z
**Source review:** .planning/phases/02-receivertransferscreen-hardening-memory-safety/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5 (CR-01, CR-02, WR-01, WR-02, WR-03)
- Fixed: 5
- Skipped: 0

---

## Fixed Issues

### CR-01: ReceiverTransferScreen Has No Kill-Switch — SessionState.terminated Is Silently Dropped

**Files modified:** `lib/presentation/receiver/receiver_transfer_screen.dart`, `lib/presentation/receiver/receiver_screen.dart`
**Commit:** ad84740
**Applied fix:**
- Added `SessionManager sessionManager` as a required constructor parameter to `ReceiverTransferScreen`.
- Applied `SecurityLifecycleMixin<ReceiverTransferScreen>` to `_ReceiverTransferScreenState` (alongside existing `SingleTickerProviderStateMixin`).
- In `initState()`, added `widget.sessionManager.stateNotifier.addListener(_onSessionStateChanged)`.
- Added `_onSessionStateChanged()` handler: when `SessionState.terminated` fires, sets `_cancelled = true`, calls `wipeAll()`, and calls `Navigator.of(context).popUntil((route) => route.isFirst)`.
- In `dispose()`, added `_disposed = true`, removed the listener, and kept `_bounceCtrl.dispose()` before `super.dispose()` (which now calls `wipeAll()` via the mixin).
- Updated `receiver_screen.dart` `_navigateToDecrypt()` to pass `sessionManager: _sessionManager` to the navigation push.

### CR-02: SenderScreen._pickFile() Uses withData: true — Entire File Loaded Into RAM on Mobile

**Files modified:** `lib/presentation/sender/sender_screen.dart`
**Commit:** b3c076d
**Applied fix:**
- Changed `FilePicker.pickFiles(withData: true)` to `FilePicker.pickFiles(withData: kIsWeb)` at line 153 — file bytes are now only eagerly loaded on web; mobile/desktop use the path-based `TransferService.resolve` chunked read path.
- Removed the `file.bytes == null` component of the early-return guard in `_encryptFile` (was `if (file == null || file.bytes == null) return;`). Guard is now `if (file == null) return;` with a comment noting `TransferService.resolve` handles null bytes via `file.path`.

### WR-01: _encryptFile — Key and IV Registered Before FLAG_SECURE Guard, Not Wiped on Early Return

**Files modified:** `lib/presentation/sender/sender_screen.dart`
**Commit:** b3c076d
**Applied fix:**
- Moved the `isFlagSecureActive()` check to before the `try` block and before any `_secureBytes` / `registerBuffer` calls.
- The early-return path now also calls `setState(() => _encrypting = false)` so the UI recovers cleanly.
- On the FLAG_SECURE failure path, no buffers are registered, so no orphaned registered-but-unwiped memory remains.

### WR-02: ReceiverTransferScreen.PopScope Allows Back-Nav After _allStepsDone — No Wipe on Pop

**Files modified:** `lib/presentation/receiver/receiver_transfer_screen.dart`
**Commit:** ad84740
**Applied fix:**
- Added `onPopInvokedWithResult: (didPop, _) { if (didPop) wipeAll(); }` to the existing `PopScope`. This is safe because `SecurityLifecycleMixin` is now applied via CR-01, so `wipeAll()` is available.

### WR-03: _runSteps Timer Completes After dispose() — setState Called on Dead Widget If Animation Outlives Widget

**Files modified:** `lib/presentation/receiver/receiver_transfer_screen.dart`
**Commit:** ad84740
**Applied fix:**
- Added `bool _disposed = false` field to state.
- Added `bool _cancelled = false` field (set by `_onSessionStateChanged` on kill-switch) which also blocks step progression.
- Set `_disposed = true` at the top of `dispose()` before `_bounceCtrl.dispose()`.
- All `if (!mounted)` guards in `_runSteps` updated to `if (!mounted || _disposed || _cancelled)`.
- Final `setState` at end of `_runSteps` guarded as `if (mounted && !_disposed && !_cancelled)`.

---

## Skipped Issues

None — all in-scope findings were successfully fixed.

---

_Fixed: 2026-04-20T02:37:39Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
