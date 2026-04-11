---
tags: [module, security, agent-active]
status: complete
---

# Module: Security

## Responsibility
End-to-end security architecture: in-memory buffer zeroing, session key lifecycle,
Closed Mailbox Kill Switch, session hijack prevention, and automated audit reporting.

## Files Owned
- `lib/core/utils/security_lifecycle_mixin.dart` — `SecurityLifecycleMixin`
- `lib/data/services/encryption_service.dart` — Kill Switch + audit logger
- `test/security/session_wipe_test.dart` — TC-WIPE-001 to TC-WIPE-006
- `test/security/key_storage_audit_test.dart` — key storage audit
- `scripts/silent_guardian.ps1` — nightly scanner + Obsidian report
- `scripts/security_audit_report.dart` — Obsidian security audit writer
- `SECURITY_PROTOCOL.md` — full threat model and protocol spec

## SecurityLifecycleMixin
Applied to: `SenderScreen`, `DecryptScreen`, `TransferProgressScreen`,
`DownloadConfirmScreen`, `EndSessionScreen`

```dart
// Register any Uint8List that contains key/plaintext material:
registerBuffer(aesKey);
registerBuffer(iv);
registerBuffer(encryptedBytes);

// Zero all buffers (called automatically on dispose, or manually):
wipeAll();

// Hook for additional cleanup after wipe:
@override
void onBuffersWiped() { setState(() => _aesKey = null); }
```

**Guarantee:** `dispose()` always calls `wipeAll()` → key material never persists
beyond the widget lifecycle.

## Closed Mailbox Kill Switch

### Threat
If receiver's public key is left in Firestore after session ends, an attacker can
encrypt files to that receiver without their knowledge ("ghost mailbox" attack).

### Defence
`EncryptionService.closeReceiverSession(uid)` atomically:
1. Deletes `publicKey` from Firestore (`FieldValue.delete()`)
2. Wipes private key from `FlutterSecureStorage`
3. Batch-deletes `rsa_key_transfers` documents
4. Purges `rsa_key_received` notifications
5. Logs `Receiver_Session_Closed` to `security_audit_log`

### Three Triggers
| Trigger | Code Path |
|---------|-----------|
| Toggle switch OFF | `ReceiverScreen._onToggleReady(false)` |
| App paused / detached | `ReceiverScreen.didChangeAppLifecycleState` |
| Back navigation | `PopScope.onPopInvokedWithResult` |

### Session Lock
While a transfer is in progress, `_sessionLocked = true` prevents the receiver
from closing the mailbox mid-transfer. `_showSessionLockedBanner()` informs the user.

## Radioactive Buffer Tracker
| Buffer | Screen | Wipe Trigger |
|--------|--------|--------------|
| `_aesKey` | SenderScreen | Pre-flight + handoff + dispose |
| `_iv` | SenderScreen | Pre-flight + handoff + dispose |
| `_encryptedBytes` | SenderScreen | Pre-flight + handoff + dispose |
| `_encryptedAesKey` | SenderScreen | Pre-flight + handoff + dispose |
| `_aesKey` | DecryptScreen | Post-isolate + save + dispose |
| `_iv` | DecryptScreen | Post-decrypt + save + dispose |
| `_decryptedBytes` | DecryptScreen | Save + dispose |
| `privateKeyJson` | DecryptScreen | After isolate starts |

## Session Wipe Test Suite
File: `test/security/session_wipe_test.dart`

| TC | Test | Status |
|----|------|--------|
| TC-WIPE-001 | `publicKey` deleted from Firestore after session close | ✅ PASS |
| TC-WIPE-002 | `rsa_key_transfers` purged after session close | ✅ PASS |
| TC-WIPE-003 | AES key buffer zeroed after use | ✅ PASS |
| TC-WIPE-004 | Session hijack prevented — `publicKey` null after kill switch | ✅ PASS |
| TC-WIPE-005 | New session generates different keypair each time | ✅ PASS |
| TC-WIPE-006 | Notifications purged after session close | ✅ PASS |

## Startup Session Wipe: KeyRepository.wipeAllSessionKeys()
On app startup, `wipeAllSessionKeys(uid)` performs a full wipe:
1. Deletes all SecureStorage entries with `rsa_private_key_*` / `rsa_public_key_*` prefixes
2. Deletes all `rsa_key_transfers` where `fromUserId == uid`
3. Deletes all `rsa_key_transfers` where `toUserId == uid`
4. Deletes all `rsa_key_received` notifications for `uid`

This is the **startup** wipe (belt-and-suspenders with the Closed Mailbox Kill Switch).
It ensures no stale session keys survive a crash or force-close.

## ✅ compute() Coverage (all crypto paths)
`AuthRepository.generateAndStoreKeyPair()` was migrated from `Isolate.run()` to `compute()`
(top-level `_generateKeyPairIsolate` function in `auth_repository.dart`).
All crypto isolate paths now use `compute()` — Guardian scanner shows no WARNING for this file.

## Silent Guardian Scanner
`scripts/silent_guardian.ps1` runs nightly and checks:
- `SecurityLifecycleMixin` present in screen files → VERIFIED
- `FieldValue.delete()` present in `closeReceiverSession` → Kill Switch confirmed
- `Receiver_Session_Closed` audit event present → Logging active
- `closeReceiverSession` wired in `receiver_screen.dart` → VERIFIED
- `didChangeAppLifecycleState` present in `receiver_screen.dart` → VERIFIED
- `debugPrint` with key terms → CRITICAL flag
- Direct Firestore in presentation layer → WARNING flag

## OWASP Mobile Top 10 Coverage
| ID | Threat | Mitigation |
|----|--------|-----------|
| M1 | Improper Credential Usage | Keys never hardcoded; env-free |
| M2 | Inadequate Supply Chain | Only pub.dev verified packages |
| M4 | Insufficient Input Validation | GCM auth tag validates file integrity |
| M9 | Insecure Data Storage | Private keys in Android Keystore via `flutter_secure_storage` |
| M10 | Insufficient Cryptography | AES-256-GCM + RSA-2048-OAEP; no ECB, no PKCS1v1.5 |

## Security Audit Logging
`EncryptionService._logSecurityEvent(event, userId, details)`:
- Writes to Firestore `security_audit_log` collection
- Logs event name + timestamp — **never** key material
- Fire-and-forget (`.ignore()`) — does not block session operations

## Agent Instructions
1. Every screen handling crypto buffers MUST use `SecurityLifecycleMixin`
2. `closeReceiverSession` MUST be called on all three trigger paths — not just toggle
3. `_logSecurityEvent` MUST NOT log key material — event names and status strings only
4. Run `flutter test test/security/` after any crypto or session change
5. Update TC results table in this doc after every test run
6. Update this doc after any security architecture changes
