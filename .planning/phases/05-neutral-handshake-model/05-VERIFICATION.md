---
phase: 05-neutral-handshake-model
verified: 2026-05-12T00:00:00Z
status: gaps_found
score: 9/10 must-haves verified
overrides_applied: 0
gaps:
  - truth: "Tapping Active Connection → role picker → Send File / Receive File → transfer creation succeeds end-to-end"
    status: failed
    reason: "The firestore.rules transfers create rule has no neutral_handshakes existence check. Users who connect exclusively through the new neutral_handshakes path (no legacy connections sub-collection docs) will be denied when SenderScreen attempts to create a transfer document. The selectedSenderUid handshake path still works but the connection-based fallback is blind to neutral_handshakes."
    artifacts:
      - path: "firestore.rules"
        issue: "transfers create rule (lines 139-160) only checks users/{uid}/connections sub-collection and selectedSenderUid. Missing neutral_handshakes OR branch."
    missing:
      - "Add two OR branches to the transfers create rule: exists(/neutral_handshakes/${auth.uid}_${receiverId}) || exists(/neutral_handshakes/${receiverId}_${auth.uid})"
human_verification:
  - test: "HAND-06 — Approval banner live test"
    expected: "User B opens HomeScreen. User A sends a connection proposal to User B. Within 5 seconds, a _ProposalBanner OverlayEntry appears on User B's screen showing '@{A's username} wants to connect' with 'Accept Request' and 'Decline Request' buttons. Tapping X dismisses the banner and leaves the proposal visible in the Pending Requests section."
    why_human: "OverlayEntry behaviour requires two live Firebase sessions. flutter unit tests cannot test Overlay insertion."
  - test: "HAND-09 — Firestore rules security validation"
    expected: "(1) Create with proposerId != auth.uid → DENY. (2) Update by proposer setting status='rejected' → DENY (proposer cannot reject own proposal). (3) Update by partner setting status='connected' → ALLOW. (4) Read by a third party (not proposerId or partnerId) → DENY."
    why_human: "Requires Firebase Rules Playground or Firebase Emulator — cannot be verified by static grep."
---

# Phase 05: Neutral Handshake Model — Verification Report

**Phase Goal:** Refactor the CrypTransfer connection architecture to a neutral Handshake model that decouples "Establishing a Connection" from "Defining Sender/Receiver Roles." Introduces proposerId/partnerId semantics, a pending-approval flow with global listener and approval UI, and defers role selection (Send/Receive) to the moment a user taps an active connection.
**Verified:** 2026-05-12T00:00:00Z
**Status:** gaps_found
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| #  | Truth | Status | Evidence |
|----|-------|--------|----------|
| 1  | HandshakeRepository implements proposerId/partnerId semantics with sendProposal/acceptProposal/rejectProposal/cancelProposal | VERIFIED | `lib/data/repositories/handshake_repository.dart` — 9 public methods; all use `FirebaseConstants.neutralHandshakes`; deterministic doc ID `${_uid}_${partnerUid}` |
| 2  | streamIncomingPending/streamOutgoingPending/streamActiveConnectionsAsProposer/streamActiveConnectionsAsPartner/streamProposalOutcome all exist | VERIFIED | `handshake_repository.dart` lines 129-179; all 5 stream methods verified; no hardcoded collection strings |
| 3  | TC-HAND-01 through TC-HAND-05 all pass (HandshakeRepository unit tests) | VERIFIED | `flutter test test/handshake/` ran live: 7 tests passed, 0 failures |
| 4  | Firestore neutral_handshakes security rules block present with proposer-spoof prevention and status whitelist | VERIFIED | `firestore.rules` lines 186-214; `request.resource.data.proposerId == request.auth.uid` on create; `status in ['connected', 'rejected']` whitelist; dual update condition present |
| 5  | HomeScreen no longer shows "I am a Sender" / "I am a Receiver" role buttons | VERIFIED | grep for "I am a Sender" and "I am a Receiver" in `home_screen.dart` — no matches |
| 6  | HomeScreen Active Connections section wired to HandshakeRepository streams | VERIFIED | `home_screen.dart` lines 900-993; three nested StreamBuilders on `streamActiveConnectionsAsProposer()`, `streamActiveConnectionsAsPartner()`, `streamOutgoingPending()`; deduplication via `seenUids Set<String>` |
| 7  | HomeScreen Pending Requests section renders with Accept/Decline buttons | VERIFIED | `_PendingRequestsSection` at line 1070; `streamIncomingPending()` StreamBuilder; returns `SizedBox.shrink()` when empty; `_PendingRequestRow` has "Accept Request" CrypButton + "Decline Request" TextButton |
| 8  | SenderScreen.preFilledPartnerUid/preFilledPartnerUsername pre-fill params exist and are wired in initState | VERIFIED | `sender_screen.dart` lines 35-42, 82-91; `_onHandshakeUpdate` guard at lines 136-137; TC-HAND-07 passes |
| 9  | ReceiverScreen.preFilledSenderUid/preFilledSenderUsername pre-fill params exist and wired via _checkKeyStatus().then() | VERIFIED | `receiver_screen.dart` lines 22-29, 72-84; `.then()` pattern (not fire-and-forget) confirmed; TC-HAND-08 passes |
| 10 | Tapping Active Connection → _RolePickerSheet → transfer creation succeeds end-to-end | FAILED | `firestore.rules` transfers create rule (lines 144-152) has no neutral_handshakes OR branch. Users with only a neutral_handshakes connection (no legacy connections sub-collection docs) will be denied on transfer write. |

**Score:** 9/10 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `lib/data/repositories/handshake_repository.dart` | Full HandshakeRepository with CRUD + 5 streams | VERIFIED | 181 lines; class HandshakeRepository; 9 public methods; uses FirebaseConstants.neutralHandshakes |
| `lib/core/constants/firebase_constants.dart` | neutralHandshakes constant | VERIFIED | Line 14: `static const String neutralHandshakes = 'neutral_handshakes'` |
| `firestore.rules` | neutral_handshakes security block | VERIFIED | Lines 186-214; all 4 operations covered |
| `lib/presentation/sender/sender_screen.dart` | preFilledPartnerUid/Username optional params + initState guard | VERIFIED | Lines 35-42, 82-91, 136-137 |
| `lib/presentation/receiver/receiver_screen.dart` | preFilledSenderUid/Username optional params + .then() sequencing | VERIFIED | Lines 22-29, 72-84 |
| `lib/presentation/home/home_screen.dart` | Restructured HomeScreen with _ProposalBanner, Active Connections, _RolePickerSheet | VERIFIED | 1436 lines; all required classes and methods present |
| `test/handshake/handshake_repository_test.dart` | TC-HAND-01 through TC-HAND-05 real assertions | VERIFIED | 133 lines; all 5 tests pass |
| `test/handshake/sender_prefill_test.dart` | TC-HAND-07 constructor test | VERIFIED | 32 lines; passes |
| `test/handshake/receiver_prefill_test.dart` | TC-HAND-08 constructor test | VERIFIED | 22 lines; passes |

---

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `HandshakeRepository` | `FirebaseConstants.neutralHandshakes` | `FirebaseConstants.neutralHandshakes` constant | WIRED | All 9 methods use the constant; no hardcoded `'neutral_handshakes'` strings |
| `firestore.rules` | neutral_handshakes collection | `match /neutral_handshakes/{handshakeId}` | WIRED | Block present at lines 186-214 |
| `_HomeScreenState._startHandshakeListener()` | `HandshakeRepository.streamIncomingPending()` | `_pendingProposalSub = _handshakeRepo.streamIncomingPending().listen(...)` | WIRED | Line 72 |
| `_HomeScreenState._startOutcomeListener()` | `HandshakeRepository.streamProposalOutcome()` | `_outcomeSubs[docId] = _handshakeRepo.streamProposalOutcome(docId).listen(...)` | WIRED | Lines 95-96 |
| `_RolePickerSheet onSendFile` | `SenderScreen(preFilledPartnerUid:)` | `Navigator.push MaterialPageRoute` | WIRED | Lines 232-237 |
| `_RolePickerSheet onReceiveFile` | `ReceiverScreen(preFilledSenderUid:)` | `Navigator.push MaterialPageRoute` | WIRED | Lines 244-249 |

---

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|--------------|--------|--------------------|--------|
| `_ActiveConnectionsSection` | `proposerDocs`, `partnerDocs`, `pendingDocs` | `streamActiveConnectionsAsProposer()`, `streamActiveConnectionsAsPartner()`, `streamOutgoingPending()` — all Firestore `.where().snapshots()` queries | Yes — live Firestore queries with field filters on `proposerId`/`partnerId`/`status` | FLOWING |
| `_PendingRequestsSection` | `docs` | `streamIncomingPending()` — Firestore `.where('partnerId').where('status','pending').snapshots()` | Yes | FLOWING |
| `_startHandshakeListener` | `snap.docChanges` | `streamIncomingPending()` live stream | Yes | FLOWING |
| `_startOutcomeListener` | `docSnap.data()?['status']` | `streamProposalOutcome(docId)` per-doc Firestore stream | Yes | FLOWING |

---

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| All 7 handshake tests pass | `flutter test test/handshake/` | 7 passed, 0 failed | PASS |
| Static analysis clean on phase files | `flutter analyze lib/data/repositories/handshake_repository.dart lib/presentation/home/home_screen.dart lib/presentation/sender/sender_screen.dart lib/presentation/receiver/receiver_screen.dart` | No issues found | PASS |
| Role buttons absent from HomeScreen | grep "I am a Sender" home_screen.dart | No matches | PASS |
| neutral_handshakes Firestore block count | grep -c "match /neutral_handshakes" firestore.rules | 1 | PASS |
| transfers rule missing neutral_handshakes branch | Inspection of firestore.rules lines 144-152 | No `neutral_handshakes` OR branch present — transfer write will fail for new-model connections | FAIL |

---

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|---------|
| HAND-01 | 05-01, 05-02 | sendProposal() creates neutral_handshakes doc with proposerId/partnerId/status=pending | SATISFIED | TC-HAND-01 passes; `handshake_repository.dart` lines 35-61 |
| HAND-02 | 05-01, 05-02 | acceptProposal() WriteBatch updates status to connected | SATISFIED | TC-HAND-02 passes; `handshake_repository.dart` lines 71-93 |
| HAND-03 | 05-01, 05-02 | rejectProposal() updates status to rejected | SATISFIED | TC-HAND-03 passes; `handshake_repository.dart` lines 96-109 |
| HAND-04 | 05-01, 05-02 | cancelProposal() deletes the doc | SATISFIED | TC-HAND-04 passes; `handshake_repository.dart` lines 112-122 |
| HAND-05 | 05-01, 05-02 | streamIncomingPending emits docs where partnerId==uid and status==pending | SATISFIED | TC-HAND-05 passes; stream wired in HomeScreen and _PendingRequestsSection |
| HAND-06 | 05-04 | Global listener fires approval banner for incoming proposals | NEEDS HUMAN | `_startHandshakeListener` + `_showProposalBanner` + `_ProposalBanner` are all wired in code; live OverlayEntry behavior requires two-device test |
| HAND-07 | 05-03 | SenderScreen accepts preFilledPartnerUid without opening _FindSenderSheet | SATISFIED | TC-HAND-07 passes; `sender_screen.dart` lines 82-91; _onHandshakeUpdate guard at lines 136-137 |
| HAND-08 | 05-03 | ReceiverScreen accepts preFilledSenderUid, calls selectSender after checkKeyStatus | SATISFIED | TC-HAND-08 passes; `receiver_screen.dart` lines 72-84; .then() sequencing correct |
| HAND-09 | 05-02 | Firestore rules block spoofing and unauthorized updates | PARTIAL | Rules block written and all four mitigations present; self-accept gap (WR-05) and field-restriction gap (WR-06) identified in review; requires Rules Playground validation |

---

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `firestore.rules` | 144-152 | `transfers` create rule missing `neutral_handshakes` existence check | Blocker | Phase 5 users connecting exclusively via neutral_handshakes cannot create transfers |
| `home_screen.dart` | 85-123 | `_startOutcomeListener` outer `streamOutgoingPending().listen()` not stored or cancelled in dispose() | Warning | Firestore listener leaks after widget dispose — subscription stays open indefinitely |
| `home_screen.dart` | 140, 147 | `FirebaseAuth.instance.currentUser!.uid` bang operator in banner callbacks | Warning | Null crash if user signs out while banner is displayed |
| `handshake_repository.dart` | 46-57 | `sendProposal` with `SetOptions(merge: true)` overwrites `createdAt` on re-send | Warning | Audit trail timestamp corrupted on idempotent re-proposals |
| `firestore.rules` | 202-208 | Update rule permits proposer to self-accept own proposal (no `proposerId != partnerId` guard on create) | Warning | Security gap: user can send a proposal to themselves and immediately accept it |
| `test/handshake/handshake_repository_test.dart` | 67-87 | TC-HAND-03 uses proposer (user1) to call rejectProposal — incorrect actor for the authorization path | Info | Test passes on fake_cloud_firestore but would fail on real Firestore where rule requires partnerId |

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

**One blocking gap** prevents full end-to-end goal achievement:

**CR-01 — transfers Firestore rule missing neutral_handshakes check (BLOCKER)**

The `transfers` collection create rule (`firestore.rules` lines 144-152) was not updated in Phase 5. It checks `selectedSenderUid` (the existing Phase 4 handshake path) and a bilateral `users/{uid}/connections` subcollection. Phase 5 introduces a new `neutral_handshakes` collection but never adds it as an OR branch to the transfers rule.

Concrete failure scenario: User A and User B establish a connection through the new neutral handshake flow. No `connections` subcollection docs are created (the new flow only writes to `neutral_handshakes`). User A opens the role picker, taps "Send File", and attempts to create a transfer document. The `selectedSenderUid` check may not be set yet (it is set on ReceiverScreen's mailbox toggle, not on role-picker navigation). Result: Firestore DENIES the transfer write with a PERMISSION_DENIED error.

**Fix required:**

Add two OR branches to the transfers create rule in `firestore.rules`:
```javascript
// Phase 5 neutral handshake: either party may have proposed
|| exists(/databases/$(database)/documents/neutral_handshakes/$(request.auth.uid + '_' + request.resource.data.receiverId))
|| exists(/databases/$(database)/documents/neutral_handshakes/$(request.resource.data.receiverId + '_' + request.auth.uid))
```

The six warning-level issues from the code review (WR-01 through WR-07 excluding WR-05 self-accept) are genuine quality issues but do not prevent the core connection architecture from functioning at the data and UI layers. They are documented in `05-REVIEW.md` for closure in a follow-up pass.

---

_Verified: 2026-05-12T00:00:00Z_
_Verifier: Claude (gsd-verifier)_
