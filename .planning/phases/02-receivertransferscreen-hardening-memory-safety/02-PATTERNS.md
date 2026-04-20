# Phase 2: ReceiverTransferScreen Hardening + Memory Safety - Pattern Map

**Mapped:** 2026-04-17
**Files analyzed:** 3 (files to be modified)
**Analogs found:** 3 / 3

---

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/presentation/receiver/receiver_transfer_screen.dart` | screen (stateful widget) | event-driven (kill-switch reactive) | `lib/presentation/receiver/decrypt_screen.dart` | exact — same role, same security/lifecycle pattern |
| `lib/presentation/receiver/receiver_screen.dart` | screen (one-line caller change) | event-driven | self (existing) | n/a — one-line change |
| `lib/presentation/sender/sender_screen.dart` | screen (one-line logic change) | file-I/O | self (existing) | n/a — two-line change |

---

## Pattern Assignments

### `lib/presentation/receiver/receiver_transfer_screen.dart`

**Changes required:**
1. Add `SessionManager` as required constructor param (D-10, D-11)
2. Add `bool _cancelled = false` flag (D-02)
3. Change mixin declaration to include `SecurityLifecycleMixin` (D-06)
4. Add `ValueListenableBuilder` on `sessionManager.stateNotifier` for kill-switch pop (D-01, D-04, D-05)
5. Guard `_runSteps()` loop with `if (_cancelled || !mounted) return;` (D-02)
6. Add `onPopInvokedWithResult` to existing `PopScope` (D-09)

---

#### Pattern 1: SecurityLifecycleMixin application (mixin ordering)

**Analog:** `lib/presentation/receiver/decrypt_screen.dart` lines 45–46

```dart
class _DecryptScreenState extends State<DecryptScreen>
    with SecurityLifecycleMixin<DecryptScreen> {
```

**Apply to `receiver_transfer_screen.dart` as** (D-06 — SecurityLifecycleMixin last):
```dart
class _ReceiverTransferScreenState extends State<ReceiverTransferScreen>
    with SingleTickerProviderStateMixin, SecurityLifecycleMixin<ReceiverTransferScreen> {
```

**Why last:** Dart mixin linearization — `super.dispose()` in the State override chains `wipeAll()` before `SingleTickerProviderStateMixin` cleanup. Mixin order in the rest of the codebase (`DecryptScreen`, `SenderScreen`) always places `SecurityLifecycleMixin` as the final mixin.

---

#### Pattern 2: SessionManager constructor parameter

**Analog:** `lib/presentation/receiver/receiver_screen.dart` lines 96–109 (`_navigateToDecrypt`) — this is the single call site.

**Widget declaration pattern** — modelled after how `transferId` is already a required param:

```dart
// receiver_transfer_screen.dart — widget class (lines 14–26 current)
class ReceiverTransferScreen extends StatefulWidget {
  final String transferId;
  final String fileName;
  final SessionManager sessionManager;   // ADD THIS (D-11)

  const ReceiverTransferScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.sessionManager,        // ADD THIS
  });
```

**Caller update pattern** — `receiver_screen.dart` line 107 (D-10):
```dart
// BEFORE (line 107):
builder: (_) => ReceiverTransferScreen(transferId: id, fileName: name),

// AFTER:
builder: (_) => ReceiverTransferScreen(
  transferId: id,
  fileName: name,
  sessionManager: _sessionManager,
),
```

Note: `ReceiverTransferScreen` only holds a **reference** — it does NOT call `dispose()` on it. `ReceiverScreen` owns and disposes the instance (D-03).

---

#### Pattern 3: `_cancelled` flag + `_runSteps()` guard

**Analog:** `lib/presentation/receiver/receiver_screen.dart` — `bool _sessionLocked = false` pattern (line 48), used as a re-entry guard.

**Apply to `_ReceiverTransferScreenState`:**

```dart
// In state class field declarations (alongside _allStepsDone):
bool _cancelled = false;
```

**Guard in `_runSteps()`** — check added at each `await` yield point (D-02). Current `_runSteps()` is at lines 105–121:

```dart
Future<void> _runSteps() async {
  for (int i = 0; i < _steps.length; i++) {
    await Future.delayed(const Duration(milliseconds: 400));
    if (_cancelled || !mounted) return;          // ADD: explicit clean exit
    setState(() => _steps[i].active = true);

    await Future.delayed(const Duration(seconds: 1));
    if (_cancelled || !mounted) return;          // ADD: explicit clean exit
    setState(() {
      _steps[i].active = false;
      _steps[i].done = true;
    });
  }

  await Future.delayed(const Duration(milliseconds: 200));
  if (_cancelled || !mounted) return;            // ADD: explicit clean exit
  if (mounted) setState(() => _allStepsDone = true);
}
```

Position of check: **before each `setState` call**, immediately after every `await Future.delayed`. This mirrors how `_SenderScreenState._onHandshakeUpdate` (sender_screen.dart lines 124–160) guards `if (!mounted || _handshakeStatus != HandshakeStatus.verifying) return;` after its own `await Future.delayed`.

---

#### Pattern 4: Kill-switch `ValueListenableBuilder` — immediate pop on `terminated`

**Analog source:** `lib/core/utils/session_manager.dart` lines 36–37 — `stateNotifier` is a `ValueNotifier<SessionState>`.

**Listener pattern used in `ReceiverScreen`** (receiver_screen.dart lines 70, 79, 85–93):
```dart
// initState:
_sessionManager.stateNotifier.addListener(_onSessionStateChanged);
// dispose:
_sessionManager.stateNotifier.removeListener(_onSessionStateChanged);

void _onSessionStateChanged() {
  if (!mounted) return;
  setState(() {});
  if (_sessionManager.state == SessionState.decrypting && ...) {
    _navigateToDecrypt();
  }
}
```

**For `ReceiverTransferScreen` the decisions require `ValueListenableBuilder` wrapping the entire build tree** (D-01, D-04, D-05) — no equivalent currently exists in the codebase. This is the one genuinely new Flutter pattern. The `ValueNotifier<SessionState>` API is already present; only the widget wrapper is new.

**Pattern to implement** (wraps the outermost `PopScope` in `build()`):

```dart
@override
Widget build(BuildContext context) {
  final cs = Theme.of(context).colorScheme;

  return ValueListenableBuilder<SessionState>(
    valueListenable: widget.sessionManager.stateNotifier,
    builder: (context, sessionState, child) {
      // D-01: immediate pop the moment terminated fires
      if (sessionState == SessionState.terminated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // D-04: SnackBar before pop — ScaffoldMessenger is app-scoped,
          //        survives the route pop and appears on ReceiverScreen below.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transfer cancelled — session wiped'),  // D-05
            ),
          );
          // D-02: set _cancelled so _runSteps exits cleanly
          setState(() => _cancelled = true);
          Navigator.pop(context);
        });
      }
      return child!;
    },
    child: PopScope(
      // ... existing PopScope body
    ),
  );
}
```

**Why `addPostFrameCallback`:** `Navigator.pop` cannot be called during a build. `addPostFrameCallback` defers it to after the frame completes — this is the same technique used in `ReceiverScreen._transferStatusWidget` (receiver_screen.dart line 878).

```dart
// ReceiverScreen analog (lines 876–881):
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (mounted && !_sessionLocked) {
    _handleIncomingTransfer(doc.id, doc.data());
  }
});
```

---

#### Pattern 5: `onPopInvokedWithResult` on existing `PopScope` (D-09)

**Best analog:** `lib/presentation/receiver/decrypt_screen.dart` lines 242–246

```dart
// decrypt_screen.dart — exact pattern to copy:
return PopScope(
  canPop: _phase != _Phase.decrypting && !_saving,
  onPopInvokedWithResult: (didPop, _) {
    if (didPop) wipeAll();
  },
```

**Apply to `receiver_transfer_screen.dart`** — existing `PopScope` at line 148:

```dart
// BEFORE (line 148–150):
return PopScope(
  canPop: _allStepsDone,

// AFTER:
return PopScope(
  canPop: _allStepsDone,
  onPopInvokedWithResult: (didPop, _) {
    if (didPop && _allStepsDone) wipeAll();
  },
```

The `_allStepsDone` condition matches D-09. Second `wipeAll()` call from `dispose()` chain is safe — `SecurityLifecycleMixin.wipeAll()` clears `_radioactiveBuffers` on first pass; second call iterates an empty list (no-op).

---

#### Pattern 6: `dispose()` body — no manual `wipeAll()` needed (D-07)

**Analog:** `lib/presentation/sender/sender_screen.dart` lines 101–104

```dart
// sender_screen.dart:
@override
void dispose() {
  _handshakeSub?.cancel();
  super.dispose(); // SecurityLifecycleMixin.dispose() → wipeAll()
}
```

**Apply to `receiver_transfer_screen.dart`** — existing `dispose()` at lines 79–82. Keep as-is with the mixin applied:

```dart
@override
void dispose() {
  _bounceCtrl.dispose();
  super.dispose(); // chains: SecurityLifecycleMixin.dispose() → wipeAll() → SingleTickerProviderStateMixin.dispose()
}
```

No manual `wipeAll()` call needed. The mixin's `dispose()` override calls `wipeAll()` then `super.dispose()`, which continues up the mixin chain to `SingleTickerProviderStateMixin`. (D-07)

---

### `lib/presentation/receiver/receiver_screen.dart` — `_navigateToDecrypt()` (one-line change)

**Location:** lines 96–109

**Change:** Pass `_sessionManager` to `ReceiverTransferScreen` constructor (D-10).

```dart
// BEFORE (line 107):
builder: (_) => ReceiverTransferScreen(transferId: id, fileName: name),

// AFTER:
builder: (_) => ReceiverTransferScreen(
  transferId: id,
  fileName: name,
  sessionManager: _sessionManager,
),
```

No other changes to `receiver_screen.dart`. `_sessionManager` is already declared at line 30 and is in scope.

---

### `lib/presentation/sender/sender_screen.dart` — `_pickFile()` (two-line change)

**Location:** lines 184–199

**Current code (lines 184–199):**

```dart
Future<void> _pickFile() async {
  _wipeSensitiveData();
  try {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _file = result.files.first;
      _encryptedBytes = null;
      _aesKey = null;
      _iv = null;
      _encryptedAESKey = null;
    });
  } catch (e) {
    if (mounted) _showError('Could not open file picker: $e');
  }
}
```

**Change 1 — D-12:** `withData: true` → `withData: !kIsWeb`

Requires adding `import 'package:flutter/foundation.dart';` — already present at line 8 (`import 'package:flutter/foundation.dart';`). `kIsWeb` is exported from `foundation.dart`.

**Change 2 — D-13:** Null-path guard after `result.files.first` assignment.

**Pattern for null guard** — mirrors `_encryptFile()` guard at line 204:
```dart
// Existing guard analog in sender_screen.dart line 204:
if (file == null || file.bytes == null) return;
```

**Full replacement for `_pickFile()`:**

```dart
Future<void> _pickFile() async {
  _wipeSensitiveData();
  try {
    final result = await FilePicker.pickFiles(withData: !kIsWeb);   // D-12
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    // D-13: cloud URI edge case — both path and bytes can be null for
    // Google Drive/Gmail picks on Android.  Cheap guard prevents a crash
    // deeper in _encryptFile when TransferService.resolve finds no source.
    if (!kIsWeb && file.path == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "This file type isn't supported — try saving it locally first.",
            ),
          ),
        );
      }
      return;
    }
    setState(() {
      _file = file;
      _encryptedBytes = null;
      _aesKey = null;
      _iv = null;
      _encryptedAESKey = null;
    });
  } catch (e) {
    if (mounted) _showError('Could not open file picker: $e');
  }
}
```

**SnackBar style note:** Error SnackBars in `sender_screen.dart` use `_showError()` (which sets `backgroundColor: Theme.of(context).colorScheme.error`). This guard is a soft warning (user-recoverable), so plain `SnackBar` without a colour override is appropriate — consistent with the "info" snackbars used elsewhere (e.g., receiver_screen.dart line 251).

---

## Shared Patterns

### SecurityLifecycleMixin — apply defensively
**Source:** `lib/core/utils/security_lifecycle_mixin.dart`
**Apply to:** `ReceiverTransferScreen` (new application for this phase)
**Key methods:**
- `registerBuffer(Uint8List)` — register on creation
- `unregisterBuffer(Uint8List)` — after explicit early wipe
- `wipeAll()` — zeroes all registered buffers; safe to call multiple times
- `onBuffersWiped()` — override for additional post-wipe state cleanup
- `dispose()` — automatically calls `wipeAll()` then `super.dispose()`

`ReceiverTransferScreen` currently holds no sensitive `Uint8List` buffers — `wipeAll()` will be a no-op until future decrypt-adjacent code registers buffers here. Mixin is applied defensively (D-08).

### ScaffoldMessenger before Navigator.pop
**Source:** `lib/presentation/receiver/receiver_screen.dart` lines 282–288
**Apply to:** Kill-switch pop in `ReceiverTransferScreen.build()`

```dart
// receiver_screen.dart pattern:
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: const Text('Session closed. Public key deleted.'),
    backgroundColor: Colors.orange.shade700,
  ),
);
// ... then navigate
```

`ScaffoldMessenger` is app-scoped (not route-scoped), so the SnackBar survives the `Navigator.pop()` and renders on the `ReceiverScreen` below. Call `showSnackBar` **before** `Navigator.pop()` (D-04).

### `addPostFrameCallback` for deferred navigation
**Source:** `lib/presentation/receiver/receiver_screen.dart` lines 876–881
**Apply to:** `ValueListenableBuilder` builder callback in `ReceiverTransferScreen`

Cannot call `Navigator.pop` during a `build()` method execution. Defer via:
```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!mounted) return;
  // snackbar + pop here
});
```

### `_cancelled` / boolean re-entry guard pattern
**Source:** `lib/presentation/receiver/receiver_screen.dart` line 48 — `bool _sessionLocked = false`
**Apply to:** `bool _cancelled = false` in `ReceiverTransferScreen`

Single boolean field declared with other state flags. Set to `true` before any navigation that should abort async loops. Checked at every `await` yield point in the loop.

---

## No Analog Found

No files fall into this category. All three files have strong existing analogs:
- `receiver_transfer_screen.dart` → `decrypt_screen.dart` (exact role + security pattern match)
- Caller change in `receiver_screen.dart` → self (existing, one-line addition)
- `_pickFile` change in `sender_screen.dart` → self (existing, two-line modification)

---

## Imports Reference

### `receiver_transfer_screen.dart` — imports to add

```dart
// Already present — no new imports needed for most changes.
// ADD:
import '../../core/utils/session_manager.dart';  // SessionManager + SessionState (via export)
import 'package:flutter/foundation.dart';        // NOT needed here (kIsWeb is sender-only)
```

`SessionState` comes free via `session_manager.dart`'s `export 'session_state.dart';` directive (session_manager.dart line 8).

### `sender_screen.dart` — imports

`kIsWeb` is already available: `import 'package:flutter/foundation.dart';` is at line 8 of `sender_screen.dart`. No new import needed.

---

## Metadata

**Analog search scope:** `lib/presentation/`, `lib/core/utils/`
**Files scanned:** 9 source files read + grep across full `lib/`
**Pattern extraction date:** 2026-04-17
