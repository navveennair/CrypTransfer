# Phase 09: Navigation Safety & Session Integrity Hardening - Research

**Researched:** 2026-05-29
**Domain:** Flutter PopScope navigation guard, stateful widget lifecycle, session integrity
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Gap 1 — ReceiverScreen back-nav confirmation**
- D-01: `canPop` changes from `true` to `_isReadyToReceive ? false : (_handshakeDocId == null)`
- D-02: When `_isReadyToReceive` is true and user taps back: call `_showCloseSessionDialog()` — reuse existing BottomSheet as-is
- D-03: When `_sessionLocked` is true and user taps back: show SnackBar "Cannot close session — transfer in progress." Do NOT pop.
- D-04: When `_isReadyToReceive` is false AND `_handshakeDocId != null`: clear transfer roles via `_connService.clearTransferRoles(handshakeDocId: _handshakeDocId!)` and allow pop silently.

**Gap 2 — SenderScreen stale `_encryptedAESKey` invalidation**
- D-05: In `_onHandshakeUpdate`, in the `else` branch: after setting `_selectedReceiverPublicKeyJson = publicKey`, check if key changed AND `_encryptedAESKey != null` — call `_wipeSensitiveData()` and show SnackBar "Receiver key changed — re-encrypt required."
- D-06: Mid-flight guard: `if (_encrypting || _encryptingKey) return` before stale key check.
- D-07: Light wipe only — `_wipeSensitiveData()` (clears bytes + calls `wipeAll()`). Do NOT call `_revertToWaiting()`. `_file` and receiver connection preserved.

**Gap 3 — SenderScreen Step 1 re-pick UX lock**
- D-08: After `_fileEncrypted` is true, set "Browse Files" CrypButton `onPressed: null`.
- D-09: Add `TextButton` labelled "Change File" below `_FileCard`, visible only when `_fileEncrypted` is true. Color: `cs.onSurfaceVariant`. Shows `AlertDialog` with title "Change File?", content "This will wipe your encrypted data and AES key. Are you sure?", actions "Cancel" and "Confirm" (calls `_wipeSensitiveData()` then `_pickFile()`).
- D-10: After `_fileEncrypted` reset (`_encryptedBytes == null`), "Change File" TextButton disappears and CrypButton re-enables automatically.

**Gap 4 — ReceiverScreen Step 1 lockout**
- D-11: When `_isReadyToReceive` is true, wrap Step 1 StepCard in `AnimatedOpacity(opacity: _isReadyToReceive ? 0.4 : 1.0, ...)` + `IgnorePointer(ignoring: _isReadyToReceive, ...)`.
- D-12: AppBar settings `IconButton`: `onPressed: _isReadyToReceive ? null : _openKeyManager`.

### Claude's Discretion
- Exact placement of the stale-key comparison (capture old value before setState vs. compare inside setState callback)
- Whether to use `AlertDialog` or `showDialog` wrapper for the "Change File" confirmation
- `onPopInvokedWithResult` signature (Flutter version-dependent; follow existing patterns in the file)
- Order of operations in `onPopInvokedWithResult` (check `_sessionLocked` first, then `_isReadyToReceive`, then base case)

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

This phase is a surgical hardening of two existing screens (`receiver_screen.dart` and `sender_screen.dart`) with no schema changes, no new screens, and no new dependencies. All four gaps are pure Dart/Flutter widget-layer fixes exploiting patterns that already exist in the codebase.

The key insight from reading the actual source: the `PopScope` on `ReceiverScreen` (line 644) currently has `canPop: true` unconditionally, meaning `onPopInvokedWithResult` always receives `didPop: true` and the existing wipe code in the callback fires silently with no confirmation gate. The SenderScreen `_onHandshakeUpdate` (line 136) sets `_selectedReceiverPublicKeyJson` from the stream doc without comparing it to the prior value — `_encryptedAESKey` computed against the old key is never invalidated. Step 1's "Browse Files" button (line 777) is always enabled once a receiver is selected (`onPressed: _receiverSelected ? _pickFile : null`), ignoring `_fileEncrypted` state.

**Primary recommendation:** All four gaps are 1-20 line fixes using identical patterns already present in the file. No new widgets, no new imports, no architecture changes required.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Back-nav confirmation gate | Frontend/Widget | — | PopScope is a Flutter widget-layer construct; confirmation dialog is UI |
| Session wipe on confirmed back-nav | Widget → SessionManager | EncryptionService (reactive) | SessionManager owns state transitions; EncryptionService binds reactively via stateStream |
| Stale key invalidation | Widget (_onHandshakeUpdate) | — | Firestore stream listener is already in the widget; comparison and wipe are local state ops |
| Step 1 re-pick UX lock | Widget (build method) | — | `_fileEncrypted` getter is derived local state; button enable/disable is pure UI |
| Step 1 lockout (Gap 4) | Widget (build method) | — | `_isReadyToReceive` drives existing AnimatedOpacity/IgnorePointer pattern throughout screen |

---

## Standard Stack

This phase introduces no new libraries. All tools are already in the project.

### Core (already in pubspec.yaml)
| Library | Purpose | Relevance to Phase 09 |
|---------|---------|----------------------|
| flutter/material.dart | `PopScope`, `AlertDialog`, `showDialog`, `showModalBottomSheet`, `AnimatedOpacity`, `IgnorePointer`, `TextButton` | All four gaps use these primitives |
| google_fonts | Typography | Existing usage in both screens |

**Version verification:** Flutter 3.44.0 confirmed installed. [VERIFIED: flutter --version]

---

## Architecture Patterns

### System Architecture Diagram

```
User taps "Back" on ReceiverScreen
         │
         ▼
  PopScope evaluates canPop
         │
   ┌─────┴─────┐
   │ canPop=false │ canPop=true
   │ (mailbox   │  (no mailbox,
   │  open OR   │   no handshake)
   │  locked)   │
   ▼            ▼
onPopInvokedWithResult   Navigator pops silently
(didPop=false)
         │
         ├── _sessionLocked == true
         │       └── show SnackBar "Cannot close..." (no pop)
         │
         └── _isReadyToReceive == true
                 └── _showCloseSessionDialog()
                         │
                    ┌────┴────┐
                    Cancel   Confirm
                               │
                  _sessionManager.wipeSession(onBuffersWipe: wipeAll)
                               │
                        Navigator.pop()


Firestore handshake stream fires new doc with changed publicKey
         │
         ▼
  _onHandshakeUpdate()
         │
         ├── mid-flight guard: _encrypting || _encryptingKey → return
         │
         ├── capture oldKey = _selectedReceiverPublicKeyJson
         ├── setState: _selectedReceiverPublicKeyJson = newPublicKey
         │
         └── oldKey != null && newPublicKey != oldKey && _encryptedAESKey != null
                 └── _wipeSensitiveData()
                     show SnackBar "Receiver key changed — re-encrypt required."


_fileEncrypted == true (after Step 2 completes)
         │
         ▼
  Step 1 CrypButton: onPressed = null  (greyed out)
  "Change File" TextButton appears below _FileCard
         │
    user taps "Change File"
         │
         ▼
  AlertDialog "Change File?"
         │
    ┌────┴────┐
   Cancel   Confirm
               │
          _wipeSensitiveData()
          _pickFile()
```

### Recommended Project Structure
No structural changes. All edits are confined to:
```
lib/presentation/
├── receiver/
│   └── receiver_screen.dart       (PopScope + Step 1 lockout)
└── sender/
    └── sender_screen.dart         (_onHandshakeUpdate + Step 1 UX)
```

### Pattern 1: PopScope with conditional canPop and deferred navigation
**What:** `canPop: false` prevents the system from popping until `onPopInvokedWithResult` explicitly calls `Navigator.pop()`. `didPop` is `false` when `canPop` was false — so all confirmation logic runs in the `!didPop` branch.
**When to use:** When a screen has state that must be confirmed before leaving.
**Example (from SenderScreen, line 639-675):** [VERIFIED: reading sender_screen.dart]
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
      showDialog(...); // confirmation, then nav.pop()
    }
  },
  ...
)
```
**ReceiverScreen Gap 1 applies this pattern** — D-01 changes `canPop: true` to the conditional; D-02/D-03/D-04 implement the `else` (didPop=false) branch.

### Pattern 2: AnimatedOpacity + IgnorePointer step gating
**What:** Dims and disables a UI section reactively based on a boolean condition.
**When to use:** When a stepper step should be inaccessible while a prior condition holds.
**Example (from receiver_screen.dart, lines 717-727):** [VERIFIED: reading receiver_screen.dart]
```dart
AnimatedOpacity(
  opacity: _step1Done ? 1.0 : 0.4,
  duration: const Duration(milliseconds: 300),
  child: StepCard(
    step: 2,
    ...
  ),
),
```
**Gap 4 applies this pattern** to Step 1 with `_isReadyToReceive` as the condition.

### Pattern 3: CrypButton disabled via onPressed: null
**What:** Passing `onPressed: null` to `CrypButton` renders it greyed/disabled — the existing `_CrypButtonState.build` checks `widget.onPressed != null` for the `enabled` flag and applies `cs.onSurface.withValues(alpha: 0.12)` face color.
**When to use:** Any CrypButton that should be non-interactive based on state.
**Example (from sender_screen.dart, lines 811-815):** [VERIFIED: reading sender_screen.dart]
```dart
CrypButton(
  icon: const Icon(Icons.lock_rounded, size: 20),
  label: const Text('Encrypt with AES Key'),
  onPressed: _fileSelected ? _encryptFile : null,  // null = disabled
  color: cs.tertiary,
),
```
**Gap 3 applies this** by changing `_receiverSelected ? _pickFile : null` to `(_receiverSelected && !_fileEncrypted) ? _pickFile : null`.

### Pattern 4: Old-value capture before setState for stream comparison
**What:** Capture the current value of a field before calling `setState` so the old and new values can be compared without a closure timing issue.
**When to use:** In stream callbacks where a field will be updated inside `setState`.
**Implementation for D-05 (Gap 2):**
```dart
void _onHandshakeUpdate(QuerySnapshot<Map<String, dynamic>> snap) {
  // ... existing empty-snapshot and role-validation logic ...
  if (publicKey != null && publicKey.isNotEmpty && status == 'handshake_complete' ...) {
    // Capture BEFORE setState to enable stale-key comparison (D-05)
    final previousPublicKey = _selectedReceiverPublicKeyJson;
    
    setState(() {
      _receiverId = receiverId;
      _receiverUsername = receiverUsername;
      _selectedReceiverPublicKeyJson = publicKey;
    });
    
    // D-06: mid-flight guard (matches existing pattern in the else-if branch above)
    if (_encrypting || _encryptingKey) return;
    
    // D-05: stale key check — key changed while encrypted AES key exists
    if (previousPublicKey != null &&
        publicKey != previousPublicKey &&
        _encryptedAESKey != null) {
      _wipeSensitiveData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Receiver key changed — re-encrypt required.')),
        );
      }
    }
    // ... rest of existing logic ...
  }
}
```
[ASSUMED] — The exact capture location (before vs inside setState) is Claude's Discretion per CONTEXT.md. The pattern above (capture before setState) is the simpler approach and avoids any risk of comparing against the value just written.

### Anti-Patterns to Avoid
- **Placing stale-key check INSIDE setState callback:** The comparison would always be false since `_selectedReceiverPublicKeyJson` has already been updated.
- **Calling `Navigator.pop()` directly inside `onPopInvokedWithResult` when `canPop: false`:** When `canPop` is false, the pop was NOT processed by the system — calling `Navigator.pop()` from within the confirmation callback is the correct and only way to actually pop.
- **Calling `wipeSession()` before showing the confirmation dialog:** wipeSession transitions state to `terminated` immediately (stateStream fires, EncryptionService reacts). The dialog must show first; wipeSession fires only on "Confirm".
- **Using `_revertToWaiting()` for the stale-key case (Gap 2):** D-07 explicitly locks this — `_revertToWaiting()` clears receiver connection and file, which is too destructive. Only `_wipeSensitiveData()` is correct.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Confirmation before back-nav | Custom back button / custom AppBar leading | `PopScope` + `onPopInvokedWithResult` | System-level back gesture and hardware back button are intercepted by PopScope; a custom button misses hardware back |
| Disable a section of the UI | Custom widget visibility flag | `AnimatedOpacity` + `IgnorePointer` | Pattern already used in both screens; consistent step-gating visual language |
| Disable a CrypButton | `Opacity(0.4)` wrapper | `onPressed: null` parameter | CrypButton already computes the disabled visual from `onPressed == null` |

---

## Code Insights (Exact Source Mapping)

### receiver_screen.dart — What Exists and What Changes

| Location | Current State | Gap 1 Change |
|----------|--------------|-------------|
| Line 644-655: `PopScope` | `canPop: true` always | Change to `canPop: _isReadyToReceive ? false : (_handshakeDocId == null)` |
| Line 646: `onPopInvokedWithResult` | `if (didPop) { wipe or clearRoles }` | Move to `else` branch (didPop=false); add `_sessionLocked` check first, then `_isReadyToReceive` check with dialog |
| Line 715: Step 1 `StepCard` | No opacity/ignorePointer wrapping | Gap 4: wrap in `AnimatedOpacity` + `IgnorePointer` gated on `_isReadyToReceive` |
| Line 660-663: AppBar settings button | `onPressed: _openKeyManager` always | Gap 4: `onPressed: _isReadyToReceive ? null : _openKeyManager` |

**Current PopScope callback (lines 646-654):**
```dart
onPopInvokedWithResult: (didPop, _) {
  if (didPop) {
    if (_isReadyToReceive) {
      _sessionManager.wipeSession(onBuffersWipe: wipeAll);
    } else if (_handshakeDocId != null) {
      _connService.clearTransferRoles(handshakeDocId: _handshakeDocId!);
    }
  }
},
```
This is the existing code. It fires AFTER the pop happens (since `canPop: true` always allows the pop). The fix moves logic to the `!didPop` branch (when pop is blocked) and adds the confirmation dialog.

**Critical ordering for D-03 (session locked check must come first):**
```dart
onPopInvokedWithResult: (didPop, _) {
  if (!didPop) {
    // Order matters: check locked first (highest priority)
    if (_sessionLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot close session — transfer in progress.')),
      );
    } else if (_isReadyToReceive) {
      _showCloseSessionDialog().then((confirmed) {
        if (confirmed && mounted) {
          _sessionManager.wipeSession(onBuffersWipe: wipeAll);
          Navigator.pop(context);
        }
      });
    }
  } else {
    // didPop == true: canPop was true (no mailbox, no handshake)
    // Nothing additional needed — existing roles already cleared or absent
  }
},
```
Note: `_showCloseSessionDialog()` returns `Future<bool>`. The pop must wait for the dialog result, then call `Navigator.pop(context)` imperatively.

### sender_screen.dart — What Exists and What Changes

| Location | Current State | Change |
|----------|--------------|--------|
| Line 136: `_onHandshakeUpdate` | Sets `_selectedReceiverPublicKeyJson = publicKey` without comparison | Gap 2: capture old value first, compare after setState |
| Line 777-780: Step 1 CrypButton | `onPressed: _receiverSelected ? _pickFile : null` | Gap 3: also disable when `_fileEncrypted` is true |
| Line 783-785: `_FileCard` shown when `_file != null` | No "Change File" button | Gap 3: add TextButton after `_FileCard` when `_fileEncrypted` |

**Current Step 1 CrypButton (line 777-780):** [VERIFIED]
```dart
CrypButton(
  icon: const Icon(Icons.folder_open_rounded, size: 20),
  label: Text(_file == null ? 'Browse Files' : 'Change File'),
  onPressed: _receiverSelected ? _pickFile : null,
  color: cs.primary,
),
```
Note: The label already says "Change File" when a file is selected — but the button is still active and just calls `_pickFile()` silently. Gap 3 disables it after encryption and provides an explicit confirmation path.

**`_wipeSensitiveData()` (lines 442-451):** [VERIFIED]
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
This does NOT clear `_file`, `_receiverId`, `_receiverUsername`, `_selectedReceiverPublicKeyJson`, or receiver-ready state — confirming D-07 (light wipe, preserves receiver connection and file reference).

---

## Common Pitfalls

### Pitfall 1: `_showCloseSessionDialog()` future not awaited in `onPopInvokedWithResult`
**What goes wrong:** `onPopInvokedWithResult` is a synchronous `void` callback. If you `await` the dialog inside, the pop happens before the dialog resolves.
**Why it happens:** `async`/`await` in `onPopInvokedWithResult` will return a `Future` that the Flutter framework ignores — the method runs to completion immediately.
**How to avoid:** Use `.then()` to chain the navigation after the dialog result. Example:
```dart
_showCloseSessionDialog().then((confirmed) {
  if (confirmed && mounted) {
    _sessionManager.wipeSession(onBuffersWipe: wipeAll);
    Navigator.pop(context);
  }
});
```
**Warning signs:** Linter warning "Don't use BuildContext across async gaps" — avoid `async/await` here entirely.

### Pitfall 2: stale-key comparison always evaluates to false
**What goes wrong:** If the old value of `_selectedReceiverPublicKeyJson` is captured after `setState`, it already holds the new value, so `previousPublicKey != publicKey` is always false.
**Why it happens:** `setState` is synchronous in Dart — the state is updated before any subsequent reads.
**How to avoid:** Capture `final previousPublicKey = _selectedReceiverPublicKeyJson;` BEFORE the `setState` call.

### Pitfall 3: `Navigator.pop()` called when `canPop: true` already processed the pop
**What goes wrong:** If `canPop: true` and `didPop: true`, calling `Navigator.pop()` from inside `onPopInvokedWithResult` would attempt a double-pop (popping the screen below).
**Why it happens:** When `canPop: true`, the framework pops before calling `onPopInvokedWithResult(true, ...)`.
**How to avoid:** Only call `Navigator.pop(context)` in the `didPop == false` branch (when `canPop: false` blocked the pop and confirmation was needed).

### Pitfall 4: `_sessionLocked` canPop logic interaction
**What goes wrong:** If `canPop` is set to block only `_isReadyToReceive`, then when `_sessionLocked` is true (but perhaps `_isReadyToReceive` is also true — which it always is when `_sessionLocked` is true), the block still fires but for the wrong reason in the callback.
**Why it happens:** `_sessionLocked` is only set to true inside `_handleIncomingTransfer`, which can only fire when `_isReadyToReceive` is true. So the two conditions are not mutually exclusive — `_sessionLocked` implies `_isReadyToReceive`.
**How to avoid:** D-01 already handles this correctly: `canPop: _isReadyToReceive ? false : (_handshakeDocId == null)`. Both `_sessionLocked` and non-locked-open-mailbox cases are caught by `_isReadyToReceive == true`. The distinction between them is handled in the callback ordering (D-03: check `_sessionLocked` first).

### Pitfall 5: "Change File" dialog context leak
**What goes wrong:** AlertDialog is shown with `context` from the screen. If the screen is disposed while the dialog is open, `Navigator.pop(context)` on Cancel/Confirm will throw.
**Why it happens:** The dialog's `builder` is a closure over `context`.
**How to avoid:** The existing `AlertDialog` pattern in `sender_screen.dart` (lines 650-674) uses a local `ctx` in the builder, and calls `Navigator.pop(ctx)` to close the dialog — then chains `nav.pop()` for the screen navigation. Replicate this pattern. The "Change File" dialog only calls `_wipeSensitiveData()` and `_pickFile()` — no screen navigation needed.

---

## Code Examples

### Gap 1: Correct PopScope structure for ReceiverScreen
```dart
// Source: derived from existing SenderScreen pattern (line 639-675) + D-01..D-04
PopScope(
  canPop: _isReadyToReceive ? false : (_handshakeDocId == null),
  onPopInvokedWithResult: (didPop, _) {
    if (!didPop) {
      if (_sessionLocked) {
        // D-03: blocked by active transfer — show info SnackBar, no pop
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot close session — transfer in progress.')),
        );
      } else if (_isReadyToReceive) {
        // D-02: mailbox open — require confirmation
        _showCloseSessionDialog().then((confirmed) {
          if (confirmed && mounted) {
            _sessionManager.wipeSession(onBuffersWipe: wipeAll);
            Navigator.pop(context);
          }
        });
      }
      // D-04 case (_isReadyToReceive=false, _handshakeDocId!=null) cannot reach
      // here since canPop would be true in that case (didPop would be true)
    } else {
      // D-04: didPop == true means canPop was true (mailbox closed, no lock)
      // _handshakeDocId != null case: clear roles then pop already happened
      if (_handshakeDocId != null) {
        _connService.clearTransferRoles(handshakeDocId: _handshakeDocId!);
      }
    }
  },
  child: Scaffold(...),
)
```

### Gap 2: Stale-key invalidation in _onHandshakeUpdate
```dart
// Source: derived from existing mid-flight guard pattern + D-05..D-07
// In the `else` branch of _onHandshakeUpdate, where publicKey is valid:
final previousPublicKey = _selectedReceiverPublicKeyJson;  // capture BEFORE setState

setState(() {
  _receiverId = receiverId;
  _receiverUsername = receiverUsername;
  _selectedReceiverPublicKeyJson = publicKey;
});
_streamSettled = true;
_checkTofuStatus(receiverId, publicKey);

// D-06: mid-flight guard — existing pattern from lines 224-226
if (_encrypting || _encryptingKey) return;

// D-05: stale AES key invalidation
if (previousPublicKey != null &&
    publicKey != previousPublicKey &&
    _encryptedAESKey != null) {
  _wipeSensitiveData();
  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Receiver key changed — re-encrypt required.')),
    );
  }
}
// ... rest of receiverReady logic unchanged ...
```

### Gap 3: Step 1 CrypButton disable + "Change File" TextButton
```dart
// Source: derived from existing CrypButton pattern + D-08..D-10
CrypButton(
  icon: const Icon(Icons.folder_open_rounded, size: 20),
  label: const Text('Browse Files'),  // label simplified — "Change File" is now the TextButton
  onPressed: (_receiverSelected && !_fileEncrypted) ? _pickFile : null,  // D-08
  color: cs.primary,
),
if (_file != null) ...[
  const SizedBox(height: 16),
  _FileCard(file: _file!),
  if (_fileEncrypted) ...[                              // D-09: only when encrypted
    const SizedBox(height: 8),
    TextButton(
      onPressed: () {
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Change File?',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
            content: const Text(
                'This will wipe your encrypted data and AES key. Are you sure?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _wipeSensitiveData();
                  _pickFile();
                },
                child: const Text('Confirm'),
              ),
            ],
          ),
        );
      },
      style: TextButton.styleFrom(foregroundColor: cs.onSurfaceVariant),
      child: const Text('Change File'),                 // D-09
    ),
  ],
],
```

### Gap 4: Step 1 lockout + AppBar settings disable
```dart
// Source: derived from existing AnimatedOpacity pattern (receiver_screen.dart line 717-727) + D-11..D-12

// Step 1 lockout (in build(), replace bare StepCard with wrapped version):
AnimatedOpacity(
  opacity: _isReadyToReceive ? 0.4 : 1.0,
  duration: const Duration(milliseconds: 300),
  child: IgnorePointer(
    ignoring: _isReadyToReceive,
    child: StepCard(step: 1, title: 'RSA Keypair', done: _step1Done,
        currentStep: !_step1Done, child: _step1Content()),
  ),
),

// AppBar settings button (D-12):
IconButton(
  icon: const Icon(Icons.settings_suggest_rounded),
  onPressed: _isReadyToReceive ? null : _openKeyManager,
),
```

---

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | flutter_test (bundled with Flutter 3.44.0) |
| Config file | pubspec.yaml `dev_dependencies: flutter_test` |
| Quick run command | `flutter test test/security/ --no-pub` |
| Full suite command | `flutter test --no-pub` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| GAP1-01 | ReceiverScreen canPop is false when mailbox is open | unit | `flutter test test/security/navigation_guard_test.dart --no-pub` | Wave 0 |
| GAP1-02 | Back nav during active transfer shows SnackBar, no pop | unit | `flutter test test/security/navigation_guard_test.dart --no-pub` | Wave 0 |
| GAP1-03 | Confirmed close from back-nav calls wipeSession | unit | `flutter test test/security/navigation_guard_test.dart --no-pub` | Wave 0 |
| GAP2-01 | Stale AES key wiped when receiver public key changes mid-session | unit | `flutter test test/sender/stale_key_test.dart --no-pub` | Wave 0 |
| GAP2-02 | Mid-flight guard prevents wipe during active compute() | unit | `flutter test test/sender/stale_key_test.dart --no-pub` | Wave 0 |
| GAP3-01 | Browse Files button disabled after file encrypted | manual-only | n/a — widget test requires file picker mock | manual |
| GAP3-02 | Change File confirmation dialog calls wipeSensitiveData | unit | `flutter test test/sender/stale_key_test.dart --no-pub` | Wave 0 |
| GAP4-01 | Step 1 IgnorePointer active when mailbox open | manual-only | n/a — requires widget test with tap simulation | manual |

**Manual-only justification:** GAP3-01 and GAP4-01 require widget pump + tap simulation on platform channel-dependent widgets (`CrypButton` with haptic, `FilePicker`). These are tested via UAT in the verification phase. The behavioral logic (button state driven by boolean getter) is verified through code review and the existing pattern.

### Sampling Rate
- **Per task commit:** `flutter test test/security/ test/sender/ --no-pub`
- **Per wave merge:** `flutter test --no-pub`
- **Phase gate:** Full suite green (107/108 baseline maintained) before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/security/navigation_guard_test.dart` — covers GAP1-01, GAP1-02, GAP1-03 (SessionManager unit tests for PopScope logic)
- [ ] `test/sender/stale_key_test.dart` — covers GAP2-01, GAP2-02, GAP3-02 (sender state machine unit tests)

*(Existing test infrastructure covers the broader session wipe suite. Phase 09 adds targeted gap-specific tests.)*

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | — |
| V3 Session Management | yes | PopScope confirmation gate ensures session is not silently abandoned; wipeSession clears all key material |
| V4 Access Control | yes | Step 1 lockout prevents RSA key regeneration while session is active (prevents key-swap attack mid-session) |
| V5 Input Validation | no | — |
| V6 Cryptography | yes | Stale AES key invalidation prevents an encrypted AES key from being sent to a changed RSA public key (wrong recipient's key) |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Silent session abandonment via hardware back | Tampering | PopScope canPop=false + confirmation + wipeSession |
| Stale encrypted key sent to changed receiver key | Spoofing | Stream comparison + wipeSensitiveData on key change |
| RSA key regeneration while mailbox open (invalidates handshake) | Tampering | AnimatedOpacity + IgnorePointer on Step 1 when _isReadyToReceive |
| Re-picking file silently discards encrypted state | Information Disclosure | Explicit "Change File" confirmation dialog before wipeSensitiveData |

---

## Runtime State Inventory

This is a code-only hardening phase. No Firestore schema changes, no collection renames, no new fields.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — no field names or collection names changed | None |
| Live service config | None — no n8n workflows, Firestore rules, or external service config touched | None |
| OS-registered state | None — no Task Scheduler, pm2, or systemd changes | None |
| Secrets/env vars | None — no SOPS keys or env vars referenced | None |
| Build artifacts | None — no package renames or pyproject.toml changes | None |

---

## Environment Availability

All dependencies are local Flutter widgets. No external tools required.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Flutter SDK | All widget changes | ✓ | 3.44.0 | — |
| flutter_test | Test suite | ✓ | bundled | — |
| fake_cloud_firestore | Existing test mocks | ✓ | in pubspec | — |

**No missing dependencies.**

---

## Open Questions (RESOLVED)

1. **`_showCloseSessionDialog()` context parameter**
   - What we know: The existing `_showCloseSessionDialog()` at line 306 uses `context` from `Theme.of(context)` inside the builder. Since `onPopInvokedWithResult` is called synchronously in the same frame as the pop gesture, `context` is still valid.
   - What's unclear: Whether `mounted` check is needed before showing the dialog inside the `.then()` callback.
   - Recommendation: Add `if (confirmed && mounted)` before calling `wipeSession` and `Navigator.pop()` — this is the existing pattern used throughout the file.

2. **CrypButton label when disabled in Gap 3**
   - What we know: Current label logic at line 779 is `Text(_file == null ? 'Browse Files' : 'Change File')`. After Gap 3, "Change File" becomes a separate TextButton.
   - What's unclear: Whether the CrypButton label should revert to a static "Browse Files" once `_fileEncrypted` is true (since the "Change File" action moves to the TextButton).
   - Recommendation (Claude's Discretion): Use a static `const Text('Browse Files')` on the CrypButton. The dynamic label logic was a workaround; the TextButton is now the explicit change-file path.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Stale-key comparison captured before setState is the correct placement | Code Examples / Gap 2 | Wrong placement → comparison always false → stale key never detected |
| A2 | CrypButton label should be simplified to static 'Browse Files' in Gap 3 | Open Questions | Minor UX confusion only — both labels are correct, just different UX |

---

## Sources

### Primary (HIGH confidence)
- `lib/presentation/receiver/receiver_screen.dart` — read directly; lines 644-655 (PopScope), 715-727 (AnimatedOpacity pattern), 306-356 (_showCloseSessionDialog), 235-303 (_onToggleReady), 59 (_sessionLocked)
- `lib/presentation/sender/sender_screen.dart` — read directly; lines 136-237 (_onHandshakeUpdate), 442-451 (_wipeSensitiveData), 240-262 (_revertToWaiting), 777-789 (Step 1 CrypButton), 639-675 (PopScope), 66-79 (fields and getters)
- `lib/presentation/widgets/shared_widgets.dart` — read directly; lines 345-493 (CrypButton stateful widget, disabled state logic)
- `lib/core/utils/session_manager.dart` — read directly; lines 110-115 (wipeSession signature)
- `.planning/phases/09-navigation-safety-session-integrity-hardening/09-CONTEXT.md` — locked decisions D-01..D-12
- `flutter --version` — Flutter 3.44.0 confirmed

### Secondary (MEDIUM confidence)
- `test/security/session_wipe_test.dart` — verified test baseline; 29/29 security tests passing before this phase
- `.planning/config.json` — nyquist_validation: true confirmed
- `flutter test test/security/ --no-pub` — current test suite runs clean (29 passing)

---

## Metadata

**Confidence breakdown:**
- Gap identification: HIGH — all four gaps verified by reading source code directly
- PopScope API usage: HIGH — existing SenderScreen is live, working reference implementation in the same file
- AnimatedOpacity + IgnorePointer pattern: HIGH — identical pattern exists at lines 717-727 of receiver_screen.dart
- Stale-key comparison placement: MEDIUM — A1 assumption; capture-before-setState is standard Dart but not verified against Flutter's setState() execution semantics

**Research date:** 2026-05-29
**Valid until:** 2026-06-28 (stable Flutter widget APIs, no fast-moving dependencies)
