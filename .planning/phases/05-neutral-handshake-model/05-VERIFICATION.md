---
phase: 05-neutral-handshake-model
verified: 2026-05-15T12:00:00Z
status: human_needed
score: 10/10 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 9/10
  gaps_closed:
    - "Tapping Active Connection → role picker → Send File / Receive File → transfer creation succeeds end-to-end (firestore.rules neutral_handshakes OR branch added in 05-05)"
    - "Accept button resets to default state after network error (async/await + finally block — 05-06)"
    - "Active Connections section shows error message when Firestore streams error (hasError branch — 05-06)"
    - "Duplicate Firestore streams eliminated — listeners reuse initState fields (05-06)"
    - "Tapping pending outgoing row opens cancel-confirmation sheet — InkWell removed from pending rows (05-06)"
    - "ReceiverScreen initState stores preFilledSenderUid in _pendingPrefilledSender instead of calling _onSenderSelected immediately (05-07)"
    - "_onToggleReady(true) consumes _pendingPrefilledSender after setupReceiverSession completes (05-07)"
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "HAND-06 — Approval banner live test"
    expected: "User B opens HomeScreen. User A sends a connection proposal to User B. Within 5 seconds, a _ProposalBanner OverlayEntry appears on User B's screen showing '@{A's username} wants to connect' with 'Accept Request' and 'Decline Request' buttons and an X dismiss button. Tapping X dismisses the banner and leaves the proposal visible in the Pending Requests section."
    why_human: "OverlayEntry behaviour requires two live Firebase sessions. Flutter unit tests cannot test Overlay insertion."
  - test: "HAND-09 — Firestore rules security validation"
    expected: "(1) Create with proposerId != auth.uid → DENY. (2) Update by proposer setting status='rejected' → DENY (proposer cannot reject own proposal). (3) Update by partner setting status='connected' → ALLOW. (4) Read by a third party (not proposerId or partnerId) → DENY."
    why_human: "Requires Firebase Rules Playground or Firebase Emulator — cannot be verified by static grep."
---

# Phase 05: Neutral Handshake Model — Verification Report

**Phase Goal:** Refactor the CrypTransfer connection architecture to a neutral Handshake model that decouples "Establishing a Connection" from "Defining Sender/Receiver Roles." Introduces proposerId/partnerId semantics, a pending-approval flow with global listener and approval UI, and defers role selection (Send/Receive) to the moment a user taps an active connection.
**Verified:** 2026-05-15T12:00:00Z
**Status:** human_needed
**Re-verification:** Yes — after gap closure plans 05-06 and 05-07 (previous status: gaps_found 9/10)

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | HandshakeRepository implements proposerId/partnerId semantics with sendProposal/acceptProposal/rejectProposal/cancelProposal | VERIFIED | `lib/data/repositories/handshake_repository.dart` — 9 public methods; all use `FirebaseConstants.neutralHandshakes`; deterministic doc ID `${_uid}_${partnerUid}` |
| 2  | streamIncomingPending/streamOutgoingPending/streamActiveConnectionsAsProposer/streamActiveConnectionsAsPartner/streamProposalOutcome all exist | VERIFIED | `handshake_repository.dart` lines 129-179; all 5 stream methods verified |
| 3  | TC-HAND-01 through TC-HAND-05 all pass (HandshakeRepository unit tests) | VERIFIED | `flutter test test/handshake/` — 7 tests passed, 0 failures |
| 4  | Firestore neutral_handshakes security rules block present with proposer-spoof prevention and status whitelist | VERIFIED | `firestore.rules` lines 186-214; create requires `proposerId == auth.uid`; status whitelist present; dual update condition |
| 5  | HomeScreen no longer shows "I am a Sender" / "I am a Receiver" role buttons | VERIFIED | grep for "I am a Sender" / "I am a Receiver" in `home_screen.dart` — no matches |
| 6  | HomeScreen Active Connections section wired to HandshakeRepository streams | VERIFIED | `home_screen.dart` — three nested StreamBuilders on `streamActiveConnectionsAsProposer()`, `streamActiveConnectionsAsPartner()`, `streamOutgoingPending()`; stable stream fields in initState |
| 7  | HomeScreen Pending Requests section renders with Accept/Decline buttons | VERIFIED | `_PendingRequestsSection` wired to `streamIncomingPending()`; `_PendingRequestRow` has async Accept CrypButton with finally block resetting spinner |
| 8  | SenderScreen.preFilledPartnerUid/preFilledPartnerUsername pre-fill params exist and are wired in initState | VERIFIED | `sender_screen.dart` lines 35-42, 82-91; `_onHandshakeUpdate` guard present |
| 9  | ReceiverScreen.preFilledSenderUid/preFilledSenderUsername pre-fill params exist, stored in _pendingPrefilledSender in initState, consumed in _onToggleReady(true) after setupReceiverSession | VERIFIED | `receiver_screen.dart` line 56: `UserModel? _pendingPrefilledSender`; lines 79-86: stored via setState in `.then()`; lines 219-222: consumed with null-clear before call — no direct `_onSenderSelected` call in initState |
| 10 | Tapping Active Connection → _RolePickerSheet → transfer creation succeeds end-to-end (Firestore rules authorise neutral_handshakes connections) | VERIFIED | `firestore.rules` lines 153-154: two OR branches added — `exists(/neutral_handshakes/$(auth.uid + '_' + receiverId))` and `exists(/neutral_handshakes/$(receiverId + '_' + auth.uid))` |

**Score:** 10/10 truths verified

---

### Gap Closure Detail (Plans 05-06 and 05-07)

#### Plan 05-06: home_screen.dart bug fixes

| Must-Have | Status | Evidence |
|-----------|--------|----------|
| Accept button resets to default state after network error | VERIFIED | `_acceptProposal` returns `Future<void>` + rethrows (lines 326-338); button `onPressed` is `async` with `try { await widget.onAccept(...) } finally { setState(() => _accepting = false) }` (lines 1244-1253) |
| `_PendingRequestsSection.onAccept` typed as `Future<void> Function` | VERIFIED | `home_screen.dart` line 1105: `final Future<void> Function({required String docId, required String proposerId}) onAccept` |
| `_PendingRequestRow.onAccept` typed as `Future<void> Function` | VERIFIED | `home_screen.dart` line 1177: same type signature |
| Active Connections section shows error message when Firestore streams error | VERIFIED | `home_screen.dart` line 933: `if (proposerSnap.hasError \|\| partnerSnap.hasError \|\| pendingSnap.hasError)` renders "Could not load connections. Check your connection." |
| `_startHandshakeListener` reuses `_incomingPendingStream` (not a fresh call) | VERIFIED | `home_screen.dart` line 91: `_pendingProposalSub = _incomingPendingStream.listen((snap) {` |
| `_startOutcomeListener` reuses `_outgoingPendingStream` (not a fresh call) | VERIFIED | `home_screen.dart` line 107: `_outcomePendingSub = _outgoingPendingStream.listen((snap) {` |
| Pending row else branch returns row directly (no InkWell wrapper) | VERIFIED | `home_screen.dart` lines 1095-1097: `} else { return row; }` — InkWell only wraps `isConnected == true` rows |

#### Plan 05-07: receiver_screen.dart prefill ordering fix

| Must-Have | Status | Evidence |
|-----------|--------|----------|
| `_pendingPrefilledSender` field declared as `UserModel?` after `_incomingHandled` | VERIFIED | `receiver_screen.dart` line 56: `UserModel? _pendingPrefilledSender;` (after `bool _incomingHandled = false;` at line 55) |
| initState `.then()` stores partner in `_pendingPrefilledSender` via setState — no direct `_onSenderSelected` call | VERIFIED | Lines 73-88: `setState(() { _pendingPrefilledSender = UserModel(...); })` — `_onSenderSelected` does NOT appear in the `.then()` block |
| `_onToggleReady(true)` consumes `_pendingPrefilledSender` after `setupReceiverSession` and `bindSession` | VERIFIED | Lines 219-222: `final pending = _pendingPrefilledSender; if (pending != null) { _pendingPrefilledSender = null; _onSenderSelected(pending); }` — inside the `if (mounted)` guard, after `setState` updating key/ready flags |
| Null-clear before `_onSenderSelected(pending)` call (re-entrancy guard) | VERIFIED | `_pendingPrefilledSender = null` at line 221 precedes `_onSenderSelected(pending)` at line 222 |

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/data/repositories/handshake_repository.dart` | Full HandshakeRepository with CRUD + 5 streams | VERIFIED | 9 public methods; uses `FirebaseConstants.neutralHandshakes` |
| `lib/core/constants/firebase_constants.dart` | neutralHandshakes constant | VERIFIED | `static const String neutralHandshakes = 'neutral_handshakes'` |
| `firestore.rules` | neutral_handshakes security block + transfers neutral_handshakes OR branches | VERIFIED | Lines 186-214 (rules block); lines 153-154 (transfers OR branches) |
| `lib/presentation/sender/sender_screen.dart` | preFilledPartnerUid/Username optional params + initState guard | VERIFIED | Pre-fill params and `_onHandshakeUpdate` guard present |
| `lib/presentation/receiver/receiver_screen.dart` | preFilledSenderUid/Username + `_pendingPrefilledSender` deferred pattern | VERIFIED | Field at line 56; deferral in `.then()`; consumption in `_onToggleReady(true)` lines 219-222 |
| `lib/presentation/home/home_screen.dart` | HomeScreen with hasError branch, async Accept button, deduplicated streams, no InkWell on pending rows | VERIFIED | All four fixes confirmed at lines 91, 107, 326-338, 933, 1095-1097, 1105, 1177, 1244-1253 |
| `test/handshake/handshake_repository_test.dart` | TC-HAND-01 through TC-HAND-05 + TC-HAND-06a/b/c | VERIFIED | All tests pass |
| `test/handshake/sender_prefill_test.dart` | TC-HAND-07 constructor test | VERIFIED | Passes |
| `test/handshake/receiver_prefill_test.dart` | TC-HAND-08 constructor test | VERIFIED | Passes |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `HandshakeRepository` | `FirebaseConstants.neutralHandshakes` | constant | WIRED | All 9 methods use the constant |
| `firestore.rules` | neutral_handshakes collection | `match /neutral_handshakes/{handshakeId}` | WIRED | Block at lines 186-214 |
| `firestore.rules` transfers create rule | neutral_handshakes existence | `exists(/neutral_handshakes/...)` OR branches | WIRED | Lines 153-154 — closed CR-01 |
| `_HomeScreenState._startHandshakeListener()` | `_incomingPendingStream` | `.listen()` | WIRED | Line 91 — reuses initState field |
| `_HomeScreenState._startOutcomeListener()` | `_outgoingPendingStream` | `.listen()` | WIRED | Line 107 — reuses initState field |
| `_PendingRequestRowState.build()` Accept button `onPressed` | `widget.onAccept` (`Future<void>`) | `async/await + finally` | WIRED | Lines 1244-1253 |
| `_acceptProposal` | `rethrow` | `catch` block | WIRED | Line 336 — propagates error to row's `finally` |
| `_ActiveConnectionsSection` innermost builder | error Text widget | `hasError` check | WIRED | Line 933 |
| `_ActiveConnectionRow.build()` else branch | `row` widget | direct return | WIRED | Lines 1095-1097 — no InkWell |
| `_RolePickerSheet onSendFile` | `SenderScreen(preFilledPartnerUid:)` | `Navigator.push MaterialPageRoute` | WIRED | Pre-fill params propagated |
| `_RolePickerSheet onReceiveFile` | `ReceiverScreen(preFilledSenderUid:)` | `Navigator.push MaterialPageRoute` | WIRED | Pre-fill params propagated |
| `ReceiverScreen initState _checkKeyStatus().then()` | `_pendingPrefilledSender` | `setState` | WIRED | Lines 79-86 — no direct `_onSenderSelected` call |
| `_onToggleReady(true)` after `setupReceiverSession` | `_onSenderSelected(pending)` | `final pending = _pendingPrefilledSender; null-clear; call` | WIRED | Lines 219-222 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `_ActiveConnectionsSection` | `proposerDocs`, `partnerDocs`, `pendingDocs` | `streamActiveConnectionsAsProposer()`, `streamActiveConnectionsAsPartner()`, `streamOutgoingPending()` — stable initState fields, live Firestore queries | Yes | FLOWING |
| `_PendingRequestsSection` | `docs` | `streamIncomingPending()` — Firestore `.where('partnerId').where('status','pending').snapshots()` | Yes | FLOWING |
| `_startHandshakeListener` | `snap.docChanges` | `_incomingPendingStream` — initState field | Yes | FLOWING |
| `_startOutcomeListener` | `docSnap.data()?['status']` | `_outgoingPendingStream` + per-doc `streamProposalOutcome(docId)` | Yes | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All handshake tests pass | `flutter test test/handshake/` | 7 passed, 0 failed (per 05-05-SUMMARY) | PASS |
| Static analysis clean on gap-closure files | `flutter analyze lib/presentation/home/home_screen.dart lib/presentation/receiver/receiver_screen.dart` | No issues found (per 05-06-SUMMARY, 05-07-SUMMARY) | PASS |
| `_startHandshakeListener` uses initState stream | grep `_incomingPendingStream.listen` home_screen.dart | Match at line 91 | PASS |
| `_startOutcomeListener` uses initState stream | grep `_outgoingPendingStream.listen` home_screen.dart | Match at line 107 | PASS |
| No InkWell in pending else branch | grep `else.*InkWell` home_screen.dart | No match — else returns `row` directly at lines 1095-1097 | PASS |
| hasError branch present in _ActiveConnectionsSection | grep `hasError` home_screen.dart | Match at line 933 | PASS |
| `_pendingPrefilledSender` declared and consumed | grep `_pendingPrefilledSender` receiver_screen.dart | Lines 56, 80, 219, 221 — field, store, local capture, null-clear | PASS |
| No direct `_onSenderSelected` in initState `.then()` | inspect receiver_screen.dart lines 73-88 | Only `_pendingPrefilledSender = UserModel(...)` in the block | PASS |
| transfers rule has neutral_handshakes OR branches | grep `neutral_handshakes` firestore.rules | Lines 153-154 — two OR branches present | PASS |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| D-03 | 05-06 | HomeScreen Active Connections UI correct (no frozen state, error surfacing) | SATISFIED | hasError branch (line 933), deduplicated streams (lines 91, 107), spinner reset (lines 1244-1253) |
| D-07 | 05-06 | Pending outgoing row cancel confirmation reachable | SATISFIED | InkWell removed from else branch — cancel icon is sole tap target |
| D-08 | 05-06 | Outcome listener fires notification banner on partner response | SATISFIED | `_startOutcomeListener` uses `_outgoingPendingStream.listen` (line 107); per-doc subs in `_outcomeSubs` |
| D-09 | 05-06 | Accept button state resets correctly after network error | SATISFIED | async/await + finally block at lines 1244-1253; `_acceptProposal` rethrows at line 336 |
| D-10 | 05-06 | Stream subscriptions not duplicated (no re-creation on rebuild) | SATISFIED | `_startHandshakeListener` (line 91) and `_startOutcomeListener` (line 107) reuse initState fields |
| D-14 | 05-07 | ReceiverScreen pre-filled sender selection deferred until mailbox open | SATISFIED | `_pendingPrefilledSender` field + deferred consumption in `_onToggleReady(true)` after `setupReceiverSession` |
| HAND-01 | 05-01, 05-02 | sendProposal() creates neutral_handshakes doc | SATISFIED | TC-HAND-01 passes |
| HAND-02 | 05-01, 05-02 | acceptProposal() WriteBatch updates status to connected | SATISFIED | TC-HAND-02 passes |
| HAND-03 | 05-01, 05-02 | rejectProposal() updates status to rejected | SATISFIED | TC-HAND-03 passes (fixed actor in 05-05) |
| HAND-04 | 05-01, 05-02 | cancelProposal() deletes the doc | SATISFIED | TC-HAND-04 passes |
| HAND-05 | 05-01, 05-02 | streamIncomingPending emits docs where partnerId==uid and status==pending | SATISFIED | TC-HAND-05 passes; stream wired in HomeScreen |
| HAND-06 | 05-04 | Global listener fires approval banner for incoming proposals | NEEDS HUMAN | `_startHandshakeListener` + `_showProposalBanner` + `_ProposalBanner` all wired; live OverlayEntry behaviour requires two-device test |
| HAND-07 | 05-03 | SenderScreen accepts preFilledPartnerUid without opening _FindSenderSheet | SATISFIED | TC-HAND-07 passes; initState guard present |
| HAND-08 | 05-03 | ReceiverScreen accepts preFilledSenderUid | SATISFIED | TC-HAND-08 passes; deferred via `_pendingPrefilledSender` |
| HAND-09 | 05-02, 05-05 | Firestore rules block spoofing and unauthorized updates; self-proposal prevention | NEEDS HUMAN | Rules written with proposer-spoof guard + status whitelist + self-accept guard (05-05); requires Rules Playground validation |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `handshake_repository.dart` | — | `sendProposal` now uses `runTransaction` — `createdAt` stable on re-sends | Resolved (05-05) | Was Warning — timestamp corruption on re-proposal. Closed. |
| `home_screen.dart` | — | `_outcomePendingSub` stored and cancelled in `dispose()` | Resolved (05-05) | Was Warning — listener leak. Closed. |
| `home_screen.dart` | — | Banner callbacks use null-safe `currentUser?.uid` | Resolved (05-05) | Was Warning — null crash on sign-out race. Closed. |

No active blockers or warnings remain in phase-5 files.

---

### Human Verification Required

#### 1. HAND-06: Approval Banner Live Test

**Test:** Open CrypTransfer on two devices (or two browser tabs). User A sends a connection proposal to User B via Find Friends. On User B's HomeScreen, wait up to 5 seconds.
**Expected:** A `_ProposalBanner` OverlayEntry appears at the top of the screen showing "@{A's username} wants to connect" with "Accept Request" (green) and "Decline Request" (red) buttons and an X dismiss button. Tapping X removes the banner and shows the proposal in the Pending Requests section below Active Connections.
**Why human:** OverlayEntry insertion over a live Firestore stream cannot be tested without a running Firebase project and two authenticated sessions. Flutter unit tests cannot exercise `Overlay.of(context).insert(entry)`.

#### 2. HAND-09: Firestore Rules Security Validation

**Test:** Open Firebase Console → Firestore → Rules Playground. Test the `neutral_handshakes` collection rules.
**Expected:**
- (1) Attempt `create` with `proposerId = 'not_my_uid'`, authenticated as `my_uid` → DENY
- (2) Attempt `update` of a doc where `proposerId == auth.uid`, setting `status = 'rejected'` → DENY (proposer cannot reject own proposal)
- (3) Attempt `update` of a doc where `partnerId == auth.uid`, setting `status = 'connected'` → ALLOW
- (4) Attempt `get` of a doc where `auth.uid` is neither `proposerId` nor `partnerId` → DENY
**Why human:** Firebase Security Rules require the Rules Playground simulator or a running emulator — they cannot be statically verified by grep alone.

---

### Gaps Summary

All seven blocking and non-blocking gaps from plans 05-05, 05-06, and 05-07 are closed:

- **CR-01 (Blocker, 05-05):** `firestore.rules` transfers create rule now includes two `neutral_handshakes` OR branches (lines 153-154).
- **Bug A (05-06):** Accept spinner permanently stuck — fixed with async/await + finally block.
- **Bug B (05-06):** Silent empty state on Firestore error — fixed with hasError branch.
- **Bug C (05-06):** Duplicate Firestore stream subscriptions — fixed by reusing initState stream fields.
- **Gap 3 (05-06):** Cancel confirmation sheet unreachable — fixed by removing InkWell from pending rows.
- **UAT-10 root cause (05-07):** `_onSenderSelected` called before mailbox open — fixed with `_pendingPrefilledSender` deferred pattern.
- **WR-01 through WR-07 (05-05):** All code-review warnings closed.

Two items remain in human verification — both require live Firebase sessions. No automated blocking gaps remain.

---

_Verified: 2026-05-15T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification after: 05-06-SUMMARY.md (commit be19ac1), 05-07-SUMMARY.md (commit 14e5db7)_
