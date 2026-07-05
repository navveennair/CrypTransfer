---
slug: decryption-failed-aes
status: resolved
trigger: "Decryption just failed, stating that the operation cannot be done"
created: "2026-07-02"
updated: "2026-07-05"
---

# Debug Session: decryption-failed-aes

## Symptoms

- **Expected:** Receiver taps "Decrypt File" on a brand-new transfer and the file decrypts successfully.
- **Actual:** Decryption fails every time with an "AES decryption failed" error (per user, error text starts with "AES decryption failed:" — exact inner exception message not yet captured).
- **Errors:** "AES decryption failed: ..." shown on DecryptScreen's error view (`decrypt_screen.dart` `_Phase.error` / `_buildError`). Exact suffix (the `$e` interpolation) not yet obtained from user.
- **Repro:** Brand-new sender/receiver pairing, first attempt (not a retry of a previously failed transfer). Consistent — happens every time, not intermittent.
- **Timeline:** First reported today, right after `.planning/debug/recent-transfers-not-showing.md` fix was applied (unrelated file — `receiver_end_session_screen.dart` — see Eliminated Hypotheses).

## Current Focus

reasoning_checkpoint:
  hypothesis: "Unknown — exhausted static-analysis leads without the exact inner exception string or a live repro. Leading candidate if the message mentions mac/tag/authentication: GCM auth tag mismatch (wrong key, wrong IV, or corrupted ciphertext). Leading candidate if it mentions invalid/corrupted/pad: truncated or corrupted ciphertext bytes."
  confirming_evidence: []
  falsification_test: "Get the exact error string via AskUserQuestion (asked, no response — user AFK) or reproduce with `flutter run` + adb logcat and capture the real stack trace / exception type."
next_action: "Ask user for exact error text (the full string after 'AES decryption failed:'), OR get logcat output from a repro run. Do not apply a fix to crypto code without this — multiple plausible root causes with different fixes."

## Evidence

- timestamp: "2026-07-02T00:00:00Z"
  checked: "encryption_service.dart runAesGcmEncrypt / runAesGcmDecrypt (lines 22-58)"
  found: "Symmetric AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)) on both encrypt and decrypt — 32-byte key, 12-byte IV, 128-bit tag, no AAD. No mismatch found."
  implication: "AES-GCM implementation itself is internally consistent — not the bug, assuming key/iv/ciphertext values reaching it are correct."

- timestamp: "2026-07-02T00:00:00Z"
  checked: "encryption_service.dart encodePublicKey/decodePublicKey/encodePrivateKey/decodePrivateKey (lines 141-177), rsaEncrypt/rsaDecrypt (183-203)"
  found: "Symmetric hex-radix JSON round-trip for RSA key material; RSAPrivateKey(modulus, privateExponent, p, q) constructor order matches decode order. OAEP encrypt/decrypt symmetric."
  implication: "RSA-OAEP key wrap/unwrap path is internally consistent — not the bug on its own."

- timestamp: "2026-07-02T00:00:00Z"
  checked: "sender_controller.dart encryptAesKey() (460-526) — freshness check at line 479"
  found: "Before RSA-encrypting the AES key, sender re-fetches the receiver's live public key via connService.fetchHandshakePublicKey(receiverId) and aborts if it differs from the cached publicKeyJson used for encryption. Prevents encrypting against a stale/rotated public key."
  implication: "Rules out sender encrypting against an outdated receiver public key for a brand-new, first-attempt transfer."

- timestamp: "2026-07-02T00:00:00Z"
  checked: "transfer_repository.dart uploadAndCreate() (30-81)"
  found: "Storage upload (`await task`) fully completes and `getDownloadURL()` resolves BEFORE the Firestore transfer doc is created with status 'pending'. Receiver has no visibility into the transfer until upload is 100% complete."
  implication: "Rules out a race where the receiver starts downloading a not-yet-fully-uploaded (truncated) ciphertext."

- timestamp: "2026-07-02T00:00:00Z"
  checked: "git diff of all currently-uncommitted files (transfer_service.dart, key_repository.dart, handshake_repository.dart, cleanup_repository.dart, transfer_repository.dart, user_repository.dart) touching the crypto/transfer path"
  found: "All changes are dead-code removal (unused methods like getConnectedFriends, resyncPublicKeyToAllConnections, watchPendingTransfers, updateTransferStatus, cancelTransfer, getTransferDoc, readFile, readChunked, resolve) and comment trimming. None touch encrypt/decrypt, key encode/decode, upload, or download logic."
  implication: "The bug is very unlikely to be caused by this session's pending changes (including the recent-transfers-not-showing fix in receiver_end_session_screen.dart, which runs strictly after decryption/save completes)."

## Eliminated Hypotheses

- hypothesis: "Caused by the receiver_end_session_screen.dart audit-log fix applied earlier this session."
  evidence: "That screen is only reached AFTER _saveAndWipe() in decrypt_screen.dart completes successfully — i.e. after decryption already succeeded. Decryption failure happens strictly before that screen is ever built."
  timestamp: "2026-07-02T00:00:00Z"

- hypothesis: "User ran the new Clear Cache / clearStaleKeys() feature and it wiped an in-use RSA key."
  evidence: "User confirmed they never used Clear Cache."
  timestamp: "2026-07-02T00:00:00Z"

- hypothesis: "Retry of a previously-aborted transfer reusing a stale AES key."
  evidence: "User confirmed this is a brand-new transfer, first attempt."
  timestamp: "2026-07-02T00:00:00Z"

- hypothesis: "Storage upload/Firestore-doc-creation race exposes a truncated download to the receiver."
  evidence: "uploadAndCreate() awaits full upload + getDownloadURL() before writing the transfer doc; receiver cannot see the transfer until then."
  timestamp: "2026-07-02T00:00:00Z"

## Resolution

root_cause: "Not conclusively identified — investigation was blocked waiting on the exact error string/logcat from the user, which was never obtained."
fix: "No code change was applied as part of this debug session."
verification: "User confirmed on 2026-07-05 that decryption now succeeds. Root mechanism was never isolated; treat as possibly transient/environment-specific (e.g. stale key state on one device) unless it recurs."
files_changed: []
