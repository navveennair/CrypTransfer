---
plan: 09-03
phase: 09-navigation-safety-session-integrity-hardening
status: complete
completed: "2026-05-29"
commit: 793e226
---

# Plan 09-03: SenderScreen Stale Key Wipe + Change File Guard (Gap 2 & 3)

## What Was Built

Two surgical changes to `sender_screen.dart`:

**Gap 2 — Stale AES key invalidation in `_onHandshakeUpdate`:**
- `final previousPublicKey = _selectedReceiverPublicKeyJson;` captured BEFORE setState
- Consolidated mid-flight guard `if (_encrypting || _encryptingKey) return;` after `_checkTofuStatus` (replaces the redundant second guard in the `else if` branch)
- Stale-key check: when `previousPublicKey != null && publicKey != previousPublicKey && _encryptedAESKey != null` → `_wipeSensitiveData()` + SnackBar "Receiver key changed — re-encrypt required."
- Preserves `_file`, `_receiverId`, `_receiverUsername` after wipe (light wipe, not `_revertToWaiting`)

**Gap 3 — Step 1 re-pick UX lock:**
- Browse Files `CrypButton.onPressed`: `(_receiverSelected && !_fileEncrypted) ? _pickFile : null` — greyed after encryption
- `'Change File'` TextButton visible only when `_fileEncrypted` — rendered below `_FileCard`
- AlertDialog: title "Change File?", body "This will wipe your encrypted data and AES key. Are you sure?", Confirm → `Navigator.pop(ctx)` + `_wipeSensitiveData()` + `_pickFile()`
- When `_encryptedBytes` becomes null, `_fileEncrypted` getter returns false → TextButton disappears, Browse Files re-enables automatically

## Key Files Modified

- `lib/presentation/sender/sender_screen.dart`

## Verification

- `flutter analyze lib/presentation/sender/sender_screen.dart --no-pub` → **No issues found**
- `flutter test test/sender/ --no-pub` → **13/13 passed** (10 existing + 3 GAP2/GAP3 stubs)
- Full suite: **113/114** (TC010 pre-existing failure unchanged)

## Self-Check: PASSED

All must_haves satisfied:
- ✓ Stale-key wipe fires when receiver public key changes with non-null `_encryptedAESKey`
- ✓ Mid-flight guard skips stale check when `_encrypting` or `_encryptingKey`
- ✓ `_file` and receiver connection preserved after stale wipe
- ✓ Browse Files disabled when `_fileEncrypted`
- ✓ "Change File" TextButton appears only when `_fileEncrypted`
- ✓ AlertDialog shows correct copy, Confirm calls `_wipeSensitiveData()` then `_pickFile()`
- ✓ Cancel dismisses with no state change
- ✓ flutter analyze clean, stale_key_test.dart 3/3 pass
