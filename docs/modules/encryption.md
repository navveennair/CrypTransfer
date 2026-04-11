---
tags: [module, encryption, agent-active]
status: complete
---

# Module: Encryption

## Responsibility
Hybrid encryption pipeline — AES-256-GCM for file data, RSA-2048-OAEP for key wrapping.
Manages the full receiver session lifecycle including the Closed Mailbox Kill Switch.

## Files Owned
- `lib/data/services/encryption_service.dart` — all crypto logic
- `lib/core/utils/security_lifecycle_mixin.dart` — in-memory buffer zeroing mixin

## Dependencies
- `pointycastle` — AES-256-GCM, RSA-2048, FortunaRandom CSPRNG
- `flutter_secure_storage` — Android Keystore-backed private key storage
- `cloud_firestore` — public key publishing and session state

## Crypto Pipeline

### Sender Side
1. Generate 256-bit AES key + 96-bit IV via `secureRandomBytes()`
2. Encrypt file with AES-256-GCM in `compute()` isolate → `AesEncryptResult`
3. RSA-OAEP encrypt the AES key with receiver's public key (`rsaEncrypt`)
4. Upload: encrypted file to Firebase Storage, encrypted AES key + IV to Firestore

### Receiver Side
1. Retrieve private key from `FlutterSecureStorage`
2. RSA-OAEP decrypt the AES key (`decryptAesKeyWithPrivateKeyJson`)
3. AES-256-GCM decrypt file bytes in `compute()` isolate
4. GCM authentication tag verified automatically — integrity guaranteed

## Closed Mailbox Rule (Kill Switch)

### Toggle ON — `setupReceiverSession(uid)`
1. Generate fresh RSA-2048 keypair in background isolate via `compute()`
2. Store private key in `FlutterSecureStorage` (never leaves device)
3. Publish public key to `users/{uid}` in Firestore
4. Set `isReadyToReceive: true`, `sessionActive: true`

### Toggle OFF / App Background / Screen Exit — `closeReceiverSession(uid)`
1. Delete `publicKey` field from Firestore with `FieldValue.delete()`
2. Wipe private key from `FlutterSecureStorage`
3. Batch-delete all `rsa_key_transfers` documents from this user
4. Best-effort delete `rsa_key_received` notifications
5. Set `isReadyToReceive: false`, `sessionActive: false`, write `lastSessionClosed`
6. Log `Receiver_Session_Closed` event to `security_audit_log` via `_logSecurityEvent()`

### Triggers
| Trigger | Handler |
|---------|---------|
| Toggle switch OFF | `ReceiverScreen._onToggleReady(false)` |
| App paused / detached | `didChangeAppLifecycleState` |
| Back navigation | `PopScope.onPopInvokedWithResult` |

## ⚠️ Legacy Key Path: Isolate.run()
`AuthRepository.generateAndStoreKeyPair()` uses `Isolate.run()` (not `compute()`).
Called from `ReceiverScreen._generateKeys()` (step 0 stepper) and `SidebarDrawer`.
The Guardian scanner flags this as WARNING. This is intentional legacy behaviour —
the Closed Mailbox path (`setupReceiverSession()`) correctly uses `compute()`.

## Current Status
✅ AES-256-GCM encryption/decryption (`compute()` isolate)  
✅ RSA-2048-OAEP key wrapping/unwrapping (OAEP only — no PKCS1v1.5)  
✅ Fresh per-session keypair via `setupReceiverSession()`  
✅ Kill Switch via `closeReceiverSession()` — public key deleted, private key wiped  
✅ `SecurityLifecycleMixin` — auto-zeroes `Uint8List` buffers on dispose  
✅ `_logSecurityEvent()` — audit logger (event names only, no key material)  
✅ Closed Mailbox crypto ops run in `compute()` isolate — UI never blocks  
✅ GCM tag always verified on decrypt — integrity enforced  
✅ Private keys never uploaded to Firestore  
⚠️ `generateAndStoreKeyPair()` (legacy step 0) uses `Isolate.run()` — Guardian WARNING (intentional)

## Agent Instructions
1. NEVER persist private keys beyond the session
2. ALWAYS use OAEP padding for RSA — never PKCS1v1.5
3. GCM tag must always be verified on decrypt — it is, via PointyCastle GCMBlockCipher
4. New session = new keypair — never reuse RSA keys across sessions
5. `_logSecurityEvent` must NEVER log key material — event names and status strings only
6. Update this doc after any crypto changes
