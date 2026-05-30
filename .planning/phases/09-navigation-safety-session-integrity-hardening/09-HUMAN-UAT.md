---
status: complete
phase: 09-navigation-safety-session-integrity-hardening
source: [09-VERIFICATION.md]
started: 2026-05-30T00:00:00Z
updated: 2026-05-30T09:00:00Z
---

## Current Test

[testing complete]

## Tests

### 1. ReceiverScreen Back-Nav When Mailbox Open

expected: _showCloseSessionDialog() BottomSheet appears — no silent pop
result: pass

**Device steps:** Open mailbox (toggle receive ON), then tap hardware back button or swipe back gesture.

### 2. ReceiverScreen Back-Nav When Transfer Locked

expected: SnackBar 'Cannot close session — transfer in progress.' appears; no navigation
result: pass
note: ReceiverTransferScreen (Incoming File page) shows 'Abort & Destroy' confirmation — correct behavior. ReceiverScreen _sessionLocked SnackBar is a race-condition safety net unreachable in normal flow; transfer protection confirmed working via the screen users actually occupy.

### 3. Step 1 StepCard Opacity + Tap Block

expected: Taps are absorbed; card is visually at ~40% opacity
result: pass

**Device steps:** Open mailbox (toggle receive ON), then attempt to tap any button inside Step 1 RSA Keypair card.

### 4. AppBar Settings Button Disabled When Mailbox Open

expected: Settings icon is greyed and non-responsive
result: pass

**Device steps:** Open mailbox, observe AppBar top-right settings icon — tap should produce no response.

### 5. Browse Files Button Disabled After Encryption

expected: 'Browse Files' CrypButton is visually disabled (greyed) and non-tappable; no way to change file once encryption is complete and user has progressed to Step 3
result: issue
reported: "You can actually change file after encryption, that shouldn't be it. once encryption, there should not be a way to change file. it is only when the stepper 2 is live, that is only when you can change file. otherwise, progressing to stepper 3 there should be greyed out stepper 2"
severity: major

**Device steps:** On SenderScreen, select receiver, pick file, complete Step 2 encryption — then tap 'Browse Files'.

### 6. Change File AlertDialog

expected: AlertDialog appears: 'Change File?' title, 'This will wipe your encrypted data and AES key. Are you sure?' body; Cancel dismisses; Confirm wipes state and opens file picker
result: skipped
reason: Superseded by Test 5 gap — design intent is for no file-change mechanism once encryption is complete. Fix for Test 5 removes the Change File TextButton when Step 3 is active; this test becomes moot.

**Device steps:** With file encrypted, tap the 'Change File' TextButton below the file card.

### 7. Stale Key Invalidation (Two-Device Test)

expected: SnackBar 'Receiver key changed — re-encrypt required.' appears; encrypted state cleared; Browse Files re-enables
result: skipped
reason: Scenario not reachable in normal protocol flow. Receiver closing mailbox deletes the handshake doc entirely, which fires _revertToWaiting() on the sender (connection dropped). The stale-key check in _onHandshakeUpdate requires publicKey to change on an existing handshake doc — that never happens; the doc is deleted first. The defensive code is unreachable dead code given current protocol design.

**Device steps:** Sender connects to receiver; sender picks file and completes Step 2 encryption; receiver closes and reopens their mailbox (regenerating RSA keys).

## Summary

total: 7
passed: 4
issues: 1
pending: 0
skipped: 2
blocked: 0
skipped: 0
blocked: 0

## Gaps

- truth: "Step 2 is fully locked once encryption complete and user progresses to Step 3 — no Browse Files, no Change File"
  status: failed
  reason: "User reported: You can actually change file after encryption, that shouldn't be it. once encryption, there should not be a way to change file. it is only when the stepper 2 is live, that is only when you can change file. otherwise, progressing to stepper 3 there should be greyed out stepper 2"
  severity: major
  test: 5
  root_cause: ""
  artifacts: []
  missing: []
  debug_session: ""
