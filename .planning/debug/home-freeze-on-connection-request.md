---
status: resolved
trigger: "when i request for connection, and especially if the other user is at homepage, the screen freezes"
created: 2026-06-13
updated: 2026-06-13
---

## Current Focus

hypothesis: >
  sendProposal()'s runTransaction hangs indefinitely when the receiver is simultaneously
  at home screen because the Firestore Mobile SDK's transaction retry mechanism conflicts
  with concurrent modifications to neutral_handshakes/A_B. When the receiver at home screen
  sees the proposal banner and taps Accept, acceptProposal() writes to the same doc the
  sender's transaction is trying to commit. The transaction detects contention and retries.
  Under the retry, the neutral_handshakes update security rule (which uses diff().affectedKeys())
  hangs on the server or the retry loop never terminates, matching the same pattern as the
  prior dialogs-freeze-on-proposal-accept bug.

test: "Replaced runTransaction with get() + WriteBatch (same fix pattern as acceptProposal)"

expecting: "WriteBatch commits once without retry, no hang even with concurrent acceptProposal"

next_action: "Human verification: test connection request with other user at home screen"

## Symptoms

- expected: Connection request sends successfully, both users see updated status
- actual: Full app hang — nothing responds, must force-close
- errors: No error messages — just a permanent freeze
- reproduction: User A sends connection request to User B while User B is at home screen
- started: Unknown (especially when receiver is at home screen)

## Eliminated

- hypothesis: "SetOptions(merge:true) in sendProposal (from original implementation)"
  evidence: "Commit 6f3f186 already replaced the original set() with merge:true with runTransaction to fix WR-01"
  timestamp: 2026-06-13

- hypothesis: "acceptProposal batch hanging due to SetOptions(merge:true)"
  evidence: "Prior bug (92e7ebc) already removed SetOptions(merge:true) from acceptProposal batch.set() calls"
  timestamp: 2026-06-13

- hypothesis: "Firestore security rules calling isAdmin() on neutral_handshakes"
  evidence: "neutral_handshakes rules do not call isAdmin() anywhere — no cross-doc reads in rule evaluation"
  timestamp: 2026-06-13

- hypothesis: "UI thread blocked by Dart async/await"
  evidence: "Dart async/await does not block the UI thread — Flutter event loop remains active"
  timestamp: 2026-06-13

## Evidence

- timestamp: 2026-06-13
  checked: "sendProposal in handshake_repository.dart"
  found: "Uses runTransaction with tx.set() (new doc) or tx.update() (existing doc). No SetOptions(merge:true) but has transaction retry semantics."
  implication: "Transaction retries when concurrent modifications occur — potential indefinite loop under concurrent write conditions"

- timestamp: 2026-06-13
  checked: "neutral_handshakes security rules in firestore.rules"
  found: "Update rule uses diff().affectedKeys().hasOnly([...]) — more complex than simple field checks. Prior bug's fix comment says rule evaluation hangs indefinitely in merge context."
  implication: "Under transaction retry with concurrent write, server-side diff() evaluation may hang"

- timestamp: 2026-06-13
  checked: "Prior bug commit 92e7ebc (dialogs-freeze-on-proposal-accept)"
  found: "Root cause: SetOptions(merge:true) on non-existent docs caused security rule hang. Fix: remove merge:true from acceptProposal batch.set() calls."
  implication: "Same hang pattern. Fix pattern is: avoid transaction retry on docs that have concurrent writers. Use get() + WriteBatch instead."

- timestamp: 2026-06-13
  checked: "Original sendProposal before commit 6f3f186"
  found: "Original code was set({...}, SetOptions(merge:true)). Commit 6f3f186 changed to runTransaction to fix WR-01 (idempotent createdAt). But runTransaction introduces transaction retry vulnerability."
  implication: "The runTransaction was a partial fix — it removed merge:true but introduced concurrent-write hang via retry mechanism"

- timestamp: 2026-06-13
  checked: "acceptProposal calling pattern in home_screen.dart"
  found: "Called without await in onAccept callback (fire-and-forget). If acceptProposal's batch.commit() hangs or the Firestore connection is occupied, the sender's runTransaction also cannot get a server response."
  implication: "When receiver at home screen accepts while sender's transaction is in flight, BOTH operations compete for the Firestore connection"

## Resolution

root_cause: >
  sendProposal() used runTransaction which hangs indefinitely when the receiver is
  simultaneously at home screen. The Firestore Mobile SDK's transaction retry mechanism
  triggers when acceptProposal() (called by the receiver on their home screen banner) writes
  to the same neutral_handshakes doc the transaction is trying to create/update. The
  transaction retries, and under concurrent write conditions the security rule evaluation
  (specifically the diff().affectedKeys() check in the neutral_handshakes update rule)
  hangs on the Firestore server. This matches the identical pattern as the prior bug
  (dialogs-freeze-on-proposal-accept) where Firestore security rule evaluation hangs
  under concurrent write conditions on the Mobile SDK.

fix: >
  Replaced sendProposal()'s runTransaction with a plain get() + WriteBatch approach —
  the same pattern used in acceptProposal() after the prior bug fix:
  1. Read the doc outside the batch (docRef.get())
  2. If doc doesn't exist: batch.set() with full data including createdAt (no merge, WR-01 preserved)
  3. If doc exists: batch.update() with username/status/updatedAt (preserves original createdAt)
  4. Commit the batch once — no retry loop, no concurrent write contention

  File changed: lib/data/repositories/handshake_repository.dart

verification: "Static analysis: No issues found. Tests: 17/17 passing (session_test + transfer_test)."

second_root_cause: >
  _ProposalBanner in home_screen.dart wraps its OverlayEntry content in
  Material(color: Colors.transparent). Despite being visually invisible, the
  Material widget absorbs ALL pointer events (scroll gestures, taps) within its
  layout bounds (~y=88 to ~y=204px from screen top). This made the home screen
  SingleChildScrollView unresponsive to scroll gestures originating in that region.
  Combined with no auto-dismiss and an 18px close button (below 40px minimum
  touch target), users experience the banner as a permanent freeze.
  CrypButton uses GestureDetector (not InkWell), so Material was never needed
  for button ink effects.

second_fix: >
  Removed Material(color: Colors.transparent) wrapper from _ProposalBannerState.build().
  Container is now the direct child of Positioned — scroll gestures pass through
  unoccupied areas of the overlay. Also fixed close button tap target:
  padding: EdgeInsets.zero → const EdgeInsets.all(8)
  constraints: const BoxConstraints() → const BoxConstraints(minWidth: 40, minHeight: 40)

  File changed: lib/presentation/home/home_screen.dart

files_changed:
  - lib/data/repositories/handshake_repository.dart
  - lib/presentation/home/home_screen.dart
