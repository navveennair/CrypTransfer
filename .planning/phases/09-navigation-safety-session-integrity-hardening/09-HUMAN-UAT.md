---
status: partial
phase: 09-navigation-safety-session-integrity-hardening
source: [09-VERIFICATION.md]
started: 2026-05-30T00:00:00Z
updated: 2026-05-30T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. ReceiverScreen Back-Nav When Mailbox Open

expected: _showCloseSessionDialog() BottomSheet appears — no silent pop
result: [pending]

**Device steps:** Open mailbox (toggle receive ON), then tap hardware back button or swipe back gesture.

### 2. ReceiverScreen Back-Nav When Transfer Locked

expected: SnackBar 'Cannot close session — transfer in progress.' appears; no navigation
result: [pending]

**Device steps:** Start an active file transfer so `_sessionLocked=true`, then press hardware back.

### 3. Step 1 StepCard Opacity + Tap Block

expected: Taps are absorbed; card is visually at ~40% opacity
result: [pending]

**Device steps:** Open mailbox (toggle receive ON), then attempt to tap any button inside Step 1 RSA Keypair card.

### 4. AppBar Settings Button Disabled When Mailbox Open

expected: Settings icon is greyed and non-responsive
result: [pending]

**Device steps:** Open mailbox, observe AppBar top-right settings icon — tap should produce no response.

### 5. Browse Files Button Disabled After Encryption

expected: 'Browse Files' CrypButton is visually disabled (greyed) and non-tappable
result: [pending]

**Device steps:** On SenderScreen, select receiver, pick file, complete Step 2 encryption — then tap 'Browse Files'.

### 6. Change File AlertDialog

expected: AlertDialog appears: 'Change File?' title, 'This will wipe your encrypted data and AES key. Are you sure?' body; Cancel dismisses; Confirm wipes state and opens file picker
result: [pending]

**Device steps:** With file encrypted, tap the 'Change File' TextButton below the file card.

### 7. Stale Key Invalidation (Two-Device Test)

expected: SnackBar 'Receiver key changed — re-encrypt required.' appears; encrypted state cleared; Browse Files re-enables
result: [pending]

**Device steps:** Sender connects to receiver; sender picks file and completes Step 2 encryption; receiver closes and reopens their mailbox (regenerating RSA keys).

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps
