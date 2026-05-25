---
phase: 07-sender-reactive-cleanup-sync
nyquist_enabled: true
date: 2026-05-23
---

# Phase 07 Validation Strategy

## Validation Architecture

### Test Files
- `test/sender/transfer_progress_timeout_test.dart` — widget tests for TransferProgressScreen timeout + waiting UI

### Nyquist Stubs Required

#### Pulsing Indicator Tests
- V07-01: CircularProgressIndicator visible when _canEndSession=true && _senderWipeSent=false
- V07-02: Pulsing indicator hidden when _senderWipeSent=true (Turn 2 executed)
- V07-03: Pulsing indicator hidden when _canEndSession=false (initial state)

#### Safety Timeout Tests
- V07-04: _startCleanupTimeout() creates a 300-second Timer
- V07-05: Timer expiry calls wipeAll() and navigates to SenderSessionEndedScreen
- V07-06: SenderSessionEndedScreen receives timeoutReason != null on timeout path
- V07-07: Timer is cancelled when Turn 2 branch fires (_senderWipeSent set to true)
- V07-08: Timer is cancelled in dispose() — no use-after-dispose crash

#### SenderSessionEndedScreen Banner
- V07-09: Orange banner visible when timeoutReason != null
- V07-10: Normal subtitle shown when timeoutReason == null
