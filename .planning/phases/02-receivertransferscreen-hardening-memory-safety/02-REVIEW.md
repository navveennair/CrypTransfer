---
phase: 02-receivertransferscreen-hardening-memory-safety
reviewed: 2026-04-20T00:00:00Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/presentation/receiver/receiver_transfer_screen.dart
  - lib/presentation/receiver/receiver_screen.dart
  - lib/presentation/sender/sender_screen.dart
findings:
  critical: 2
  warning: 3
  info: 2
  total: 7
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-04-20
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

This review covers the Phase 02 hardening work: wiring `SessionManager` into `ReceiverTransferScreen` for kill-switch propagation, and fixing a memory-safety issue in `SenderScreen` related to `FilePicker.pickFiles(withData: true)`.

The most significant finding is that **neither hardening goal was fully implemented in the reviewed code**. `ReceiverTransferScreen` has no `SessionManager`, no `SecurityLifecycleMixin`, and no kill-switch handler — the screen is completely blind to `SessionState.terminated`. `SenderScreen` still passes `withData: true` to `FilePicker.pickFiles`, loading the entire file into RAM on mobile/desktop and bypassing the 64 KB chunked `TransferService.resolve` path that was wired in on the same screen.

Additionally, a secondary bug exists in `_encryptFile`: a guard `file.bytes == null` causes a silent no-op return when `withData: kIsWeb` is correctly set and a non-web path is used, because `file.bytes` will then be `null` on mobile.

---

## Critical Issues

### CR-01: ReceiverTransferScreen Has No Kill-Switch — SessionState.terminated Is Silently Dropped

**File:** `lib/presentation/receiver/receiver_transfer_screen.dart:40`
**Issue:** `_ReceiverTransferScreenState` mixes in only `SingleTickerProviderStateMixin`. It does not apply `SecurityLifecycleMixin`, does not receive a `SessionManager` reference, and has no `WidgetsBindingObserver`. When the receiver backgrounds the app mid-transfer, `ReceiverScreen.didChangeAppLifecycleState` calls `SessionManager.wipeSession()` — the state transitions to `SessionState.terminated` and `EncryptionService.closeReceiverSession()` fires reactively — but `ReceiverTransferScreen` has no listener on `stateNotifier` or `stateStream`. The screen continues rendering with a live `_bounceCtrl` animation and an active "Proceed to Decrypt" path, presenting a broken UX and leaving the screen on the navigation stack after all crypto credentials have been revoked. This directly contradicts the CLAUDE.md Known Open Issue and the stated Phase 02 goal.

**Fix:**
```dart
// 1. Add SessionManager constructor parameter:
class ReceiverTransferScreen extends StatefulWidget {
  final String transferId;
  final String fileName;
  final SessionManager sessionManager; // ADD THIS

  const ReceiverTransferScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.sessionManager, // ADD THIS
  });
  ...
}

// 2. Apply SecurityLifecycleMixin and listen to stateNotifier in State:
class _ReceiverTransferScreenState extends State<ReceiverTransferScreen>
    with SingleTickerProviderStateMixin, SecurityLifecycleMixin<ReceiverTransferScreen> {

  @override
  void initState() {
    super.initState();
    ...
    widget.sessionManager.stateNotifier.addListener(_onSessionStateChanged);
  }

  @override
  void dispose() {
    widget.sessionManager.stateNotifier.removeListener(_onSessionStateChanged);
    _bounceCtrl.dispose();
    super.dispose(); // SecurityLifecycleMixin.dispose() → wipeAll()
  }

  void _onSessionStateChanged() {
    if (widget.sessionManager.state == SessionState.terminated && mounted) {
      wipeAll();
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
  ...
}

// 3. Pass sessionManager when navigating from ReceiverScreen._navigateToDecrypt():
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => ReceiverTransferScreen(
      transferId: id,
      fileName: name,
      sessionManager: _sessionManager, // ADD THIS
    ),
  ),
);
```

---

### CR-02: SenderScreen._pickFile() Uses withData: true — Entire File Loaded Into RAM on Mobile

**File:** `lib/presentation/sender/sender_screen.dart:153`
**Issue:** `FilePicker.pickFiles(withData: true)` is called unconditionally. On Android/iOS this eagerly reads the entire file into `PlatformFile.bytes`, placing the whole plaintext in heap memory regardless of file size. This directly contradicts the 64 KB chunked `TransferService.resolve` path that was wired in at line 194 — the chunked read is exercised only when `file.path != null`, but `file.bytes` is always populated due to `withData: true`, so the early guard at line 171 (`if (file == null || file.bytes == null) return;`) always passes and the encrypt path works — but via bytes, not the chunked path. The `withData: true` flag was supposed to be changed to `withData: kIsWeb` as part of Phase 02.

**Fix:**
```dart
// lib/presentation/sender/sender_screen.dart, line 153
// BEFORE:
final result = await FilePicker.pickFiles(withData: true);

// AFTER:
final result = await FilePicker.pickFiles(withData: kIsWeb);
```

Then also fix the guard in `_encryptFile` (line 171) — after the fix, `file.bytes` will be `null` on mobile, so the guard must be removed or changed:

```dart
// BEFORE (line 169-171):
Future<void> _encryptFile() async {
  final file = _file;
  if (file == null || file.bytes == null) return; // REMOVE file.bytes == null check

// AFTER:
Future<void> _encryptFile() async {
  final file = _file;
  if (file == null) return;
  // TransferService.resolve handles null bytes on mobile (uses file.path)
```

---

## Warnings

### WR-01: _encryptFile — Key and IV Registered Before FLAG_SECURE Guard, Not Wiped on Early Return

**File:** `lib/presentation/sender/sender_screen.dart:176-188`
**Issue:** `key` and `iv` are created and registered with `registerBuffer` at lines 176-178 before the `isFlagSecureActive()` check at line 183. If the check returns `false`, the method returns without zeroing `key` or `iv`. They will eventually be zeroed by `wipeAll()` on dispose, but they are not eagerly wiped on this specific early-exit path — the FLAG_SECURE failure path was designed to abort immediately, and leaving the buffers registered without zeroing them here is inconsistent with the defensive design.

**Fix:**
```dart
Future<void> _encryptFile() async {
  final file = _file;
  if (file == null) return;
  setState(() => _encrypting = true);

  // Run FLAG_SECURE check BEFORE allocating any sensitive bytes.
  if (!await SecurityLifecycleMixin.isFlagSecureActive()) {
    if (mounted) {
      setState(() => _encrypting = false);
      _showError(
        'Screen is not protected (FLAG_SECURE inactive). '
        'Cannot process file on an unsecured window.',
      );
    }
    return;
  }

  try {
    final key = _secureBytes(32);
    final iv = _secureBytes(12);
    registerBuffer(key);
    registerBuffer(iv);
    ...
```

---

### WR-02: ReceiverTransferScreen.PopScope Allows Back-Nav After _allStepsDone — No Wipe on Pop

**File:** `lib/presentation/receiver/receiver_transfer_screen.dart:148-149`
**Issue:** `PopScope(canPop: _allStepsDone, ...)` permits back-navigation once all steps complete. There is no `onPopInvokedWithResult` callback, so popping the screen performs no cleanup — no buffer wipe, no notification to `SessionManager`. If any sensitive context has been loaded (transfer metadata, sender identity), it is silently discarded without zeroing. With `SecurityLifecycleMixin` absent, `dispose()` does not call `wipeAll()` either.

**Fix:**
```dart
return PopScope(
  canPop: _allStepsDone,
  onPopInvokedWithResult: (didPop, _) {
    if (didPop) wipeAll(); // requires SecurityLifecycleMixin applied (see CR-01)
  },
  child: Scaffold(...),
);
```

---

### WR-03: _runSteps Timer Completes After dispose() — setState Called on Dead Widget If Animation Outlives Widget

**File:** `lib/presentation/receiver/receiver_transfer_screen.dart:105-121`
**Issue:** `_runSteps()` is a `Future<void>` with sequential `Future.delayed` calls totalling approximately 3.8 seconds. Each delay checks `if (!mounted) return`. However, `_bounceCtrl.dispose()` is called in `dispose()` while `_runSteps()` may still be in a `Future.delayed` await. `_bounceCtrl` is disposed first, and then if `_runSteps` resumes before the Dart event loop marks it done, the `setState` at line 120 (`_allStepsDone = true`) will fire on an unmounted widget — but the `if (mounted)` guard at line 120 does catch this. The real risk is that `AnimationController.dispose()` is called while `AnimatedBuilder` is still referencing it via the `_bounceAnim` animation. This can produce a "AnimationController used after dispose" Flutter framework error in the gap between `dispose()` completing and the pending `Future.delayed` waking up. The issue is benign in practice since `AnimatedBuilder` checks `mounted` before scheduling a frame, but it will produce console errors.

**Fix:**
```dart
// Cancel the steps future on dispose by tracking whether disposed:
bool _disposed = false;

@override
void dispose() {
  _disposed = true;
  _bounceCtrl.dispose();
  super.dispose();
}

Future<void> _runSteps() async {
  for (int i = 0; i < _steps.length; i++) {
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted || _disposed) return;
    setState(() => _steps[i].active = true);

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted || _disposed) return;
    setState(() {
      _steps[i].active = false;
      _steps[i].done = true;
    });
  }
  await Future.delayed(const Duration(milliseconds: 200));
  if (mounted && !_disposed) setState(() => _allStepsDone = true);
}
```

---

## Info

### IN-01: Stale UI Text in _KeyManagerSheet References Removed Step

**File:** `lib/presentation/receiver/receiver_screen.dart:1471`
**Issue:** `_EmptyHint` text reads `'Use "Share Public Key" (Step 3) to send it.'` — but the "Share Public Key" step was removed as part of the Receiver-Authorized Handshake refactor. This is dead instructional text that directs users to a UI element that no longer exists.

**Fix:**
```dart
// BEFORE:
'Your public key hasn\'t been sent to anyone yet.\n'
'Use "Share Public Key" (Step 3) to send it.',

// AFTER:
'Your public key will be shared automatically when you '
'select a sender and open a session.',
```

---

### IN-02: ReceiverTransferScreen Has No SecurityLifecycleMixin — dispose() Does Not Zero Buffers

**File:** `lib/presentation/receiver/receiver_transfer_screen.dart:79-82`
**Issue:** The current `dispose()` only calls `_bounceCtrl.dispose()`. There are no registered buffers at present because no sensitive data is stored in `Uint8List` fields on this screen. However, this is a structural gap — when `SessionManager` integration is added (per CR-01) and if any encrypted metadata is buffered here in future, `wipeAll()` will not be called on navigation away. The mixin should be applied proactively as a defence-in-depth measure, consistent with how it is applied to every other screen in the project.

**Fix:** Apply `SecurityLifecycleMixin` as described in CR-01. Once applied, `dispose()` automatically calls `wipeAll()` via the mixin's `dispose()` override.

---

_Reviewed: 2026-04-20_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
