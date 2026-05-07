# Phase 4: Zero Remanence Reactive Session Termination - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-07
**Phase:** 04-zero-remanence-reactive-session-termination-receiver-as-mast
**Areas discussed:** Receiver trigger point, Receiver cleanup scope, Sender destination screen, Audit log in reactive flow, Sender cleanup step visibility, Sender reactive listener mechanism, Receiver nav flow

---

## Receiver Trigger Point

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-fire after save | Cleanup fires automatically inside _saveAndWipe() — no extra screen | |
| Dedicated 'End Session' screen for receiver | Receiver lands on a confirmation/summary screen and presses "End Session" manually | ✓ |
| Immediate + undo window | Auto-fire with 5-second snackbar countdown to cancel | |

**User's choice:** Dedicated 'End Session' screen for receiver  
**Notes:** Receiver should review before data is permanently purged.

---

## Receiver Navigation Flow

| Option | Description | Selected |
|--------|-------------|----------|
| DecryptScreen → ReceiverEndSessionScreen directly | pushReplacement from DecryptScreen, absorbing DownloadConfirmScreen step | ✓ |
| DownloadConfirmScreen → then End Session | Keep DownloadConfirmScreen, add End Session button to it | |

**User's choice:** Direct from DecryptScreen  
**Notes:** DownloadConfirmScreen is bypassed in the new flow.

---

## Receiver Cleanup Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Full zero-remanence: closeReceiverSession() | Wipes RSA private key, Firestore public key, handshakes — complete wipe | ✓ |
| Transfer-only cleanup | Only transfer doc + handshake; RSA keys remain intact | |

**User's choice:** Full zero-remanence  
**Notes:** Receiver must regenerate RSA keys for next transfer session.

---

## Audit Log in Reactive Flow

| Option | Description | Selected |
|--------|-------------|----------|
| Receiver writes it before cleanup | Step 1 before WriteBatch deletion; mirrors existing EndSessionScreen | ✓ |
| Skip audit log | Transfer doc serves as the record; simpler cleanup | |

**User's choice:** Receiver writes it before cleanup  
**Notes:** Immutable personal copy preserved even if later cleanup steps fail.

---

## Sender Destination Screen

**User's freeform response:** "Show what the Receiver has cleaned up. Sender should check if the AESKey is written in firebase. If yes, perform an AESKey cleanup + let sender know what receiver has cleaned up. Be precise. I dont want anything that is misleading the user."

**Decision captured:** New `SenderSessionEndedScreen` with precise two-section layout (Receiver cleaned up / Your device). AES key existence check in Firestore before confirming local wipe.

---

## Sender Cleanup Step Visibility

| Option | Description | Selected |
|--------|-------------|----------|
| Precise two-section list | "Receiver cleaned up:" + "Your device:" each with ✓ checklist | ✓ |
| Single summary message | Simple "Session ended by receiver" card | |

**User's choice:** Precise two-section list  
**Notes:** Attribution honesty — user explicitly rejected misleading UX.

---

## Sender Reactive Listener Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| Extend existing listener to check !snapshot.exists | Minimal change to _startTransferListener | ✓ |
| New dedicated signal doc | Receiver writes signal before deletion; sender listens to it | |

**User's choice:** Extend existing listener  
**Notes:** The `_startTransferListener` stream already runs — just add the `!snapshot.exists` branch.

---

## Claude's Discretion

- `DownloadConfirmScreen` fate — user did not specify; planner should remove if unused
- Exact `ReceiverEndSessionScreen` UI layout within the established step-card pattern
- Whether to delete `EndSessionScreen` class entirely or leave as dead code

## Deferred Ideas

None raised during discussion.
