---
phase: 06-synchronized-readiness-gate
verified: 2026-05-16T00:00:00Z
status: gaps_found
score: 5/8 must-haves verified
overrides_applied: 0
gaps:
  - truth: "When handshake doc is absent (snap.docs.isEmpty) while !_receiverReady: timer cancelled, red SnackBar shown, Navigator.pushAndRemoveUntil to HomeScreen"
    status: failed
    reason: "CR-01 confirmed. No _streamSettled guard or _receiverSelected guard protects the isEmpty branch. The Firestore stream fires an initial empty snapshot synchronously after _startHandshakeListener() in initState. At that point _receiverReady is false, so _ejectToHomeScreen() fires immediately — before the receiver has any chance to act, and before the sender has even opened the FindSenderSheet. This breaks both the pre-filled sender flow (Active Connection role picker) and the normal sender flow (fresh SenderScreen with no pre-fill). The fix recommended in REVIEW.md (a _streamSettled flag) is absent."
    artifacts:
      - path: "lib/presentation/sender/sender_screen.dart"
        issue: "_onHandshakeUpdate isEmpty branch at lines 120-127 ejects on first empty snapshot regardless of whether the stream has ever seen a non-empty doc. No _streamSettled flag, no _receiverSelected guard."
    missing:
      - "Add bool _streamSettled = false field to _SenderScreenState"
      - "In isEmpty branch: if (!_streamSettled) { _streamSettled = true; return; } before the !_receiverReady eject guard"
      - "In the non-empty else branch (after setState): _streamSettled = true;"

  - truth: "Stale receiverReady: false is guaranteed on every new session for returning sender/receiver pairs"
    status: failed
    reason: "WR-01 confirmed. In selectSenderHandshake(), the keyPayload map (lines 480-488) does not include receiverReady: false. When an existing handshake doc is found, batch.update(existing.docs.first.reference, keyPayload) at line 492 leaves the previous session's receiverReady value (true) intact. On a second session between the same pair, _onHandshakeUpdate immediately receives receiverReady: true from the initial snapshot, calls _onReceiverBecameReady(), and unlocks Steps 1-4 without waiting for the receiver to actually signal readiness in the new session. The gate is completely bypassed for returning pairs."
    artifacts:
      - path: "lib/data/repositories/key_repository.dart"
        issue: "keyPayload at lines 480-488 missing 'receiverReady': false. The new-doc batch.set() at line 497 correctly includes it, but the existing-doc batch.update() at line 492 does not reset it."
    missing:
      - "Add 'receiverReady': false to keyPayload map so both the batch.update and batch.set paths reset the field on every new session"

  - truth: "WR-03: No frozen-UI state when receiverReady reverts to false after being true"
    status: failed
    reason: "WR-03 confirmed. The else if (_receiverReady != receiverReady) branch at line 167-168 calls setState(() => _receiverReady = receiverReady) when the field reverts false. The timer was already cancelled in _onReceiverBecameReady(). After revert, _readinessTimer is null and _secondsRemaining holds its last value (likely 0 or a low number), frozen. The UI shows _WaitingForReceiverWidget with a non-ticking countdown. No timer restart, no revert-to-waiting, no eject path. User is stuck."
    artifacts:
      - path: "lib/presentation/sender/sender_screen.dart"
        issue: "Lines 165-169: else if branch sets _receiverReady = false but does not restart _readinessTimer or call _revertToWaiting(). The sender screen deadlocks with a frozen countdown widget."
    missing:
      - "Replace the else if branch body with a call to _revertToWaiting() (which already resets _receiverReady, _secondsRemaining, and cancels timer) and optionally show a SnackBar indicating session reset"

deferred: []

human_verification:
  - test: "CR-01 smoke test: open SenderScreen with preFilledPartnerUid before receiver opens mailbox"
    expected: "Screen stays at Step 0 showing _WaitingForConnectionWidget; no immediate navigation to HomeScreen"
    why_human: "Requires a real device/emulator with two Firebase accounts. Cannot simulate the Firestore stream cold-start timing programmatically."
  - test: "WR-01 regression test: complete a transfer between pair A-B, then initiate a second transfer between A-B immediately"
    expected: "Sender sees _WaitingForReceiverWidget and countdown timer; Step 0 does NOT show _ConnectedBadge until receiver explicitly signals readiness in the new session"
    why_human: "Requires two real accounts with an existing completed-session handshake doc in Firestore. Cannot verify without live Firestore state from a prior session."
---

# Phase 06: Synchronized Readiness Gate — Verification Report

**Phase Goal:** Synchronized Readiness Gate — prevent sender from advancing past Step 0 until receiver has signaled cryptographic readiness; eliminate the race condition where sender initiates before receiver has published their RSA key.
**Verified:** 2026-05-16
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Goal Achievement

The core mechanics of the readiness gate are implemented and correctly wired: the data layer (`setReceiverReady`, `selectSenderHandshake` returning `Future<String>`), the receiver trigger (`_writeReceiverReady` with retry SnackBar), and the sender-side UI gate (`_WaitingForReceiverWidget`, countdown timer, `AnimatedOpacity`/`IgnorePointer` on Steps 1-4) all exist and are substantive. However, **three defects prevent the phase goal from being reliably achieved**:

1. **CR-01** (critical): The eject path fires on the stream's cold-start empty snapshot, immediately removing the sender from `SenderScreen` before the receiver has acted — breaking both the normal and pre-filled sender flows.
2. **WR-01** (critical for security gate correctness): Returning sender/receiver pairs bypass the gate because `receiverReady: true` from a prior session is never reset.
3. **WR-03** (correctness): If `receiverReady` reverts to `false` after being `true` (e.g. due to WR-01 cleanup or an unexpected write), the sender screen deadlocks with a non-functional frozen countdown widget.

WR-02 (missing `mounted` guard in retry closure) is a real defect but is a safety concern rather than a goal-blocking race condition — the SnackBar has a 6s auto-dismiss and the failure path is rare.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `selectSenderHandshake()` returns Future<String> doc ID | VERIFIED | `Future<String> selectSenderHandshake` at key_repository.dart:445; `return docId;` at line 519 |
| 2 | `setReceiverReady(docId)` writes `receiverReady: true` to handshake doc | VERIFIED | key_repository.dart:626-636 — targeted `.update({'receiverReady': true})` with `NetworkException` wrapping |
| 3 | After `selectSenderHandshake` succeeds, receiver writes `receiverReady: true` | VERIFIED | receiver_screen.dart:333-344 — `handshakeDocId` captured, `_writeReceiverReady(handshakeDocId)` called after setState |
| 4 | Retry SnackBar shown on `receiverReady` write failure | VERIFIED | receiver_screen.dart:404-425 — floating SnackBar with text "Failed to signal readiness — tap to retry." and SnackBarAction "Retry" |
| 5 | While `_receiverSelected && !_receiverReady`: Step 0 shows `_WaitingForReceiverWidget` with countdown; Steps 1-4 invisible and non-interactive | VERIFIED | sender_screen.dart:519-537 — three-state child switch; AnimatedOpacity(opacity: `_receiverReady ? 1.0 : 0.0`) + IgnorePointer wrapping Steps 1-4 |
| 6 | When `receiverReady` becomes true: countdown cancelled, green SnackBar, Steps 1-4 fade in | VERIFIED | sender_screen.dart:424-436 — `_onReceiverBecameReady()` cancels timer, sets `_receiverReady = true`, shows "Secure channel established. Receiver is ready." |
| 7 | When handshake doc disappears while `!_receiverReady`: eject to HomeScreen | FAILED | CR-01: no `_streamSettled` guard. Cold-start empty snapshot triggers eject before receiver can act. Also triggers in normal flow (no pre-fill). |
| 8 | Returning sender/receiver pairs must not bypass the gate (`receiverReady` reset on new session) | FAILED | WR-01: `keyPayload` at key_repository.dart:480-488 omits `'receiverReady': false`; the `batch.update` path (existing doc) leaves previous session's `receiverReady: true` intact |

**Score:** 5/8 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/data/repositories/key_repository.dart` | `setReceiverReady()` + `selectSenderHandshake()` returning `Future<String>` | VERIFIED | Both methods present and substantive. 637 lines. |
| `lib/presentation/receiver/receiver_screen.dart` | `_writeReceiverReady()` + `_onSenderSelected` capturing docId | VERIFIED | `_writeReceiverReady` at line 406; `handshakeDocId` capture at line 333 |
| `lib/presentation/sender/sender_screen.dart` | `_WaitingForReceiverWidget`, `_receiverReady` state, `_readinessTimer`, `_startReadinessTimer`, `_onReceiverBecameReady`, `_ejectToHomeScreen`, Steps 1-4 gate | VERIFIED (partially defective) | All artifacts present and substantive; defect is in eject-guard logic, not artifact existence |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `receiver_screen.dart` | `key_repository.dart` | `await _connService.selectSenderHandshake(...)` → captures `handshakeDocId` | WIRED | Line 333-336 |
| `receiver_screen.dart` | `key_repository.dart` | `await _connService.setReceiverReady(handshakeDocId)` | WIRED | Line 408 inside `_writeReceiverReady` |
| `sender_screen.dart` | Firestore handshakes doc | `_onHandshakeUpdate` parses `doc['receiverReady'] as bool?` | WIRED | Line 159 |
| `sender_screen.dart` | `home_screen.dart` | `_ejectToHomeScreen` → `Navigator.pushAndRemoveUntil` → `HomeScreen()` | WIRED | Lines 438-453 |
| `_onHandshakeUpdate` isEmpty branch | `_ejectToHomeScreen` | `if (!_receiverReady) { ... _ejectToHomeScreen(); return; }` | PARTIALLY BROKEN | Guard fires on cold-start empty snapshot (CR-01) |
| `selectSenderHandshake` existing-doc branch | Firestore `receiverReady` reset | `keyPayload` should include `'receiverReady': false` | NOT WIRED | `keyPayload` omits the reset; WR-01 bypass |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `_WaitingForReceiverWidget` | `widget.secondsRemaining` | `_secondsRemaining` in `_SenderScreenState`, decremented by `Timer.periodic` | Yes — real timer-driven decrement | FLOWING |
| Step 0 child switch | `_receiverReady` | Parsed from Firestore handshake doc snapshot (`doc['receiverReady'] as bool?`) | Yes — live Firestore stream | FLOWING (when stream settled; defective on cold start) |
| Steps 1-4 AnimatedOpacity | `_receiverReady` | Same as above | Same | FLOWING (same caveat) |

---

### Behavioral Spot-Checks

Step 7b skipped — behavioral checks require running the app with live Firestore state. The CR-01 defect makes automated runner-based testing non-viable without a real emulator.

---

### Requirements Coverage

| Requirement | Source Plan | Description (derived from plan must_haves) | Status |
|-------------|------------|---------------------------------------------|--------|
| SYNC-01 | 06-01-PLAN | `selectSenderHandshake()` returns `Future<String>` doc ID | SATISFIED |
| SYNC-02 | 06-01-PLAN | `setReceiverReady(docId)` writes `receiverReady: true` to handshake doc | SATISFIED |
| SYNC-03 | 06-02-PLAN | ReceiverScreen signals readiness after handshake; retry SnackBar on failure | SATISFIED |
| SYNC-04 | 06-03-PLAN | Steps 1-4 hidden with `AnimatedOpacity`/`IgnorePointer` until `receiverReady` | SATISFIED |
| SYNC-05 | 06-03-PLAN | Countdown timer ejects sender at 0 seconds; doc deletion ejects while `!_receiverReady` | BLOCKED — doc deletion eject fires spuriously on cold-start empty snapshot (CR-01) |
| SYNC-06 | 06-03-PLAN | `receiverReady: false` initialized on new sessions; gate not bypassable by prior session | BLOCKED — existing-doc `batch.update` path does not reset `receiverReady` (WR-01) |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `sender_screen.dart` | 120-127 | `isEmpty` branch ejects without stream-settled guard | Blocker | CR-01: immediate ejection on cold-start breaks both sender flows |
| `key_repository.dart` | 480-492 | `keyPayload` missing `'receiverReady': false`; `batch.update` path skips reset | Blocker | WR-01: gate bypass for returning pairs — defeats the phase's security goal |
| `sender_screen.dart` | 165-169 | `else if (_receiverReady != receiverReady)` resets flag without restarting timer | Warning | WR-03: sender screen deadlocks if `receiverReady` reverts to false post-established |
| `receiver_screen.dart` | 418-421 | `onPressed: () => _writeReceiverReady(handshakeDocId)` retry closure has no `mounted` guard | Warning | WR-02: use-after-dispose risk if ReceiverScreen disposes before SnackBar's 6s duration; recursive call enters `Theme.of(context)` on dead widget |

---

### Human Verification Required

#### 1. CR-01 Smoke Test

**Test:** Open `SenderScreen` with a `preFilledPartnerUid` (via Active Connection role picker) before the receiver has opened their mailbox. Wait 5 seconds.
**Expected:** Screen remains on Step 0 showing `_WaitingForConnectionWidget`; no navigation to HomeScreen occurs.
**Why human:** Requires live Firestore with two real accounts. The cold-start empty-snapshot timing depends on Firestore network behavior.

#### 2. CR-01 Normal-Flow Smoke Test

**Test:** Navigate to `SenderScreen` via `const SenderScreen()` (from a notification push, for example). Before tapping any button, wait 5 seconds.
**Expected:** Screen remains at Step 0; no navigation to HomeScreen.
**Why human:** Same reason as above.

#### 3. WR-01 Bypass Test

**Test:** Complete a successful file transfer between users A (sender) and B (receiver). Then immediately have A navigate to `SenderScreen` again with B as pre-filled partner. Observe Step 0 state.
**Expected:** Sender sees `_WaitingForReceiverWidget` with countdown; Steps 1-4 remain invisible until B explicitly opens ReceiverScreen and selects A again.
**Why human:** Requires live Firestore state with a completed prior session's handshake doc having `receiverReady: true` persisted.

---

### Gaps Summary

Three gaps prevent the phase goal from being reliably achieved:

**CR-01 (Blocker) — Premature ejection on cold-start empty stream snapshot.**
`_onHandshakeUpdate` in `sender_screen.dart` has no `_streamSettled` guard. The Firestore stream's first callback fires immediately in `initState` with an empty snapshot. Because `_receiverReady` is always `false` at that point, `_ejectToHomeScreen()` fires before any receiver can act — or before the sender can even pick a receiver in the non-pre-filled flow. The feature is effectively non-functional for most entry paths.

**WR-01 (Blocker for gate correctness) — Stale `receiverReady: true` bypasses gate for returning pairs.**
In `key_repository.dart`, `keyPayload` does not include `'receiverReady': false`. When an existing handshake doc is found (line 490), `batch.update(..., keyPayload)` leaves the prior session's `receiverReady: true` value on the doc. The sender's first stream snapshot sees `receiverReady: true` and calls `_onReceiverBecameReady()` immediately — unlocking all steps without waiting for the receiver. The race condition this phase aims to prevent is reintroduced for every pair after their first session.

**WR-03 (Warning, near-blocker) — Frozen UI when `receiverReady` reverts.**
If `receiverReady` flips back to `false` after the gate was unlocked (e.g. due to Firestore correction after a WR-01 bypass, or a concurrent session event), the `else if` branch sets `_receiverReady = false` but neither restarts the countdown timer nor calls `_revertToWaiting()`. The sender is left with a frozen `_WaitingForReceiverWidget` showing a stale countdown value with no tick and no eject path. The screen is stuck.

**Root cause grouping:** CR-01 and WR-03 share the same root — the `_onHandshakeUpdate` isEmpty/else logic lacks defensive guards for edge-case stream states. WR-01 is a separate data-layer omission in `keyPayload`.

---

_Verified: 2026-05-16_
_Verifier: Claude (gsd-verifier)_
