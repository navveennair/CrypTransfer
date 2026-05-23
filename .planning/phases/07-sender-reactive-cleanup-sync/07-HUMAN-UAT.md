---
status: partial
phase: 07-sender-reactive-cleanup-sync
source: [07-VERIFICATION.md]
started: 2026-05-23T00:00:00Z
updated: 2026-05-23T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Pulsing spinner appears and disappears at correct moments
expected: After receiver saves the file (receiverStatus == 'saved'), a CircularProgressIndicator with text "Waiting for secure session close…" appears below the green status badge. Once receiver taps End Session (cleanup_initiated fires), the spinner disappears and the status message changes to "Keys destroyed. Waiting for receiver to terminate session…"
result: [pending]

### 2. End-to-end timeout path with orange banner
expected: Temporarily change Duration(seconds: 300) to Duration(seconds: 10) in transfer_progress_screen.dart. Complete a transfer. Do NOT tap End Session on the receiver. After 10 seconds, the sender should navigate to SenderSessionEndedScreen showing an orange banner with text "Session ended by timeout — receiver did not complete cleanup" and subtitle "Session ended by safety timeout."
result: [pending]

### 3. Back-navigation while timer is running — no crash
expected: Navigate back from TransferProgressScreen while the cleanup timer is running (after receiver saved but before cleanup_initiated). No crash should occur. dispose() should fire, cancel the timer, and SecurityLifecycleMixin.wipeAll() should zero registered buffers.
result: [pending]

## Summary

total: 3
passed: 0
issues: 0
pending: 3
skipped: 0
blocked: 0

## Gaps
