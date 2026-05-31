---
plan: 10-01
phase: 10-ui-polish-phase-2-stale-key-security-fix
status: complete
commit: f1bf0a7
completed: 2026-05-31
---

## Summary

Restored the three-line stale-key invalidation guard in `SenderScreen._onHandshakeUpdate` that
was dropped in commit `580616d` after Phase 09 verification.

## What Was Built

Three code blocks inserted surgically into the non-empty branch of `_onHandshakeUpdate`:

- **D-01**: `final previousPublicKey = _selectedReceiverPublicKeyJson;` — captures the old public
  key BEFORE `setState()` so the comparison is against the pre-update value
- **D-02**: `if (_encrypting || _encryptingKey) return;` — mid-flight guard placed after
  `_checkTofuStatus` and the `isReconnect` SnackBar block to skip stale check during active `compute()`
- **D-03**: Stale AES key check — if `previousPublicKey != null && publicKey != previousPublicKey
  && _encryptedAESKey != null`, calls `_wipeSensitiveData()` and shows "Receiver key changed —
  re-encrypt required." SnackBar

All 580616d additions (`_everConnected`, `isReconnect` SnackBar) preserved intact.

## key-files

- modified: `lib/presentation/sender/sender_screen.dart` — stale-key guard in `_onHandshakeUpdate`

## Verification

- `flutter test test/sender/stale_key_test.dart --no-pub` — 3/3 passing (GAP2-01, GAP2-02, GAP3-02)
- `flutter analyze lib/presentation/sender/sender_screen.dart` — No issues found
- `flutter test --no-pub` — 113/114 passing (1 pre-existing TC010 skip)

## Self-Check: PASSED
