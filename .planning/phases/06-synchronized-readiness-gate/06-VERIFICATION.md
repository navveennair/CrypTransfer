---
phase: 06-synchronized-readiness-gate
verified: 2026-05-16T01:00:00Z
status: resolved
resolved_note: "All 3 human_verification items (CR-01, WR-01, WR-03) satisfied via 06-HUMAN-UAT.md (2026-07-05): 8/8 passed. WR-02 (missing mounted guard on retry closure) remains open as non-blocking tech debt — receiver_screen.dart has since been refactored and _writeReceiverReady no longer exists in its original form; needs a fresh look if revisited."
score: 8/8 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 5/8
  gaps_closed:
    - "CR-01: _streamSettled guard added — cold-start empty Firestore snapshot no longer triggers _ejectToHomeScreen"
    - "WR-01: 'receiverReady': false added to keyPayload — both batch.update (existing doc) and batch.set (new doc) paths reset the field on every new session"
    - "WR-03: else-if branch replaced with _revertToWaiting() call + orange SnackBar — timer restarts and eject path re-activates on revert"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "CR-01 smoke test: open SenderScreen with preFilledPartnerUid before receiver opens mailbox"
    expected: "Screen stays at Step 0 showing _WaitingForConnectionWidget; no immediate navigation to HomeScreen occurs"
    why_human: "Requires a real device/emulator with two Firebase accounts. Cannot simulate the Firestore stream cold-start timing programmatically."
  - test: "WR-01 regression test: complete a transfer between pair A-B, then immediately initiate a second transfer between A-B"
    expected: "Sender sees _WaitingForReceiverWidget with countdown timer; Step 0 does NOT show _ConnectedBadge until receiver explicitly opens ReceiverScreen and selects A again in the new session"
    why_human: "Requires two real accounts with an existing completed-session handshake doc in Firestore. Cannot verify without live Firestore state from a prior session."
  - test: "WR-03 regression test: sender reaches _ConnectedBadge state (receiverReady == true), then receiver closes session"
    expected: "Sender screen shows orange SnackBar 'Receiver readiness was reset — waiting for confirmation.' and _WaitingForReceiverWidget with a ticking 60-second countdown restarts; eject fires at 0 or on subsequent doc deletion"
    why_human: "Requires two real accounts and coordinated session control to force a receiverReady field revert after the gate was unlocked."
---

# Phase 06: Synchronized Readiness Gate — Verification Report

**Phase Goal:** Synchronized Readiness Gate — prevent sender from advancing past Step 0 until receiver has signaled cryptographic readiness; eliminate the race condition where sender initiates before receiver has published their RSA key.
**Verified:** 2026-05-16T01:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure (Plan 04, commit bb37773)

---

## Goal Achievement

All eight must-have truths are now verified in the codebase. The three blockers from the initial verification (CR-01, WR-01, WR-03) have been closed by Plan 04. The synchronized readiness gate is implemented correctly across all code paths: cold-start, pre-filled sender, returning pairs, and post-unlock reverts. What remains is live device smoke testing that cannot be automated.

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `selectSenderHandshake()` returns `Future<String>` doc ID | VERIFIED | `key_repository.dart:445` — `Future<String> selectSenderHandshake`; `return docId;` at line 522 |
| 2 | `setReceiverReady(docId)` writes `receiverReady: true` to handshake doc | VERIFIED | `key_repository.dart:629-639` — `.update({'receiverReady': true})` with `NetworkException` wrapping |
| 3 | After `selectSenderHandshake` succeeds, receiver writes `receiverReady: true` | VERIFIED | `receiver_screen.dart:333-344` — `handshakeDocId` captured, `_writeReceiverReady(handshakeDocId)` called after setState |
| 4 | Retry SnackBar shown on `receiverReady` write failure | VERIFIED | `receiver_screen.dart:406-425` — floating SnackBar with `'Failed to signal readiness — tap to retry.'` and SnackBarAction `'Retry'` |
| 5 | While `_receiverSelected && !_receiverReady`: Step 0 shows `_WaitingForReceiverWidget` with countdown; Steps 1-4 invisible and non-interactive | VERIFIED | `sender_screen.dart:544-559` — three-state child switch; `AnimatedOpacity(opacity: _receiverReady ? 1.0 : 0.0)` + `IgnorePointer(ignoring: !_receiverReady)` wrapping Steps 1-4 |
| 6 | When `receiverReady` becomes true: countdown cancelled, green SnackBar, Steps 1-4 fade in | VERIFIED | `sender_screen.dart:445-457` — `_onReceiverBecameReady()` cancels timer, sets `_receiverReady = true`, shows `'Secure channel established. Receiver is ready.'` with `Colors.green.shade700` |
| 7 | Cold-start empty Firestore snapshot does NOT eject the sender | VERIFIED | `sender_screen.dart:83,124-126` — `bool _streamSettled = false` field; `if (!_streamSettled) { _streamSettled = true; return; }` guard at top of isEmpty branch absorbs first snapshot; eject only fires after `_streamSettled == true` |
| 8 | Returning sender/receiver pairs cannot bypass the gate (`receiverReady` reset on every new session) | VERIFIED | `key_repository.dart:480-491` — `'receiverReady': false` included in `keyPayload`; both `batch.update` (existing doc, line 495) and `batch.set` (new doc, line 499-504) paths now reset the field |

**Score:** 8/8 truths verified

---

### Re-verification: Gaps Closed

| Gap | Previous Status | Current Status | Evidence |
|-----|----------------|----------------|----------|
| CR-01: cold-start empty-snapshot ejects sender | FAILED | CLOSED | `_streamSettled` field at line 83; guard at lines 124-126; settler at line 164; reset in `_revertToWaiting` at line 211 |
| WR-01: stale `receiverReady: true` bypasses gate for returning pairs | FAILED | CLOSED | `'receiverReady': false` added to `keyPayload` at line 490; covers both `batch.update` and `batch.set` paths |
| WR-03: frozen UI when `receiverReady` reverts after unlock | FAILED | CLOSED | Lines 175-188: `else if (_receiverReady != receiverReady)` branch now calls `_revertToWaiting()` + orange SnackBar `'Receiver readiness was reset — waiting for confirmation.'`; bare `setState` one-liner is gone (confirmed by grep returning 0 matches) |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/data/repositories/key_repository.dart` | `setReceiverReady()` + `selectSenderHandshake()` returning `Future<String>` + `keyPayload` with `receiverReady: false` | VERIFIED | All three present; 640+ lines; substantive implementations |
| `lib/presentation/receiver/receiver_screen.dart` | `_writeReceiverReady()` + `_onSenderSelected` capturing `handshakeDocId` | VERIFIED | `_writeReceiverReady` at line 406; `handshakeDocId` capture at line 333; retry SnackBar at lines 413-423 |
| `lib/presentation/sender/sender_screen.dart` | `_WaitingForReceiverWidget`, `_streamSettled`, `_receiverReady`, `_readinessTimer`, `_startReadinessTimer`, `_onReceiverBecameReady`, `_ejectToHomeScreen`, Steps 1-4 gate | VERIFIED | All artifacts present and substantive; `_WaitingForReceiverWidget` class at line 1023 with full animation and countdown display |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `receiver_screen.dart` | `key_repository.dart` | `await _connService.selectSenderHandshake(...)` captures `handshakeDocId` | WIRED | Lines 333-336 |
| `receiver_screen.dart` | `key_repository.dart` | `await _connService.setReceiverReady(handshakeDocId)` in `_writeReceiverReady` | WIRED | Lines 407-408 |
| `sender_screen.dart` | Firestore handshakes doc | `_onHandshakeUpdate` parses `doc['receiverReady'] as bool? ?? false` | WIRED | Line 167 |
| `sender_screen.dart` | `home_screen.dart` | `_ejectToHomeScreen` → `Navigator.pushAndRemoveUntil` → `HomeScreen()` | WIRED | Lines 459-475 |
| `_onHandshakeUpdate` isEmpty branch | `_ejectToHomeScreen` | `_streamSettled` guard absorbs cold-start; eject fires only after stream settled AND `!_receiverReady` | WIRED | Lines 122-133; `_streamSettled` guard confirmed at line 124 |
| `keyPayload` | Firestore `receiverReady` reset | `'receiverReady': false` in `keyPayload` — both `batch.update` and `batch.set` paths | WIRED | Lines 490 (keyPayload) + 495 (update) + 499-504 (set with spread) |
| `_onHandshakeUpdate` revert branch | `_revertToWaiting()` | `else if (_receiverReady != receiverReady)` calls `_revertToWaiting()` | WIRED | Lines 175-188; old bare-setState one-liner confirmed absent |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|--------------------|--------|
| `_WaitingForReceiverWidget` | `widget.secondsRemaining` | `_secondsRemaining` in `_SenderScreenState`, decremented by `Timer.periodic` in `_startReadinessTimer` | Yes — real timer-driven decrement at 1Hz | FLOWING |
| Step 0 child switch | `_receiverReady` | Parsed from Firestore handshake doc snapshot via `_onHandshakeUpdate` | Yes — live Firestore stream; guarded by `_streamSettled` for cold-start | FLOWING |
| Steps 1-4 `AnimatedOpacity` | `_receiverReady` | Same Firestore-derived state | Yes | FLOWING |
| `_writeReceiverReady` → Firestore | `receiverReady: true` | `_connService.setReceiverReady(handshakeDocId)` — targeted Firestore `.update()` | Yes — real Firestore write; `handshakeDocId` from `selectSenderHandshake` return value | FLOWING |

---

### Behavioral Spot-Checks

Step 7b: SKIPPED — behavioral checks require running the Flutter app with live Firestore. The three human verification items below cover the critical behaviors that need real-device confirmation.

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SYNC-01 | 06-01-PLAN | `selectSenderHandshake()` returns `Future<String>` doc ID | SATISFIED | `key_repository.dart:445` — `Future<String> selectSenderHandshake`; `return docId;` at line 522 |
| SYNC-02 | 06-01-PLAN | `setReceiverReady(docId)` writes `receiverReady: true` to handshake doc | SATISFIED | `key_repository.dart:629-639` — method present with `.update({'receiverReady': true})` and `NetworkException` |
| SYNC-03 | 06-02-PLAN | ReceiverScreen signals readiness after handshake; retry SnackBar on failure | SATISFIED | `receiver_screen.dart:333-344` (capture + call); lines 406-425 (SnackBar with Retry action) |
| SYNC-04 | 06-03-PLAN | Steps 1-4 hidden with `AnimatedOpacity`/`IgnorePointer` until `receiverReady` | SATISFIED | `sender_screen.dart:553-558` — outer `AnimatedOpacity(opacity: _receiverReady ? 1.0 : 0.0)` + `IgnorePointer(ignoring: !_receiverReady)` confirmed |
| SYNC-05 | 06-03/06-04-PLAN | Countdown timer ejects sender at 0; doc deletion ejects while `!_receiverReady`; cold-start snapshot does NOT eject | SATISFIED | `_startReadinessTimer` at line 432; `_ejectToHomeScreen` called at lines 132 and 440; `_streamSettled` guard at lines 124-126 prevents cold-start eject (CR-01 closed) |
| SYNC-06 | 06-03/06-04-PLAN | `receiverReady: false` initialized on new sessions; gate not bypassable by prior session | SATISFIED | `keyPayload` at line 480-491 includes `'receiverReady': false`; both `batch.update` and `batch.set` paths covered (WR-01 closed) |

No REQUIREMENTS.md file exists at `.planning/REQUIREMENTS.md`. Requirement IDs are defined exclusively in plan frontmatter. All six IDs (SYNC-01 through SYNC-06) are accounted for across plans 01-04. No orphaned requirements found.

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `receiver_screen.dart` | 418-421 | `onPressed: () => _writeReceiverReady(handshakeDocId)` retry closure has no `mounted` guard | Warning | WR-02 (carried from initial review): use-after-dispose risk if ReceiverScreen disposes before SnackBar's 6s duration elapses; `_writeReceiverReady` does check `!mounted` at its top before the catch block's SnackBar show, but the outer retry call itself has no guard. Risk is low in practice (SnackBar 6s auto-dismiss; failure path is rare) and not goal-blocking. |

No blocker anti-patterns found. The WR-02 warning is the same one identified in the initial review and remains a non-blocking safety concern only.

---

### Human Verification Required

#### 1. CR-01 Cold-Start Smoke Test

**Test:** Open `SenderScreen` with a `preFilledPartnerUid` (via Active Connection role picker on HomeScreen) before the partner receiver has opened their mailbox. Wait 10 seconds on Step 0.
**Expected:** Screen remains at Step 0 showing `_WaitingForConnectionWidget` (or `_WaitingForReceiverWidget` if the stream settles quickly); no navigation to HomeScreen occurs during that window.
**Why human:** Requires a real device or emulator with two Firebase accounts. The cold-start empty-snapshot timing depends on Firestore network latency and cannot be simulated programmatically.

#### 2. WR-01 Returning-Pair Bypass Test

**Test:** Complete a full file transfer between users A (sender) and B (receiver). Then immediately have A navigate to `SenderScreen` again with B as a pre-filled partner. Observe Step 0 state when B's handshake doc is found on the stream.
**Expected:** Sender sees `_WaitingForReceiverWidget` with a ticking 60-second countdown. Steps 1-4 remain invisible and non-interactive. `_ConnectedBadge` must NOT appear until B explicitly opens ReceiverScreen and selects A as sender in the new session.
**Why human:** Requires live Firestore state with an existing prior-session handshake doc that previously had `receiverReady: true`. The `keyPayload` reset now writes `receiverReady: false` on the new session's batch write, but confirming the field actually arrives as `false` on the stream requires inspecting actual Firestore document state.

#### 3. WR-03 Post-Unlock Revert Test

**Test:** Have sender A reach `_ConnectedBadge` state (B has opened mailbox, `receiverReady == true`). Then have B close their session (kill-switch). Observe A's SenderScreen.
**Expected:** A sees the orange SnackBar `'Receiver readiness was reset — waiting for confirmation.'` and `_WaitingForReceiverWidget` reappears with a fresh 60-second countdown ticking down. The eject path activates: if no new connection arrives within 60 seconds, A is navigated to HomeScreen.
**Why human:** Requires coordinated two-device session control and live Firestore observation to confirm the timer restarts (not frozen at 0) and the eject path is active.

---

### Gaps Summary

No automated-verifiable gaps remain. All three blockers from the initial verification (CR-01, WR-01, WR-03) are confirmed closed in the codebase. The remaining items are human smoke tests that could not be run without live Firestore and two real accounts.

The one open warning (WR-02 — missing `mounted` guard on the retry closure in `_writeReceiverReady`) is a pre-existing non-blocking safety concern. It does not prevent the phase goal from being achieved.

---

_Verified: 2026-05-16T01:00:00Z_
_Verifier: Claude (gsd-verifier)_
