---
status: complete
phase: 06-synchronized-readiness-gate
source: [06-01-SUMMARY.md, 06-02-SUMMARY.md, 06-03-SUMMARY.md, 06-04-SUMMARY.md]
started: 2026-05-23T00:00:00Z
updated: 2026-05-23T00:10:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Sender steps locked until receiver is ready
expected: After the sender selects a receiver (handshake initiated), Steps 1–4 on SenderScreen are visibly faded out and non-interactive. In place of the connected badge, a pulsing hourglass widget appears showing a MM:SS countdown starting at 1:00.
result: issue
reported: "The is pulsing but no countdown that shows reduction in number from 1:00"
severity: major

### 2. Countdown timer ticks in real time
expected: The MM:SS countdown in the hourglass widget decrements by 1 second each second (1:00 → 0:59 → 0:58 …). Step 0 indicator stays blue (incomplete) while waiting.
result: skipped
reason: related to test 1 countdown issue

### 3. Receiver ready unlocks sender
expected: When the receiver selects the sender from their side (triggering setReceiverReady), Steps 1–4 fade in and become fully interactive on the SenderScreen. A green floating SnackBar reads "Secure channel established. Receiver is ready." Step 0 switches to the connected badge and its indicator turns green/done.
result: pass

### 4. 60-second timeout ejects sender to HomeScreen
expected: If the receiver does not signal readiness within 60 seconds, the sender is navigated to HomeScreen (stack cleared) and a red/error floating SnackBar reads "Session Terminated — receiver closed the session."
result: skipped
reason: countdown display not working (test 1 issue); 60s wait not practical to verify

### 5. Cold-start no false eject
expected: When the sender selects a receiver for the first time in a session, the initial Firestore cold-start empty snapshot does NOT immediately eject to HomeScreen. The sender stays on SenderScreen in the waiting/hourglass state.
result: pass

### 6. Returning pair bypass fix
expected: Two users who previously connected (handshake doc already exists in Firestore) and now reconnect in a new session still see the waiting/hourglass gate — the sender does NOT skip straight to Steps 1–4 unlocked without the receiver signaling readiness again.
result: pass

### 7. Receiver-readiness write failure shows retryable SnackBar
expected: If writing receiverReady: true fails on the receiver side (e.g. network error), the receiver sees a floating SnackBar "Failed to signal readiness — tap to retry." with a "Retry" action button. Tapping Retry re-attempts the write.
result: skipped
reason: can't simulate a network failure

### 8. Receiver reverts to not-ready restarts countdown
expected: If receiverReady flips back to false mid-session (receiver disconnects after readiness was established but before transfer), the sender reverts to the waiting/hourglass state, the 60-second countdown restarts from 1:00, and an orange SnackBar is shown.
result: pass

## Summary

total: 8
passed: 4
issues: 1
pending: 0
skipped: 3
blocked: 0

## Gaps

- truth: "Pulsing hourglass widget shows MM:SS countdown starting at 1:00 after sender selects receiver"
  status: failed
  reason: "User reported: The is pulsing but no countdown that shows reduction in number from 1:00"
  severity: major
  test: 1
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
