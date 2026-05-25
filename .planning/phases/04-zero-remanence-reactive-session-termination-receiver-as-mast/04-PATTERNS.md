# Phase 4: Zero Remanence Reactive Session Termination — Pattern Map

**Mapped:** 2026-05-07
**Files analyzed:** 6 (2 new, 3 modified, 1 removal-candidate)
**Analogs found:** 6 / 6

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `lib/presentation/receiver/receiver_end_session_screen.dart` (NEW) | screen | CRUD + event-driven | `lib/presentation/session/end_session_screen.dart` | exact — structural copy with updated step sequence |
| `lib/presentation/sender/sender_session_ended_screen.dart` (NEW) | screen | CRUD (read-only D-10 check) | `lib/presentation/session/end_session_screen.dart` (`_buildDone`) | role-match — copy done-view pattern only |
| `lib/presentation/receiver/decrypt_screen.dart` (MODIFY) | screen | event-driven | self | self-modification — one targeted change in `_saveAndWipe()` |
| `lib/presentation/sender/transfer_progress_screen.dart` (MODIFY) | screen | streaming + CRUD | self | self-modification — `_startTransferListener` + remove button block |
| `lib/presentation/session/end_session_screen.dart` (REMOVE nav) | screen | CRUD | n/a — becomes dead code | template source only |
| `lib/presentation/receiver/download_confirm_screen.dart` (REMOVE nav) | screen | request-response | n/a — becomes dead code | dead code after DecryptScreen change |

---

## Pattern Assignments

### `lib/presentation/receiver/receiver_end_session_screen.dart` (NEW — screen, CRUD + event-driven)

**Primary analog:** `lib/presentation/session/end_session_screen.dart` (lines 1–703)

This file is a structural copy of `EndSessionScreen` with three differences: (1) step list is 4 steps matching D-03 not 6; (2) `_endSession()` writes audit log FIRST (step 0) before any deletion; (3) step 3 calls `EncryptionService.closeReceiverSession(uid)` instead of nothing. All widget classes, animation setup, and build methods copy verbatim.

**Imports pattern** (`end_session_screen.dart` lines 1–12):
```dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';  // ADD — needed for currentUser.displayName in _endSession
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/utils/security_lifecycle_mixin.dart';
import '../../data/repositories/key_repository.dart';
import '../../data/repositories/transfer_repository.dart';  // ADD — for deleteStorageFile()
import '../../data/services/encryption_service.dart';       // ADD — for closeReceiverSession()
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';
```

**Constructor signature** (copy from `end_session_screen.dart` lines 14–42, adapted):
```dart
class ReceiverEndSessionScreen extends StatefulWidget {
  final String transferId;
  final String fileName;
  final int fileSize;
  final String senderUsername;
  final String senderId;
  final String receiverId;
  final DateTime transferredAt;

  // No aesKey — plaintext already wiped in DecryptScreen._saveAndWipe()
  const ReceiverEndSessionScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.senderUsername,
    required this.senderId,
    required this.receiverId,
    required this.transferredAt,
  });
}
```

**_Phase enum + _Step class** (copy verbatim from `end_session_screen.dart` lines 46–57):
```dart
enum _Phase { ready, cleaning, done }

class _Step {
  final IconData icon;
  final String label;
  bool done = false;
  bool active = false;
  _Step({required this.icon, required this.label});
}
```

**State class declaration + AnimationController** (copy from `end_session_screen.dart` lines 61–96, no aesKey registration):
```dart
class _ReceiverEndSessionScreenState extends State<ReceiverEndSessionScreen>
    with SingleTickerProviderStateMixin,
         SecurityLifecycleMixin<ReceiverEndSessionScreen> {
  _Phase _phase = _Phase.ready;
  String? _error;

  late AnimationController _doneCtrl;
  late Animation<double> _doneScale;

  // 4 steps matching D-03 sequence (audit log FIRST, then storage, then batch delete, then RSA wipe)
  late final List<_Step> _steps = [
    _Step(icon: Icons.receipt_long_rounded,   label: 'Write immutable audit log'),
    _Step(icon: Icons.cloud_off_rounded,      label: 'Delete encrypted file from storage'),
    _Step(icon: Icons.delete_forever_rounded, label: 'Delete transfer & handshake records'),
    _Step(icon: Icons.person_off_rounded,     label: 'Wipe RSA keys from device'),
  ];

  @override
  void initState() {
    super.initState();
    // No aesKey to register — plaintext wiped upstream in DecryptScreen
    _doneCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _doneScale = CurvedAnimation(parent: _doneCtrl, curve: Curves.elasticOut);
  }

  @override
  void dispose() {
    _doneCtrl.dispose();
    super.dispose();
  }
```

**_endSession() cleanup sequence** (D-03 order — copy tick/done helpers from `end_session_screen.dart` lines 114–127):
```dart
Future<void> _endSession() async {
  setState(() { _phase = _Phase.cleaning; _error = null; });

  if (widget.transferId.isEmpty || widget.receiverId.isEmpty) {
    setState(() { _phase = _Phase.ready; _error = 'Missing session identifiers. Cleanup aborted.'; });
    return;
  }

  Future<void> tick(int i) async {
    setState(() { _steps[i].active = true; });
    await Future.delayed(const Duration(milliseconds: 200));
  }
  Future<void> done(int i) async {
    setState(() { _steps[i].active = false; _steps[i].done = true; });
    await Future.delayed(const Duration(milliseconds: 150));
  }

  try {
    // Step 0: Write immutable audit log FIRST — before any deletion
    await tick(0);
    final receiverUsername = FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown';
    final auditPayload = <String, dynamic>{
      'senderId': widget.senderId,
      'receiverId': widget.receiverId,
      'senderUsername': widget.senderUsername,
      'receiverUsername': receiverUsername,
      'fileName': widget.fileName,
      'fileSize': widget.fileSize,
      'status': 'completed',
      'timestamp': FieldValue.serverTimestamp(),
      'loggedAt': FieldValue.serverTimestamp(),
    };
    final auditBatch = FirebaseFirestore.instance.batch();
    auditBatch.set(
      FirebaseFirestore.instance
          .collection(FirebaseConstants.users).doc(widget.senderId)
          .collection(FirebaseConstants.auditLogs).doc(),
      auditPayload,
    );
    auditBatch.set(
      FirebaseFirestore.instance
          .collection(FirebaseConstants.users).doc(widget.receiverId)
          .collection(FirebaseConstants.auditLogs).doc(),
      auditPayload,
    );
    await auditBatch.commit();
    await done(0);

    // Step 1: Delete encrypted file from Firebase Storage
    await tick(1);
    await _repo.deleteStorageFile(widget.transferId);
    await done(1);

    // Step 2: Atomic WriteBatch — delete transfer doc + handshake doc
    await tick(2);
    final keyRepo = KeyRepository();
    final handshakeId = await keyRepo.getActiveHandshakeDocId(
      senderUid: widget.senderId,
      receiverUid: widget.receiverId,
    );
    await keyRepo.endSessionCleanup(
      transferId: widget.transferId,
      handshakeId: handshakeId,
      receiverId: widget.receiverId,
    );
    await done(2);

    // Step 3: Full RSA session close — wipes public/private keys + remaining handshakes
    await tick(3);
    await EncryptionService.closeReceiverSession(widget.receiverId);
    await done(3);

    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      setState(() => _phase = _Phase.done);
      _doneCtrl.forward();
    }
  } catch (e) {
    if (mounted) {
      setState(() { _phase = _Phase.ready; _error = e.toString().replaceFirst('Exception: ', ''); });
    }
  }
}
```

**PopScope back-nav guard** (copy from `end_session_screen.dart` line 256):
```dart
PopScope(
  canPop: _phase == _Phase.ready,  // blocks back during cleaning + done
  child: Scaffold(
    appBar: AppBar(
      automaticallyImplyLeading: _phase != _Phase.cleaning,
      ...
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: _phase == _Phase.done
          ? _buildDone(cs)
          : _phase == _Phase.cleaning
              ? _buildCleaning(cs)
              : _buildReady(cs),
    ),
  ),
)
```

**_buildReady() — session summary card + warning + CrypButton** (copy from `end_session_screen.dart` lines 281–436):
- Summary card: `_SummaryRow` for File, Size, Date, Time, Sender — copy verbatim
- Warning banner (red): copy verbatim (`Colors.red.shade700` border)
- Error display: copy verbatim (only renders when `_error != null`)
- `CrypButton`: `icon: Icons.lock_clock_rounded`, `label: 'End Session'`, `color: Colors.red.shade700`, `onPressed: _endSession`

**_buildCleaning()** (copy verbatim from `end_session_screen.dart` lines 440–470):
```dart
Widget _buildCleaning(ColorScheme cs) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 24),
      Text('Ending Session…', style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 22), textAlign: TextAlign.center),
      const SizedBox(height: 6),
      Text('Securely wiping all transfer data.', style: TextStyle(color: cs.onSurfaceVariant), textAlign: TextAlign.center),
      const SizedBox(height: 40),
      ...List.generate(_steps.length, (i) {
        final step = _steps[i];
        return _CleanStepTile(icon: step.icon, label: step.label, done: step.done, active: step.active);
      }),
    ],
  );
}
```

**_buildDone()** (copy verbatim from `end_session_screen.dart` lines 475–546):
- `ScaleTransition` with `_doneScale`
- Green circle container, `Icons.shield_rounded` size 52
- "Session Ended" heading `Colors.green.shade700`
- Green container with `_DoneStepRow` for each `_steps` entry
- `CrypButton` "Back to Home" with `Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeScreen()), (_) => false)`

**Private widget classes — copy verbatim** from `end_session_screen.dart`:
- `_SummaryRow` (lines 551–595)
- `_CleanStepTile` (lines 599–675)
- `_DoneStepRow` (lines 679–703)

**TransferRepository field:**
```dart
final _repo = TransferRepository();
```
(used only for `_repo.deleteStorageFile(widget.transferId)` in step 1)

---

### `lib/presentation/sender/sender_session_ended_screen.dart` (NEW — screen, CRUD read-only)

**Primary analog:** `lib/presentation/session/end_session_screen.dart` `_buildDone()` section (lines 475–546) plus `_DoneStepRow` (lines 679–703)

This is a minimal static screen with no cleanup sequence. It shows two checklist sections and a single "Back to Home" button. It runs the D-10 edge-case Firestore check in `initState`.

**Imports pattern:**
```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/firebase_constants.dart';
import '../../core/utils/security_lifecycle_mixin.dart';  // defensive practice — Claude's discretion D-14 analog
import '../home/home_screen.dart';
import '../widgets/shared_widgets.dart';
```

**Constructor signature:**
```dart
class SenderSessionEndedScreen extends StatefulWidget {
  final String transferId;   // D-10 edge-case check
  final String fileName;
  final int fileSize;
  final String receiverUsername;
  final String senderId;
  final String receiverId;

  // NO aesKey — zeroed by wipeAll() in TransferProgressScreen before navigation (D-07)
  const SenderSessionEndedScreen({
    super.key,
    required this.transferId,
    required this.fileName,
    required this.fileSize,
    required this.receiverUsername,
    required this.senderId,
    required this.receiverId,
  });
}
```

**State class + D-10 initState check** (analog: `end_session_screen.dart` initState lines 80–90):
```dart
class _SenderSessionEndedScreenState extends State<SenderSessionEndedScreen>
    with SecurityLifecycleMixin<SenderSessionEndedScreen> {
  bool _aesCleanDone = false;

  @override
  void initState() {
    super.initState();
    // No buffers to register — AES already zeroed upstream
    _checkAndMarkDone();
  }

  Future<void> _checkAndMarkDone() async {
    // D-10: edge-case safety net — verify transfer doc is already gone
    final doc = await FirebaseFirestore.instance
        .collection(FirebaseConstants.transfers)
        .doc(widget.transferId)
        .get();
    if (doc.exists) {
      await FirebaseFirestore.instance
          .collection(FirebaseConstants.transfers)
          .doc(widget.transferId)
          .delete();
    }
    if (mounted) setState(() => _aesCleanDone = true);
  }
```

**PopScope — no back nav** (analog: `end_session_screen.dart` line 256, stricter):
```dart
PopScope(
  canPop: false,  // only exit is "Back to Home"
  child: Scaffold(...),
)
```

**Build body — two-section checklist** (analog: `_buildDone` from `end_session_screen.dart` lines 475–546):
```dart
// Section 1: "Receiver cleaned up:" — 4 green _DoneStepRow items, shown immediately
// Section 2: "Your device cleaned up:" — 1 item shown after _aesCleanDone == true
//   (D-10 check completes asynchronously; AnimatedSwitcher or Visibility to reveal)

// "Back to Home" CrypButton — same pattern as end_session_screen.dart line 535
CrypButton(
  icon: const Icon(Icons.home_rounded),
  label: const Text('Back to Home'),
  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const HomeScreen()),
    (_) => false,
  ),
  color: Colors.green.shade600,
)
```

**Private widget class to copy:** `_DoneStepRow` from `end_session_screen.dart` lines 679–703.

---

### `lib/presentation/receiver/decrypt_screen.dart` (MODIFY — targeted change in `_saveAndWipe()`)

**Analog:** self (`decrypt_screen.dart` lines 189–239)

**Exact change location:** `_saveAndWipe()` lines 215–229 — replace `DownloadConfirmScreen(...)` route with `ReceiverEndSessionScreen(...)`.

**Current pattern** (lines 215–229):
```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => DownloadConfirmScreen(
      transferId: widget.transferId,
      fileName: _transfer.fileName,
      fileSize: _transfer.fileSize,
      senderUsername: _senderUsername,
      senderId: _transfer.senderId,
      receiverId: _transfer.receiverId,
      savedPath: 'Downloads/${_transfer.fileName}',
      transferredAt: DateTime.now(),
    ),
  ),
);
```

**Replacement pattern:**
```dart
Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => ReceiverEndSessionScreen(
      transferId: widget.transferId,
      fileName: _transfer.fileName,
      fileSize: _transfer.fileSize,
      senderUsername: _senderUsername,
      senderId: _transfer.senderId,
      receiverId: _transfer.receiverId,
      transferredAt: DateTime.now(),
    ),
  ),
);
```

**Import changes:**
- Remove: `import 'download_confirm_screen.dart';` (line 19)
- Add: `import 'receiver_end_session_screen.dart';`

All data required by `ReceiverEndSessionScreen` is available at `_saveAndWipe()` call site:
- `widget.transferId` — the transfer doc ID
- `_transfer.fileName`, `_transfer.fileSize`, `_transfer.senderId`, `_transfer.receiverId` — loaded in `_loadTransfer()`
- `_senderUsername` — loaded in `_loadTransfer()`
- `DateTime.now()` — approximate transfer timestamp

---

### `lib/presentation/sender/transfer_progress_screen.dart` (MODIFY — two changes)

**Analog:** self (`transfer_progress_screen.dart` lines 97–122 and 403–425)

#### Change 1: Extend `_startTransferListener` (lines 97–122)

**Current pattern** (line 103):
```dart
if (!snapshot.exists) return;
```

**Replacement pattern** — add `_sessionEnded` guard field at state level and flip the guard:
```dart
bool _sessionEnded = false;  // add to state class fields

// In _startTransferListener(), replace the guard:
if (!snapshot.exists) {
  if (!_done || _sessionEnded) return;  // only react after upload complete (D-06 Pitfall 1)
  _sessionEnded = true;
  wipeAll();  // zeros widget.encryptedBytes + widget.aesKey (both registered in initState lines 72–73)
  if (mounted) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SenderSessionEndedScreen(
          transferId: widget.transferId,
          fileName: widget.fileName,
          fileSize: widget.fileSize,
          receiverUsername: widget.receiverUsername,
          senderId: widget.senderId,
          receiverId: widget.receiverId,
        ),
      ),
    );
  }
  return;
}
```

The existing logic after this guard (lines 104–121) remains unchanged.

#### Change 2: Remove "End Session" CrypButton block (lines 403–425)

**Current pattern to remove** (lines 403–425):
```dart
CrypButton(
  icon: const Icon(Icons.lock_clock_rounded),
  label: const Text('End Session'),
  onPressed: () => Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => EndSessionScreen(
        transferId: widget.transferId,
        // ... all args ...
        aesKey: widget.aesKey,
      ),
    ),
  ),
  color: Colors.red.shade700,
),
```

Remove this entire `CrypButton` block. The `_canEndSession` field and `_statusMessage` badge remain — they are still relevant for non-repudiation display while the sender waits for receiver-driven cleanup.

**Import to remove:** `import '../session/end_session_screen.dart';` (line 12)
**Import to add:** `import 'sender_session_ended_screen.dart';`

---

## Shared Patterns

### SecurityLifecycleMixin Application
**Source:** `lib/core/utils/security_lifecycle_mixin.dart` (lines 20–108)
**Apply to:** `ReceiverEndSessionScreen` (D-14), `SenderSessionEndedScreen` (Claude's discretion)

```dart
// State class declaration pattern — used by all existing screens:
class _ScreenNameState extends State<ScreenName>
    with SingleTickerProviderStateMixin,   // if AnimationController needed
         SecurityLifecycleMixin<ScreenName> {
  // No buffers to register in either new screen (plaintext wiped upstream)
  // Mixin adds automatic wipeAll() in dispose() as defensive safety net
}
```

### PopScope Back-Nav Guard
**Source:** `lib/presentation/session/end_session_screen.dart` line 256
**Apply to:** `ReceiverEndSessionScreen` (during cleaning + done), `SenderSessionEndedScreen` (always)

```dart
// ReceiverEndSessionScreen — blocks back during cleaning and done:
PopScope(canPop: _phase == _Phase.ready, child: Scaffold(...))

// SenderSessionEndedScreen — no back nav ever:
PopScope(canPop: false, child: Scaffold(...))
```

### Navigator.pushAndRemoveUntil to HomeScreen
**Source:** `lib/presentation/session/end_session_screen.dart` lines 537–540
**Apply to:** Both new screens' "Back to Home" button

```dart
Navigator.of(context).pushAndRemoveUntil(
  MaterialPageRoute(builder: (_) => const HomeScreen()),
  (_) => false,
)
```

### Error Display Pattern
**Source:** `lib/presentation/session/end_session_screen.dart` lines 397–425
**Apply to:** `ReceiverEndSessionScreen` `_buildReady()` (retry on cleanup failure)

```dart
if (_error != null) ...[
  Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        Icon(Icons.error_outline, size: 16, color: Theme.of(context).colorScheme.error),
        const SizedBox(width: 8),
        Expanded(child: Text(_error!, style: TextStyle(fontSize: 13, color: cs.error))),
      ],
    ),
  ),
  const SizedBox(height: 12),
],
CrypButton(
  label: Text(_error != null ? 'Retry End Session' : 'End Session'),
  ...
)
```

### Firestore Audit Log WriteBatch
**Source:** `lib/presentation/session/end_session_screen.dart` lines 154–187
**Apply to:** `ReceiverEndSessionScreen._endSession()` step 0

Exact pattern — copy verbatim, substituting `widget.senderId`/`widget.receiverId` and adding `receiverUsername` from `FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown'`.

### KeyRepository.endSessionCleanup() Atomic Delete
**Source:** `lib/data/repositories/key_repository.dart` lines 648–677
**Apply to:** `ReceiverEndSessionScreen._endSession()` step 2

```dart
// Call getActiveHandshakeDocId FIRST, then endSessionCleanup:
final handshakeId = await keyRepo.getActiveHandshakeDocId(
  senderUid: widget.senderId,
  receiverUid: widget.receiverId,
);
await keyRepo.endSessionCleanup(
  transferId: widget.transferId,
  handshakeId: handshakeId,
  receiverId: widget.receiverId,
);
// endSessionCleanup handles null handshakeId gracefully (line 662 guard)
```

### TransferRepository.deleteStorageFile()
**Source:** `lib/data/repositories/transfer_repository.dart`
**Apply to:** `ReceiverEndSessionScreen._endSession()` step 1
**Use instead of** inline `FirebaseStorage.instance.ref(...).delete()` — repository method handles `object-not-found` gracefully.

---

## No Analog Found

All files in scope have close analogs. No entries needed here.

---

## Files Becoming Dead Code After Phase 4

| File | Reason | Recommendation |
|---|---|---|
| `lib/presentation/session/end_session_screen.dart` | `TransferProgressScreen` navigation removed; no other caller | Delete (D-16 discretion) |
| `lib/presentation/receiver/download_confirm_screen.dart` | `DecryptScreen._saveAndWipe()` navigation removed; only caller was `DecryptScreen` (verified line 19 import) | Delete (D-15 discretion) |

---

## Critical Ordering Note

The `ReceiverEndSessionScreen._endSession()` step order is security-critical:

```
Step 0: auditBatch.commit()          ← MUST be first (immutable record before any deletion)
Step 1: deleteStorageFile()          ← Storage first (large asset, non-atomic)
Step 2: endSessionCleanup()          ← WriteBatch: transfers + handshakes + selectedSenderUid
                                       (This deletion fires the Firestore stream on sender side)
Step 3: closeReceiverSession(uid)    ← RSA keys LAST (broader handshake sweep — idempotent after step 2)
```

Reversing steps 2 and 3 causes `closeReceiverSession` to sweep all handshakes before `endSessionCleanup` can fetch the specific handshake doc ID — `getActiveHandshakeDocId` returns null and the targeted delete is silently skipped. See RESEARCH.md Pitfall 2.

---

## Metadata

**Analog search scope:** `lib/presentation/`, `lib/data/repositories/`, `lib/core/utils/`
**Files read:** `end_session_screen.dart`, `transfer_progress_screen.dart`, `decrypt_screen.dart`, `security_lifecycle_mixin.dart`, `key_repository.dart` (lines 510–677), `shared_widgets.dart` (lines 359–418)
**Pattern extraction date:** 2026-05-07
