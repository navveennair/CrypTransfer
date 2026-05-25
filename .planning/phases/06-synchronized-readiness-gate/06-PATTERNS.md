# Phase 6: Synchronized Readiness Gate - Pattern Map

**Mapped:** 2026-05-16
**Files analyzed:** 4 files to modify (+ Firestore rules validation)
**Analogs found:** 4 / 4 (all files have strong in-codebase analogs)

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/presentation/sender/sender_screen.dart` | component (screen + child widgets) | event-driven (stream → state → UI gate) | Self — `_WaitingForConnectionWidget`, `_ConnectedBadge`, `AnimatedOpacity` steps, `_onHandshakeUpdate` are already inside this file | exact |
| `lib/data/repositories/key_repository.dart` | repository | request-response (single Firestore update) | `selectSenderHandshake()` in same file — WriteBatch + `setReadyToReceive()` pattern | exact |
| `lib/presentation/receiver/receiver_screen.dart` | component (screen) | event-driven (post-handshake write) | `_onSenderSelected()` in same file — try/catch + `setState` + `_showError` | exact |
| `firestore.rules` | config | — | Existing `handshakes` block (lines 171-189) — receiver already has update permission | exact |

---

## Pattern Assignments

### `lib/presentation/sender/sender_screen.dart` — `_WaitingForReceiverWidget`, timer, steps gate

**Role:** component (screen-level state + new child widgets)

**Analog:** Self — `_WaitingForConnectionWidget` (lines 607-683) and `_onHandshakeUpdate` (lines 110-145)

---

#### New state fields (add to `_SenderScreenState`)

Pattern source: existing bool fields at lines 65-76, `dispose()` cleanup at lines 98-103.

```dart
// Phase 6 additions — receiver readiness gate
bool _receiverReady = false;
Timer? _readinessTimer;
int _secondsRemaining = 60;
```

Cancellation in `dispose()` — mirror `_handshakeSub?.cancel()` (line 99):
```dart
_readinessTimer?.cancel();
```

---

#### `_onHandshakeUpdate` additions (lines 110-145)

**Current handler** (lines 110-145):
```dart
void _onHandshakeUpdate(QuerySnapshot<Map<String, dynamic>> snap) {
  if (!mounted) return;
  if (snap.docs.isEmpty) {
    final wasConnected = _receiverId != null;
    _revertToWaiting();
    if (wasConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Secure connection closed by receiver.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  } else {
    final doc = snap.docs.first.data();
    final receiverId = doc['receiverId'] as String? ?? '';
    final receiverUsername = doc['receiverUsername'] as String?
        ?? doc['fromUsername'] as String?
        ?? 'Unknown';
    final publicKey = doc['publicKey'] as String?;
    if (publicKey != null && publicKey.isNotEmpty && receiverId.isNotEmpty &&
        (widget.preFilledPartnerUid == null ||
         receiverId == widget.preFilledPartnerUid)) {
      setState(() {
        _receiverId = receiverId;
        _receiverUsername = receiverUsername;
        _selectedReceiverPublicKeyJson = publicKey;
      });
    }
  }
}
```

**Phase 6 additions inside the `else` branch** — parse `receiverReady`, start timer on first connection, fire `_onReceiverBecameReady()` on transition. Add after the existing `setState` block:
```dart
final receiverReady = doc['receiverReady'] as bool? ?? false;

// Start countdown the first time a receiver connects but is not yet ready.
if (_receiverSelected && !_receiverReady && _readinessTimer == null) {
  _startReadinessTimer();
}

if (!_receiverReady && receiverReady) {
  _onReceiverBecameReady();
} else if (_receiverReady != receiverReady) {
  setState(() => _receiverReady = receiverReady);
}
```

**In `snap.docs.isEmpty` branch** — cancel timer and eject if not yet ready:
```dart
if (!_receiverReady) {
  _readinessTimer?.cancel();
  _readinessTimer = null;
  _ejectToHomeScreen();
}
```

---

#### New methods on `_SenderScreenState`

Pattern for timer: `dart:async` (already imported at line 1). Pattern for SnackBar + navigation: `_showError` (lines 371-378) and `_send()` Navigator.push (lines 312-358).

```dart
void _startReadinessTimer() {
  _secondsRemaining = 60;
  _readinessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
    if (!mounted) return;
    setState(() => _secondsRemaining--);
    if (_secondsRemaining <= 0) {
      _readinessTimer?.cancel();
      _readinessTimer = null;
      _ejectToHomeScreen();
    }
  });
}

void _onReceiverBecameReady() {
  _readinessTimer?.cancel();
  _readinessTimer = null;
  setState(() => _receiverReady = true);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Secure channel established. Receiver is ready.'),
      backgroundColor: Colors.green.shade700,
      duration: const Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

void _ejectToHomeScreen() {
  _wipeSensitiveData();
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text('Session Terminated — receiver closed the session.'),
      backgroundColor: Theme.of(context).colorScheme.error,
      duration: const Duration(seconds: 5),
      behavior: SnackBarBehavior.floating,
    ),
  );
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => HomeScreen()),
    (_) => false,
  );
}
```

---

#### `_revertToWaiting` addition (lines 147-162)

Reset `_receiverReady` and cancel timer when reverting:
```dart
void _revertToWaiting() {
  _readinessTimer?.cancel();    // Phase 6 addition
  _readinessTimer = null;       // Phase 6 addition
  _wipeSensitiveData();
  if (mounted) {
    setState(() {
      _receiverReady = false;   // Phase 6 addition
      _secondsRemaining = 60;   // Phase 6 addition
      _receiverId = widget.preFilledPartnerUid;
      _receiverUsername = widget.preFilledPartnerUsername ?? 'Partner';
      _selectedReceiverPublicKeyJson = null;
      _file = null;
      _encryptedAESKey = null;
      _encrypting = false;
      _encryptingKey = false;
    });
  }
}
```

---

#### Step 0 `done:` condition change (line 447)

**Current** (line 447):
```dart
done: _receiverSelected,
```
**Phase 6 change:**
```dart
done: _receiverSelected && _receiverReady,
```

---

#### Step 0 `child:` three-state switch (lines 447-450)

**Current** (lines 447-450):
```dart
child: _receiverSelected
    ? _ConnectedBadge(username: _receiverUsername!)
    : const _WaitingForConnectionWidget(),
```
**Phase 6 change:**
```dart
child: _receiverSelected
    ? (_receiverReady
        ? _ConnectedBadge(username: _receiverUsername!)
        : _WaitingForReceiverWidget(secondsRemaining: _secondsRemaining))
    : const _WaitingForConnectionWidget(),
```

---

#### Steps 1–4 visibility gate (lines 453-550)

**Current** (line 454-455): Steps 1–4 wrapped in `AnimatedOpacity(opacity: _receiverSelected ? 1.0 : 0.4)` with `onPressed: _receiverSelected ? handler : null`.

**Phase 6 change:** replace the four individual `AnimatedOpacity` wrappers on Steps 1–4 with a single outer wrapper that hides all steps while `!_receiverReady`:

```dart
// Outer gate — hides ALL of Steps 1-4 until receiverReady
AnimatedOpacity(
  opacity: _receiverReady ? 1.0 : 0.0,
  duration: const Duration(milliseconds: 300),
  child: IgnorePointer(
    ignoring: !_receiverReady,
    child: Column(
      children: [
        // ── Step 1 ──────────────────────────────────────────────
        AnimatedOpacity(
          opacity: _receiverSelected ? 1.0 : 0.4,    // existing inner gate
          duration: const Duration(milliseconds: 300),
          child: StepCard(
            step: 1,
            title: 'Select File',
            done: _fileSelected,
            child: ...
          ),
        ),
        const SizedBox(height: 16),
        // Steps 2, 3, 4 follow the same existing pattern unchanged
      ],
    ),
  ),
),
```

---

#### `_WaitingForReceiverWidget` — new private widget

**Analog:** `_WaitingForConnectionWidget` (lines 607-683) — copy AnimationController setup, ScaleTransition + FadeTransition tree, GlassContainer countdown child.

```dart
class _WaitingForReceiverWidget extends StatefulWidget {
  final int secondsRemaining;
  const _WaitingForReceiverWidget({required this.secondsRemaining});

  @override
  State<_WaitingForReceiverWidget> createState() =>
      _WaitingForReceiverWidgetState();
}

class _WaitingForReceiverWidgetState extends State<_WaitingForReceiverWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    // Same parameters as _WaitingForConnectionWidget (lines 625-634)
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    _fade = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mins = widget.secondsRemaining ~/ 60;
    final secs = widget.secondsRemaining % 60;
    final display =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          ScaleTransition(
            scale: _scale,
            child: FadeTransition(
              opacity: _fade,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: cs.primary.withValues(alpha: 0.1),
                  border: Border.all(
                      color: cs.primary.withValues(alpha: 0.2), width: 2),
                ),
                // Differentiates from connection-wait icon (wifi_tethering_rounded)
                child: Icon(Icons.hourglass_top_rounded,
                    color: cs.primary, size: 32),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Waiting for Receiver to prepare secure vault…',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Receiver must open the secure inbox to continue.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Countdown timer container
          GlassContainer(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: cs.primary.withValues(alpha: 0.07),
            borderColor: cs.primary.withValues(alpha: 0.15),
            borderRadius: 12,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.timer_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  display,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
```

---

### `lib/data/repositories/key_repository.dart` — new `setReceiverReady()` method

**Role:** repository
**Data flow:** request-response (single targeted Firestore update)

**Analog:** `setReadyToReceive()` (lines 602-612) — same file, same pattern: single `.update()` call on a known doc reference, `FirebaseException` catch wraps `NetworkException`.

**Imports pattern** (lines 1-7): already complete — `cloud_firestore`, `firebase_auth`, `FirebaseConstants`, `NetworkException` all imported.

**Core pattern — copy from `setReadyToReceive()` (lines 602-612):**
```dart
Future<void> setReadyToReceive(bool ready) async {
  try {
    await _db.collection(FirebaseConstants.users).doc(_uid).update({
      'isReadyToReceive': ready,
      if (ready) 'readySince': FieldValue.serverTimestamp(),
    });
  } on FirebaseException catch (e) {
    throw NetworkException(
        'Could not update ready status: ${e.message ?? e.code}');
  }
}
```

**New method to add** — targets the handshake doc by its deterministic ID:
```dart
/// Sets `receiverReady: true` on the active handshake document.
///
/// [handshakeDocId] is the deterministic ID `${receiverUid}_${senderUid}`
/// written by [publishRSAPublicKey]. Called from [ReceiverScreen._onSenderSelected]
/// after [selectSenderHandshake] completes successfully.
Future<void> setReceiverReady(String handshakeDocId) async {
  try {
    await _db
        .collection(FirebaseConstants.handshakes)
        .doc(handshakeDocId)
        .update({'receiverReady': true});
  } on FirebaseException catch (e) {
    throw NetworkException(
        'Could not signal receiver readiness: ${e.message ?? e.code}');
  }
}
```

**Placement:** After `setReadyToReceive()` (line 612), before `wipeAllSessionKeys()` (line 618). Insert at approximately line 613.

---

#### Handshake doc ID derivation — how to get it in ReceiverScreen

`publishRSAPublicKey()` (lines 556-584) uses `final docId = '${_uid}_$targetUserId'`. `selectSenderHandshake()` (lines 445-520) uses a query to find or create the doc — it does NOT use the deterministic ID pattern; it uses whatever ref exists.

The receiver's UID (`myUid`) and `sender.uid` are both available in `_onSenderSelected`. The deterministic ID for `setReceiverReady` is therefore:
```dart
final handshakeDocId = '${myUid}_${sender.uid}';
```
This matches the ID written by `publishRSAPublicKey()` — the doc the receiver created when they tapped "Send" in `_FindSenderSheet`.

**Important:** `selectSenderHandshake()` may update a pre-existing doc created by a different path (not the deterministic ID). If the handshake doc was created via `selectSenderHandshake()` with a server-generated ID (line 492: `_db.collection(FirebaseConstants.handshakes).doc()`), then the deterministic `${receiverUid}_${senderUid}` ID will not match.

**Resolution pattern:** Add a `handshakeDocId` return value to `selectSenderHandshake()`, OR query for the doc ID after the batch completes. Simplest approach: modify `selectSenderHandshake()` to return the used doc ID:

```dart
// Change signature:
Future<String> selectSenderHandshake({
  required String senderUid,
  required String senderUsername,
}) async {
  // ... existing code ...
  String docId;
  if (existing.docs.isNotEmpty) {
    docId = existing.docs.first.id;           // reuse existing ID
    batch.update(existing.docs.first.reference, keyPayload);
  } else {
    final newRef = _db.collection(FirebaseConstants.handshakes).doc();
    docId = newRef.id;                        // capture generated ID
    batch.set(newRef, {'receiverId': _uid, 'senderId': senderUid, ...keyPayload});
  }
  await batch.commit();
  // ... notification code ...
  return docId;                               // return to caller
}
```

This avoids a second Firestore query and is consistent with the existing `getActiveHandshakeDocId()` pattern (lines 527-542).

---

### `lib/presentation/receiver/receiver_screen.dart` — `_onSenderSelected` addition

**Role:** component (screen)
**Data flow:** event-driven (post-handshake Firestore write)

**Analog:** `_onSenderSelected()` itself (lines 322-349) — the new `_writeReceiverReady()` call slots in after the existing `selectSenderHandshake` `setState` block.

**Current `_onSenderSelected` (lines 322-349):**
```dart
Future<void> _onSenderSelected(UserModel sender) async {
  _sessionManager.selectSender(sender.uid, sender.username);
  final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  _transferStream = FirebaseFirestore.instance
      .collection(FirebaseConstants.transfers)
      .where('receiverId', isEqualTo: myUid)
      .where('senderId', isEqualTo: sender.uid)
      .where('status', isEqualTo: 'pending')
      .snapshots();
  setState(() => _handshaking = true);
  try {
    await _connService.selectSenderHandshake(
      senderUid: sender.uid,
      senderUsername: sender.username,
    );
    if (mounted) {
      setState(() {
        _handshakeDone = true;
        _handshaking = false;
      });
    }
  } catch (e) {
    if (mounted) {
      setState(() => _handshaking = false);
      _showError(e.toString());
    }
  }
}
```

**Phase 6 change — capture doc ID and call `_writeReceiverReady`:**
```dart
Future<void> _onSenderSelected(UserModel sender) async {
  _sessionManager.selectSender(sender.uid, sender.username);
  final myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
  _transferStream = FirebaseFirestore.instance
      .collection(FirebaseConstants.transfers)
      .where('receiverId', isEqualTo: myUid)
      .where('senderId', isEqualTo: sender.uid)
      .where('status', isEqualTo: 'pending')
      .snapshots();
  setState(() => _handshaking = true);
  try {
    // selectSenderHandshake now returns the handshake doc ID (Phase 6 change)
    final handshakeDocId = await _connService.selectSenderHandshake(
      senderUid: sender.uid,
      senderUsername: sender.username,
    );
    if (mounted) {
      setState(() {
        _handshakeDone = true;
        _handshaking = false;
      });
    }
    // Phase 6: signal receiver readiness after handshake confirmed
    await _writeReceiverReady(handshakeDocId);
  } catch (e) {
    if (mounted) {
      setState(() => _handshaking = false);
      _showError(e.toString());
    }
  }
}

/// Writes receiverReady: true to the handshake doc.
/// On failure, surfaces a retry SnackBar (D-08).
Future<void> _writeReceiverReady(String handshakeDocId) async {
  try {
    await _connService.setReceiverReady(handshakeDocId);
  } catch (e) {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Failed to signal readiness — tap to retry.'),
        backgroundColor: cs.error,
        duration: const Duration(seconds: 6),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => _writeReceiverReady(handshakeDocId),
        ),
      ),
    );
  }
}
```

**Error handling pattern** — `_showError()` (lines 393-400):
```dart
void _showError(String msg) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg.replaceFirst('Exception: ', '')),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}
```
The `_writeReceiverReady` SnackBar uses `cs.error` (same source) plus `SnackBarAction` for retry — the existing `_showError` pattern extended with an action.

---

### `firestore.rules` — handshakes update rule verification

**Role:** config
**Analog:** Existing `handshakes` block (lines 171-189)

**Current update rule (lines 183-185):**
```
allow update: if isAuthenticated() &&
               (resource.data.receiverId == request.auth.uid ||
                resource.data.senderId == request.auth.uid);
```

**Analysis:** The receiver is `resource.data.receiverId`. The `receiverReady: true` write is an update by the receiver. The existing rule allows update when `resource.data.receiverId == request.auth.uid`. This covers the Phase 6 write — **no rule change required.**

**Verification:** The update rule does NOT restrict to specific fields (`affectedKeys` check) — unlike `neutral_handshakes` (lines 213-221 which uses `.hasOnly(['status', 'updatedAt'])`). The `handshakes` update is field-unrestricted for either participant. Adding `receiverReady: true` is a valid update under the existing rule.

**No modification needed** to `firestore.rules` for Phase 6.

---

## Shared Patterns

### SnackBar feedback
**Source:** `sender_screen.dart` lines 117-122 (orange SnackBar) and `receiver_screen.dart` lines 393-400 (`_showError`)
**Apply to:** All new SnackBar calls in this phase

```dart
// Error pattern (cs.error background):
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(msg),
    backgroundColor: Theme.of(context).colorScheme.error,
    behavior: SnackBarBehavior.floating,
  ),
);

// Success pattern (Colors.green.shade700):
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: const Text('...'),
    backgroundColor: Colors.green.shade700,
    duration: const Duration(seconds: 4),
    behavior: SnackBarBehavior.floating,
  ),
);
```

### AnimatedOpacity step gate
**Source:** `sender_screen.dart` lines 454-478 (Step 1), 481-505 (Step 2), 508-535 (Step 3)
**Apply to:** Outer gate wrapping Steps 1–4 in Phase 6

```dart
AnimatedOpacity(
  opacity: _receiverSelected ? 1.0 : 0.4,   // existing inner pattern
  duration: const Duration(milliseconds: 300),
  child: StepCard(...),
),
```
Phase 6 wraps this with an outer `AnimatedOpacity(opacity: _receiverReady ? 1.0 : 0.0)` + `IgnorePointer(ignoring: !_receiverReady)`.

### Dart Timer
**Source:** `receiver_screen.dart` line 778 (`_debounce = Timer(...)`) and `_FindSenderSheetState` dispose cancellation (line 767: `_debounce?.cancel()`).
**Apply to:** `_readinessTimer` in `_SenderScreenState`

```dart
// Debounce usage (single-shot):
_debounce = Timer(const Duration(milliseconds: 500), () async { ... });

// Periodic countdown (new pattern — no existing periodic, but dart:async already imported):
_readinessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
  if (!mounted) return;
  setState(() => _secondsRemaining--);
  if (_secondsRemaining <= 0) { ... }
});
```
Cancel in `dispose()`: `_readinessTimer?.cancel();`

### Navigator.pushAndRemoveUntil eject
**Source:** `end_session_screen.dart` (pattern documented in CLAUDE.md); also described in CONTEXT.md D-09.
**Apply to:** `_ejectToHomeScreen()` in `_SenderScreenState`

```dart
Navigator.pushAndRemoveUntil(
  context,
  MaterialPageRoute(builder: (_) => HomeScreen()),
  (_) => false,
);
```

### FirebaseException wrapping
**Source:** `key_repository.dart` lines 49-51, 602-612 (`setReadyToReceive`)
**Apply to:** `setReceiverReady()` in `KeyRepository`

```dart
} on FirebaseException catch (e) {
  throw NetworkException(
      'Could not update ready status: ${e.message ?? e.code}');
}
```

### WriteBatch atomic write
**Source:** `key_repository.dart` lines 469-500 (`selectSenderHandshake`)
**Apply to:** No new WriteBatch needed in Phase 6 — `setReceiverReady` is a single-field targeted update, not a batch operation.

---

## No Analog Found

None. All Phase 6 changes build directly on existing in-codebase patterns.

---

## Critical Implementation Notes for Planner

1. **`selectSenderHandshake` return type change** — this is the central coupling point. The method currently returns `Future<void>` (line 445). Phase 6 requires it return `Future<String>` (the doc ID) so `_onSenderSelected` can pass the ID to `setReceiverReady`. This is a breaking change to the method signature — the planner must coordinate both files in the same plan, and verify no other callers exist.

   Grep for other callers:
   ```
   Grep("selectSenderHandshake", type: "dart") → only receiver_screen.dart line 333
   ```
   Only one caller — safe to change the return type.

2. **Handshake doc ID ownership** — `publishRSAPublicKey` (lines 556-583) uses `'${_uid}_$targetUserId'` as doc ID (receiver_uid + _ + sender_uid). `selectSenderHandshake` (lines 445-520) may create a new doc with a server-generated ID OR update an existing one. The returned ID from `selectSenderHandshake` is always the correct one to use for `setReceiverReady`, regardless of which path created it.

3. **`_receiverReady` in `_revertToWaiting`** — when `_revertToWaiting()` is called (e.g. receiver kills session), `_receiverReady` must reset to `false`. If it stays `true`, Steps 1–4 remain visible after the receiver disconnects. The pattern for this reset mirrors how `_file`, `_encryptedAESKey`, etc. are nulled in the same method (lines 154-161).

4. **Timer lifecycle** — `Timer.periodic` fires its callback even after the widget is disposed if not cancelled. The `dispose()` cancellation guard is mandatory. The `if (!mounted) return;` inside the callback is a secondary guard (same pattern as other async operations in this file).

5. **Firestore rules** — no changes needed. The `handshakes` update rule already grants write access to either `receiverId` or `senderId`, with no field restriction. Confirmed at lines 183-185.

---

## Metadata

**Analog search scope:** `lib/presentation/sender/`, `lib/presentation/receiver/`, `lib/data/repositories/`, `firestore.rules`
**Files read:** `sender_screen.dart` (911 lines), `key_repository.dart` (693 lines), `receiver_screen.dart` (1021 lines), `firebase_constants.dart` (35 lines), `firestore.rules` (249 lines)
**Pattern extraction date:** 2026-05-16
