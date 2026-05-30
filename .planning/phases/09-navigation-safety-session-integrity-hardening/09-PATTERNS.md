# Phase 9: Navigation Safety & Session Integrity Hardening - Pattern Map

**Mapped:** 2026-05-29
**Files analyzed:** 4 (2 modified, 2 new test files)
**Analogs found:** 4 / 4

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/presentation/receiver/receiver_screen.dart` | screen/widget | event-driven (PopScope + Firestore stream) | `lib/presentation/sender/sender_screen.dart` | exact — identical PopScope + step-gating pattern already live in sender |
| `lib/presentation/sender/sender_screen.dart` | screen/widget | event-driven (Firestore handshake stream) | `lib/presentation/receiver/receiver_screen.dart` | exact — AnimatedOpacity + IgnorePointer step-gating pattern already live in receiver |
| `test/security/navigation_guard_test.dart` | test | unit / state machine | `test/security/session_wipe_test.dart` | exact — same group/test structure, same SessionManager under test, same flutter_test import |
| `test/sender/stale_key_test.dart` | test | unit / state machine | `test/sender/transfer_progress_timeout_test.dart` | role-match — same directory, same stub-first test layout, same flutter_test import |

---

## Pattern Assignments

### `lib/presentation/receiver/receiver_screen.dart` (Gap 1 + Gap 4)

**Analog:** `lib/presentation/sender/sender_screen.dart` (lines 639–675 for PopScope; lines 756–791 for AnimatedOpacity/IgnorePointer)

---

#### Gap 1 — PopScope pattern (copy from sender_screen.dart lines 639–675)

The existing `ReceiverScreen` PopScope (lines 644–655) has `canPop: true` unconditionally and executes wipe logic only in the `didPop == true` branch (after the pop has already occurred). The sender file shows the correct conditional-canPop + confirmation-dialog pattern.

**Sender PopScope to copy** (`lib/presentation/sender/sender_screen.dart` lines 639–675):
```dart
PopScope(
  canPop: !_encrypting && !_encryptingKey,
  onPopInvokedWithResult: (didPop, _) {
    if (didPop) {
      _wipeSensitiveData();
      if (_handshakeDocId != null) {
        _connService.clearTransferRoles(handshakeDocId: _handshakeDocId!);
      }
    } else if (_handshakeDocId != null && !_encrypting && !_encryptingKey) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Go Back?',
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          content: const Text(
              'Going back will clear your role assignment. The connection will remain.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final nav = Navigator.of(context);
                await _connService.clearTransferRoles(
                    handshakeDocId: _handshakeDocId!);
                if (mounted) nav.pop();
              },
              child: const Text('Clear & Go Back'),
            ),
          ],
        ),
      );
    }
  },
  child: Scaffold(...),
)
```

**Adaptation for ReceiverScreen (D-01 through D-04):**
- Replace `canPop: !_encrypting && !_encryptingKey` with `canPop: _isReadyToReceive ? false : (_handshakeDocId == null)`
- Replace the `else if` branch with a two-level check: `_sessionLocked` first (SnackBar, no pop), then `_isReadyToReceive` (call `_showCloseSessionDialog()` via `.then()`)
- `_showCloseSessionDialog()` already returns `Future<bool>` — use `.then((confirmed) { if (confirmed && mounted) { _sessionManager.wipeSession(onBuffersWipe: wipeAll); Navigator.pop(context); } })` — do NOT await inside the callback (framework ignores the returned Future)
- The `didPop == true` branch (D-04 case): clear roles if `_handshakeDocId != null`

**SnackBar error pattern** (`lib/presentation/sender/sender_screen.dart` lines 453–459):
```dart
void _showError(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
```
For D-03 (transfer-in-progress block), use a plain SnackBar without error color — consistent with the existing toggle path at `receiver_screen.dart` lines 236–239:
```dart
ScaffoldMessenger.of(context).showSnackBar(
  const SnackBar(content: Text('Cannot close session — transfer in progress.')),
);
```

**`_showCloseSessionDialog()` signature** (`lib/presentation/receiver/receiver_screen.dart` lines 306–356):
```dart
Future<bool> _showCloseSessionDialog() async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) => GlassContainer(
      borderRadius: 24,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ... icon, title, body text, Cancel + CrypButton('Close Session') ...
          TextButton(onPressed: () => Navigator.pop(ctx, false), ...),
          CrypButton(onPressed: () => Navigator.pop(ctx, true), ...),
        ],
      ),
    ),
  );
  return result ?? false;
}
```
This is already correct. Call it with `.then()` from `onPopInvokedWithResult`.

---

#### Gap 4 — AnimatedOpacity + IgnorePointer step gating (copy from receiver_screen.dart lines 717–727)

**Existing pattern in receiver_screen.dart** (lines 717–727) — Step 2 and Step 3 already use this:
```dart
AnimatedOpacity(
  opacity: _step1Done ? 1.0 : 0.4,
  duration: const Duration(milliseconds: 300),
  child: StepCard(step: 2, title: 'Receive Mode', done: _step2Done,
      currentStep: _step1Done && !_step2Done, child: _step2Content()),
),
```

**Step 1 at receiver_screen.dart line 715** currently has NO wrapping:
```dart
StepCard(step: 1, title: 'RSA Keypair', done: _step1Done, currentStep: !_step1Done, child: _step1Content()),
```

Apply the same pattern with `_isReadyToReceive` as the gate condition (D-11). Add `IgnorePointer` as the inner wrapper (the existing pattern above does not use IgnorePointer — but the sender screen at lines 757–762 shows both together):

**Sender combined AnimatedOpacity + IgnorePointer** (`lib/presentation/sender/sender_screen.dart` lines 757–762):
```dart
AnimatedOpacity(
  opacity: _receiverReady ? 1.0 : 0.4,   // ← substitute _isReadyToReceive ? 0.4 : 1.0
  duration: const Duration(milliseconds: 300),
  child: IgnorePointer(
    ignoring: !_receiverReady,            // ← substitute ignoring: _isReadyToReceive
    child: Column(children: [ /* steps 1–4 */ ]),
  ),
),
```

**AppBar settings button (D-12)** — current state at receiver_screen.dart lines 660–664:
```dart
actions: [
  IconButton(
    icon: const Icon(Icons.settings_suggest_rounded),
    onPressed: _openKeyManager,           // ← change to: _isReadyToReceive ? null : _openKeyManager
  ),
],
```

---

### `lib/presentation/sender/sender_screen.dart` (Gap 2 + Gap 3)

**Analog:** `lib/presentation/receiver/receiver_screen.dart` (AnimatedOpacity step-gating), plus the existing sender patterns.

---

#### Gap 2 — Stale key invalidation in `_onHandshakeUpdate` (lines 136–238)

**Existing mid-flight guard pattern** already in `_onHandshakeUpdate` (`sender_screen.dart` lines 156 and 224–225):
```dart
// Line 156 — empty-snapshot branch:
if (_encrypting || _encryptingKey) return;

// Lines 224–225 — receiverReady changed branch:
if (_encrypting || _encryptingKey) return;
```
Apply the same guard before the stale-key check (D-06).

**setState block to modify** (`sender_screen.dart` lines 205–211):
```dart
setState(() {
  _receiverId = receiverId;
  _receiverUsername = receiverUsername;
  _selectedReceiverPublicKeyJson = publicKey;
});
```
Insert `final previousPublicKey = _selectedReceiverPublicKeyJson;` BEFORE this `setState` call (D-05: capture-before-setState, avoids comparing new value against itself).

**`_wipeSensitiveData()` implementation** (`sender_screen.dart` lines 442–451) — confirmed light wipe (D-07):
```dart
void _wipeSensitiveData() {
  _aesKey?.fillRange(0, _aesKey!.length, 0);
  _iv?.fillRange(0, _iv!.length, 0);
  _encryptedBytes?.fillRange(0, _encryptedBytes!.length, 0);
  _aesKey = null;
  _iv = null;
  _encryptedBytes = null;
  _encryptedAESKey = null;
  wipeAll();
}
```
Does NOT clear `_file`, `_receiverId`, `_receiverUsername`, or `_selectedReceiverPublicKeyJson` — correct for D-07 (file and receiver connection preserved).

**SnackBar info pattern** (`sender_screen.dart` lines 480–488):
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: const Text('Secure channel established. Receiver is ready.'),
    backgroundColor: Theme.of(context).colorScheme.secondary,
    duration: const Duration(seconds: 4),
    behavior: SnackBarBehavior.floating,
  ),
);
```
For D-05 stale-key notification, use the simpler form (no background color override, plain text):
```dart
if (mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Receiver key changed — re-encrypt required.')),
  );
}
```

---

#### Gap 3 — Step 1 CrypButton disable + "Change File" TextButton (lines 777–789)

**Current Step 1 CrypButton** (`sender_screen.dart` lines 777–780):
```dart
CrypButton(
  icon: const Icon(Icons.folder_open_rounded, size: 20),
  label: Text(_file == null ? 'Browse Files' : 'Change File'),
  onPressed: _receiverSelected ? _pickFile : null,
  color: cs.primary,
),
if (_file != null) ...[
  const SizedBox(height: 16),
  _FileCard(file: _file!),
],
```

**CrypButton disabled-state pattern** (`sender_screen.dart` lines 811–815 — Step 2 Encrypt button):
```dart
CrypButton(
  icon: const Icon(Icons.lock_rounded, size: 20),
  label: const Text('Encrypt with AES Key'),
  onPressed: _fileSelected ? _encryptFile : null,   // null = disabled/greyed
  color: cs.tertiary,
),
```
Same pattern: pass `null` to `onPressed` to get the automatic grey disabled rendering from `CrypButton._CrypButtonState`.

**AlertDialog pattern** (`sender_screen.dart` lines 648–674 — existing "Go Back?" dialog):
```dart
showDialog(
  context: context,
  builder: (ctx) => AlertDialog(
    title: Text('Go Back?',
        style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
    content: const Text(
        'Going back will clear your role assignment. The connection will remain.'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () async {
          Navigator.pop(ctx);
          final nav = Navigator.of(context);
          await _connService.clearTransferRoles(handshakeDocId: _handshakeDocId!);
          if (mounted) nav.pop();
        },
        child: const Text('Clear & Go Back'),
      ),
    ],
  ),
);
```
Replicate this pattern for "Change File?" (D-09) — use `ctx` for dialog pop, use `context` only for `_wipeSensitiveData()` / `_pickFile()` calls (no screen navigation needed, so no `nav` capture needed).

**`_fileEncrypted` getter** (`sender_screen.dart` line 78):
```dart
bool get _fileEncrypted => _encryptedBytes != null;
```
This getter drives both the CrypButton disable condition and the "Change File" TextButton visibility — no new field needed.

---

## Shared Patterns

### PopScope canPop conditional
**Source:** `lib/presentation/sender/sender_screen.dart` line 640
**Apply to:** ReceiverScreen Gap 1 (D-01)
```dart
canPop: !_encrypting && !_encryptingKey,
```
ReceiverScreen adaptation:
```dart
canPop: _isReadyToReceive ? false : (_handshakeDocId == null),
```

### AnimatedOpacity + IgnorePointer step gating
**Source:** `lib/presentation/sender/sender_screen.dart` lines 757–762 (combined); `lib/presentation/receiver/receiver_screen.dart` lines 717–727 (AnimatedOpacity only)
**Apply to:** ReceiverScreen Gap 4 (D-11), sender_screen.dart Gap 3 (CrypButton disable is simpler — `onPressed: null` suffices)
```dart
AnimatedOpacity(
  opacity: <condition> ? 1.0 : 0.4,
  duration: const Duration(milliseconds: 300),
  child: IgnorePointer(
    ignoring: !<condition>,
    child: <widget>,
  ),
),
```

### Mid-flight guard
**Source:** `lib/presentation/sender/sender_screen.dart` lines 156, 224–225
**Apply to:** SenderScreen Gap 2 stale-key check (D-06)
```dart
if (_encrypting || _encryptingKey) return;
```

### mounted check before SnackBar/Navigator
**Source:** throughout both screens (e.g., `sender_screen.dart` line 227, `receiver_screen.dart` line 300)
**Apply to:** All new SnackBar calls and Navigator.pop() calls added in this phase
```dart
if (mounted) {
  ScaffoldMessenger.of(context).showSnackBar(...);
}
```

---

## Test File Patterns

### `test/security/navigation_guard_test.dart`

**Analog:** `test/security/session_wipe_test.dart` (exact structure match)

**Imports pattern** (`session_wipe_test.dart` lines 1–7):
```dart
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';
import 'package:cryptransfer/core/utils/session_manager.dart';
```
For navigation_guard_test.dart add:
```dart
import 'package:cryptransfer/core/utils/session_state.dart';
```
(No Firestore or fake_cloud_firestore needed — these tests exercise SessionManager state machine directly, not Firestore operations.)

**Group + test structure** (`session_wipe_test.dart` lines 8–9, 18–68):
```dart
void main() {
  group('SESSION WIPE SECURITY TESTS', () {
    // no setUp needed unless using fakeFirestore

    test('TC-WIPE-001: ...', () async {
      // arrange
      // act
      // assert with expect() + reason: string
      // ignore: avoid_print
      print('✅ TC-WIPE-001 PASSED: ...');
    });
  });
}
```

**SessionManager direct instantiation pattern** (`session_wipe_test.dart` lines 272–298):
```dart
final manager = SessionManager();

expect(manager.state, SessionState.open);

bool wipeCallbackFired = false;
manager.wipeSession(onBuffersWipe: () => wipeCallbackFired = true);

expect(manager.state, SessionState.terminated,
    reason: 'wipeSession() must transition to SessionState.terminated');
expect(wipeCallbackFired, true,
    reason: 'onBuffersWipe callback must be invoked by wipeSession()');
```
The navigation guard tests (GAP1-01, GAP1-02, GAP1-03) exercise `SessionManager` state transitions and `_sessionLocked`-equivalent boolean logic at the pure-Dart level — no widget pump needed.

---

### `test/sender/stale_key_test.dart`

**Analog:** `test/sender/transfer_progress_timeout_test.dart` (role-match — same directory, same stub style)

**Imports pattern** (`transfer_progress_timeout_test.dart` lines 1–2):
```dart
import 'package:flutter_test/flutter_test.dart';
// No Firebase imports needed for state-machine unit tests
```

**Group + stub test structure** (`transfer_progress_timeout_test.dart` lines 7–58):
```dart
void main() {
  group('TransferProgressScreen — pulsing waiting indicator', () {
    test('V07-01: CircularProgressIndicator visible when ...', () {
      // TODO: pump TransferProgressScreen with ...
      // expect: find.byType(CircularProgressIndicator) ...
    });
    // ...
  });
}
```
For stale_key_test.dart, GAP2-01 and GAP2-02 can be pure Dart state-machine tests (no widget pump). GAP3-02 ("Change File confirmation calls wipeSensitiveData") requires simulating the `_wipeSensitiveData()` effect — test by checking that the boolean getters (`_fileEncrypted`, `_encryptedAESKey != null`) reflect null after a simulated wipe. Since these are widget-internal methods, stub them as Dart unit tests on the state model, not widget tests.

---

## No Analog Found

None — all four gaps have direct analogs within the two primary source files.

---

## Metadata

**Analog search scope:** `lib/presentation/receiver/`, `lib/presentation/sender/`, `lib/presentation/widgets/`, `lib/core/utils/`, `test/security/`, `test/sender/`
**Files scanned:** 8 source files, 2 test files read directly
**Pattern extraction date:** 2026-05-29
