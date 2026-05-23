---
status: complete
phase: 07-sender-reactive-cleanup-sync
source: [07-VERIFICATION.md]
started: 2026-05-23T00:00:00Z
updated: 2026-05-23T00:00:00Z
---

## Current Test

number: 3
name: Back-navigation while timer is running — no crash
result: passed

## Tests

### 1. Pulsing spinner appears and disappears at correct moments
expected: After receiver saves the file (receiverStatus == 'saved'), a CircularProgressIndicator with text "Waiting for secure session close…" appears below the green status badge. Once receiver taps End Session (cleanup_initiated fires), the spinner disappears and the status message changes to "Keys destroyed. Waiting for receiver to terminate session…"
result: passed
fix_applied: "Moved _startTransferListener() from initState() to inside _startUpload() after the Firestore .set() call succeeds. Root cause: listener subscribed to a non-existent doc — Firestore security rule (resource.data.senderId) evaluated resource as null → permission denied → subscription silently cancelled."

### 2. End-to-end timeout path with orange banner
expected: Temporarily change Duration(seconds: 300) to Duration(seconds: 10) in transfer_progress_screen.dart. Complete a transfer. Do NOT tap End Session on the receiver. After 10 seconds, the sender should navigate to SenderSessionEndedScreen showing an orange banner with text "Session ended by timeout — receiver did not complete cleanup" and subtitle "Session ended by safety timeout."
result: passed

### 3. Back-navigation while timer is running — no crash
expected: Navigate back from TransferProgressScreen while the cleanup timer is running (after receiver saved but before cleanup_initiated). No crash should occur. dispose() should fire, cancel the timer, and SecurityLifecycleMixin.wipeAll() should zero registered buffers.
result: passed

## Summary

total: 3
passed: 3
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "Sender receives receiverStatus='saved' and cleanup_initiated signals via Firestore stream; pulsing indicator appears/disappears at correct moments"
  status: fixed — awaiting retest
  reason: "Root cause: _startTransferListener() called in initState() before the transfers doc exists. Firestore security rule resource.data.senderId evaluates null for non-existent doc → returns false → permission denied → subscription silently cancelled. Fix: listener now starts inside _startUpload() after .set() completes."
  severity: major
  test: 1
  root_cause: "listener subscribed before doc exists → Firestore rule denies initial snapshot → stream subscription silently cancelled"
  artifacts: ["lib/presentation/sender/transfer_progress_screen.dart"]
  missing: []
  debug_session: "sender-stream-no-receiverstatus-signals"
