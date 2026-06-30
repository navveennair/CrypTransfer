---
status: resolved
trigger: "receiver received file but not moving forward to decrypt file"
created: 2026-06-05
updated: 2026-06-05
---

## Symptoms

- **Expected**: After sender sends encrypted file, receiver should auto-navigate from ReceiverScreen to ReceiverTransferScreen (decrypt flow)
- **Actual**: Receiver gets a notification/signal that sender sent an encrypted file, but stays on ReceiverScreen — no navigation occurs
- **Errors**: Log shows `🛡️ [2026-06-05T14:51:16.769916] Receiver_Session_Closed | Firestore_Key_Deleted & Local_Buffer_Zeroed` firing — session is being WIPED before decryption can start
- **Timeline**: Broke after a recent code change (was working before)
- **Reproduction**: Complete sender-receiver handshake, sender sends encrypted file, observe receiver side

## Evidence

- timestamp: 2026-06-05
  type: code_analysis
  finding: |
    `_startSenderPresenceWatch` was added in commit 2cae827. The "abandoned" branch
    fires when `_senderPresenceConfirmed = true` AND `pendingSenderFor != receiverUid`.
    The guard was only `if (!mounted || _sessionLocked) return;` — but `_sessionLocked`
    is set INSIDE `_handleIncomingTransfer`, which runs via `addPostFrameCallback`
    (deferred to next frame). In the window between the transfer doc appearing in
    Firestore and `_sessionLocked` being set (the next frame), if the presence watch
    fires an abandoned snapshot, it resets `_transferStream = null`, `_handshakeDone = false`,
    removing the StreamBuilder from the widget tree and preventing the incoming transfer
    from ever triggering `_handleIncomingTransfer`.

- timestamp: 2026-06-05
  type: code_analysis
  finding: |
    `_incomingHandled` was never reset in `_onToggleReady(false)`. If the receiver
    closes and reopens the mailbox, or if a session reset occurs (e.g., from the
    presence watch abandoned branch resetting state causing `_incomingHandshakeSub`
    to call `_onSenderSelected` again), any subsequent transfer would be silently
    ignored because `_incomingHandled = true` blocks the detection logic.

## Current Focus

- hypothesis: "Two related bugs in receiver_screen.dart introduced by commit 2cae827"
- test: "flutter analyze passes — no issues"
- expecting: "Navigation to decrypt proceeds when transfer doc arrives"
- next_action: "COMPLETE — fix applied"
- reasoning_checkpoint: |
    Root cause confirmed: `_startSenderPresenceWatch` abandoned branch had insufficient
    guard — `_incomingHandled` was not checked, allowing session state to be torn down
    even when a transfer was already being queued for processing. Additionally,
    `_incomingHandled` was never reset on session close, blocking subsequent transfers.

## Resolution

- root_cause: |
    Two bugs introduced in commit 2cae827's `_startSenderPresenceWatch` function:
    1. The abandoned branch guard only checked `_sessionLocked` (set in next frame via
       addPostFrameCallback), not `_incomingHandled` (set synchronously when transfer
       detected). Race window: transfer doc arrives → `_incomingHandled = true` → post-frame
       callback scheduled → presence watch fires with `_sessionLocked = false` (not yet set)
       → abandoned branch tears down `_transferStream = null`, `_handshakeDone = false` →
       StreamBuilder removed from widget tree → transfer doc arrival never triggers
       `_handleIncomingTransfer` → no navigation.
    2. `_incomingHandled` was never reset in `_onToggleReady(false)`, causing subsequent
       transfers (after any session reset/reopen) to be silently ignored.
- fix: |
    Fix 1: Extended the presence watch guard from `!_sessionLocked` to
    `!_sessionLocked || _incomingHandled` — once a transfer is already in the
    processing pipeline, the abandoned branch cannot fire.
    Fix 2: Added `_incomingHandled = false` to the `_onToggleReady(false)` setState
    block so the flag is properly reset when the session closes.
- files_changed:
  - lib/presentation/receiver/receiver_screen.dart
    - Line 436: guard extended to `if (!mounted || _sessionLocked || _incomingHandled) return;`
    - Line 310: `_incomingHandled = false;` added to _onToggleReady(false) setState block
