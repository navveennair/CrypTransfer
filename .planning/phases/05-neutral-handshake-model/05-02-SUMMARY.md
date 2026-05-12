---
phase: 05-neutral-handshake-model
plan: 02
subsystem: data-layer
tags: [handshake, firestore, repository, security-rules, tdd]

# Dependency graph
requires:
  - phase: 05-neutral-handshake-model
    plan: 01
    provides: "Failing stub tests in test/handshake/handshake_repository_test.dart + HandshakeRepository stub"
provides:
  - "Full HandshakeRepository class with 9 methods (CRUD + 5 streams)"
  - "FirebaseConstants.neutralHandshakes = 'neutral_handshakes'"
  - "Firestore neutral_handshakes security rules block (read/create/update/delete)"
affects:
  - 05-03-PLAN (sender/receiver pre-fill — depends on HandshakeRepository existing)
  - 05-04-PLAN (HomeScreen — merges streamActiveConnectionsAsProposer + streamActiveConnectionsAsPartner)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deterministic doc ID pattern: '${proposerId}_${partnerUid}' for idempotent re-proposals"
    - "WriteBatch mutual-accept: both A_B and B_A docs updated atomically when mutual proposal exists"
    - "Dual Firestore stream pattern: streamActiveConnectionsAsProposer() + streamActiveConnectionsAsPartner() merged client-side (Firestore OR limitation workaround)"
    - "Firestore rules dual update condition: partnerId clause for accept/reject + proposerId clause for mutual-accept WriteBatch"

key-files:
  created:
    - lib/data/repositories/handshake_repository.dart
  modified:
    - lib/core/constants/firebase_constants.dart
    - firestore.rules
    - test/handshake/handshake_repository_test.dart

key-decisions:
  - "HandshakeRepository uses no FlutterSecureStorage — neutral handshakes are connection-layer only (no key material stored locally)"
  - "Two separate stream methods (streamActiveConnectionsAsProposer/Partner) instead of one combined stream — Firestore cannot OR-query on different fields in a single query"
  - "partnerUid empty guard added to sendProposal() per T-05-02-05 threat mitigation"

patterns-established:
  - "Neutral proposerId/partnerId semantics: symmetric roles, no sender/receiver asymmetry"
  - "Mutual-accept WriteBatch: check for reverse doc existence before committing batch"

requirements-completed:
  - HAND-01
  - HAND-02
  - HAND-03
  - HAND-04
  - HAND-05
  - HAND-09

# Metrics
duration: 12min
completed: 2026-05-12
---

# Phase 05 Plan 02: HandshakeRepository Data Layer Summary

**Full HandshakeRepository with 9 public methods (CRUD + streaming) for the neutral_handshakes Firestore collection, neutralHandshakes constant registered, and Firestore security rules block enforcing proposer-spoof prevention, status whitelist, and dual update condition**

## Performance

- **Duration:** ~12 min
- **Completed:** 2026-05-12
- **Tasks:** 2
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- Replaced HandshakeRepository stub with full implementation: `sendProposal`, `acceptProposal`, `rejectProposal`, `cancelProposal`, `streamIncomingPending`, `streamOutgoingPending`, `streamActiveConnectionsAsProposer`, `streamActiveConnectionsAsPartner`, `streamProposalOutcome`
- Registered `FirebaseConstants.neutralHandshakes = 'neutral_handshakes'` — all collection references go through this constant, no hardcoded strings
- Replaced 5 `fail()` stubs in `handshake_repository_test.dart` with real FakeFirebaseFirestore assertions — TC-HAND-01 through TC-HAND-05 all pass
- Added `neutral_handshakes` Firestore security rules block with all 4 STRIDE mitigations from the threat model (T-05-02-01 through T-05-02-04)
- `flutter analyze lib/data/repositories/handshake_repository.dart lib/core/constants/firebase_constants.dart` — no issues

## Task Commits

1. **Task 1: HandshakeRepository + FirebaseConstants.neutralHandshakes + tests** — `3390947` (feat)
2. **Task 2: neutral_handshakes Firestore security rules** — `93d50c1` (feat)

## Files Created/Modified

- `lib/data/repositories/handshake_repository.dart` — Full implementation (created, replaces stub)
- `lib/core/constants/firebase_constants.dart` — Added `neutralHandshakes = 'neutral_handshakes'`
- `test/handshake/handshake_repository_test.dart` — 5 `fail()` stubs replaced with real assertions (all pass)
- `firestore.rules` — `neutral_handshakes` block inserted after `handshakes` block (line 185+)

## Decisions Made

- **No FlutterSecureStorage in HandshakeRepository:** Neutral handshakes are connection-layer metadata only — no key material is handled, so no secure local storage is needed. Constructor mirrors KeyRepository pattern but omits `_secure`.
- **Two stream methods instead of one:** `streamActiveConnectionsAsProposer()` and `streamActiveConnectionsAsPartner()` are separate because Firestore does not support `OR` queries across different fields in a single collection query. HomeScreen (05-04) merges them client-side.
- **T-05-02-05 guard added:** `sendProposal()` throws `AuthException('partnerUid required')` if `partnerUid.isEmpty` — this was in the threat register as a required mitigation and was added as a Rule 2 (missing critical functionality).

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All stubs from 05-01 that this plan was responsible for (TC-HAND-01 through TC-HAND-05) are now resolved.

Pre-existing stubs from 05-01 still awaiting resolution in 05-03:
- `test/handshake/sender_prefill_test.dart` — TC-HAND-07 stub (resolves in 05-03)
- `test/handshake/receiver_prefill_test.dart` — TC-HAND-08 stub (resolves in 05-03)

## Threat Surface Scan

All STRIDE mitigations from the plan's threat model are implemented in `firestore.rules`:

| Threat ID | Mitigation | Verified |
|-----------|-----------|---------|
| T-05-02-01 | `request.resource.data.proposerId == request.auth.uid` on create | Yes |
| T-05-02-02 | Update requires `partnerId == auth.uid` for accept/reject (proposer cannot self-accept) | Yes |
| T-05-02-03 | `request.resource.data.status in ['connected', 'rejected']` whitelist | Yes |
| T-05-02-04 | Read requires `proposerId == auth.uid OR partnerId == auth.uid` | Yes |
| T-05-02-05 | Dart-layer `partnerUid.isEmpty` guard in `sendProposal()` | Yes |
| T-05-02-06 | Accepted (no rate limiting — MVP) | N/A |

No new threat surface beyond what was planned.

## Self-Check

Files exist:
- `lib/data/repositories/handshake_repository.dart` — FOUND
- `lib/core/constants/firebase_constants.dart` (contains neutralHandshakes) — FOUND
- `firestore.rules` (contains match /neutral_handshakes) — FOUND

Commits exist:
- `3390947` — FOUND
- `93d50c1` — FOUND

## Self-Check: PASSED

---
*Phase: 05-neutral-handshake-model*
*Completed: 2026-05-12*
