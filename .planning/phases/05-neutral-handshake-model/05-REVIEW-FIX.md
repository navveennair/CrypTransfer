---
phase: 05-neutral-handshake-model
fixed_at: 2026-05-15T00:00:00Z
review_path: .planning/phases/05-neutral-handshake-model/05-REVIEW.md
iteration: 1
findings_in_scope: 2
fixed: 2
skipped: 0
status: all_fixed
---

# Phase 05: Code Review Fix Report

**Fixed at:** 2026-05-15
**Source review:** .planning/phases/05-neutral-handshake-model/05-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 2
- Fixed: 2
- Skipped: 0

## Fixed Issues

### WR-01: `_PendingRequestsSection` silently swallows stream errors — `onShowError` never called

**Files modified:** `lib/presentation/home/home_screen.dart`
**Commit:** 4fb0b56
**Applied fix:** Added `if (snapshot.hasError)` guard immediately after the `ConnectionState.waiting` check in `_PendingRequestsSection.build()`. When a Firestore stream error occurs, `onShowError` is now invoked with a user-facing message and the builder returns `SizedBox.shrink()`, consistent with the existing `_ActiveConnectionsSection` error branch.

### WR-02: `_rejecting` flag never reset on Firestore failure — Decline button permanently stuck

**Files modified:** `lib/presentation/home/home_screen.dart`
**Commit:** 0018918
**Applied fix:** Four coordinated changes across the callback chain:
1. `_PendingRequestsSection.onReject` field type changed from `void Function` to `Future<void> Function`.
2. `_PendingRequestRow.onReject` field type changed from `void Function` to `Future<void> Function`.
3. `_HomeScreenState._rejectProposal` converted from fire-and-forget `.catchError` to `async` with `try`/`catch`+`rethrow`, matching the pattern of `_acceptProposal`.
4. Decline `onPressed` in `_PendingRequestRowState` converted to `async` with `try`/`finally` that resets `_rejecting = false` whether the operation succeeds or throws — mirrors the existing Accept button pattern and prevents the permanently stuck spinner on Firestore failure.

---

_Fixed: 2026-05-15_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
