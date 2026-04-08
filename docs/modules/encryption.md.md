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

## Open Tasks
- [ ] Add unit tests for GCM tag verification
- [ ] Verify key wipe on session cancel
- [ ] Ensure post-decrypt file is written to local storage correctly