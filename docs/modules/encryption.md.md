---
tags: [module, encryption, agent-active]
status: in-progress
---


# Module: Encryption

## Responsibility
Hybrid encryption pipeline — AES-256-GCM for file data, RSA-2048-OAEP for key wrapping.

## Files Owned
- lib/src/features/crypto/

## Dependencies
- PointyCastle
- flutter_secure_storage (Android Keystore-backed)

## Current Status
✅ AES-256-GCM encryption done
✅ RSA-2048-OAEP key wrapping done
✅ Per-session keypairs with full wipe on app launch
✅ Private keys never leave the device

## Agent Instructions
1. NEVER persist private keys beyond the session
2. Always use OAEP padding for RSA — no PKCS1v1.5
3. GCM tag must always be verified on decrypt
4. Update this doc after any crypto changes

### 🛡️ Updated Logic: The "Closed Mailbox" Rule

In your **`encryption.md`** module, we are adding a mandate for the **Receiver Side State**:

1. **Toggle ON:** Generate RSA Pair $\rightarrow$ Save Public Key to Firestore $\rightarrow$ Set `isReadyToReceive = true`.
    
2. **Toggle OFF / App Close / Screen Exit:** Wipe Private Key from RAM $\rightarrow$ Delete Public Key from Firestore $\rightarrow$ Set `isReadyToReceive = false`.