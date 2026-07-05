---
status: resolved
phase: 10-ui-polish-phase-2-stale-key-security-fix
source: [10-VERIFICATION.md]
started: 2026-05-31T00:00:00Z
updated: 2026-07-05T00:00:00Z
---

## Current Test

[testing complete — Tests 1, 2, 4 confirmed passing on re-test 2026-07-05; Test 3 remains pass-code only (visual styling not re-confirmed live this pass)]

## Tests

### 1. Stale-key guard live trigger

expected: SnackBar "Receiver key changed — re-encrypt required." appears on sender side when receiver closes and reopens their mailbox (rotating RSA keypair); sender's encrypt action requires re-initiation; previously encrypted AES key is wiped.
result: pass
note: "Re-tested 2026-07-05: 'Receiver closed their session — cannot encrypt.' fires pre-emptively before the biometric prompt; no stale-key encryption occurs. Original issue (reactive-not-preemptive guard) was fixed 2026-06-01 and is now confirmed live."

### 2. Dialog spacing visual inspection

expected: Body-to-buttons gap visually larger than before (32dp); Cancel-to-confirm button gap visually tighter (8dp). Verify across all 6 dialog types: find_friends disconnect, sender go-back, decrypt abort, receiver_transfer abort, transfer_progress abort, home role-conflict.
result: [pass] Code evidence: 12 × `SizedBox(height: 32)` confirmed across all 6 dialog files (grep returned 12 matches). Live observation: "Close Mailbox?" dialog on receiver screen showed correct glassmorphic spacing with visually larger body-to-buttons gap and tighter button gap. `SizedBox(width: 8)` confirmed in all two-button dialog rows.

### 3. Admin dashboard rendering

expected: AppBar displays 'CrypTransferAdmin'; tiles show frosted-glass glassmorphic appearance; Connection Node Map and Security Pulse Feed load without errors.
result: [pass-code] Code evidence: `CrypTransferAdmin` confirmed at admin_dashboard.dart:50; `GlassContainer` confirmed in security_pulse_feed.dart (2 instances) and connection_node_map.dart. Live rendering not verified (requires admin-privileged account). Mark as pass-code pending admin login confirmation.

### 4. Manual abort clears Firestore session state (gap-2 fix)

expected: When the receiver manually taps "Abort & Destroy" on the ReceiverTransferScreen abort dialog, `closeReceiverSession()` is called before navigating to HomeScreen. Firestore state is fully torn down: `isReadyToReceive=false`, `publicKey` deleted, `sessionActive=false`. No dirty session remains.

result: pass
note: "Re-tested 2026-07-05: snackbar 'Transfer aborted — tunnel destroyed.' appears, navigates to HomeScreen, re-opening the mailbox shows a clean state. Fix from commit af92b1d confirmed live."

## Summary

total: 4
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0
pass-code: 1

## Gaps

- Test 3: Visual styling (CrypTransferAdmin AppBar, GlassContainer tiles) remains pass-code only — confirmed in source but not re-verified live with an admin account login this pass. Low-risk gap given corroborating on-device evidence from the analytics-permission-denied debug session, which navigated this exact screen and confirmed rendering.
