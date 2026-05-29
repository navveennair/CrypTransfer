# Phase 9: Navigation Safety & Session Integrity Hardening - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-29
**Phase:** 09-navigation-safety-session-integrity-hardening
**Areas discussed:** Back-nav dialog copy, Change File secondary action, Stale key reset depth

---

## Back-nav dialog copy

| Option | Description | Selected |
|--------|-------------|----------|
| Reuse _showCloseSessionDialog() | Same BottomSheet, same copy. Consistent UX — one dialog for all session-close triggers. | ✓ |
| New 'Leave Receive Mode?' dialog | Shorter alert tailored to back-nav context. More accurate messaging but adds a second dialog path. | |

**User's choice:** Reuse `_showCloseSessionDialog()` — consistent, no extra code path.

**Notes:** SnackBar for `_sessionLocked` back-nav also reuses existing copy: "Cannot close session — transfer in progress."

---

## Change File secondary action

| Option | Description | Selected |
|--------|-------------|----------|
| TextButton link below FileCard | Disable CrypButton + small TextButton 'Change File' below _FileCard. Click shows ConfirmationDialog. | ✓ |
| Warning-tinted CrypButton replaces Browse button | cs.error colour CrypButton, icon: warning_amber. Click shows ConfirmationDialog. | |
| Lock icon overlay on FileCard | Lock IconButton inside FileCard header row. Less discoverable. | |

**User's choice:** TextButton link below FileCard (subtle secondary action).

**Dialog copy chosen:** "This will wipe your encrypted data and AES key. Are you sure?" — technical/accurate wording preferred over softer copy.

---

## Stale key reset depth

| Option | Description | Selected |
|--------|-------------|----------|
| Light wipe — _wipeSensitiveData() only | Clears crypto, preserves _file and receiver connection. User re-encrypts immediately. | ✓ |
| Full revert — _revertToWaiting() | Full reset including disconnect. Safer but disruptive. | |

**User's choice:** Light wipe — preserves `_file` and connection.

**Mid-flight guard:** Defer wipe when `_encrypting || _encryptingKey` — same guard as all other wipe paths.

**Additional decision surfaced:** When the receiver opens the mailbox (`_isReadyToReceive = true`), grey out Step 1 (RSA Keypair StepCard) + disable AppBar Key Manager button via `AnimatedOpacity(opacity: 0.4) + IgnorePointer`. Prevents RSA key regeneration mid-session — preventive complement to the reactive stale-key fix.

**Step 1 lockout UX chosen:** `AnimatedOpacity(0.4) + IgnorePointer` — matches existing stepper gating pattern throughout both screens.

---

## Claude's Discretion

- Exact placement of stale-key comparison (capture old value before setState)
- `AlertDialog` wrapper implementation details
- `onPopInvokedWithResult` priority order (check `_sessionLocked` → `_isReadyToReceive` → base case)
- Mid-flight guard placement in `_onHandshakeUpdate`
