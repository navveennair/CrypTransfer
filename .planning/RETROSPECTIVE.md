# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — Pre-Viva Thesis Demonstration Build

**Shipped:** 2026-07-05
**Phases:** 11 (02-11, incl. decimal insert 07.1) | **Plans:** 40 | **Commits:** 485

### What Was Built
- Zero-remanence, end-to-end encrypted peer-to-peer file transfer app (Flutter + Firebase)
- Neutral Handshake connection model decoupling connection establishment from role assignment
- Synchronized crypto-readiness gate and 4-turn reactive session destruction protocol
- Biometric-gated RSA Key Vault with immutable audit trail
- Full layer decoupling — zero direct Firestore calls in the presentation layer
- Production Android packaging (`com.navveennair.cryptransfer`)
- Hardened, security-guarded admin dashboard with real analytics

### What Worked
- Repository-layer centralization (Phase 07.1) paid off immediately — the entire v1.0-close audit pass (14 debug sessions, 9 UAT files, 8 verification reports) could be traced by reading repositories and screens directly, without hunting for scattered Firestore calls.
- Debug sessions with explicit `reasoning_checkpoint` / `Eliminated Hypotheses` sections were consistently easy to re-verify months later — falsifiable hypotheses with evidence held up well even after the underlying code had moved on.
- User-confirmed "this works now" statements, cross-checked against actual code tracing rather than taken at face value, caught real discrepancies (e.g. Phase 09's Browse Files bug turned out to already be fixed by a later refactor nobody had gone back to confirm).

### What Was Inefficient
- Several debug sessions and UAT files accumulated stale status fields (`investigating`, `diagnosed`, `verifying`) long after the underlying fix had actually landed and been confirmed working — nobody closed the loop on the tracking artifact even though the code was done. This inflated the milestone-close audit from a handful of real open items to 44 apparent ones.
- The `friendships` subcollection bridge (added as a compatibility shim for `KeyRepository.assignTransferRole`) became a second source of truth for "is this pair connected," alongside `neutral_handshakes`. It was never backfilled for connections established before the bridge existed — this is the root of the Phase 11 ConnectionNodeMap "ISOLATED" bug found at milestone close.
- Several presentation files were substantially rewritten/renamed during the milestone (`transfer_progress_screen.dart` → `sender_transfer_screen.dart`, `sender_screen.dart` logic partially extracted into `sender_controller.dart`) without updating the VERIFICATION.md/REVIEW.md documents that referenced the old file names and line numbers — made later tracing slower.

### Patterns Established
- When closing a milestone with a lot of drift between planning docs and code, trace the actual current code before trusting a debug session's or UAT's recorded root cause — status fields and even file paths go stale fast on an actively-refactored codebase.
- Distinguish "fix applied, needs re-test" from "root cause never found" when triaging old debug sessions — the two categories need very different next actions (confirm vs. investigate).

### Key Lessons
1. A debug session or verification report's `status` field is a snapshot, not a guarantee — always re-check against current code before treating it as ground truth, especially on a codebase with heavy churn between when it was written and when it's read again.
2. Bridging/denormalization shims (like the `friendships` collection here) need an explicit backfill plan or an expiry date — otherwise they silently diverge from the "real" data model and produce confusing bugs much later.
3. GSD tooling itself can have bugs (the quick-task audit scanner's hardcoded filename assumption) — when every item in a category looks suspiciously uniform ("11 incomplete," all identical `[missing]` reason), check the tool before assuming the project is actually behind.

### Cost Observations
- Sessions: 1 long milestone-close session covering debug triage, UAT re-test, verification-gap tracing, and full archival
- Notable: conversational UAT re-testing (asking the user to confirm specific on-device behavior rather than re-deriving it from code) was the fastest way to resolve genuinely ambiguous "is this still broken" questions — cheaper than spinning up new debug sessions for things that may have already been fixed as a side effect of later refactors

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | 1 (close) | 11 | First milestone close — established the pattern of re-tracing stale debug/UAT/verification artifacts against current code before archiving |

### Cumulative Quality

| Milestone | Tests | Coverage | Zero-Dep Additions |
|-----------|-------|----------|---------------------|
| v1.0 | 27 test files | Not measured | — |

### Top Lessons (Verified Across Milestones)

1. Re-verify stale planning artifacts against live code before trusting them at milestone close.
