---
status: resolved
phase: 06-synchronized-readiness-gate
source: [06-VERIFICATION.md]
started: 2026-05-16T01:00:00Z
updated: 2026-07-05T00:00:00Z
---

## Current Test

[testing complete — 8/8 passed; both gap fixes (handshake-delete-permission-denied, revert-to-waiting-timer-not-restarted) applied and verified via re-test]

## Tests

### 1. CR-01 Cold-Start Smoke Test
expected: Screen stays at Step 0 showing _WaitingForConnectionWidget; no navigation to HomeScreen occurs during a 10-second wait before receiver opens mailbox
result: pass

### 2. WR-01 Returning-Pair Bypass Test (re-test after rules deploy)
expected: Complete a full transfer end-to-end. On end session, 'Delete transfer record and handshake' step completes without any Cleanup error. After that, re-enter SenderScreen with same partner — Step 0 shows _WaitingForReceiverWidget with ticking countdown, NOT _ConnectedBadge.
result: pass

### 3. WR-03 Post-Unlock Revert Test (re-test after timer fix)
expected: After sender reaches _ConnectedBadge (receiverReady=true) and receiver closes session, sender sees orange SnackBar 'Receiver readiness was reset — waiting for confirmation.' and a fresh 60-second ticking countdown restarts
result: pass

### 4. TB-01 Receiver Initiates Cleanup — Waiting UI
expected: |
  After file is saved (DecryptScreen → Save & Continue), on ReceiverEndSessionScreen tap "End Session".
  Receiver UI immediately transitions to a spinner with "Waiting for Sender…" and
  "Waiting for sender to securely erase cryptographic keys…" — back navigation is blocked.
  Neither user is yet on HomeScreen.
result: pass

### 5. TB-02 Sender Turn 2 — AES Key Wipe
expected: |
  While receiver is in the "Waiting for Sender…" state (TB-01 above), sender's TransferProgressScreen
  should show status message "🔐 Keys destroyed. Waiting for receiver to terminate session…"
  within a few seconds. Firestore transfer doc should have encryptedAESKey:'' and senderCleanedUp:true.
result: pass

### 6. TB-03 Receiver Turn 3 — Full Cleanup Auto-Fires
expected: |
  Immediately after the sender wipe (TB-02), receiver's UI transitions from "Waiting for Sender…"
  to the step-by-step cleaning sequence (audit log → storage → transfer doc + handshake → RSA close),
  without any user interaction. All 4 steps complete with green checkmarks.
result: pass

### 7. TB-04 Simultaneous Home Redirect (Turn 4)
expected: |
  After receiver cleanup completes (TB-03), receiver is pushed to HomeScreen automatically
  (no manual "Back to Home" button tap required). Within ~1–2 seconds, sender's screen also
  navigates to SenderSessionEndedScreen showing the "Session Ended" summary with both cleanup
  checklists. Neither user sees a stale or broken screen state.
result: pass

### 8. TB-05 Back Navigation Locked Throughout Protocol
expected: |
  During TB-01 (waitingForSender phase), pressing the Android back button on the receiver's
  device does nothing — they cannot exit the cleanup flow until the protocol completes.
  Sender similarly cannot navigate away from TransferProgressScreen until upload is done.
result: pass

## Summary

total: 8
passed: 8
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "After decryption and save, session cleanup completes without permission errors"
  status: failed
  reason: "User reported: Decryption still fails. Cleanup error: The caller does not have permission to execute the specified operation during 'Delete transfer record and handshake'."
  severity: blocker
  test: 2
  root_cause: "firestore.rules handshakes delete rule only allowed senderId == auth.uid; endSessionCleanup is called by the receiver, so the delete failed PERMISSION_DENIED"
  artifacts:
    - path: "firestore.rules:186-189"
      issue: "allow delete only covered senderId, not receiverId"
  missing:
    - "extend delete rule: resource.data.receiverId == request.auth.uid"
  debug_session: ".planning/debug/handshake-delete-permission-denied.md"
  fix_applied: "firestore.rules extended to allow receiverId — deployed to cryptransfer-96e9f"

- truth: "When receiver closes session after sender reached _ConnectedBadge, countdown resets to 60s and starts ticking; orange SnackBar appears"
  status: failed
  reason: "User reported: Countdown remains stateless. 1.00 remains stuck as is."
  severity: major
  test: 3
  root_cause: "_revertToWaiting() reset _secondsRemaining=60 and _readinessTimer=null but never called _startReadinessTimer(); countdown showed 01:00 frozen"
  artifacts:
    - path: "lib/presentation/sender/sender_screen.dart:194-214"
      issue: "_revertToWaiting() missing _startReadinessTimer() call after setState"
  missing:
    - "call _startReadinessTimer() after setState block in _revertToWaiting()"
  debug_session: ".planning/debug/revert-to-waiting-timer-not-restarted.md"
  fix_applied: "sender_screen.dart — _startReadinessTimer() added after setState in _revertToWaiting()"
