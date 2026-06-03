---
status: partial
phase: 10-ui-polish-phase-2-stale-key-security-fix
source: [10-VERIFICATION.md]
started: 2026-05-31T00:00:00Z
updated: 2026-06-01T08:45:00Z
---

## Current Test

Autonomous UAT run on 2026-06-01 using emulator-5554 (navveennair/sender) and emulator-5556 (testt123/receiver). FLAG_SECURE temporarily bypassed for screenshots (restored after). Tests 2 and 3 verified via code evidence + live dialog observation. Test 1 needs manual re-run with precise timing.

## Tests

### 1. Stale-key guard live trigger

expected: SnackBar "Receiver key changed — re-encrypt required." appears on sender side when receiver closes and reopens their mailbox (rotating RSA keypair); sender's encrypt action requires re-initiation; previously encrypted AES key is wiped.
result: [needs-further-analysis] Manual UAT revealed the guard was reactive, not pre-emptive. When receiver closed mailbox then sender tapped "Encrypt Key", the RSA encryption ran first using the cached (stale) key. Only ~1-2 seconds later did the Firestore stream deliver the null snapshot and trigger _revertToWaiting(). Root cause: the stream-based guard cannot block the RSA encrypt call in the latency window.

FIX APPLIED (2026-06-01): Pre-emptive freshness check added to _encryptAesKey() — a one-shot Firestore get() is performed before the biometric prompt. If the live key is null (receiver gone) or differs from the cached key, encryption is aborted and _wipeSensitiveData() is called immediately. New test GAP2-03 added to stale_key_test.dart. flutter analyze clean, 4/4 stale key tests passing.

Re-test required: perform the same scenario — receiver closes mailbox, sender taps "Encrypt Key" within ~1-2 seconds. Expected result: "Receiver closed their session — cannot encrypt." error fires before biometric prompt appears, and the AES state is wiped.

### 2. Dialog spacing visual inspection

expected: Body-to-buttons gap visually larger than before (32dp); Cancel-to-confirm button gap visually tighter (8dp). Verify across all 6 dialog types: find_friends disconnect, sender go-back, decrypt abort, receiver_transfer abort, transfer_progress abort, home role-conflict.
result: [pass] Code evidence: 12 × `SizedBox(height: 32)` confirmed across all 6 dialog files (grep returned 12 matches). Live observation: "Close Mailbox?" dialog on receiver screen showed correct glassmorphic spacing with visually larger body-to-buttons gap and tighter button gap. `SizedBox(width: 8)` confirmed in all two-button dialog rows.

### 3. Admin dashboard rendering

expected: AppBar displays 'CrypTransferAdmin'; tiles show frosted-glass glassmorphic appearance; Connection Node Map and Security Pulse Feed load without errors.
result: [pass-code] Code evidence: `CrypTransferAdmin` confirmed at admin_dashboard.dart:50; `GlassContainer` confirmed in security_pulse_feed.dart (2 instances) and connection_node_map.dart. Live rendering not verified (requires admin-privileged account). Mark as pass-code pending admin login confirmation.

### 4. Manual abort clears Firestore session state (gap-2 fix)

expected: When the receiver manually taps "Abort & Destroy" on the ReceiverTransferScreen abort dialog, `closeReceiverSession()` is called before navigating to HomeScreen. Firestore state is fully torn down: `isReadyToReceive=false`, `publicKey` deleted, `sessionActive=false`. No dirty session remains.

result: [needs-retest] Fix applied 2026-06-03 (commit af92b1d): `_abortSessionDueToDisconnect()` in `receiver_transfer_screen.dart` now calls `EncryptionService.closeReceiverSession(uid)` after `wipeAll()` and before `pushAndRemoveUntil(HomeScreen)`. Other abort paths (`_watchTransferStatus`, `_abortDueToWatchdog`, and all `decrypt_screen.dart` paths) already had this call.

Re-test scenario: enter ReceiverTransferScreen (sender has initiated a transfer, receiver is on the status-steps screen), tap the back button to open the abort dialog, confirm "Abort & Destroy". Expected: (1) snackbar "Transfer aborted — tunnel destroyed." appears; (2) navigates to HomeScreen; (3) re-opening the receiver mailbox shows a clean state with no active session (no stale publicKey or isReadyToReceive=true in Firestore).

## Summary

total: 4
passed: 1
issues: 0
pending: 0
skipped: 0
blocked: 0
needs-retest: 2
pass-code: 1
fix-applied: 1

## Gaps

- Test 1: Re-run after pre-emptive freshness fix (2026-06-01). Stop sender after "Encrypt with AES Key", then have receiver close mailbox, then tap "Encrypt Key" within 1-2 s. Expected: "Receiver closed their session — cannot encrypt." fires before biometric prompt; no stale-key RSA encryption occurs.
- Test 3: Verify live with admin account login to confirm GlassContainer tiles render and feeds load without runtime errors.
- Test 4: Manual abort dialog on ReceiverTransferScreen — confirm Firestore session state is clean after abort.
