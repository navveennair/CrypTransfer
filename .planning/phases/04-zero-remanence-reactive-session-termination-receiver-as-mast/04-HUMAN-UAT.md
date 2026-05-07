---
status: partial
phase: 04-zero-remanence-reactive-session-termination-receiver-as-mast
source: [04-VERIFICATION.md]
started: 2026-05-08T00:00:00Z
updated: 2026-05-08T00:00:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. TERM-06: Back navigation blocked during cleanup

expected: Tapping the system back button during the cleaning phase (while "End Session" steps are running) does nothing — the screen cannot be popped. PopScope(canPop: _phase == _Phase.ready) enforces this.
result: [pending]

### 2. TERM-07: "Back to Home" clears navigation stack

expected: After cleanup completes and the done screen is shown, tapping "Back to Home" navigates to HomeScreen with no back arrow visible — the full navigation stack has been cleared. Navigator.pushAndRemoveUntil(..., (_) => false) enforces this.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
