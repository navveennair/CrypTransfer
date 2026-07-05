---
status: resolved
phase: 05-neutral-handshake-model
source: [05-01-SUMMARY.md, 05-02-SUMMARY.md, 05-03-SUMMARY.md, 05-04-SUMMARY.md, 05-05-SUMMARY.md, 05-06-SUMMARY.md, 05-07-SUMMARY.md]
started: 2026-05-13T00:00:00Z
updated: 2026-07-05T00:00:00Z
---

## Current Test

[testing complete — all 4 issues fixed by 05-06-PLAN.md and 05-07-PLAN.md gap closure, verified against current source 2026-07-05]

## Tests

### 1. HomeScreen Role Button Removal
expected: Open the app and navigate to HomeScreen. The "I am a Sender" and "I am a Receiver" buttons should be completely gone. In their place you should see an "Active Connections" section header (with an "Add New Connection" link/button) and below it an empty state message like "No connections yet".
result: pass

### 2. Send a Connection Proposal
expected: Tap "Add New Connection" to open the FindFriendsScreen. Search for another user, then interact with their entry to send a connection request. Back on HomeScreen, the new connection should appear under "Active Connections" with an amber "Pending" badge next to the partner's name, and a cancel (trash) icon.
result: pass
note: "Fixed — FindFriendsScreen rewired to HandshakeRepository (0a25966) + Firestore rules read guard for non-existent docs (30184fb)"

### 3. Incoming Proposal Banner
expected: When another device/user sends you a connection proposal, a banner overlay appears at the top of the screen showing the proposer's name with Accept and Reject buttons. If you do nothing, it auto-dismisses after ~5 seconds. The pending request also appears in a "Pending Requests" section below Active Connections.
result: pass

### 4. Accept a Connection Proposal
expected: Tap "Accept Request" (CrypButton) in the Pending Requests section. The row disappears from Pending Requests and reappears in Active Connections with a green "Connected" badge. The partner who sent the proposal should receive a notification that their request was accepted.
result: issue
reported: "Once a user accepts the request. A white blank page is shown. The requester on the other hand, remains at pending"
severity: major

### 5. Role Picker on Active Connection
expected: Tap on a row in the Active Connections section for a user showing a green "Connected" badge. A bottom sheet appears with two tiles: "Send File" and "Receive File". Tapping either one navigates to the respective SenderScreen or ReceiverScreen, with the partner's name/UID already pre-filled — no need to use the Find Sender sheet or manually select a receiver.
result: issue
reported: "Active connections is going through a frozen screen. While testing, a green Connected badge is not seen. The bottom sheet works with two titles, navigating to SenderScreen, ReceiverScreen works with UID prefilled."
severity: major

### 6. Sender Pre-fill Context Preserved After Receiver Closes Session
expected: Navigate to SenderScreen via the Role Picker (pre-filled with a partner). The partner's name is visible without any manual search. If the receiver temporarily closes their mailbox mid-session and then reopens it, the SenderScreen should revert to its waiting state (pulsing animation) but the partner's name/context should REMAIN displayed — it should NOT be cleared back to the "find sender" empty state.
result: blocked
blocked_by: prior-phase
reason: "Accept flow broken (test 4) — cannot reach a stable Connected state to test sender pre-fill behaviour"

### 7. Reject a Connection Proposal
expected: From the Pending Requests section, tap "Decline Request" (TextButton). The row disappears from Pending Requests. The proposer receives a notification that their request was rejected. The rejected connection does not appear in Active Connections.
result: blocked
blocked_by: prior-phase
reason: "Screen frozen — cannot reach Pending Requests section to test rejection"

### 8. Cancel an Outgoing Pending Proposal
expected: For an outgoing pending connection (amber "Pending" badge in Active Connections), tap the cancel/trash icon next to it. A confirmation sheet appears asking you to confirm cancellation. After confirming, the pending row disappears from the list. The other user no longer sees a pending request from you.
result: issue
reported: "no confirmation screen"
severity: major

### 9. Self-Proposal Prevention
expected: Attempt to send a connection proposal to yourself (your own account, if testable). The app should block this — either graying out your own entry or showing an error. No proposal document should be created.
result: skipped
reason: single device/account — cannot test self-proposal

### 10. End-to-End Transfer via Neutral Handshake Connection
expected: With two users who connected via the new neutral handshake flow (accepted each other's proposals), one user taps the connection on HomeScreen, picks "Send File", selects a file, and sends it. The other user picks "Receive File" from the same connection, and the file arrives, decrypts, and saves successfully. The full transfer completes without any Firestore PERMISSION_DENIED errors.
result: issue
reported: "From receiver's side, the third stepper does not recognize their very first stepper, that the automatic connection has been performed. Stepper 0 to 2 works fine, but stepper 3 does not recognize stepper 0, that a user has been connected, preventing RSA handshake to occur successfully."
severity: major

## Summary

total: 10
passed: 3
issues: 0
pending: 0
skipped: 1
blocked: 0
fixed: 4
verified: 2026-07-05

## Gaps — all fixed, verified against current source 2026-07-05

- truth: "After accepting a proposal: acceptor sees connection in Active Connections with green badge; requester's status updates from Pending to Connected"
  status: failed
  reason: "User reported: Once a user accepts the request. A white blank page is shown. The requester on the other hand, remains at pending"
  severity: major
  test: 4
  root_cause: "Streams were constructed inline inside build() methods (_ActiveConnectionsSection and _PendingRequestsSection), returning a new Stream object on every rebuild. StreamBuilder detected the changed reference and resubscribed from scratch, resetting connectionState to waiting and blanking the UI. The fix (lift streams to initState as stable fields) is already applied in commit 801ed35 — user may need to hot-restart to pick it up."
  artifacts:
    - path: "lib/presentation/home/home_screen.dart"
      issue: "Streams previously created inline in build() — fixed in 801ed35 by lifting to initState"
  missing:
    - "Verify fix is live: hot-restart and retest accept flow"
  debug_session: ".planning/debug/handshake-accept-blank-page.md"
  fixed: "05-06-PLAN.md — streams lifted to initState (commit 801ed35); debug session already marked resolved"

- truth: "Active Connections row shows green Connected badge; tapping opens role picker bottom sheet without freezing"
  status: failed
  reason: "User reported: Active connections is going through a frozen screen. While testing, a green Connected badge is not seen. The bottom sheet works with two titles, navigating to SenderScreen, ReceiverScreen works with UID prefilled."
  severity: major
  test: 5
  root_cause: "Three compounding bugs in home_screen.dart: (1) No hasError branch in triple-nested StreamBuilder — Firestore errors silently produce empty list, appearing frozen. (2) _PendingRequestRowState sets _accepting=true but never resets to false on failure (onAccept is fire-and-forget) — Accept button stuck as spinner after error, badge never appears. (3) _startHandshakeListener and _startOutcomeListener open duplicate Firestore streams instead of reusing the stable initState streams."
  artifacts:
    - path: "lib/presentation/home/home_screen.dart"
      issue: "~line 929: no hasError guard in _ActiveConnectionsSection StreamBuilder"
    - path: "lib/presentation/home/home_screen.dart"
      issue: "~line 1210: onAccept is fire-and-forget, _accepting never reset to false on error"
    - path: "lib/presentation/home/home_screen.dart"
      issue: "lines 91, 107: _startHandshakeListener and _startOutcomeListener create duplicate Firestore streams instead of reusing _incomingPendingStream / _outgoingPendingStream"
  missing:
    - "Add hasError branch before empty-list check in _ActiveConnectionsSection"
    - "Make onAccept return Future<void>, await in _PendingRequestRowState, reset _accepting in finally block"
    - "Replace fresh .snapshots() calls in listeners with reuse of initState stream fields"
  debug_session: ".planning/debug/home-connections-frozen-badge.md"
  fixed: "05-06-PLAN.md — verified 2026-07-05: home_screen.dart:762 has hasError branch across all 3 nested StreamBuilders; _PendingRequestRow/_accepting no longer exists (accept flow moved to FindFriendsScreen); duplicate stream subscriptions removed"

- truth: "Tapping the cancel/trash icon on a pending outgoing proposal shows a confirmation sheet before cancelling"
  status: failed
  reason: "User reported: no confirmation screen"
  severity: major
  test: 8
  root_cause: "Pending row wrapped in InkWell (home_screen.dart ~line 1078) that fires a SnackBar on tap, intercepting taps near the icon. The confirmation sheet IS implemented in _cancelProposal() but only reached by a pixel-perfect tap on the icon itself. Fix: remove the InkWell for pending rows — return the row widget directly."
  artifacts:
    - path: "lib/presentation/home/home_screen.dart"
      issue: "InkWell wrapping pending rows (~lines 1078–1085) intercepts taps that should reach the cancel IconButton"
  missing:
    - "Remove InkWell wrapper for non-connected rows in _ActiveConnectionRow.build()"
  debug_session: ".planning/debug/cancel-proposal-confirmation-missing.md"
  fixed: "05-06-PLAN.md — verified 2026-07-05: home_screen.dart:913 InkWell now only wraps isConnected rows; pending rows use bare IconButton onPressed calling _cancelProposal() directly"

- truth: "ReceiverScreen stepper 3 recognises the pre-connected user from the neutral handshake (stepper 0) and proceeds with RSA key exchange"
  status: failed
  reason: "User reported: From receiver's side, the third stepper does not recognize their very first stepper, that the automatic connection has been performed. Stepper 0 to 2 works fine, but stepper 3 does not recognize stepper 0, that a user has been connected, preventing RSA handshake to occur successfully."
  severity: major
  test: 10
  root_cause: "_onSenderSelected is called in initState inside _checkKeyStatus().then() before the mailbox toggle fires. selectSenderHandshake throws KeyNotFoundException because setupReceiverSession (which writes the public key to Firestore) hasn't run yet. The catch block swallows the error silently, leaving _handshakeDone=false and the transfer stream never created. Fix: store the pre-filled partner in a _pendingPrefilledSender field and consume it inside _onToggleReady(true) after setupReceiverSession completes."
  artifacts:
    - path: "lib/presentation/receiver/receiver_screen.dart"
      issue: "initState calls _onSenderSelected in _checkKeyStatus().then() (lines 72–84) before mailbox is open; _onToggleReady(true) hasn't run yet"
    - path: "lib/data/repositories/key_repository.dart"
      issue: "selectSenderHandshake (lines 453–455) throws KeyNotFoundException when publicKey is null — i.e. before setupReceiverSession has written the key"
  missing:
    - "Store preFilledSender in _pendingPrefilledSender in initState instead of calling _onSenderSelected immediately"
    - "Consume _pendingPrefilledSender inside _onToggleReady(true) after setupReceiverSession succeeds"
  debug_session: ".planning/debug/stepper3-prefill-sender-not-recognized.md"
  fixed: "05-07-PLAN.md — verified 2026-07-05: receiver_screen.dart:61,89-96,327-329 confirms _pendingPrefilledSender field deferred and consumed in _onToggleReady(true) exactly per prescribed fix"
