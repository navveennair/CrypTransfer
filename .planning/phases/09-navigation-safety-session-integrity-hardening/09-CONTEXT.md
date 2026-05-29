# Phase 9: Navigation Safety & Session Integrity Hardening - Context

**Gathered:** 2026-05-29
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix three code-verified gaps in navigation safety and session integrity across `receiver_screen.dart` and `sender_screen.dart`. No new screens, no Firestore schema changes, no new collections — pure hardening of existing flows.

**In scope:**
1. ReceiverScreen back-nav: `canPop: true` → guarded pop with confirmation dialog and `_sessionLocked` block
2. SenderScreen stale `_encryptedAESKey`: invalidate encrypted key when receiver's RSA public key changes mid-session
3. SenderScreen Step 1 re-pick UX: disable "Browse Files" after `_fileEncrypted`; add confirmed "Change File" secondary action
4. ReceiverScreen Step 1 lockout: grey out RSA Keypair step while mailbox is open (preventive complement to gap 2)

**Out of scope:** New screens, Firestore rule changes, receiver transfer flow, admin screens, any UI theming.

</domain>

<decisions>
## Implementation Decisions

### Gap 1 — ReceiverScreen back-nav confirmation

- **D-01:** Change `canPop` from `true` to `_isReadyToReceive ? false : (_handshakeDocId == null)` — pop is blocked (requiring interception) only when the mailbox is open. When the mailbox is not open and there is no handshake, back-nav proceeds freely.
- **D-02:** When `_isReadyToReceive` is true and user taps back: call `_showCloseSessionDialog()` (existing BottomSheet) — reuse as-is. Same copy ("Close your secure mailbox?"), same cancel/confirm behaviour. If confirmed, call `_sessionManager.wipeSession(onBuffersWipe: wipeAll)` then pop. If cancelled, do nothing.
- **D-03:** When `_sessionLocked` is true (transfer in progress) and user taps back: show SnackBar with existing copy "Cannot close session — transfer in progress." Do NOT pop. Consistent with the toggle path.
- **D-04:** When `_isReadyToReceive` is false AND `_handshakeDocId != null`: keep current silent behaviour — clear transfer roles via `_connService.clearTransferRoles(handshakeDocId: _handshakeDocId!)` and allow pop. No confirmation needed (mailbox not open, no key material at risk).

### Gap 2 — SenderScreen stale _encryptedAESKey invalidation

- **D-05:** In `_onHandshakeUpdate`, in the `else` branch where `publicKey` is valid and `status == 'handshake_complete'`: after setting `_selectedReceiverPublicKeyJson = publicKey`, add a check: if `publicKey != _selectedReceiverPublicKeyJson` (key changed from previous value) AND `_encryptedAESKey != null`, call `_wipeSensitiveData()` and show SnackBar "Receiver key changed — re-encrypt required."
- **D-06:** Mid-flight guard: apply the same guard as all other wipe paths — `if (_encrypting || _encryptingKey) return` before the stale key check. If encryption is in flight, defer (return early); the stream will fire again after compute() completes.
- **D-07:** Reset depth: **light wipe only** — call `_wipeSensitiveData()` (clears `_encryptedBytes`, `_encryptedAESKey`, `_aesKey`, `_iv`, calls `wipeAll()`). Do NOT call `_revertToWaiting()`. `_file` is preserved — user can re-encrypt the same file immediately. Receiver connection (`_receiverId`, `_receiverReady`) is preserved.

### Gap 3 — SenderScreen Step 1 re-pick UX lock

- **D-08:** After `_fileEncrypted` is true, set the "Browse Files" CrypButton `onPressed: null` (disabled/greyed). The file card (`_FileCard`) remains visible below it.
- **D-09:** Add a `TextButton` labelled "Change File" immediately below the `_FileCard` widget, visible only when `_fileEncrypted` is true. Use `cs.onSurfaceVariant` colour (secondary/subtle). Tapping shows an `AlertDialog` with:
  - Title: "Change File?"
  - Content: "This will wipe your encrypted data and AES key. Are you sure?"
  - Actions: "Cancel" (dismiss) and "Confirm" (calls `_wipeSensitiveData()` then calls `_pickFile()`)
- **D-10:** After `_fileEncrypted` is reset (i.e., `_encryptedBytes == null`), the "Change File" TextButton disappears and the CrypButton re-enables automatically (driven by the `_fileEncrypted` getter).

### Gap 4 — ReceiverScreen Step 1 lockout (preventive)

- **D-11:** When `_isReadyToReceive` is true, wrap Step 1 StepCard in `AnimatedOpacity(opacity: _isReadyToReceive ? 0.4 : 1.0, ...)` + `IgnorePointer(ignoring: _isReadyToReceive, ...)` — matching the existing step-gating pattern used throughout the stepper. Prevents RSA key regeneration while the mailbox is open.
- **D-12:** The AppBar settings `IconButton` (→ `_openKeyManager`) is also disabled while `_isReadyToReceive` is true — set `onPressed: _isReadyToReceive ? null : _openKeyManager`.

### Claude's Discretion

- Exact placement of the stale-key comparison (capture old value before setState vs. compare inside setState callback)
- Whether to use `AlertDialog` or `showDialog` wrapper for the "Change File" confirmation
- `onPopInvokedWithResult` vs `onPopInvokedWithResult` signature (Flutter version-dependent; follow existing patterns in the file)
- Order of operations in `onPopInvokedWithResult` (check `_sessionLocked` first, then `_isReadyToReceive`, then base case)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source files (primary targets)
- `lib/presentation/receiver/receiver_screen.dart` — PopScope (line 644), `_showCloseSessionDialog()` (line 306), `_onToggleReady()` (line 235), `_sessionLocked` (line 59), Step 1 content builder, AppBar settings button
- `lib/presentation/sender/sender_screen.dart` — `_onHandshakeUpdate()` (line 136), `_wipeSensitiveData()` (line 442), `_revertToWaiting()` (line 240), Step 1 CrypButton (line 777), `_fileEncrypted` getter (line 78), `_encryptedAESKey` field (line 66)

### Established patterns to replicate
- `lib/presentation/widgets/shared_widgets.dart` — `CrypButton` (for disabled-state pattern: `onPressed: null`), `StepCard` (for `AnimatedOpacity` + `IgnorePointer` gating pattern)
- `lib/core/utils/session_manager.dart` — `wipeSession()` signature (called from `onPopInvokedWithResult`)

### Architecture context
- `CLAUDE.md` → Kill Switch table — shows `PopScope` → `wipeSession()` as the back-nav trigger; Phase 9 adds the confirmation gate before that trigger fires
- `CLAUDE.md` → "Completed Features" section — `_showCloseSessionDialog()` and `_sessionLocked` behaviour documented there

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_showCloseSessionDialog()` (receiver_screen.dart:306) — BottomSheet already used for toggle-off confirmation; reuse directly for back-nav confirmation (D-02)
- `_wipeSensitiveData()` (sender_screen.dart:442) — clears crypto bytes and calls `wipeAll()`; use for both stale-key wipe (D-07) and Change File confirm (D-09)
- `AnimatedOpacity` + `IgnorePointer` pattern — used throughout both screens for step gating; replicate for Step 1 lockout (D-11)
- `CrypButton(onPressed: null)` — already renders greyed/disabled; no new widget needed for Step 1 disable

### Established Patterns
- Mid-flight guard: `if (_encrypting || _encryptingKey) return` — used before every wipe path in `_onHandshakeUpdate`; apply same to stale-key check (D-06)
- `canPop` is already `false` in SenderScreen when encrypting (`canPop: !_encrypting && !_encryptingKey`); ReceiverScreen adopts similar conditional (D-01)
- SnackBar error pattern: `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('...')))` — consistent throughout both screens

### Integration Points
- `PopScope.onPopInvokedWithResult` → `_showCloseSessionDialog()` → `_sessionManager.wipeSession(onBuffersWipe: wipeAll)` — back-nav confirmation chain
- `_onHandshakeUpdate` → stale-key check → `_wipeSensitiveData()` — invalidation chain
- `_fileEncrypted` getter (derived from `_encryptedBytes != null`) — drives both Step 1 CrypButton disabled state AND "Change File" TextButton visibility

</code_context>

<specifics>
## Specific Ideas

- Step 1 lockout (D-11/D-12): when `_isReadyToReceive` becomes true, the user should feel "locked in" — they opened the mailbox for a reason. Greying out key generation makes the session lifecycle explicit.
- "Change File" TextButton (D-09): deliberately subtle (secondary colour, text-only) — it should not compete visually with the main "Encrypt" step. It is an escape hatch, not a primary action.
- The stale-key SnackBar (D-05) copy "Receiver key changed — re-encrypt required." is intentionally terse — the user just needs to know to re-run Step 2. No alarm needed.

</specifics>

<deferred>
## Deferred Ideas

- None — discussion stayed within phase scope.

</deferred>

---

*Phase: 09-navigation-safety-session-integrity-hardening*
*Context gathered: 2026-05-29*
