---
phase: 05-neutral-handshake-model
plan: 05
subsystem: security, database, testing
tags: [firestore-rules, handshake, flutter, dart, stream-lifecycle]

requires:
  - phase: 05-neutral-handshake-model (plans 01-04)
    provides: HandshakeRepository, HomeScreen restructure, SenderScreen/ReceiverScreen pre-fill, Firestore neutral_handshakes rules block
provides:
  - Firestore transfers create rule authorises neutral_handshakes connections (CR-01 closed)
  - neutral_handshakes create rule blocks self-proposals (WR-05)
  - neutral_handshakes update rule restricts modified fields to status+updatedAt (WR-06)
  - sendProposal uses runTransaction — createdAt stable on re-sends (WR-01)
  - sendProposal throws AuthException on empty username (WR-02)
  - HomeScreen _outcomePendingSub stored and cancelled in dispose (WR-03)
  - HomeScreen banner callbacks null-safe currentUser?.uid (WR-04)
  - HomeScreen _recentTransfersStream lifted to initState (IN-04)
  - SenderScreen _revertToWaiting preserves pre-fill partner context (WR-07)
  - TC-HAND-03 uses correct actor (partner/auth2); TC-HAND-06a/b/c added (IN-01, IN-02)
affects: [phase-06, security-audit, firestore-rules]

tech-stack:
  added: []
  patterns:
    - runTransaction for idempotent createdAt on re-sends
    - null-safe currentUser?.uid guard in overlay callbacks
    - stream fields lifted to initState to prevent rebuild re-subscriptions

key-files:
  created: []
  modified:
    - firestore.rules
    - lib/data/repositories/handshake_repository.dart
    - lib/presentation/home/home_screen.dart
    - lib/presentation/sender/sender_screen.dart
    - test/handshake/handshake_repository_test.dart

key-decisions:
  - "runTransaction chosen over SetOptions(merge:true) for sendProposal — preserves original createdAt timestamp on re-sends, which SetOptions.merge would overwrite"
  - "setUp seeds users/user1 with username to satisfy new empty-username guard without modifying each individual test"
  - "_revertToWaiting preserves widget.preFilledPartner* rather than nulling — sender stays targeted after receiver temporarily closes mailbox"

patterns-established:
  - "Stream fields lifted to initState: prevents new Firestore subscriptions on every build() call"
  - "Null-safe banner callbacks: currentUser?.uid with early return avoids crash on sign-out race"

requirements-completed:
  - HAND-09

duration: 20min
completed: 2026-05-13
---

# Phase 05-05: Gap Closure — Firestore Rules + Repository + UI Hardening Summary

**Firestore `transfers` create rule now authorises `neutral_handshakes` connections (CR-01); 7 code-review warnings closed; 3 stream tests added — Phase 5 end-to-end transfer creation unblocked**

## Performance

- **Duration:** ~20 min
- **Completed:** 2026-05-13
- **Tasks:** 5
- **Files modified:** 5

## Accomplishments

- **CR-01 (BLOCKER) closed** — two OR branches added to `transfers` create rule; users who connected exclusively via `neutral_handshakes` can now create transfer documents without PERMISSION_DENIED
- **Firestore security hardened** — WR-05 self-proposal guard (`proposerId != partnerId`) and WR-06 field restriction (`affectedKeys().hasOnly(['status','updatedAt'])`) added to `neutral_handshakes` rules
- **Repository idempotency fixed** — `sendProposal` uses `runTransaction` so `createdAt` is never overwritten on re-sends; empty-username guard throws `AuthException` before any Firestore write
- **HomeScreen stream lifecycle corrected** — `_outcomePendingSub` stored and cancelled in `dispose()`; banner callbacks use null-safe `currentUser?.uid`; `_recentTransfersStream` lifted to `initState`
- **Sender revert behaviour fixed** — `_revertToWaiting()` restores pre-fill partner context instead of nulling; sender stays targeted after receiver temporarily closes session
- **Test coverage expanded** — TC-HAND-03 now uses `auth2` (partner) matching the Firestore rule; TC-HAND-06a/b/c validate active connection and outcome streams — 10 tests total, all passing

## Task Commits

1. **Task 1: firestore.rules CR-01 + WR-05 + WR-06** — `08ebc8d`
2. **Tasks 2 & 3: repository + home screen fixes** — `6f3f186`
3. **Tasks 4 & 5: sender revert + test fixes** — `12f8020`

## Files Created/Modified

- `firestore.rules` — transfers create rule OR branches; neutral_handshakes self-proposal guard; update field restriction
- `lib/data/repositories/handshake_repository.dart` — sendProposal rewritten with runTransaction + username guard
- `lib/presentation/home/home_screen.dart` — _outcomePendingSub field; _recentTransfersStream in initState; null-safe banner callbacks
- `lib/presentation/sender/sender_screen.dart` — _revertToWaiting preserves preFilledPartner*
- `test/handshake/handshake_repository_test.dart` — setUp seeds users/user1; TC-HAND-03 uses auth2; TC-HAND-06a/b/c added

## Decisions Made

- `runTransaction` chosen over `SetOptions(merge:true)` — preserves original `createdAt` timestamp on re-sends
- Added `users/user1` seed in `setUp` (not per-test) to satisfy the new username guard for all future tests using `sendProposal`
- `_revertToWaiting` restores `widget.preFilledPartner*` instead of `null` so the sender UI stays connected to the intended partner after transient session close

## Deviations from Plan

**1. users/user1 seed added to setUp (not in plan spec)**
- **Found during:** Task 5 — TC-HAND-01 failed after adding the empty-username guard because fakeFirestore has no user doc
- **Fix:** Added `await fakeFirestore.collection('users').doc('user1').set({'username': 'testuser1'})` to setUp
- **Impact:** Zero scope creep — required for plan's own acceptance criterion (TC-HAND-01 must pass)

---

**Total deviations:** 1 auto-fixed (test setup required by new guard)
**Impact:** All fixes necessary for plan acceptance criteria. No scope creep.

## Issues Encountered

None beyond the setUp seed noted above.

## Self-Check: PASSED

- `firestore.rules` contains both neutral_handshakes OR branches in transfers create rule ✓
- `firestore.rules` neutral_handshakes create rule contains `proposerId != partnerId` ✓
- `firestore.rules` neutral_handshakes update rule contains `hasOnly(['status', 'updatedAt'])` on both branches ✓
- `handshake_repository.dart` sendProposal contains `runTransaction` ✓
- `home_screen.dart` contains `_outcomePendingSub`, lifted `_recentTransfersStream`, null-safe banner callbacks ✓
- `sender_screen.dart` _revertToWaiting contains `widget.preFilledPartnerUid` ✓
- `flutter test test/handshake/` — 10 passed, 0 failed ✓
- `flutter analyze` — No issues found ✓

## Next Phase Readiness

Phase 5 gap closure complete. All must-haves from 05-VERIFICATION.md are now satisfied:
- CR-01 (blocking transfer creation) is closed
- All WR-01–07 and IN-01, IN-02, IN-04 findings are resolved
- Human verification items HAND-06 (live OverlayEntry) and HAND-09 (Firestore Rules Playground) remain as manual tests requiring two live sessions

---
*Phase: 05-neutral-handshake-model*
*Completed: 2026-05-13*
