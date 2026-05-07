# Phase 4: Zero Remanence Reactive Session Termination - Context

**Gathered:** 2026-05-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Flip session termination control from sender to receiver. The receiver drives atomic cleanup after
a file is saved; the sender's existing Firestore stream listener reacts to the transfer document
disappearing and auto-wipes local state. No "End Session" button on the sender side.

Two new screens are introduced:
- `ReceiverEndSessionScreen` — receiver reviews session and triggers cleanup
- `SenderSessionEndedScreen` — sender sees precisely what the receiver cleaned + local AES wipe

</domain>

<decisions>
## Implementation Decisions

### Receiver Trigger Point
- **D-01:** After `DecryptScreen._saveAndWipe()` succeeds, navigate via `pushReplacement` **directly to `ReceiverEndSessionScreen`** — `DownloadConfirmScreen` is no longer in the post-decrypt flow.
- **D-02:** Cleanup is NOT auto-fired on save. The receiver lands on `ReceiverEndSessionScreen`, reviews the session summary (fileName, sender, fileSize), and presses "End Session" to trigger cleanup explicitly.

### Receiver Cleanup Sequence
- **D-03:** Receiver's "End Session" button triggers a sequential cleanup — order matters for atomicity and audit integrity:
  1. Write audit log to `users/{senderId}/audit_logs` AND `users/{receiverId}/audit_logs` (before any deletion — immutable record first)
  2. Delete Firebase Storage file: `transfers/{transferId}/encrypted_file`
  3. Atomic `WriteBatch`: delete `transfers/{transferId}` document (which contains `encryptedAESKey` field) + delete `handshakes` doc for this session pair
  4. Call `EncryptionService.closeReceiverSession(uid)` — wipes RSA private key from `FlutterSecureStorage`, deletes `publicKey` + `selectedSenderUid` from Firestore, purges all handshakes for this receiver
- **D-04:** Full zero-remanence scope — the receiver's cleanup is a complete wipe including RSA keys, not just the transfer record. Receiver must re-generate RSA keys for the next transfer session.
- **D-05:** Audit log payload mirrors the existing `EndSessionScreen` pattern: `{senderId, receiverId, senderUsername, receiverUsername, fileName, fileSize, status: 'completed', timestamp, loggedAt}`. Written via `WriteBatch` to both users' `audit_logs` subcollections atomically.

### Sender Reactive Listener
- **D-06:** Extend the existing `_startTransferListener` in `TransferProgressScreen` to check `!snapshot.exists`. When the receiver's WriteBatch deletes `transfers/{transferId}`, the Firestore snapshot stream emits a non-existent snapshot — sender detects this and acts.
- **D-07:** On `!snapshot.exists` detection, sender:
  1. Calls `SecurityLifecycleMixin.wipeAll()` to zero all registered buffers (including `widget.aesKey`)
  2. Navigates via `pushReplacement` to `SenderSessionEndedScreen`, passing metadata for display (fileName, receiverUsername, list of what receiver cleaned)
- **D-08:** Remove the manual "End Session" `CrypButton` from `TransferProgressScreen`. The sender side is fully reactive — no user action required or permitted.

### SenderSessionEndedScreen
- **D-09:** New screen (not the existing `EndSessionScreen`). Shows two precise sections:
  - **"Receiver cleaned up:"** — checklist with `✓` for: audit log written, encrypted file deleted, transfer record deleted, RSA key wiped
  - **"Your device cleaned up:"** — checklist with `✓` for: AES key zeroed from memory
- **D-10:** Before showing the "Your device" section as complete, sender checks if `transfers/{transferId}` doc still exists (edge-case safety net). If it still exists, sender performs a delete before marking the AES key cleanup done. In the normal flow, the doc is already gone.
- **D-11:** "Back to Home" is the only action. `Navigator.pushAndRemoveUntil` to `HomeScreen`, clearing the full stack.

### ReceiverEndSessionScreen
- **D-12:** Displays a session summary card identical in structure to the existing `EndSessionScreen._buildReady()`: fileName, fileSize, sender username, transfer timestamp — passed as constructor args from `DecryptScreen`.
- **D-13:** Shows the cleanup step list (6 steps matching `EndSessionScreen._steps`) before cleanup starts, then animates them done during cleanup. Same `_CleanStepTile` pattern.
- **D-14:** Apply `SecurityLifecycleMixin` to `ReceiverEndSessionScreen` (established pattern for all screens handling sensitive data).

### DownloadConfirmScreen
- **D-15 (Claude's Discretion):** `DownloadConfirmScreen` is no longer navigated to from the post-decrypt flow. Planner may remove it or leave it in place as dead code — removal is preferred if no other screens navigate to it.

### Existing EndSessionScreen
- **D-16:** The existing `EndSessionScreen` (sender-driven) is no longer navigated to from `TransferProgressScreen`. Planner should remove the navigation call from `TransferProgressScreen`. Whether to delete `EndSessionScreen` itself is Claude's discretion — it is currently unused after Phase 4.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Primary screens to modify
- `lib/presentation/receiver/decrypt_screen.dart` — `_saveAndWipe()` navigation target changes to `ReceiverEndSessionScreen`; pass transferId, fileName, fileSize, senderUsername, senderId, receiverId
- `lib/presentation/sender/transfer_progress_screen.dart` — extend `_startTransferListener` to check `!snapshot.exists`; remove "End Session" button + `EndSessionScreen` navigation
- `lib/presentation/session/end_session_screen.dart` — pattern reference for cleanup step UI, audit log payload, `_CleanStepTile` widget; may be removed from production flow

### Services for cleanup
- `lib/data/services/encryption_service.dart` — `closeReceiverSession(uid)` (step 4 of receiver cleanup); `bindSession()` / `unbindSession()` pattern for reference
- `lib/core/utils/security_lifecycle_mixin.dart` — `registerBuffer()`, `wipeAll()`, `requestNativeClear()` — apply to both new screens

### Repositories
- `lib/data/repositories/key_repository.dart` — `endSessionCleanup()` (atomic WriteBatch pattern), `getActiveHandshakeDocId()` — may be extended or reused for receiver's atomic cleanup
- `lib/data/repositories/transfer_repository.dart` — transfer document operations, `updateReceiverStatus()`

### Constants and patterns
- `lib/core/constants/firebase_constants.dart` — `transfers`, `handshakes`, `auditLogs`, `transfersStorageRoot`, `encryptedFileName`, `privateKeyStorageKey`
- `lib/presentation/widgets/shared_widgets.dart` — `CrypButton` for "End Session" button on `ReceiverEndSessionScreen`
- `lib/app_theme.dart` — GitHub Dark palette; new screens follow the same theme

### State management
- `lib/core/utils/session_manager.dart` — `wipeSession()`, `stateNotifier` — `ReceiverEndSessionScreen` should propagate `SessionManager` if accessible, or call cleanup directly
- `lib/core/utils/session_state.dart` — `SessionState` enum

### Prior phase context
- `.planning/phases/03-managed-profile-rsa-vault/03-CONTEXT.md` — `closeReceiverSession()` context, WriteBatch pattern, audit log decisions

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `EndSessionScreen._buildCleaning(cs)` and `_CleanStepTile` widget — copy this step-animation pattern into `ReceiverEndSessionScreen` for the cleanup progress view
- `EndSessionScreen._buildDone(cs)` — copy the success animation (green shield icon + `ScaleTransition`) for both new screens
- `EndSessionScreen._endSession()` — reference implementation for the sequential cleanup steps; `ReceiverEndSessionScreen` follows the same tick/done pattern
- `CrypButton` — use for "End Session" button on `ReceiverEndSessionScreen`
- `SecurityLifecycleMixin` — apply to both new screens via `with SecurityLifecycleMixin<T>`

### Established Patterns
- `WriteBatch` for atomic multi-document Firestore ops (Phase 03 established; `endSessionCleanup()` in `KeyRepository` is an existing atomic batch pattern)
- `compute()` for crypto ops — not needed here (cleanup is Firestore/Storage, not crypto)
- `pushReplacement` for navigation that should not be back-navigable (established in `EndSessionScreen._buildDone`)
- `Navigator.pushAndRemoveUntil` for "Back to Home" full-stack clear
- `PopScope(canPop: _phase == _Phase.ready)` — prevent back-nav during cleanup (same as `EndSessionScreen`)

### Integration Points
- `DecryptScreen._saveAndWipe()` → `pushReplacement` to `ReceiverEndSessionScreen` with constructor args: `{transferId, fileName, fileSize, senderUsername, senderId, receiverId, transferredAt}`
- `TransferProgressScreen._startTransferListener` → add `if (!snapshot.exists) { wipeAll(); pushReplacement(SenderSessionEndedScreen) }`
- `SenderSessionEndedScreen` receives: `{transferId, fileName, receiverUsername, senderId, receiverId, aesKey?}` from `TransferProgressScreen`
- `EncryptionService.closeReceiverSession(uid)` is the final cleanup step called from `ReceiverEndSessionScreen._endSession()`

### What to Remove
- `EndSessionScreen` navigation from `TransferProgressScreen` (the `CrypButton` "End Session" and its `onPressed` block)
- `DownloadConfirmScreen` usage from `DecryptScreen` if it navigates there post-save

</code_context>

<specifics>
## Specific Ideas

- **Sender precision over simplicity**: "I don't want anything that is misleading the user" — the sender screen must clearly attribute each cleanup action to who did it (receiver vs. device).
- **AES key safety check**: Sender checks if `transfers/{transferId}` doc still exists as an edge-case safety net before marking AES key cleanup done. Normal path: doc is already gone by the time the listener fires.
- **Audit log first**: The audit log is written as step 1 — before any Firestore document deletion — so the immutable record survives even if a later cleanup step fails.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast*
*Context gathered: 2026-05-07*
