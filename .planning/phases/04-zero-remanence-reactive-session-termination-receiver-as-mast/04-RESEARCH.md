# Phase 4: Zero Remanence Reactive Session Termination — Research

**Researched:** 2026-05-07
**Domain:** Flutter session lifecycle, Firestore reactive streams, zero-remanence cleanup patterns
**Confidence:** HIGH — all findings verified directly against codebase source files

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** After `DecryptScreen._saveAndWipe()` succeeds, navigate via `pushReplacement` directly to `ReceiverEndSessionScreen` — `DownloadConfirmScreen` is no longer in the post-decrypt flow.
- **D-02:** Cleanup is NOT auto-fired on save. The receiver lands on `ReceiverEndSessionScreen`, reviews the session summary, and presses "End Session" to trigger cleanup explicitly.
- **D-03:** Receiver's "End Session" button triggers a sequential cleanup in this exact order:
  1. Write audit log to `users/{senderId}/audit_logs` AND `users/{receiverId}/audit_logs` (before any deletion)
  2. Delete Firebase Storage file: `transfers/{transferId}/encrypted_file`
  3. Atomic `WriteBatch`: delete `transfers/{transferId}` document + delete `handshakes` doc for this session pair
  4. Call `EncryptionService.closeReceiverSession(uid)` — wipes RSA private key from `FlutterSecureStorage`, deletes `publicKey` + `selectedSenderUid` from Firestore, purges all handshakes for this receiver
- **D-04:** Full zero-remanence scope — receiver's cleanup is a complete wipe including RSA keys. Receiver must re-generate RSA keys for the next session.
- **D-05:** Audit log payload: `{senderId, receiverId, senderUsername, receiverUsername, fileName, fileSize, status: 'completed', timestamp, loggedAt}`. Written via `WriteBatch` to both users' `audit_logs` subcollections atomically.
- **D-06:** Extend the existing `_startTransferListener` in `TransferProgressScreen` to check `!snapshot.exists`. When the receiver's WriteBatch deletes `transfers/{transferId}`, the stream emits a non-existent snapshot — sender detects and acts.
- **D-07:** On `!snapshot.exists` detection, sender: (1) calls `SecurityLifecycleMixin.wipeAll()`, (2) navigates via `pushReplacement` to `SenderSessionEndedScreen` passing metadata.
- **D-08:** Remove the manual "End Session" `CrypButton` from `TransferProgressScreen`. Sender side is fully reactive.
- **D-09:** `SenderSessionEndedScreen` shows two sections: "Receiver cleaned up:" checklist (audit log, encrypted file, transfer record, RSA key) and "Your device cleaned up:" checklist (AES key zeroed from memory).
- **D-10:** Before showing "Your device" section as complete, sender checks if `transfers/{transferId}` doc still exists as edge-case safety net. If still exists, sender deletes before marking AES cleanup done.
- **D-11:** "Back to Home" is the only action on `SenderSessionEndedScreen`. `Navigator.pushAndRemoveUntil` to `HomeScreen`, clearing the full stack.
- **D-12:** `ReceiverEndSessionScreen` displays a session summary card identical in structure to `EndSessionScreen._buildReady()`: fileName, fileSize, sender username, transfer timestamp — passed as constructor args from `DecryptScreen`.
- **D-13:** Shows the cleanup step list (6 steps matching `EndSessionScreen._steps`) before cleanup starts, then animates them done during cleanup. Same `_CleanStepTile` pattern.
- **D-14:** Apply `SecurityLifecycleMixin` to `ReceiverEndSessionScreen`.
- **D-15 (Claude's Discretion):** `DownloadConfirmScreen` is no longer navigated to from the post-decrypt flow. Removal is preferred if no other screens navigate to it.
- **D-16:** The existing `EndSessionScreen` is no longer navigated to from `TransferProgressScreen`. Remove the navigation call. Whether to delete `EndSessionScreen` itself is Claude's discretion.

### Claude's Discretion

- Whether to delete `DownloadConfirmScreen` (D-15) — removal preferred
- Whether to delete `EndSessionScreen` (D-16) — discretion after removing navigation
- `SenderSessionEndedScreen` does not need `SecurityLifecycleMixin` unless it holds sensitive buffers — Claude decides based on what the screen actually registers

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

## Summary

Phase 4 is a **navigation refactor + two new screens** built entirely on patterns that already exist in this codebase. No new packages are required. The full zero-remanence cleanup sequence is already implemented piecemeal across `EndSessionScreen`, `EncryptionService.closeReceiverSession()`, `KeyRepository.endSessionCleanup()`, and `TransferRepository.deleteStorageFile()` — this phase assembles those pieces into a receiver-controlled flow.

The most important structural insight: `TransferProgressScreen._startTransferListener` already subscribes to `transfers/{transferId}` snapshots but currently short-circuits with `if (!snapshot.exists) return`. The sender reactive path requires flipping that guard to trigger cleanup and navigation instead of ignoring the non-existent snapshot.

The `EndSessionScreen` is the canonical template — `ReceiverEndSessionScreen` is a structural copy with one key difference: the receiver's cleanup sequence calls `EncryptionService.closeReceiverSession(uid)` as step 4 (RSA key wipe), which `EndSessionScreen` does not do. `SenderSessionEndedScreen` is a simpler read-only screen with a two-section checklist and a single "Back to Home" button — it performs no Firestore operations except the D-10 edge-case doc-existence check.

**Primary recommendation:** Copy `EndSessionScreen` into `ReceiverEndSessionScreen`, update the step list to match the D-03 receiver cleanup sequence, and change the `_endSession()` body to call the receiver's cleanup chain. For `SenderSessionEndedScreen`, build a minimal static screen with the two-section checklist; the D-10 Firestore check is a single `getTransfer()` or `doc().get()` call before marking the AES step done.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Receiver end-session trigger | Frontend (ReceiverEndSessionScreen) | — | Receiver presses "End Session" explicitly after reviewing summary |
| Audit log write | API/Backend (Firestore WriteBatch) | Frontend orchestrates | Both users' subcollections written atomically before any deletion |
| Storage file deletion | API/Backend (Firebase Storage) | Frontend orchestrates | `FirebaseStorage.instance.ref(...).delete()` called from Dart |
| Firestore atomic batch delete | API/Backend (Firestore WriteBatch) | KeyRepository | Transfer doc + handshake doc deleted in single batch commit |
| RSA key wipe (Firestore + SecureStorage) | API/Backend + Device | EncryptionService | `closeReceiverSession()` owns this — deletes publicKey from Firestore, private key from FlutterSecureStorage |
| Sender reactive detection | Frontend (TransferProgressScreen) | Firestore stream | `_startTransferListener` detects `!snapshot.exists` and auto-navigates |
| AES key zero | Device / Memory | SecurityLifecycleMixin | `wipeAll()` on sender side; AES key is a registered buffer |
| D-10 edge-case check | Frontend (SenderSessionEndedScreen) | Firestore | `doc().get()` to verify transfer doc is already gone before marking cleanup complete |
| Navigation stack clear | Frontend | Navigator | `pushAndRemoveUntil` on both new screens' final action |

---

## Standard Stack

### Core (No new packages required)
[VERIFIED: codebase source files]

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `cloud_firestore` | existing | WriteBatch, stream snapshots, document ops | Already in pubspec, used everywhere |
| `firebase_storage` | existing | Storage file deletion | Already in pubspec, used in `EndSessionScreen` and `TransferRepository` |
| `flutter_secure_storage` | existing | RSA private key wipe | Used in `EncryptionService.closeReceiverSession()` |
| `google_fonts` | existing | Poppins typography | Used on all screens |
| `fake_cloud_firestore` | existing | Unit test mocking | Used in all existing test files |
| `firebase_auth_mocks` | existing | Auth mocking in tests | Used in `mock_firebase.dart` |

**Installation:** None required — all packages already present.

---

## Architecture Patterns

### System Architecture Diagram

```
DecryptScreen._saveAndWipe()
        │
        │  pushReplacement (transferId, fileName, fileSize, senderUsername,
        │                   senderId, receiverId, transferredAt)
        ▼
ReceiverEndSessionScreen
  │  _phase == ready → show summary + "End Session" CrypButton
  │
  │  onPressed → _endSession()
  │       │
  │       ├── Step 0: Write audit log (WriteBatch → both audit_logs subcollections)
  │       ├── Step 1: Delete Storage file (FirebaseStorage.ref.delete())
  │       ├── Step 2: WriteBatch delete (transfers/{id} + handshakes/{id})
  │       │           getActiveHandshakeDocId() → then endSessionCleanup()
  │       ├── Step 3: EncryptionService.closeReceiverSession(uid)
  │       │       ├── Firestore: publicKey delete + selectedSenderUid delete
  │       │       ├── SecureStorage: rsa_private_key delete
  │       │       ├── WriteBatch: delete all handshakes WHERE receiverId==uid
  │       │       └── Best-effort: notifications purge + GC hint
  │       └── _phase = done → "Session Ended" + "Back to Home"
  │
  │  Back to Home → Navigator.pushAndRemoveUntil(HomeScreen)
  │
  │         (Firestore stream fires: transfers/{transferId} no longer exists)
  │                              ↓
  │         TransferProgressScreen._startTransferListener
  │                   └── !snapshot.exists → wipeAll() → pushReplacement
  │                                                           ↓
  │                                            SenderSessionEndedScreen
  │                                              ├── "Receiver cleaned up:" checklist (4 items ✓)
  │                                              ├── D-10 check: doc.get() → if exists → delete
  │                                              ├── "Your device cleaned up:" checklist (AES zeroed ✓)
  │                                              └── "Back to Home" → pushAndRemoveUntil(HomeScreen)
```

### Recommended Project Structure

Two new files created:

```
lib/presentation/
├── receiver/
│   ├── decrypt_screen.dart           (MODIFY: _saveAndWipe navigation target)
│   ├── receiver_end_session_screen.dart   (NEW)
│   └── download_confirm_screen.dart  (REMOVE navigation from decrypt; optionally delete)
├── sender/
│   ├── transfer_progress_screen.dart (MODIFY: _startTransferListener + remove End Session button)
│   └── sender_session_ended_screen.dart   (NEW)
└── session/
    └── end_session_screen.dart       (navigation removed from TransferProgressScreen; optionally delete)
```

### Pattern 1: _CleanStepTile widget — copy from EndSessionScreen

[VERIFIED: `lib/presentation/session/end_session_screen.dart` lines 599–675]

```dart
// _CleanStepTile — already exists in EndSessionScreen, copy verbatim into ReceiverEndSessionScreen
// Signature:
const _CleanStepTile({
  required IconData icon,
  required String label,
  required bool done,
  required bool active,
});
// States:
//   done: green background, check_circle icon
//   active: primaryContainer bg, CircularProgressIndicator (2.5 stroke)
//   pending: surfaceContainerLow bg, radio_button_unchecked icon
// Animation: AnimatedContainer(duration: 250ms)
```

### Pattern 2: _Phase enum + tick/done helpers — copy from EndSessionScreen

[VERIFIED: `lib/presentation/session/end_session_screen.dart` lines 46–57, 114–127]

```dart
enum _Phase { ready, cleaning, done }

// Inside _endSession():
Future<void> tick(int i) async {
  setState(() { _steps[i].active = true; });
  await Future.delayed(const Duration(milliseconds: 200));
}

Future<void> done(int i) async {
  setState(() { _steps[i].active = false; _steps[i].done = true; });
  await Future.delayed(const Duration(milliseconds: 150));
}
```

### Pattern 3: Audit log WriteBatch — copy from EndSessionScreen

[VERIFIED: `lib/presentation/session/end_session_screen.dart` lines 150–187]

```dart
final auditPayload = <String, dynamic>{
  'senderId': widget.senderId,
  'receiverId': widget.receiverId,
  'senderUsername': widget.senderUsername,
  'receiverUsername': widget.receiverUsername,
  'fileName': widget.fileName,
  'fileSize': widget.fileSize,
  'status': 'completed',
  'timestamp': FieldValue.serverTimestamp(),
  'loggedAt': FieldValue.serverTimestamp(),
};
final auditBatch = FirebaseFirestore.instance.batch();
auditBatch.set(
  FirebaseFirestore.instance
      .collection(FirebaseConstants.users)
      .doc(widget.senderId)
      .collection(FirebaseConstants.auditLogs)
      .doc(),
  auditPayload,
);
auditBatch.set(
  FirebaseFirestore.instance
      .collection(FirebaseConstants.users)
      .doc(widget.receiverId)
      .collection(FirebaseConstants.auditLogs)
      .doc(),
  auditPayload,
);
await auditBatch.commit();
```

### Pattern 4: Storage deletion — copy from EndSessionScreen

[VERIFIED: `lib/presentation/session/end_session_screen.dart` lines 137–147]

```dart
try {
  await FirebaseStorage.instance
      .ref('transfers/${widget.transferId}/encrypted_file')
      .delete();
} on FirebaseException catch (e) {
  if (e.code != 'object-not-found') rethrow;
}
// 'object-not-found' is acceptable — already deleted
```

`TransferRepository.deleteStorageFile()` does the same with `FirebaseConstants.transfersStorageRoot` + `FirebaseConstants.encryptedFileName` constants. Either approach is valid; using `TransferRepository.deleteStorageFile(transferId)` is cleaner for `ReceiverEndSessionScreen`.

### Pattern 5: KeyRepository.endSessionCleanup() — atomic WriteBatch for Firestore docs

[VERIFIED: `lib/data/repositories/key_repository.dart` lines 648–677]

```dart
// endSessionCleanup({String? transferId, String? handshakeId, required String receiverId})
// WriteBatch:
//   - delete transfers/{transferId}
//   - delete handshakes/{handshakeId}
//   - update users/{receiverId}: selectedSenderUid = FieldValue.delete()
// Must call getActiveHandshakeDocId(senderUid, receiverUid) BEFORE this to get handshakeId.
```

### Pattern 6: _startTransferListener — current implementation in TransferProgressScreen

[VERIFIED: `lib/presentation/sender/transfer_progress_screen.dart` lines 97–122]

Current code:
```dart
void _startTransferListener() {
  _transferListener = FirebaseFirestore.instance
      .collection('transfers')
      .doc(widget.transferId)
      .snapshots()
      .listen((snapshot) {
    if (!snapshot.exists) return;  // ← CHANGE THIS LINE
    final data = snapshot.data()!;
    final receiverStatus = data['receiverStatus'] as String?;
    // ...
  });
}
```

Required change — when `!snapshot.exists`, trigger sender cleanup:
```dart
if (!snapshot.exists) {
  // Receiver completed cleanup — sender reacts
  wipeAll();  // zeros widget.encryptedBytes + widget.aesKey (both registered in initState)
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

### Pattern 7: PopScope back-nav guard — copy from EndSessionScreen

[VERIFIED: `lib/presentation/session/end_session_screen.dart` lines 256–258]

```dart
PopScope(
  canPop: _phase == _Phase.ready,  // blocks back during cleaning + done
  child: Scaffold(...),
)
```

### Pattern 8: Done view with ScaleTransition — copy from EndSessionScreen

[VERIFIED: `lib/presentation/session/end_session_screen.dart` lines 475–546]

```dart
// AnimationController + CurvedAnimation(Curves.elasticOut) → ScaleTransition
// Green shield icon (Icons.shield_rounded), size 52
// "Session Ended" heading in Colors.green.shade700
// Completed steps summary in green container
// CrypButton "Back to Home" → Navigator.pushAndRemoveUntil to HomeScreen
```

### Pattern 9: SecurityLifecycleMixin application

[VERIFIED: `lib/core/utils/security_lifecycle_mixin.dart`]

```dart
class _ReceiverEndSessionScreenState extends State<ReceiverEndSessionScreen>
    with SingleTickerProviderStateMixin,
         SecurityLifecycleMixin<ReceiverEndSessionScreen> {
  // No buffers to register on ReceiverEndSessionScreen (plaintext already wiped in DecryptScreen)
  // Mixin applied per D-14 — defensive safety net
}
```

`SenderSessionEndedScreen` — `widget.aesKey` is NOT passed to this screen (wipeAll() fires in TransferProgressScreen before navigation per D-07). No buffers to register. Decision: SecurityLifecycleMixin still applies as defensive practice (Claude's discretion: apply it).

### Anti-Patterns to Avoid

- **Calling closeReceiverSession() before writing audit log:** The audit log must be step 1 (before any deletion). If it is called after `endSessionCleanup()`, the transfer record is already gone and audit context cannot be read from Firestore. D-03 order is mandatory.
- **Auto-triggering cleanup on navigate to ReceiverEndSessionScreen:** D-02 explicitly requires user review before cleanup. No `initState` cleanup call.
- **Passing aesKey to SenderSessionEndedScreen:** The AES key is zeroed via `wipeAll()` in `TransferProgressScreen` before navigating (D-07). SenderSessionEndedScreen must not hold it — it can only display a "zeroed" confirmation.
- **Registering aesKey buffer again in SenderSessionEndedScreen:** It is already wiped. Registering an already-zeroed buffer would be harmless but misleading.
- **Non-atomic Firestore deletes for transfer + handshake:** Both must be in the same WriteBatch — partial writes leave ghost documents that the sender stream would never see deleted.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Atomic multi-doc Firestore delete | Custom sequential deletes | `KeyRepository.endSessionCleanup()` | Already handles WriteBatch for transfer + handshake + selectedSenderUid |
| Storage file deletion | Custom HTTP delete | `TransferRepository.deleteStorageFile(transferId)` | Already handles `object-not-found` gracefully |
| Handshake doc ID lookup | Re-implement query | `KeyRepository.getActiveHandshakeDocId(senderUid, receiverUid)` | Already exists and returns nullable String |
| Step tile animation widget | Build new widget | `_CleanStepTile` from EndSessionScreen | Copy verbatim — identical requirements |
| Session state broadcast | Custom ValueNotifier | `SessionManager.stateNotifier` | Already emits state changes; but ReceiverEndSessionScreen does not need it directly |
| Buffer zero on screen dispose | Manual fillRange in dispose | `SecurityLifecycleMixin` | Already handles via `wipeAll()` in dispose() |

---

## Current Navigation Flow (VERIFIED)

### DecryptScreen._saveAndWipe() — current navigation target

[VERIFIED: `lib/presentation/receiver/decrypt_screen.dart` lines 189–238]

Current `Navigator.pushReplacement` at line 215 navigates to `DownloadConfirmScreen` with these args:
- `transferId: widget.transferId`
- `fileName: _transfer.fileName`
- `fileSize: _transfer.fileSize`
- `senderUsername: _senderUsername`
- `senderId: _transfer.senderId`
- `receiverId: _transfer.receiverId`
- `savedPath: 'Downloads/${_transfer.fileName}'`
- `transferredAt: DateTime.now()`

**Phase 4 change:** Replace the `DownloadConfirmScreen(...)` route with `ReceiverEndSessionScreen(...)` using the same args minus `savedPath`, plus `senderUsername` (already present as `_senderUsername`).

Available data in `DecryptScreen` at the time `_saveAndWipe()` completes:
- `widget.transferId` — the transfer doc ID
- `_transfer.fileName` — file name
- `_transfer.fileSize` — file size in bytes
- `_transfer.senderId` — sender UID
- `_transfer.receiverId` — receiver UID
- `_senderUsername` — sender display username (loaded in `_loadTransfer()`)
- `DateTime.now()` — transfer timestamp (approximate; no exact Firestore timestamp available in DecryptScreen)

All required constructor args for `ReceiverEndSessionScreen` are available.

### TransferProgressScreen — current "End Session" path

[VERIFIED: `lib/presentation/sender/transfer_progress_screen.dart` lines 403–425]

Current `CrypButton("End Session")` at line 403 navigates to `EndSessionScreen(...)` with:
- `transferId: widget.transferId`
- `fileName: widget.fileName`
- `fileSize: widget.fileSize`
- `senderUsername: FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown'`
- `receiverUsername: widget.receiverUsername`
- `senderId: widget.senderId`
- `receiverId: widget.receiverId`
- `transferredAt: _completedAt ?? DateTime.now()`
- `aesKey: widget.aesKey`

**Phase 4 change:** Remove this entire CrypButton block. The `EndSessionScreen` import can be removed from `transfer_progress_screen.dart`.

### TransferProgressScreen — data available for SenderSessionEndedScreen

From `widget.*` fields at snapshot-exists detection time:
- `widget.transferId` — needed for D-10 edge-case check
- `widget.fileName` — display
- `widget.fileSize` — display
- `widget.receiverUsername` — display
- `widget.senderId` — display
- `widget.receiverId` — display

`widget.aesKey` is zeroed by `wipeAll()` before navigation and must NOT be passed.

---

## EndSessionScreen Pattern — Full Reference

[VERIFIED: `lib/presentation/session/end_session_screen.dart`]

### Constructor signature
```dart
EndSessionScreen({
  required String transferId,
  required String fileName,
  required int fileSize,
  required String senderUsername,
  required String receiverUsername,
  required String senderId,
  required String receiverId,
  required DateTime transferredAt,
  Uint8List? aesKey,
})
```

### _Step class
```dart
class _Step {
  final IconData icon;
  final String label;
  bool done = false;
  bool active = false;
  _Step({required this.icon, required this.label});
}
```

### _endSession() cleanup sequence (EndSessionScreen — sender-driven, for reference)
1. Step 0: Zero AES key from memory (`widget.aesKey!.fillRange(0, len, 0)`)
2. Step 1: Delete encrypted file from Firebase Storage
3. Step 2: Write immutable audit log (`WriteBatch` to both `audit_logs` subcollections)
4. Steps 3–5: `KeyRepository.getActiveHandshakeDocId()` then `endSessionCleanup()` (atomic WriteBatch: transfers + handshakes + selectedSenderUid)

**ReceiverEndSessionScreen cleanup sequence differs:**
- Step 0: Write audit log (FIRST — before deletion)
- Step 1: Delete Storage file
- Step 2: WriteBatch delete (`endSessionCleanup` — transfers + handshakes + selectedSenderUid)
- Step 3: `EncryptionService.closeReceiverSession(uid)` — RSA keys + publicKey Firestore + all handshakes for receiver

### _SummaryRow widget (private to EndSessionScreen — copy verbatim)
```dart
_SummaryRow({required IconData icon, required String label, required String value, required Color color})
// Width 68 label column, Expanded value
```

### _DoneStepRow widget (private to EndSessionScreen — copy verbatim)
Used in the done view's completed-steps summary inside the green container.

### AnimationController setup
```dart
_doneCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
_doneScale = CurvedAnimation(parent: _doneCtrl, curve: Curves.elasticOut);
// Forward at: setState(() => _phase = _Phase.done); _doneCtrl.forward();
```

Requires `SingleTickerProviderStateMixin` mixed in alongside `SecurityLifecycleMixin`.

---

## Firebase Constants Reference

[VERIFIED: `lib/core/constants/firebase_constants.dart`]

| Constant | Value | Used In |
|----------|-------|---------|
| `FirebaseConstants.users` | `'users'` | User doc reads/updates |
| `FirebaseConstants.transfers` | `'transfers'` | Transfer doc delete |
| `FirebaseConstants.handshakes` | `'handshakes'` | Handshake doc delete |
| `FirebaseConstants.auditLogs` | `'audit_logs'` | Audit log subcollection write |
| `FirebaseConstants.transfersStorageRoot` | `'transfers'` | Storage path prefix |
| `FirebaseConstants.encryptedFileName` | `'encrypted_file'` | Storage file name |
| `FirebaseConstants.privateKeyStorageKey` | `'rsa_private_key'` | SecureStorage key for private RSA key |

Storage path for deletion: `'transfers/{transferId}/encrypted_file'`
(equivalently: `${FirebaseConstants.transfersStorageRoot}/$transferId/${FirebaseConstants.encryptedFileName}`)

---

## closeReceiverSession(uid) — Complete Step Inventory

[VERIFIED: `lib/data/services/encryption_service.dart` lines 238–321]

| Step | Operation | Collection/Storage |
|------|-----------|-------------------|
| 0 | Read user doc to capture `selectedSenderUid` for audit context | `users/{uid}` |
| 1 | Firestore update: delete `publicKey`, set `isReadyToReceive=false`, `sessionActive=false`, `lastSessionClosed=serverTimestamp()`, delete `selectedSenderUid` | `users/{uid}` |
| 2 | SecureStorage delete: `rsa_private_key` | FlutterSecureStorage |
| 3 | Write kill-switch audit log (only if `selectedSenderUid` was non-null) | `transfer_logs` (top-level) |
| 4 | WriteBatch delete all `handshakes` WHERE `receiverId==uid` | `handshakes` |
| 5 | WriteBatch delete all `rsa_key_received` notifications from user's inbox | `users/{uid}/notifications` |
| 6 | Log security event (debugPrint + `security_audit_log`) | internal |
| 7 | `SecurityLifecycleMixin.requestNativeClear()` — Kotlin GC hint | MethodChannel |

**Critical note:** `closeReceiverSession(uid)` deletes ALL handshakes WHERE `receiverId==uid` — this is broader than just the current session's handshake. The D-03 Step 2 `endSessionCleanup()` already deletes the specific session handshake by doc ID; `closeReceiverSession` then purges any residual handshakes. This means the order (endSessionCleanup first, closeReceiverSession second) avoids double-delete conflicts — both are idempotent on Firestore.

---

## Firestore Transfer Document Structure

[VERIFIED: `lib/presentation/sender/transfer_progress_screen.dart` lines 158–174]

Fields written by `TransferProgressScreen._startUpload()`:
```
transfers/{transferId}:
  senderId: String
  receiverId: String
  encryptedAESKey: String (base64)
  encryptedFileUrl: String (download URL)
  fileName: String
  fileSize: int
  iv: String (base64)
  status: 'pending'
  sessionActive: bool
  createdAt: Timestamp
```

Fields added by `DecryptScreen` via `updateReceiverStatus()`:
```
  receiverStatus: 'downloading' | 'decrypting' | 'decrypted' | 'saved'
  receiverStatusUpdatedAt: Timestamp
  status: 'received' (via markReceived())
  receivedAt: Timestamp
```

The `encryptedAESKey` field is the key material at rest — its deletion is the primary zero-remanence goal for the transfer doc. It is deleted when `endSessionCleanup()` deletes the whole document.

---

## DownloadConfirmScreen Analysis

[VERIFIED: `lib/presentation/receiver/download_confirm_screen.dart`]

Current navigation into `DownloadConfirmScreen` is only from `DecryptScreen._saveAndWipe()` (line 216). Navigating out from `DownloadConfirmScreen` calls `_goToEndSession()` which navigates to `EndSessionScreen`.

After Phase 4:
- `DecryptScreen` no longer navigates to `DownloadConfirmScreen`
- `DownloadConfirmScreen` navigates to `EndSessionScreen` — both become dead code
- Removal is preferred per D-15/D-16

Check if anything else navigates to `DownloadConfirmScreen`:

Only `DecryptScreen` imports and uses `DownloadConfirmScreen` (confirmed by single import at line 19 of `decrypt_screen.dart`). Safe to remove. `EndSessionScreen` — only `TransferProgressScreen` (line 12 import) and `DownloadConfirmScreen` (line 11 import) navigate to it. After removing both callers, `EndSessionScreen` is unused.

---

## SenderSessionEndedScreen Design

[VERIFIED via D-09, D-10, D-11 in CONTEXT.md + existing TransferProgressScreen codebase]

### Constructor args (from TransferProgressScreen at detection time)
```dart
SenderSessionEndedScreen({
  required String transferId,    // needed for D-10 doc-existence check
  required String fileName,
  required int fileSize,
  required String receiverUsername,
  required String senderId,
  required String receiverId,
})
```

No `aesKey` — it is already zeroed by `wipeAll()` in `TransferProgressScreen.initState` registered buffers.

### D-10 edge-case check implementation
```dart
// In initState or _checkAndMarkDone():
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
// Then mark AES cleanup done
```

### Screen structure (static — no cleanup sequence, just display)
- `PopScope(canPop: false)` — no back nav (only "Back to Home" exits)
- Title: "Session Ended"
- Section 1 — "Receiver cleaned up:" (4 green check items):
  1. Audit log written
  2. Encrypted file deleted from storage
  3. Transfer record deleted
  4. RSA key wiped from device
- Section 2 — "Your device cleaned up:" (1 item, shown after D-10 check):
  1. AES key zeroed from memory
- CrypButton "Back to Home" → `Navigator.pushAndRemoveUntil(HomeScreen, (_) => false)`

---

## Common Pitfalls

### Pitfall 1: `!snapshot.exists` guard fires before upload completes
**What goes wrong:** If the listener is attached before the Firestore document is written, the initial snapshot may show `!snapshot.exists` (document not yet created) and incorrectly navigate the sender to `SenderSessionEndedScreen`.
**Why it happens:** `_startTransferListener()` is called in `initState()` at the same time as `_startUpload()`. The Firestore doc is written inside `_startUpload()` after the Storage upload completes. There is a window where the listener fires before the doc exists.
**How to avoid:** Guard the `!snapshot.exists` branch with `if (!_done) return;` — only treat a non-existent snapshot as "receiver cleaned up" after the upload is confirmed complete (`_done == true`). This is the same flag already used to gate the "End Session" CrypButton display.
**Warning signs:** SenderSessionEndedScreen appearing immediately without transfer completing.

### Pitfall 2: `endSessionCleanup()` called with null handshakeId
**What goes wrong:** `getActiveHandshakeDocId()` returns null if the handshake doc was already deleted (e.g., by a concurrent kill-switch). The `endSessionCleanup()` method handles null gracefully (guard at line 661: `if (handshakeId != null && handshakeId.isNotEmpty)`), so no crash, but the handshake is not deleted.
**Why it happens:** Race between `closeReceiverSession()` (which batch-deletes all handshakes WHERE receiverId==uid) and the explicit handshake delete in `endSessionCleanup()`.
**How to avoid:** Order matters: call `endSessionCleanup()` (Step 2) BEFORE `closeReceiverSession()` (Step 3). `endSessionCleanup()` will delete the specific session handshake; `closeReceiverSession()` then finds nothing to delete (idempotent). If order is reversed, `closeReceiverSession()` deletes all handshakes first, then `endSessionCleanup()` gets null handshakeId.
**Warning signs:** Handshake docs persisting after session end (check Firestore console).

### Pitfall 3: Receiver's receiverUsername not available in ReceiverEndSessionScreen
**What goes wrong:** `ReceiverEndSessionScreen` needs to display both sender username AND receiver username in the audit log. The receiver username is not passed from `DecryptScreen`.
**Why it happens:** `DecryptScreen` knows `_senderUsername` but not the current user's display name.
**How to avoid:** Get receiver username from `FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown'` inside `ReceiverEndSessionScreen._endSession()` at the time of audit log write — same pattern as `EndSessionScreen` step 2 (which uses senderUsername from widget). Alternatively, load it from the user profile if `displayName` may not match `username`.
**Warning signs:** Audit log has blank or incorrect `receiverUsername`.

### Pitfall 4: Double cleanup if PopScope allows back-nav from cleaning phase
**What goes wrong:** If `canPop` allows back during `_Phase.cleaning`, user could pop and re-trigger `_endSession()`.
**Why it happens:** Misimplementation of the PopScope gate.
**How to avoid:** `canPop: _phase == _Phase.ready` — same as `EndSessionScreen`. This blocks back nav during `cleaning` AND `done` phases.
**Warning signs:** Duplicate audit log entries in Firestore.

### Pitfall 5: wipeAll() in TransferProgressScreen zeroing already-registered buffers
**What goes wrong:** `widget.encryptedBytes` and `widget.aesKey` are both registered in `initState()` (lines 73–74 of `transfer_progress_screen.dart`). Calling `wipeAll()` in the `!snapshot.exists` branch zeros them — correct. But if `_startTransferListener` fires multiple times (e.g., due to stream reconnection), `wipeAll()` is called again on already-zeroed buffers.
**Why it happens:** Streams can reconnect.
**How to avoid:** Add a `_sessionEnded` bool guard. Once set to true, the listener returns immediately. Also, `wipeAll()` is safe to call multiple times (zeroing zeros is harmless; registry is cleared after first call so second call is a no-op).
**Warning signs:** None — this is inherently safe but good to be explicit.

---

## Code Examples

### ReceiverEndSessionScreen._endSession() — step sequence

[VERIFIED: pattern from `lib/presentation/session/end_session_screen.dart` + D-03 decisions]

```dart
Future<void> _endSession() async {
  setState(() { _phase = _Phase.cleaning; _error = null; });

  if (widget.transferId.isEmpty || widget.receiverId.isEmpty) {
    setState(() { _phase = _Phase.ready; _error = 'Missing session identifiers.'; });
    return;
  }

  try {
    // Step 0: Write immutable audit log FIRST (before any deletion)
    await tick(0);
    final receiverUsername = FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown';
    final auditPayload = { /* senderId, receiverId, senderUsername, receiverUsername, ... */ };
    final auditBatch = FirebaseFirestore.instance.batch();
    auditBatch.set(/* users/{senderId}/audit_logs/{newDoc} */, auditPayload);
    auditBatch.set(/* users/{receiverId}/audit_logs/{newDoc} */, auditPayload);
    await auditBatch.commit();
    await done(0);

    // Step 1: Delete encrypted file from Firebase Storage
    await tick(1);
    await _repo.deleteStorageFile(widget.transferId);  // TransferRepository
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
      setState(() { _phase = _Phase.ready; _error = e.toString(); });
    }
  }
}
```

### TransferProgressScreen — modified _startTransferListener

[VERIFIED: `lib/presentation/sender/transfer_progress_screen.dart` lines 97–122 + D-06/D-07]

```dart
bool _sessionEnded = false; // guard against double-fire

void _startTransferListener() {
  _transferListener = FirebaseFirestore.instance
      .collection('transfers')
      .doc(widget.transferId)
      .snapshots()
      .listen((snapshot) {
    // D-06: detect receiver cleanup — doc deleted
    if (!snapshot.exists) {
      if (!_done || _sessionEnded) return; // only react after upload complete
      _sessionEnded = true;
      wipeAll(); // zeros widget.encryptedBytes + widget.aesKey (registered in initState)
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

    // Existing logic unchanged:
    final data = snapshot.data()!;
    final receiverStatus = data['receiverStatus'] as String?;
    if (receiverStatus == 'decrypted' && mounted) {
      setState(() { _receiverDecrypted = true; _statusMessage = '✅ Receiver successfully decrypted file'; });
      _clearSenderLocalMetadata();
    }
    if (receiverStatus == 'saved' && mounted) {
      setState(() { _statusMessage = '✅ Receiver saved the file securely'; _canEndSession = true; });
    }
  });
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Sender-driven session end (manual "End Session" button) | Receiver-driven (receiver triggers cleanup; sender reacts reactively) | Phase 4 | Sender cannot end session unilaterally — receiver controls cleanup timing |
| DownloadConfirmScreen intermediate step | Direct to ReceiverEndSessionScreen post-decrypt | Phase 4 | Removes one navigation hop; receiver sees session summary before cleanup |
| TransferProgressScreen listener ignores `!snapshot.exists` | Listener reacts to `!snapshot.exists` as cleanup signal | Phase 4 | Enables reactive sender termination |

**Deprecated/outdated after Phase 4:**
- `EndSessionScreen`: No longer navigated to from any screen (callers removed in Phase 4). Can be deleted.
- `DownloadConfirmScreen`: No longer navigated to from `DecryptScreen`. Can be deleted.
- Manual "End Session" `CrypButton` in `TransferProgressScreen`: Removed.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `FirebaseAuth.instance.currentUser?.displayName` returns the receiver's username at the time `_endSession()` runs | Code Examples | Audit log has wrong `receiverUsername`; mitigation: load from Firestore user doc instead |
| A2 | `_done == true` is a reliable gate for `!snapshot.exists` (upload completes before receiver can trigger cleanup) | Pitfall 1 | False positive navigation to `SenderSessionEndedScreen` during upload; add `_sessionEnded` guard as belt-and-suspenders |

All other claims are VERIFIED against source files.

---

## Open Questions (RESOLVED)

1. **ReceiverEndSessionScreen: 4 steps or 6?**
   - What we know: `EndSessionScreen` has 6 steps. D-03 specifies 4 logical phases for receiver cleanup. D-13 says "6 steps matching `EndSessionScreen._steps`".
   - What's unclear: D-03 and D-13 appear to conflict — D-03 has 4 numbered items; D-13 says "6 steps." The reconciled interpretation: receiver has 4 steps (audit log, storage delete, WriteBatch delete, closeReceiverSession). "Matching EndSessionScreen._steps" in D-13 refers to the pattern (same `_CleanStepTile` widget), not the count.
   - **RESOLVED (Plan 02): 4 steps** — D-03 sequence takes precedence; D-13 references the `_CleanStepTile` pattern, not the step count.

2. **SenderSessionEndedScreen: Apply SecurityLifecycleMixin?**
   - What we know: No sensitive buffers are held in this screen. Claude's discretion per analysis.
   - **RESOLVED (Plan 03): Applied** — `SecurityLifecycleMixin<SenderSessionEndedScreen>` applied as defensive practice; no buffers registered (AES already zeroed upstream).

3. **Receiver username source**
   - What we know: `FirebaseAuth.instance.currentUser?.displayName` may not match `users/{uid}.username` (they are set independently).
   - **RESOLVED (Plan 02): `FirebaseAuth.instance.currentUser?.displayName ?? 'Unknown'`** — consistent with `EndSessionScreen` pattern; acceptable for audit log context.

---

## Environment Availability

Step 2.6: SKIPPED — no external dependencies beyond the existing Flutter/Firebase stack. All required packages are already in `pubspec.yaml`. No new tools, CLIs, or services required.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | flutter_test + fake_cloud_firestore + firebase_auth_mocks |
| Config file | None (standard flutter test runner) |
| Quick run command | `flutter test test/security/session_termination_test.dart` |
| Full suite command | `flutter test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| TERM-01 | Receiver end session writes audit log to both subcollections before deletion | unit | `flutter test test/security/session_termination_test.dart::TC-TERM-001` | ❌ Wave 0 |
| TERM-02 | Receiver end session deletes Storage file (object-not-found tolerated) | unit | `flutter test test/security/session_termination_test.dart::TC-TERM-002` | ❌ Wave 0 |
| TERM-03 | WriteBatch deletes transfers/{id} + handshakes/{id} atomically | unit | `flutter test test/security/session_termination_test.dart::TC-TERM-003` | ❌ Wave 0 |
| TERM-04 | closeReceiverSession() deletes publicKey + private key after endSessionCleanup() | unit | `flutter test test/security/session_termination_test.dart::TC-TERM-004` | ❌ Wave 0 |
| TERM-05 | Sender stream detects !snapshot.exists and triggers wipeAll() | unit | `flutter test test/security/session_termination_test.dart::TC-TERM-005` | ❌ Wave 0 |
| TERM-06 | Back navigation blocked during ReceiverEndSessionScreen cleanup phase | manual | N/A — PopScope canPop logic | N/A |
| TERM-07 | SenderSessionEndedScreen "Back to Home" clears navigation stack | manual | N/A — Navigator stack | N/A |
| TERM-08 | D-10 edge case: sender deletes transfer doc if it still exists on arrival | unit | `flutter test test/security/session_termination_test.dart::TC-TERM-008` | ❌ Wave 0 |

### Sampling Rate
- **Per task commit:** `flutter test test/security/session_termination_test.dart -x`
- **Per wave merge:** `flutter test`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps
- [ ] `test/security/session_termination_test.dart` — covers TERM-01 through TERM-05, TERM-08
- [ ] No new conftest/setup needed — `FakeFirebaseFirestore` + `FakeSecureStorage` patterns are established in `test/mocks/mock_firebase.dart`

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | N/A — no auth changes |
| V3 Session Management | yes | Sequential cleanup order (audit → delete); PopScope block during cleanup |
| V4 Access Control | no | N/A |
| V5 Input Validation | no | transferId/receiverId emptiness check before cleanup |
| V6 Cryptography | yes | RSA private key deleted from SecureStorage; AES key zeroed via fillRange before navigation |

### Known Threat Patterns for this Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Ghost key material after session end | Information Disclosure | `wipeAll()` zeros buffers before navigation; `closeReceiverSession()` deletes Firestore publicKey + SecureStorage privateKey |
| Partial cleanup on Firestore write failure | Tampering | Audit log written first; WriteBatch makes transfer+handshake delete atomic |
| Sender re-using stale AES key reference | Information Disclosure | `wipeAll()` called in `_startTransferListener` before any navigation; AES buffer is registered and zeroed |
| Transfer doc deletion race (receiver cleans before sender marks metadata_cleared) | Denial of Service | `_clearSenderLocalMetadata()` update may fail with Firestore "document not found" — wrap in try/catch; non-critical metadata path |

---

## Sources

### Primary (HIGH confidence)
All findings verified directly against codebase source files — no external documentation consulted.

- `lib/presentation/session/end_session_screen.dart` — `_CleanStepTile`, `_Step`, `_Phase`, `_endSession()` sequence, `_buildReady()`, `_buildCleaning()`, `_buildDone()`, `_SummaryRow`, `_DoneStepRow` — copied as canonical template
- `lib/presentation/receiver/decrypt_screen.dart` — `_saveAndWipe()` navigation target, all available data at save time
- `lib/presentation/sender/transfer_progress_screen.dart` — `_startTransferListener()` current implementation, all widget fields, registered buffers
- `lib/data/services/encryption_service.dart` — `closeReceiverSession()` full step inventory, `bindSession()`/`unbindSession()`
- `lib/core/utils/security_lifecycle_mixin.dart` — `registerBuffer()`, `unregisterBuffer()`, `wipeAll()`, `requestNativeClear()`
- `lib/data/repositories/key_repository.dart` — `endSessionCleanup()`, `getActiveHandshakeDocId()`, `selectSenderHandshake()` WriteBatch pattern
- `lib/data/repositories/transfer_repository.dart` — `deleteStorageFile()`, `updateReceiverStatus()`, `writeAuditLog()`
- `lib/core/constants/firebase_constants.dart` — all collection names and storage constants
- `lib/core/utils/session_manager.dart` — `wipeSession()`, `stateStream`, `stateNotifier`
- `lib/core/utils/session_state.dart` — `SessionState` enum
- `lib/presentation/widgets/shared_widgets.dart` — `CrypButton` full signature and session-state behavior
- `lib/app_theme.dart` — `AppTheme.darkBg`, `darkSurface`, `textMain`, `textSecondary`
- `test/security/session_wipe_test.dart` — existing test patterns (FakeFirebaseFirestore, test structure)
- `test/mocks/mock_firebase.dart` — `FakeSecureStorage`, `MockFirebaseStorage` available for new tests
- `.planning/phases/04-zero-remanence-reactive-session-termination-receiver-as-mast/04-CONTEXT.md` — all locked decisions

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all verified against pubspec and existing imports
- Architecture: HIGH — all patterns verified against existing code
- Navigation flow: HIGH — read every relevant `_saveAndWipe()` and listener line
- Pitfalls: HIGH — derived from reading actual code behavior, not guesswork
- Test cases: MEDIUM — test IDs are new (no existing TERM tests), but framework/mock patterns are HIGH confidence

**Research date:** 2026-05-07
**Valid until:** 2026-06-07 (stable Flutter/Firebase stack; no fast-moving dependencies)
