---
status: diagnosed
phase: 06-synchronized-readiness-gate
source: [06-VERIFICATION.md]
started: 2026-05-16T01:00:00Z
updated: 2026-05-20T00:10:00Z
---

## Current Test

[testing complete]

## Tests

### 1. CR-01 Cold-Start Smoke Test
expected: Screen stays at Step 0 showing _WaitingForConnectionWidget; no navigation to HomeScreen occurs during a 10-second wait before receiver opens mailbox
result: pass

### 2. WR-01 Returning-Pair Bypass Test (re-test after fix)
expected: After completing a prior transfer (decryption completes without error), re-entering SenderScreen with same partner shows _WaitingForReceiverWidget with ticking countdown — NOT _ConnectedBadge — until receiver explicitly re-selects sender in new session.
result: issue
reported: "Decryption still fails. Cleanup error: The caller does not have permission to execute the specified operation during 'Delete transfer record and handshake'."
severity: blocker

### 3. WR-03 Post-Unlock Revert Test
expected: After sender reaches _ConnectedBadge (receiverReady=true) and receiver closes session, sender sees orange SnackBar 'Receiver readiness was reset — waiting for confirmation.' and a fresh 60-second ticking countdown restarts
result: issue
reported: "Countdown remains stateless. 1.00 remains stuck as is."
severity: major

## Summary

total: 3
passed: 1
issues: 2
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "After decryption and save, session cleanup completes without permission errors"
  status: failed
  reason: "User reported: Decryption still fails. Cleanup error: The caller does not have permission to execute the specified operation during 'Delete transfer record and handshake'."
  severity: blocker
  test: 2
  root_cause: "firestore.rules handshakes delete rule only allows senderId == auth.uid; endSessionCleanup is called by the receiver, so the delete fails PERMISSION_DENIED"
  artifacts:
    - path: "firestore.rules:186-189"
      issue: "allow delete only covers senderId, not receiverId"
  missing:
    - "extend delete rule: resource.data.receiverId == request.auth.uid"
  debug_session: ".planning/debug/handshake-delete-permission-denied.md"
  fix_applied: "firestore.rules:186-189 extended to allow receiverId — deploy required"

- truth: "When receiver closes session after sender reached _ConnectedBadge, countdown resets to 60s and starts ticking; orange SnackBar appears"
  status: failed
  reason: "User reported: Countdown remains stateless. 1.00 remains stuck as is."
  severity: major
  test: 3
  root_cause: "_revertToWaiting() resets _secondsRemaining=60 and _readinessTimer=null but never calls _startReadinessTimer(); countdown shows 01:00 frozen because no Timer.periodic is running"
  artifacts:
    - path: "lib/presentation/sender/sender_screen.dart:194-214"
      issue: "_revertToWaiting() missing _startReadinessTimer() call after setState"
  missing:
    - "call _startReadinessTimer() after setState block in _revertToWaiting()"
  debug_session: ".planning/debug/revert-to-waiting-timer-not-restarted.md"
  fix_applied: "sender_screen.dart:212 — _startReadinessTimer() added after setState in _revertToWaiting()"
